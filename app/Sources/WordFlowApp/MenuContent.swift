// The menu bar menu: current state, quick model and microphone switchers, pause,
// Settings and History (which opens Settings at Dictation data), and Quit
// (AC-8.1-b).

import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: DictationController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.backendSummary)
        if let message = controller.statusMessage {
            Text(message)
        }
        if controller.needsAccessibility {
            Button("Open Accessibility Settings…") { controller.openAccessibilitySettings() }
        }
        Divider()

        Button(model.paused ? "Resume dictation" : "Pause dictation") {
            model.paused.toggle()
        }
        Text("Hotkey: hold \(model.hotkeyKind.display)")

        Menu("Model") {
            ForEach(["parakeet", "whisper"], id: \.self) { name in
                Button {
                    model.switchModel(name)
                } label: {
                    Label(displayName(name), systemImage: model.activeModel == name ? "checkmark" : "")
                }
            }
        }

        Menu("Microphone") {
            ForEach(model.microphones.devices) { device in
                Button {
                    model.microphones.choose(device)
                } label: {
                    Label(device.name, systemImage: model.microphones.selection.uid == device.uid ? "checkmark" : "")
                }
            }
        }

        Divider()
        Button("Settings…") {
            model.settingsTab = .general
            openSettings()
        }
        Button("History…") {
            model.settingsTab = .dictationData
            openSettings()
        }
        Divider()
        Button("Quit WordFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func displayName(_ name: String) -> String {
        name == "parakeet" ? "Parakeet (primary)" : "Whisper large-v3-turbo"
    }
}
