// Inserting the cleaned transcript at the cursor of the frontmost app. The
// primary path is the Accessibility API (text at the caret, not appended); the
// fallback is a clipboard paste with the prior pasteboard fully restored across
// every representation type, not just strings (AC-4.2). A secure field is never
// written to (AC-4.4), and a trailing newline is always stripped so dictating
// into a terminal never executes the text (AC-4.7).

import AppKit
import ApplicationServices
import Carbon
import WordFlowCore

enum InsertionOutcome: Equatable {
    case inserted
    case clipboard          // no focused field; left on the clipboard (AC-4.3)
    case refusedSecureField // secure input active (AC-4.4)
    case nothing
}

@MainActor
final class TextInserter {
    struct Target {
        let app: String?
        let bundleID: String?
    }

    func frontmostTarget() -> Target {
        let app = NSWorkspace.shared.frontmostApplication
        return Target(app: app?.localizedName, bundleID: app?.bundleIdentifier)
    }

    /// macOS secure input (a password field) suppresses event taps entirely, so
    /// the hotkey may not fire; we also never inject into one.
    func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }

    func insert(_ rawText: String) -> InsertionOutcome {
        let route = InsertionText.plan(
            text: rawText,
            hasFocusedField: hasFocusedTextField(),
            isSecureInput: isSecureInputActive())
        switch route {
        case .nothing:
            return .nothing
        case .refusedSecureField:
            return .refusedSecureField
        case .clipboardOnly(let text):
            place(onClipboard: text)
            return .clipboard
        case .insertAtCursor(let text):
            // A clipboard paste is used rather than the Accessibility set-value
            // API: many apps (Electron, web views) accept the AX set and then
            // silently drop it, so nothing would appear. Cmd-V pastes at the
            // caret and works everywhere; the prior clipboard is restored after.
            pasteViaClipboard(text)
            return .inserted
        }
    }

    // MARK: - Accessibility

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let element = focused else { return nil }
        return (element as! AXUIElement)
    }

    private func hasFocusedTextField() -> Bool {
        // Any focused element (a text field, a web area, an Electron input)
        // means we can paste at the caret. Only when nothing at all is focused
        // do we fall back to leaving the text on the clipboard (AC-4.3).
        focusedElement() != nil
    }

    // MARK: - Clipboard

    private func place(onClipboard text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCommandV()
        // Restore the user's clipboard once the paste has been delivered. The
        // delay is generous so slower apps have finished reading the pasteboard
        // before it is put back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.restorePasteboard(pasteboard, from: snapshot)
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    stored[type.rawValue] = data
                }
            }
            return stored
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from snapshot: [[String: Data]]) {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
