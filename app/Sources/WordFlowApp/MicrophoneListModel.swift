// The microphone picker's state: the device list plus the remembered choice,
// re-selected after the device list changes and falling back to the system
// default when a pinned device disappears (AC-7).

import CoreAudio
import Foundation
import WordFlowCore

@MainActor
final class MicrophoneListModel: ObservableObject {
    @Published private(set) var devices: [InputDevice] = []
    @Published var selection: InputDevice

    private let preference = MicrophonePreference(store: UserDefaults.standard)

    init() {
        let list = InputDevice.allWithDefault()
        let saved = MicrophonePreference(store: UserDefaults.standard).restore()
        devices = list
        selection = list.first(where: { $0.uid == saved }) ?? .systemDefault
    }

    func refresh() {
        devices = InputDevice.allWithDefault()
        let uids = devices.map(\.uid)
        let chosen = MicrophoneSelection.choose(
            available: uids, saved: preference.restore(), current: selection.uid)
        selection = devices.first(where: { $0.uid == chosen }) ?? .systemDefault
    }

    func choose(_ device: InputDevice) {
        selection = device
        preference.save(deviceUID: device.uid)
    }

    var captureDeviceID: AudioDeviceID? { selection.captureDeviceID }
}
