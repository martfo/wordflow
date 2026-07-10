// Section 2: audio encoding to the 16 kHz mono WAV the backend decodes, and the
// level/speech metering that drives the pill and the tap decision.

import Foundation
import Testing
@testable import WordFlowCore

struct AC_2_AudioTests {
    @Test("AC-2.5-a resample to 16 kHz mono and a valid WAV header")
    func test_wav_16k_mono() {
        // One second at 48 kHz resamples to ~16 kHz.
        let input = [Float](repeating: 0.5, count: 48_000)
        let resampled = AudioWAV.resample(input, from: 48_000)
        #expect(abs(resampled.count - 16_000) <= 1)

        let wav = AudioWAV.wav(from: resampled)
        #expect(wav.count == 44 + resampled.count * 2)
        #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        let channels = wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 22, as: UInt16.self) }
        let rate = wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self) }
        let bits = wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 34, as: UInt16.self) }
        #expect(channels == 1)
        #expect(rate == 16_000)
        #expect(bits == 16)
    }

    @Test("level metering and the speech gate")
    func test_levels_and_speech_gate() {
        let loud = [Float](repeating: 0.5, count: 1_000)
        let quiet = [Float](repeating: 0.005, count: 1_000)
        #expect(abs(LevelMeter.level(of: loud) - 0.5) < 0.001)
        #expect(LevelMeter.level(of: []) == 0)
        // The speech gate distinguishes a real utterance from room noise, so a
        // sub-500 ms tap with only quiet noise is discarded (AC-1.2-a).
        #expect(LevelMeter.containsSpeech(loud))
        #expect(!LevelMeter.containsSpeech(quiet))
    }
}
