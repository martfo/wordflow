// Sections 8 and 9: the app bundle declares no Dock icon and carries a plain
// explanation for the Microphone permission it will ask for.

import Foundation
import Testing

struct AC_8_9_BundleTests {
    private func infoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WordFlowCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Support/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("AC-8.4-a the app is a menu bar app with no Dock icon")
    func test_no_dock_icon() throws {
        let plist = try infoPlist()
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    @Test("AC-9.1-a the Microphone permission carries a plain explanation")
    func test_microphone_usage_description() throws {
        let plist = try infoPlist()
        let microphone = try #require(plist["NSMicrophoneUsageDescription"] as? String)
        #expect(!microphone.isEmpty)
        #expect(plist["CFBundleIdentifier"] as? String == "co.uk.designturbine.wordflow")
    }
}
