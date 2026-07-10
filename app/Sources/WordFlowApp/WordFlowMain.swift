// The app entry point: a menu bar app with no Dock icon (LSUIElement in
// Info.plist). The floating pill is owned by the AppModel's PillController; the
// menu bar item and the Settings window are declared here.

import SwiftUI
import WordFlowCore

@main
struct WordFlowMain: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
                .environmentObject(model.controller)
        } label: {
            MenuBarLabel(controller: model.controller, supervisor: model.supervisor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.controller)
                .frame(width: 620, height: 460)
        }
    }
}

/// The menu bar icon reflects idle, recording, and processing (AC-8.1-a).
struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var supervisor: BackendSupervisor

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch controller.pill {
        case .listening, .starting: return "mic.fill"
        case .locked: return "lock.fill"
        case .processing: return "ellipsis.circle"
        case .hidden: return "waveform"
        }
    }
}
