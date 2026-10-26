// Drives one dictation's microphone capture: an AVCaptureSession audio data
// output delivering 16 kHz mono float, accumulated as samples. A single-channel
// reduction of Polenta's CaptureController, with no system-audio tap. The mic is
// opened per dictation and torn down on stop, never kept always-on. The first
// real buffer flips the pill from stream-starting to listening, so the first
// word is never clipped (AC-1.6).
//
// AVCaptureSession rather than AVAudioEngine: the engine is full duplex, and a
// Bluetooth headset (AirPods) renegotiates both its input and output when the
// mic engages, which stops the engine mid-start and starves it of audio. A
// capture session is input-only, opens the exact device by its UID, and rides
// through the headset's switch into microphone mode on its own.

import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import WordFlowCore
import WordFlowObjCSupport

/// A short tail kept recording after the key is released, so the last word is
/// not cut off mid-syllable. File-scoped so the nonisolated capture callback can
/// read it.
private let micTailPadSeconds: TimeInterval = 0.3

@MainActor
final class MicCapture: ObservableObject {
    @Published var level: Float = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isFlowing = false   // true once samples arrive

    nonisolated(unsafe) private var session: AVCaptureSession?
    nonisolated(unsafe) private var runtimeErrorObserver: NSObjectProtocol?
    nonisolated(unsafe) private var samples: [Float] = []
    private let accumulationQueue = DispatchQueue(label: "capture.accumulate")
    private let ioQueue = DispatchQueue(label: "capture.io")
    private let sampleQueue = DispatchQueue(label: "capture.samples")
    nonisolated(unsafe) private let receiver = SampleReceiver()

    // Set by the controller before start.
    nonisolated(unsafe) var onFirstBuffer: (() -> Void)?
    nonisolated(unsafe) var onSpeech: (() -> Void)?
    nonisolated(unsafe) private var sawFirstBuffer = false
    nonisolated(unsafe) private var sawSpeech = false

    init() {
        receiver.onSamples = { [weak self] mono, rate in self?.consume(mono, rate: rate) }
    }

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
        tearDownSession()

        guard let device = Self.captureDevice(for: deviceID) else {
            wfLog("capture start: no capture device (pinned=\(deviceID.map { "\($0)" } ?? "system-default"))")
            throw CaptureError.noInputDevice
        }

        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        // Ask the session for exactly what the backend wants, so no resampling.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioWAV.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(receiver, queue: sampleQueue)

        // Session configuration can raise Objective-C exceptions on a device in a
        // bad state; uncaught they abort the app. Contain them so a mic hiccup
        // fails this one dictation instead.
        var configError: Error?
        var raised: NSError?
        let ran = WFRunCatchingExceptions({
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                if session.canAddInput(input) { session.addInput(input) } else { configError = CaptureError.noInputDevice }
                if session.canAddOutput(output) { session.addOutput(output) } else { configError = CaptureError.noInputDevice }
                session.commitConfiguration()
                if configError == nil { session.startRunning() }
            } catch {
                configError = error
            }
        }, &raised)

        guard ran, configError == nil, session.isRunning else {
            session.stopRunning()
            let detail = configError?.localizedDescription ?? raised?.localizedDescription ?? "the capture session did not start"
            wfLog("capture start failed on \(device.localizedName): \(detail)")
            if let configError { throw configError }
            throw CaptureError.engineFailed(raised?.localizedDescription)
        }

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            wfLog("capture runtime error: \(error?.localizedDescription ?? "unknown")")
        }
        self.session = session
        wfLog("capture start: \(device.localizedName) [\(device.uniqueID)] running")
    }

    /// Runs on the sample queue for every delivered buffer.
    nonisolated private func consume(_ mono: [Float], rate: Double) {
        guard !mono.isEmpty else { return }
        let level = LevelMeter.level(of: mono)
        let resampled = AudioWAV.resample(mono, from: rate)   // no-op at 16 kHz
        accumulationQueue.async {
            self.samples.append(contentsOf: resampled)
            if !self.sawFirstBuffer {
                self.sawFirstBuffer = true
                wfLog("capture first buffer: \(mono.count) frames at \(rate) Hz")
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
        // The session is still live during this pad, so the trailing audio keeps
        // accumulating before we tear down.
        Thread.sleep(forTimeInterval: micTailPadSeconds)
        tearDownSession()
        sampleQueue.sync {}   // let any in-flight buffer callback finish
        let result = accumulationQueue.sync { samples }
        let flowed = accumulationQueue.sync { sawFirstBuffer }
        wfLog("capture stop: samples=\(result.count) sawAudio=\(flowed)")
        return result
    }

    nonisolated private func tearDownSession() {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
            self.runtimeErrorObserver = nil
        }
        session?.stopRunning()
        session = nil
    }

    /// The capture device for a picked Core Audio device, falling back to the
    /// system default input when nothing is pinned or the pinned device is gone.
    nonisolated private static func captureDevice(for deviceID: AudioDeviceID?) -> AVCaptureDevice? {
        if let deviceID, let uid = deviceUID(deviceID), let device = AVCaptureDevice(uniqueID: uid) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }

    nonisolated private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (value as String) : nil
    }
}

/// Receives audio sample buffers from the capture session and hands them on as
/// mono floats with their sample rate.
private final class SampleReceiver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onSamples: (([Float], Double) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { return }
        var list = AudioBufferList()
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block)
        guard status == noErr, let data = list.mBuffers.mData else { return }
        let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        let samples = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
        onSamples?(samples, format.mSampleRate)
    }
}

enum CaptureError: LocalizedError {
    case noInputDevice
    case coreAudio(OSStatus)
    case engineFailed(String?)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available. Check the input device in Settings."
        case .coreAudio(let status):
            return "The microphone could not be opened (Core Audio error \(status))."
        case .engineFailed(let detail):
            let base = "The microphone could not be opened. Try again, or pick a different input in Settings."
            return detail.map { "\(base) (\($0))" } ?? base
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
