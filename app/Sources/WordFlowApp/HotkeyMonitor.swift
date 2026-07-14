// The global hotkey as a CGEventTap on keyDown, keyUp, and flagsChanged.
//
// The default trigger is a modifier (Right Control), observed through
// flagsChanged: macOS secure input suppresses character key events to taps but
// still delivers modifier events, so a modifier hotkey keeps working while
// another app holds secure input (a character key like § would go dead then).
// Modifiers are passed through, not swallowed. A character-key hotkey (§, F5) is
// still supported and is swallowed while active so it never types; it works only
// when secure input is off. The tap needs the Accessibility permission.

import AppKit
import CoreGraphics
import WordFlowCore

@MainActor
final class HotkeyMonitor {
    /// Raw key events, already mapped, delivered on the main actor.
    var onEvent: ((HotkeyEvent) -> Void)?
    /// The controller reports whether it is recording, so Esc is swallowed only
    /// then (never stealing the Esc key the rest of the time).
    var isRecording: (() -> Bool)?

    private(set) var kind: HotkeyKind = .section
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierKeyDown = false

    private let escapeKeyCode: UInt16 = 0x35
    // Device-dependent modifier bits carried in the raw event flags.
    private let rightControlMask: UInt64 = 0x2000
    private let rightCommandMask: UInt64 = 0x10
    private let fnMask: UInt64 = 0x800000

    func setHotkey(_ kind: HotkeyKind) {
        self.kind = kind
        modifierKeyDown = false
    }

    /// Start swallowing and reporting the hotkey. Returns false when the tap
    /// could not be created, which almost always means Accessibility is off.
    @discardableResult
    func enable() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon) else {
            wfLog("tapCreate FAILED (returned nil): accessibility not effective for tap creation")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        wfLog("tap created; isEnabled=\(CGEvent.tapIsEnabled(tap: tap)); hotkey=\(kind.rawValue) keyCode=\(kind.keyCode)")
        return true
    }

    /// Stop swallowing the key. § types normally again immediately.
    func disable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.tap = nil
            self.runLoopSource = nil
        }
    }

    // nonisolated so the C callback can call it; it only touches the main actor
    // via the assumeIsolated below, since the tap runs on the main run loop.
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        MainActor.assumeIsolated {
            // The system disables the tap after a slow callback; re-enable it.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                wfLog("tap disabled (type \(type.rawValue)); re-enabling")
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            // Esc while recording cancels; swallow it only then.
            if type == .keyDown, keyCode == escapeKeyCode {
                if isRecording?() == true {
                    onEvent?(.escape)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            if kind.isModifierKey {
                if type == .flagsChanged, keyCode == kind.keyCode {
                    let down = isModifierDown(flags)
                    if down != modifierKeyDown {
                        modifierKeyDown = down
                        onEvent?(down ? .keyDown : .keyUp)
                    }
                }
                return Unmanaged.passUnretained(event)   // modifiers are not swallowed
            }

            // A character-key hotkey such as §.
            guard keyCode == kind.keyCode, type == .keyDown || type == .keyUp else {
                return Unmanaged.passUnretained(event)
            }
            let modifiers = Self.modifiers(from: flags)
            guard Hotkey.triggersDictation(kind: kind, keyCode: keyCode, modifiers: modifiers) else {
                return Unmanaged.passUnretained(event)   // ⇧§/⌥§/⌘§ pass through (AC-1.1-d)
            }
            onEvent?(type == .keyDown ? .keyDown : .keyUp)
            return nil   // swallow, so § never types (AC-1.1-c)
        }
    }

    private func isModifierDown(_ flags: CGEventFlags) -> Bool {
        switch kind {
        case .rightControl: return flags.rawValue & rightControlMask != 0
        case .rightCommand: return flags.rawValue & rightCommandMask != 0
        case .fn: return flags.rawValue & fnMask != 0
        default: return false
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> HotkeyModifiers {
        var modifiers: HotkeyModifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }
}
