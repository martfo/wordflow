// The chosen microphone is remembered across launches (AC-7.1-b). Ported from
// Polenta. The store is injected so tests use an in-memory one; the app passes
// UserDefaults.

import Foundation

public protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func set(_ value: String?, forKey key: String) {
        if let value { set(value as Any, forKey: key) } else { removeObject(forKey: key) }
    }
}

public enum MicrophoneSelection {
    /// Which device should be selected after the device list changes, for
    /// example when a headset connects or is unplugged. The remembered choice
    /// wins when it is available, then whatever is currently selected, then the
    /// first device. Unplugging a pinned device therefore falls back to the
    /// system default (AC-7.3).
    public static func choose(available uids: [String], saved: String?, current: String?) -> String? {
        if let saved, uids.contains(saved) { return saved }
        if let current, uids.contains(current) { return current }
        return uids.first
    }
}

public struct MicrophonePreference {
    static let key = "selectedMicrophoneUID"
    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func save(deviceUID: String) {
        store.set(deviceUID, forKey: Self.key)
    }

    public func restore() -> String? {
        store.string(forKey: Self.key)
    }
}
