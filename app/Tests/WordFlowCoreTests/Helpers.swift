import Foundation
@testable import WordFlowCore

final class MemoryStore: KeyValueStore {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String?, forKey key: String) { values[key] = value }
}
