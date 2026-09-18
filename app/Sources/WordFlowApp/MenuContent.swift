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

        Menu("Recover last dictation") {
            Button("Re-transcribe (copies to clipboard)") { controller.reTranscribeLast(model: nil) }
            Button("Re-transcribe with Whisper") { controller.reTranscribeLast(model: "whisper") }
        }

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
        Button("Settings…") { showSettings(.general) }
        Button("History…") { showSettings(.dictationData) }
        Divider()
        Button("Quit WordFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Open Settings on a given tab. `openSettings` alone does not bring a
    /// menu-bar-only (accessory) app to the front, so the window opens behind
    /// other apps and looks like nothing happened. Activate WordFlow and order
    /// the settings window front once SwiftUI has created it.
    private func showSettings(_ tab: AppModel.SettingsTab) {
        model.settingsTab = tab
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows
            where window.frameAutosaveName == "com_apple_SwiftUI_Settings_window" {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
