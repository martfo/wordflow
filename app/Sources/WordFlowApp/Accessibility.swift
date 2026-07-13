// Helpers for the Accessibility permission the hotkey tap and text insertion
// need. macOS does not prompt automatically for an event tap, so we ask the
// system to show its own grant dialog (which pre-adds WordFlow to the list) and
// offer a direct link to the exact Settings pane, rather than making the user
// hunt for it.

import AppKit
import ApplicationServices

enum Accessibility {
    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Show the system "…would like to control this computer" dialog once,
    /// which adds WordFlow to the Accessibility list and offers to open Settings.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Open System Settings straight at Privacy & Security → Accessibility.
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
