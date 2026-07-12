// Drives one dictation's microphone capture: AVAudioEngine input tap, resampled
// to 16 kHz mono and accumulated as floats. A single-channel reduction of
// Polenta's CaptureController, with no system-audio tap. The mic is opened per
// dictation and torn down on stop, never kept always-on. The first real buffer
// flips the pill from stream-starting to listening, so the first word is never
// clipped (AC-1.6).

import AVFoundation
import CoreAudio
import Foundation
import WordFlowCore

/// A short tail kept recording after the key is released, so the last word is
/// not cut off mid-syllable. File-scoped so the nonisolated capture callback can
/// read it.
private let micTailPadSeconds: TimeInterval = 0.3

@MainActor
final class MicCapture: ObservableObject {
    @Published var level: Float = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isFlowing = false   // true once samples arrive

    nonisolated(unsafe) private let engine = AVAudioEngine()
    nonisolated(unsafe) private var samples: [Float] = []
    private let accumulationQueue = DispatchQueue(label: "capture.accumulate")
    private let ioQueue = DispatchQueue(label: "capture.io")

    // Set by the controller before start.
    nonisolated(unsafe) var onFirstBuffer: (() -> Void)?
    nonisolated(unsafe) var onSpeech: (() -> Void)?
    nonisolated(unsafe) private var sawFirstBuffer = false
    nonisolated(unsafe) private var sawSpeech = false

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func microphonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .undetermined
        }
    }

    func start(deviceID: AudioDeviceID?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async {
                do {
                    try self.performStart(deviceID: deviceID)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        isCapturing = true
        isFlowing = false
    }

    nonisolated private func performStart(deviceID: AudioDeviceID?) throws {
        accumulationQueue.sync {
            samples = []
            sawFirstBuffer = false
            sawSpeech = false
        }
        if let deviceID {
            try selectInput(device: deviceID)
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let inputRate = format.sampleRate
        guard format.channelCount > 0, inputRate > 0 else {
            throw CaptureError.noInputDevice
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let mono = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let level = LevelMeter.level(of: mono)
            let resampled = AudioWAV.resample(mono, from: inputRate)
            self.accumulationQueue.async {
                self.samples.append(contentsOf: resampled)
                if !self.sawFirstBuffer {
                    self.sawFirstBuffer = true
                    let cb = self.onFirstBuffer
                    Task { @MainActor in self.isFlowing = true; cb?() }
                }
                if !self.sawSpeech, LevelMeter.containsSpeech(mono) {
                    self.sawSpeech = true
                    let cb = self.onSpeech
                    Task { @MainActor in cb?() }
                }
            }
            Task { @MainActor in self.level = level }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stop and return the accumulated 16 kHz mono samples.
    func stop() async -> [Float] {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[Float], Never>) in
            ioQueue.async { continuation.resume(returning: self.performStop()) }
        }
        isCapturing = false
        isFlowing = false
        level = 0
        return result
    }

    /// Stop and discard everything (Esc cancel).
    func cancel() async {
        _ = await stop()
    }

    nonisolated private func performStop() -> [Float] {
        // The engine and tap are still live during this pad, so the trailing
        // audio keeps accumulating before we tear down.
        Thread.sleep(forTimeInterval: micTailPadSeconds)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return accumulationQueue.sync { samples }
    }

    nonisolated private func selectInput(device: AudioDeviceID) throws {
        guard let unit = engine.inputNode.audioUnit else { return }
        var deviceID = device
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
            0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw CaptureError.coreAudio(status) }
    }
}

enum CaptureError: LocalizedError {
    case noInputDevice
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available. Check the input device in Settings."
        case .coreAudio(let status):
            return "The microphone could not be opened (Core Audio error \(status))."
        }
    }
}

// MARK: - Input device listing for the picker (ported from Polenta)

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    static let systemDefaultUID = "system-default"
    static let systemDefault = InputDevice(
        id: AudioDeviceID(kAudioObjectUnknown),
        uid: systemDefaultUID,
        name: "Follow system default")

    var captureDeviceID: AudioDeviceID? {
        uid == InputDevice.systemDefaultUID ? nil : id
    }

    static func allWithDefault() -> [InputDevice] {
        [systemDefault] + all()
    }

    static func all() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(deviceID) > 0,
                  let name = stringProperty(deviceID, kAudioObjectPropertyName),
                  let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return InputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let listPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { listPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, listPointer) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(
            listPointer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (value as String) : nil
    }
}
