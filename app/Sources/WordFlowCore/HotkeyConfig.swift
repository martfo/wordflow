// The dictation hotkey: which key, and how to tell a lone press (which we
// swallow and use for dictation) from a modified press (which we pass through
// so the user can still type the character). Pure logic so the swallow rule and
// the ISO/ANSI default are unit-tested without an event tap.

import Foundation

public enum HotkeyKind: String, CaseIterable, Sendable {
    case rightControl   // Right ⌃, the default: a modifier, so it works even
                        // while another app has secure input on (character keys
                        // are suppressed then, modifier events are not)
    case rightCommand   // Right ⌘
    case fn             // the fn / Globe key
    case section        // §, only usable when secure input is off
    case f5

    /// The macOS virtual key code, where the key produces one (modifiers are
    /// observed through flag changes but still carry a key code).
    public var keyCode: UInt16 {
        switch self {
        case .rightControl: return 0x3E  // kVK_RightControl (62)
        case .rightCommand: return 0x36  // kVK_RightCommand
        case .fn: return 0x3F            // kVK_Function
        case .section: return 0x0A       // kVK_ISO_Section
        case .f5: return 0x60            // kVK_F5
        }
    }

    /// True when the key is really a modifier, so the tap watches flagsChanged
    /// rather than keyDown/keyUp. Modifier hotkeys survive secure input.
    public var isModifierKey: Bool {
        self == .rightControl || self == .rightCommand || self == .fn
    }

    public var display: String {
        switch self {
        case .rightControl: return "Right Control"
        case .rightCommand: return "Right Command"
        case .fn: return "fn"
        case .section: return "§"
        case .f5: return "F5"
        }
    }
}

public struct HotkeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift = HotkeyModifiers(rawValue: 1 << 3)
}

public enum Hotkey {
    /// The default hotkey for a keyboard: § where the layout has a § key,
    /// otherwise Right ⌘ (AC-1.5-c).
    public static func defaultKind(hasSectionKey: Bool) -> HotkeyKind {
        hasSectionKey ? .section : .rightCommand
    }

    /// Whether a key event should start (or drive) dictation. A character key
    /// like § triggers only when pressed with no other modifier, so ⇧§, ⌥§, ⌘§
    /// pass straight through to the app (AC-1.1-d). Modifier-key hotkeys (Right
    /// ⌘, fn) trigger on their own toggle.
    public static func triggersDictation(
        kind: HotkeyKind, keyCode: UInt16, modifiers: HotkeyModifiers
    ) -> Bool {
        guard keyCode == kind.keyCode else { return false }
        if kind.isModifierKey { return true }
        return modifiers.isEmpty
    }

    /// Whether the tap should swallow this event so it never types a character.
    /// Only a triggering, unmodified character key is swallowed; a modified
    /// combination is passed through untouched.
    public static func swallows(
        kind: HotkeyKind, keyCode: UInt16, modifiers: HotkeyModifiers
    ) -> Bool {
        triggersDictation(kind: kind, keyCode: keyCode, modifiers: modifiers)
    }
}

/// Persists the chosen hotkey across launches (AC-1.5-b).
public struct HotkeyPreference {
    static let kindKey = "hotkeyKind"
    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func save(_ kind: HotkeyKind) {
        store.set(kind.rawValue, forKey: Self.kindKey)
    }

    public func restore(defaultKind: HotkeyKind) -> HotkeyKind {
        guard let raw = store.string(forKey: Self.kindKey),
              let kind = HotkeyKind(rawValue: raw) else { return defaultKind }
        return kind
    }
}
