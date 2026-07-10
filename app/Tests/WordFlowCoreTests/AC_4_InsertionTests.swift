// Section 4: the insertion decision — trailing newline strip, secure-field
// refusal, and the no-focus clipboard fallback.

import Testing
@testable import WordFlowCore

struct AC_4_InsertionTests {
    @Test("AC-4.7-a trailing whitespace and newlines are always stripped")
    func test_trailing_newline_stripped() {
        #expect(InsertionText.sanitise("run the build\n") == "run the build")
        #expect(InsertionText.sanitise("hello\n\n") == "hello")
        #expect(InsertionText.sanitise("hello \t\n ") == "hello")
        // Interior newlines are preserved; only the trailing run is removed.
        #expect(InsertionText.sanitise("line one\nline two\n") == "line one\nline two")
    }

    @Test("AC-4.1-a a focused field inserts the sanitised text at the cursor")
    func test_insert_at_cursor() {
        let route = InsertionText.plan(text: "hello\n", hasFocusedField: true, isSecureInput: false)
        #expect(route == .insertAtCursor("hello"))
    }

    @Test("AC-4.3-a no focused field routes to the clipboard")
    func test_clipboard_fallback() {
        let route = InsertionText.plan(text: "hello", hasFocusedField: false, isSecureInput: false)
        #expect(route == .clipboardOnly("hello"))
    }

    @Test("AC-4.4-a a secure field is never written to")
    func test_secure_field_refused() {
        let route = InsertionText.plan(text: "secret", hasFocusedField: true, isSecureInput: true)
        #expect(route == .refusedSecureField)
    }

    @Test("empty text after sanitising inserts nothing")
    func test_empty_is_nothing() {
        #expect(InsertionText.plan(text: "\n\n", hasFocusedField: true, isSecureInput: false) == .nothing)
    }
}
