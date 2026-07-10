// Section 7: microphone preference persistence and re-selection after the
// device list changes.

import Testing
@testable import WordFlowCore

struct AC_7_MicrophoneTests {
    @Test("AC-7.1-b the chosen microphone is saved and restored")
    func test_preference_round_trip() {
        let store = MemoryStore()
        MicrophonePreference(store: store).save(deviceUID: "AirPods-UID")
        #expect(MicrophonePreference(store: store).restore() == "AirPods-UID")
        #expect(MicrophonePreference(store: MemoryStore()).restore() == nil)
    }

    @Test("AC-7.3-a a pinned device that disappears falls back to the default")
    func test_selection_after_device_change() {
        let builtIn = "BuiltInMic"
        let airpods = "AirPods-UID"
        // Remembered device present: it wins.
        #expect(MicrophoneSelection.choose(available: [builtIn, airpods], saved: airpods, current: builtIn) == airpods)
        // Remembered device unplugged: fall back to what is available.
        #expect(MicrophoneSelection.choose(available: [builtIn], saved: airpods, current: airpods) == builtIn)
        // Nothing available at all.
        #expect(MicrophoneSelection.choose(available: [], saved: airpods, current: airpods) == nil)
    }
}
