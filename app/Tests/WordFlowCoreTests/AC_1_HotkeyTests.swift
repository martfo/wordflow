// Section 1: the hotkey. The § state machine is the highest-risk piece, so it
// is exercised here in full with a stubbed clock, plus the swallow/passthrough
// rule and the ISO/ANSI default.

import Testing
@testable import WordFlowCore

private final class Clock {
    var now: Double = 0
    func read() -> Double { now }
}

private func machine(_ clock: Clock) -> HotkeyStateMachine {
    HotkeyStateMachine(holdThreshold: 0.5, doubleTapWindow: 0.4, clock: clock.read)
}

struct AC_1_HotkeyTests {
    @Test("AC-1.1-a/b hold then release captures and transcribes")
    func test_hold_to_talk() {
        let clock = Clock()
        let sm = machine(clock)
        #expect(sm.handle(.keyDown) == [.startCapture])
        #expect(sm.phase == .holding)
        clock.now = 1.0  // held for a second
        #expect(sm.handle(.keyUp) == [.stopAndTranscribe])
        #expect(sm.phase == .idle)
    }

    @Test("AC-1.1-c auto-repeat key-downs while held do nothing")
    func test_autorepeat_ignored() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown)
        #expect(sm.handle(.keyDown) == [])   // auto-repeat
        #expect(sm.handle(.keyDown) == [])
        #expect(sm.phase == .holding)
    }

    @Test("AC-1.1-d § with a modifier passes through and does not trigger")
    func test_modifier_passthrough() {
        let section = HotkeyKind.section.keyCode
        #expect(Hotkey.triggersDictation(kind: .section, keyCode: section, modifiers: []))
        #expect(Hotkey.swallows(kind: .section, keyCode: section, modifiers: []))
        for mod in [HotkeyModifiers.shift, .option, .command, .control] {
            #expect(!Hotkey.triggersDictation(kind: .section, keyCode: section, modifiers: mod))
            #expect(!Hotkey.swallows(kind: .section, keyCode: section, modifiers: mod))
        }
    }

    @Test("AC-1.2-a a short tap with no speech discards silently")
    func test_short_tap_no_speech_discards() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown)
        clock.now = 0.2  // under 500 ms, no speech seen
        #expect(sm.handle(.keyUp) == [])           // waits for the double-tap window
        #expect(sm.phase == .pendingTap)
        clock.now = 0.7  // window elapsed
        #expect(sm.handle(.tick) == [.discardSilently])
        #expect(sm.phase == .idle)
    }

    @Test("a short tap that did carry speech is transcribed, not discarded")
    func test_short_tap_with_speech_transcribes() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown)
        _ = sm.handle(.speechDetected)
        clock.now = 0.2
        _ = sm.handle(.keyUp)
        clock.now = 0.7
        #expect(sm.handle(.tick) == [.stopAndTranscribe])
    }

    @Test("AC-1.3-a double-tap within the window locks")
    func test_double_tap_locks() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown)
        clock.now = 0.15
        _ = sm.handle(.keyUp)          // first tap, short
        clock.now = 0.30              // within 400 ms of release
        #expect(sm.handle(.keyDown) == [.enterLocked])
        #expect(sm.isLocked)
    }

    @Test("AC-1.3-b a single tap while locked stops and transcribes")
    func test_locked_single_tap_stops() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown); clock.now = 0.15; _ = sm.handle(.keyUp)
        clock.now = 0.30; _ = sm.handle(.keyDown)   // locks
        _ = sm.handle(.keyUp)                        // the locking tap's release, ignored
        #expect(sm.phase == .locked)
        clock.now = 3.0
        #expect(sm.handle(.keyDown) == [.stopAndTranscribe])
        #expect(sm.phase == .idle)
    }

    @Test("AC-1.4-a Esc while recording cancels with nothing inserted")
    func test_escape_cancels() {
        let clock = Clock()
        let sm = machine(clock)
        _ = sm.handle(.keyDown)
        #expect(sm.handle(.escape) == [.cancel])
        #expect(sm.phase == .idle)
        // Also from locked.
        _ = sm.handle(.keyDown); clock.now = 0.15; _ = sm.handle(.keyUp)
        clock.now = 0.3; _ = sm.handle(.keyDown)
        #expect(sm.handle(.escape) == [.cancel])
    }

    @Test("AC-1.5-c the default hotkey is § on ISO, Right ⌘ on ANSI")
    func test_default_hotkey_by_layout() {
        #expect(Hotkey.defaultKind(hasSectionKey: true) == .section)
        #expect(Hotkey.defaultKind(hasSectionKey: false) == .rightCommand)
    }

    @Test("AC-1.5-b the chosen hotkey persists")
    func test_hotkey_preference_round_trip() {
        let store = MemoryStore()
        HotkeyPreference(store: store).save(.f5)
        #expect(HotkeyPreference(store: store).restore(defaultKind: .section) == .f5)
        #expect(HotkeyPreference(store: MemoryStore()).restore(defaultKind: .section) == .section)
    }
}
