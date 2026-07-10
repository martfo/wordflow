// The § press state machine: the highest-risk piece of the app, so it lives
// here as pure logic with an injected clock and is unit-tested without any
// hardware. It turns raw key events (down, up, escape) and a "speech detected"
// signal into the commands that drive capture, transcription, locking, and
// cancelling. See DESIGN.md for the full contract.

import Foundation

public enum HotkeyEvent: Equatable {
    case keyDown
    case keyUp
    case escape
    case speechDetected   // the first real audio arrived during this press
    case tick             // a timer nudge, so the tap-decision window can resolve
}

public enum HotkeyCommand: Equatable {
    case startCapture
    case stopAndTranscribe
    case discardSilently   // a short tap with no speech (AC-1.2-a)
    case enterLocked       // double-tap to lock hands-free (AC-1.3-a)
    case cancel            // Esc while recording (AC-1.4-a)
}

public enum HotkeyPhase: Equatable {
    case idle
    case holding      // key held down, deciding hold vs tap
    case pendingTap   // released after a short press, inside the double-tap window
    case locked       // hands-free
}

public final class HotkeyStateMachine {
    /// A hold of at least this long is a genuine hold-to-talk (AC-1.2-a boundary).
    public let holdThreshold: Double
    /// A second tap within this of the first tap's release locks (AC-1.3-a).
    public let doubleTapWindow: Double

    public private(set) var phase: HotkeyPhase = .idle

    private let clock: () -> Double
    private var pressDownAt: Double = 0
    private var tapReleasedAt: Double = 0
    private var speechSeen = false

    public init(
        holdThreshold: Double = 0.5, doubleTapWindow: Double = 0.4,
        clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
        self.clock = clock
    }

    /// Whether the pill should be showing (recording or about to resolve).
    public var isActive: Bool { phase != .idle }
    /// Whether we are in hands-free locked recording.
    public var isLocked: Bool { phase == .locked }

    @discardableResult
    public func handle(_ event: HotkeyEvent, now: Double? = nil) -> [HotkeyCommand] {
        let t = now ?? clock()
        switch phase {
        case .idle:
            return handleIdle(event, t)
        case .holding:
            return handleHolding(event, t)
        case .pendingTap:
            return handlePendingTap(event, t)
        case .locked:
            return handleLocked(event, t)
        }
    }

    private func handleIdle(_ event: HotkeyEvent, _ t: Double) -> [HotkeyCommand] {
        guard event == .keyDown else { return [] }
        pressDownAt = t
        speechSeen = false
        phase = .holding
        return [.startCapture]
    }

    private func handleHolding(_ event: HotkeyEvent, _ t: Double) -> [HotkeyCommand] {
        switch event {
        case .keyDown:
            return []  // auto-repeat while held; ignore
        case .speechDetected:
            speechSeen = true
            return []
        case .keyUp:
            if t - pressDownAt >= holdThreshold {
                phase = .idle
                return [.stopAndTranscribe]   // a genuine hold
            }
            // A short tap: wait to see whether a second tap locks.
            tapReleasedAt = t
            phase = .pendingTap
            return []
        case .escape:
            phase = .idle
            return [.cancel]
        case .tick:
            return []
        }
    }

    private func handlePendingTap(_ event: HotkeyEvent, _ t: Double) -> [HotkeyCommand] {
        switch event {
        case .keyDown:
            if t - tapReleasedAt <= doubleTapWindow {
                phase = .locked
                return [.enterLocked]
            }
            // Too late to be a double-tap: resolve the first tap, then this
            // key-down opens a fresh press.
            let resolved = resolveTap()
            pressDownAt = t
            speechSeen = false
            phase = .holding
            return resolved + [.startCapture]
        case .speechDetected:
            speechSeen = true
            return []
        case .escape:
            phase = .idle
            return [.cancel]
        case .tick, .keyUp:
            if t - tapReleasedAt > doubleTapWindow {
                phase = .idle
                return resolveTap()
            }
            return []
        }
    }

    private func handleLocked(_ event: HotkeyEvent, _ t: Double) -> [HotkeyCommand] {
        switch event {
        case .keyDown:
            phase = .idle
            return [.stopAndTranscribe]   // a single tap stops locked recording
        case .speechDetected:
            speechSeen = true
            return []
        case .escape:
            phase = .idle
            return [.cancel]
        case .keyUp, .tick:
            return []   // ignore the key-up from the locking tap, and idle ticks
        }
    }

    /// A lone short tap: transcribe if speech was heard, otherwise discard
    /// silently (AC-1.2-a).
    private func resolveTap() -> [HotkeyCommand] {
        [speechSeen ? .stopAndTranscribe : .discardSilently]
    }
}
