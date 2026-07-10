// Deciding what to do with a finished transcript, as pure logic so the rules
// are tested without a real focused field. Trailing whitespace and newlines are
// always stripped, so dictating into a terminal never executes the text
// (AC-4.7); a secure field is never written to (AC-4.4); with no focused field
// the text goes to the clipboard and the pill says so (AC-4.3).

import Foundation

public enum InsertionRoute: Equatable {
    case insertAtCursor(String)
    case clipboardOnly(String)
    case refusedSecureField
    case nothing
}

public enum InsertionText {
    /// Strip trailing whitespace and newlines. The cleanup pipeline already
    /// trims, but insertion strips again as a guarantee at the boundary.
    public static func sanitise(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            if text[previous].isNewline || text[previous] == " " || text[previous] == "\t" {
                end = previous
            } else {
                break
            }
        }
        return String(text[text.startIndex..<end])
    }

    public static func plan(
        text: String, hasFocusedField: Bool, isSecureInput: Bool
    ) -> InsertionRoute {
        let clean = sanitise(text)
        if clean.isEmpty { return .nothing }
        if isSecureInput { return .refusedSecureField }
        if !hasFocusedField { return .clipboardOnly(clean) }
        return .insertAtCursor(clean)
    }
}
