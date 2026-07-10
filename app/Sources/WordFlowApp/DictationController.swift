// Wires the whole dictation loop together: the hotkey tap feeds the § state
// machine, whose commands drive capture, transcription, ordered insertion, and
// the pill. This is the app-side core loop of P1.

import AppKit
import Combine
import Foundation
import WordFlowCore

@MainActor
final class DictationController: ObservableObject {
    enum PillState: Equatable {
        case hidden
        case starting      // capture requested, samples not yet flowing
        case listening     // audio flowing (AC-1.6)
        case locked        // hands-free
        case processing    // transcribing
    }

    @Published private(set) var pill: PillState = .hidden
    @Published private(set) var statusMessage: String?
    @Published private(set) var secureInputActive = false
    @Published private(set) var inFlight = 0
    @Published private(set) var level: Float = 0

    var isRecording: Bool { pill == .starting || pill == .listening || pill == .locked }

    private let stateMachine = HotkeyStateMachine()
    private let monitor = HotkeyMonitor()
    private let capture = MicCapture()
    private let inserter = TextInserter()
    private let client: BackendClient
    private let microphones: MicrophoneListModel
    private lazy var insertionQueue = InsertionQueue { [weak self] text in
        self?.performInsertion(text)
    }

    private var pendingTapTick: DispatchWorkItem?
    private var wasLockedAtStop = false
    private var secureInputTimer: Timer?
    private var messageClear: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(client: BackendClient, microphones: MicrophoneListModel) {
        self.client = client
        self.microphones = microphones
        monitor.onEvent = { [weak self] event in self?.feed(event) }
        monitor.isRecording = { [weak self] in self?.isRecording ?? false }
    }

    // MARK: - Lifecycle

    func start(hotkey: HotkeyKind) {
        monitor.setHotkey(hotkey)
        if !monitor.enable() {
            statusMessage = "Turn on Accessibility for WordFlow in System Settings so the hotkey can work."
        }
        capture.onFirstBuffer = { [weak self] in self?.onSamplesFlowing() }
        capture.onSpeech = { [weak self] in self?.feed(.speechDetected) }
        capture.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)
        startSecureInputPolling()
    }

    /// Clicking the pill cancels, the same as Esc (AC-8.2-a).
    func requestCancel() {
        feed(.escape)
    }

    func stop() {
        monitor.disable()
        secureInputTimer?.invalidate()
    }

    func setHotkey(_ kind: HotkeyKind) {
        monitor.setHotkey(kind)
    }

    /// Pause and resume disable/enable the tap, so § types normally while paused.
    func setPaused(_ paused: Bool, hotkey: HotkeyKind) {
        if paused { monitor.disable() } else { monitor.setHotkey(hotkey); monitor.enable() }
    }

    // MARK: - Event handling

    private func feed(_ event: HotkeyEvent) {
        let commands = stateMachine.handle(event)
        for command in commands { run(command) }
        scheduleTapTickIfNeeded()
    }

    private func scheduleTapTickIfNeeded() {
        pendingTapTick?.cancel()
        guard stateMachine.phase == .pendingTap else { return }
        let work = DispatchWorkItem { [weak self] in self?.feed(.tick) }
        pendingTapTick = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + stateMachine.doubleTapWindow + 0.05, execute: work)
    }

    private func run(_ command: HotkeyCommand) {
        switch command {
        case .startCapture:
            beginCapture()
        case .stopAndTranscribe:
            finishAndTranscribe()
        case .discardSilently:
            discard()
        case .enterLocked:
            pill = .locked
        case .cancel:
            cancel()
        }
    }

    // MARK: - Capture and transcription

    private func beginCapture() {
        pill = .starting
        wasLockedAtStop = false
        Task {
            if MicCapture.microphonePermission() == .undetermined {
                _ = await MicCapture.requestMicrophoneAccess()
            }
            guard MicCapture.microphonePermission() == .granted else {
                pill = .hidden
                flash("Turn on Microphone access for WordFlow in System Settings.")
                stateMachine.handle(.escape)  // reset the machine
                return
            }
            do {
                try await capture.start(deviceID: microphones.captureDeviceID)
            } catch {
                pill = .hidden
                flash("The microphone could not start: \(error.localizedDescription)")
                stateMachine.handle(.escape)
            }
        }
    }

    private func onSamplesFlowing() {
        if pill == .starting { pill = .listening }
    }

    private func finishAndTranscribe() {
        wasLockedAtStop = stateMachine.isLocked
        let target = inserter.frontmostTarget()
        let sequence = insertionQueue.submit()
        inFlight += 1
        pill = .processing
        let locked = wasLockedAtStop
        Task {
            let samples = await capture.stop()
            resetPillAfterStop()
            let wav = AudioWAV.wav(from: samples).base64EncodedString()
            do {
                let result = try await client.transcribe(
                    audioBase64: wav, sampleRate: AudioWAV.targetSampleRate,
                    targetApp: target.app, targetBundleID: target.bundleID, locked: locked)
                if result.nothing_heard {
                    insertionQueue.complete(sequence, text: nil)
                    flash("Nothing heard.")
                } else {
                    insertionQueue.complete(sequence, text: result.text)
                    if let id = result.dictation_id {
                        Task { await client.markInserted(id, inserted: true) }
                    }
                }
            } catch {
                insertionQueue.complete(sequence, text: nil)
                flash("That dictation could not be transcribed. It is in History if the backend recovers.")
            }
            inFlight = max(0, inFlight - 1)
        }
    }

    private func discard() {
        Task {
            await capture.cancel()
            resetPillAfterStop()
            flash("Nothing heard.")
        }
    }

    private func cancel() {
        pendingTapTick?.cancel()
        Task {
            await capture.cancel()
            pill = .hidden
        }
    }

    private func resetPillAfterStop() {
        // Keep the processing pill up only while something is in flight.
        pill = inFlight > 0 ? .processing : .hidden
    }

    private func performInsertion(_ text: String) {
        let outcome = inserter.insert(text)
        switch outcome {
        case .inserted: break
        case .clipboard: flash("No text field was focused, so the text is on the clipboard.")
        case .refusedSecureField: flash("A password field is focused, so nothing was inserted. It is in History.")
        case .nothing: break
        }
    }

    // MARK: - Secure input

    private func startSecureInputPolling() {
        secureInputTimer?.invalidate()
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let active = self.inserter.isSecureInputActive()
                if active != self.secureInputActive {
                    self.secureInputActive = active
                    if active {
                        self.flash("A password field is active, so dictation is paused. It resumes on its own.")
                    }
                }
            }
        }
    }

    // MARK: - Messages

    private func flash(_ message: String) {
        statusMessage = message
        messageClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.statusMessage = nil }
        messageClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
