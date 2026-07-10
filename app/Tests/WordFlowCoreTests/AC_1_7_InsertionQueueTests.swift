// AC-1.7: back-to-back dictations insert in spoken order even when their
// transcriptions finish out of order.

import Testing
@testable import WordFlowCore

struct AC_1_7_InsertionQueueTests {
    @Test("AC-1.7-a completions out of order still insert in spoken order")
    func test_in_order_insertion() {
        var inserted: [String] = []
        let queue = InsertionQueue { inserted.append($0) }
        let a = queue.submit()   // spoken first
        let b = queue.submit()   // spoken second
        let c = queue.submit()   // spoken third

        // The second finishes first: nothing inserts yet, because A is still out.
        queue.complete(b, text: "second")
        #expect(inserted.isEmpty)
        // A finishes: A then B flush together, in order.
        queue.complete(a, text: "first")
        #expect(inserted == ["first", "second"])
        // C finishes last and inserts last.
        queue.complete(c, text: "third")
        #expect(inserted == ["first", "second", "third"])
        #expect(queue.pending == 0)
    }

    @Test("a cancelled or empty dictation advances the queue without inserting")
    func test_empty_slot_does_not_block() {
        var inserted: [String] = []
        let queue = InsertionQueue { inserted.append($0) }
        let a = queue.submit()
        let b = queue.submit()
        queue.complete(a, text: nil)      // nothing heard / cancelled
        queue.complete(b, text: "after")
        #expect(inserted == ["after"])
    }
}
