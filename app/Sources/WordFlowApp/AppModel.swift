// The app's shared state: the supervised backend, the dictation controller, the
// microphone list, the pill, and the persisted hotkey and model choice. On first
// launch of the installed app it provisions the Python backend into Application
// Support before booting it (AC-12.1-b); in a dev run the backend is found via
// environment variables and setup is skipped.

import AppKit
import Combine
import Foundation
import SwiftUI
import WordFlowCore

@MainActor
final class AppModel: ObservableObject {
    let client = BackendClient()
    let microphones = MicrophoneListModel()
    let controller: DictationController
    let supervisor: BackendSupervisor
    private let pillController = PillController()
    private let setupWindow = SetupWindowController()

    @Published var hotkeyKind: HotkeyKind {
        didSet {
            HotkeyPreference(store: UserDefaults.standard).save(hotkeyKind)
            controller.setHotkey(hotkeyKind)
        }
    }
    @Published var paused = false {
        didSet { controller.setPaused(paused, hotkey: hotkeyKind) }
    }
    @Published private(set) var activeModel = "parakeet"
    @Published private(set) var backendState: BackendSupervisor.State = .starting
    @Published var settingsTab: SettingsTab = .general

    /// First-run setup progress, shown in the setup window.
    enum SetupPhase: Equatable {
        case ready
        case needsSetup
        case working(String)
        case failed(String)
    }
    @Published private(set) var setup: SetupPhase = .ready

    enum SettingsTab: Hashable {
        case general, microphone, model, cleanup, dictationData
    }

    private let configPath: String
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Right Control by default: a modifier, so it works even while another
        // app holds macOS secure input (which suppresses character keys like §
        // but not modifier events). The user can pick another key in Settings.
        let kind = HotkeyPreference(store: UserDefaults.standard).restore(defaultKind: .rightControl)
        self.hotkeyKind = kind

        let config = AppSetup.ensure()
        self.configPath = config.path
        self.controller = DictationController(client: client, microphones: microphones)
        self.supervisor = BackendSupervisor(client: client, configPath: config.path)

        controller.start(hotkey: kind)
        pillController.attach(to: controller)

        supervisor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.backendState = state
                if case .running(let model, _) = state { self?.activeModel = model }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.stop()
                self?.supervisor.stop()
            }
        }

        // Boot the backend if it can already run; otherwise present first-run
        // setup and boot once it finishes.
        if BackendSupervisor.pythonExecutable() != nil {
            setup = .ready
            supervisor.start()
        } else {
            setup = .needsSetup
            setupWindow.present(model: self)
        }
    }

    // MARK: - First-run setup

    func runSetup() {
        guard let installer = RealRuntimeInstaller() else {
            setup = .failed("This build is missing its bundled backend, so it cannot set itself up.")
            return
        }
        setup = .working("Starting…")
        let runtime = RuntimeLocation.runtimeDirectory()
        let configPath = self.configPath
        Task.detached(priority: .userInitiated) {
            let provisioner = Provisioner(runtime: runtime, installer: installer)
            provisioner.onStep = { step in
                Task { @MainActor in self.setup = .working(step) }
            }
            let result = provisioner.provision()
            if case .failed(let message) = result {
                await MainActor.run { self.setup = .failed(message) }
                return
            }
            // Fetch the speech models if they are not already in the cache.
            if !Self.modelsPresent() {
                await MainActor.run { self.setup = .working("Downloading the speech models (about 2 GB, once)…") }
                do {
                    try Self.downloadModels(runtime: runtime, configPath: configPath)
                } catch {
                    await MainActor.run {
                        self.setup = .failed("The models could not be downloaded: \(error.localizedDescription) Check the network and try again.")
                    }
                    return
                }
            }
            await MainActor.run {
                self.setup = .ready
                self.setupWindow.dismiss()
                self.supervisor.start()
            }
        }
    }

    /// Whether the speech models are already in the Hugging Face cache.
    nonisolated static func modelsPresent() -> Bool {
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        let parakeet = hub.appendingPathComponent("models--mlx-community--parakeet-tdt-0.6b-v2")
        return FileManager.default.fileExists(atPath: parakeet.path)
    }

    nonisolated private static func downloadModels(runtime: URL, configPath: String) throws {
        let python = runtime.appendingPathComponent("venv/bin/python3")
        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "wordflow.download", configPath]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8)?.suffix(300) ?? ""
            throw NSError(domain: "WordFlow", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(detail)])
        }
    }

    func switchModel(_ name: String) {
        activeModel = name
        Task { try? await client.switchModel(name) }
    }

    var backendSummary: String {
        switch backendState {
        case .starting: return "Starting the backend…"
        case .running(let model, let loaded):
            return loaded ? "Ready with \(model)" : "Loading \(model)…"
        case .down(let message): return message
        }
    }
}
