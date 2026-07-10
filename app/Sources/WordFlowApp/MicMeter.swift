// A metering-only microphone session for the Settings level meter, so the user
// can confirm the right mic before relying on it (AC-7.2). It runs only while
// the Microphone settings tab is on screen; there is no always-on microphone.

import AVFoundation
import CoreAudio
import Foundation
import WordFlowCore

@MainActor
final class MicMeter: ObservableObject {
    @Published var level: Float = 0

    nonisolated(unsafe) private let engine = AVAudioEngine()
    private var running = false

    func start(deviceID: AudioDeviceID?) {
        guard !running, MicCapture.microphonePermission() == .granted else { return }
        if let deviceID, let unit = engine.inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let mono = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let level = LevelMeter.level(of: mono)
            Task { @MainActor in self.level = level }
        }
        engine.prepare()
        try? engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
    }
}
