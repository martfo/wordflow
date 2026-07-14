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

        // One toggle: Dictate when idle, Pause dictation while listening.
        Button(controller.isDictating ? "Pause dictation" : "Dictate") {
            controller.toggleDictate()
        }
        .keyboardShortcut("d")

        Text(hotkeyStatus)

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

    /// A plain diagnostic so the hotkey state is visible at a glance.
    private var hotkeyStatus: String {
        if controller.hotkeyActive {
            return "Hotkey: hold \(model.hotkeyKind.display) (ready)"
        }
        let access = Accessibility.isTrusted ? "Accessibility on" : "Accessibility off"
        return "Hotkey \(model.hotkeyKind.display): not active. \(access). Use Dictate above."
    }
}
