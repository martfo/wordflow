// Recording never waits for processing: a new dictation can start while the
// previous one is still transcribing (AC-1.7). Transcriptions may finish out of
// order, but text must be inserted in the order it was spoken. This queue holds
// completed results until every earlier one has been inserted, then flushes in
// submission order. Used on the main actor; no internal locking.

import Foundation

public final class InsertionQueue {
    private var submittedCount = 0
    private var nextToInsert = 0
    private var completed = Set<Int>()
    private var texts: [Int: String] = [:]
    private let insert: (String) -> Void

    public init(insert: @escaping (String) -> Void) {
        self.insert = insert
    }

    /// Reserve the next slot in spoken order; call when a dictation's audio is
    /// handed off. Returns its sequence number.
    public func submit() -> Int {
        defer { submittedCount += 1 }
        return submittedCount
    }

    /// A dictation finished. `text` is nil when there is nothing to insert (a
    /// cancel, or nothing heard): the slot still advances so it never blocks the
    /// ones behind it.
    public func complete(_ sequence: Int, text: String?) {
        completed.insert(sequence)
        if let text { texts[sequence] = text }
        flush()
    }

    private func flush() {
        while completed.contains(nextToInsert) {
            if let text = texts[nextToInsert] {
                insert(text)
            }
            completed.remove(nextToInsert)
            texts[nextToInsert] = nil
            nextToInsert += 1
        }
    }

    /// The number of dictations submitted but not yet inserted, for the pill.
    public var pending: Int { submittedCount - nextToInsert }
}
