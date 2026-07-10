// Input level readings and first-real-audio detection. The pill switches from
// stream-starting to listening only once samples are actually flowing, so the
// first word is never clipped (AC-1.6). Ported from Polenta and extended with a
// speech gate for the tap-versus-hold decision.

import Foundation

public enum LevelMeter {
    /// Root-mean-square level of a buffer, 0 to 1.
    public static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return min(1, (sumOfSquares / Float(samples.count)).squareRoot())
    }

    /// Above this level a buffer counts as speech rather than room noise, used
    /// to decide whether a sub-500 ms tap carried anything worth transcribing
    /// (AC-1.2-a).
    public static let speechThreshold: Float = 0.02

    public static func containsSpeech(_ samples: [Float]) -> Bool {
        level(of: samples) >= speechThreshold
    }
}
