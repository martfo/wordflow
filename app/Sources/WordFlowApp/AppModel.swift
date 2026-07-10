// The app's shared state: the supervised backend, the dictation controller, the
// microphone list, the pill, and the persisted hotkey and model choice.

import AppKit
import Combine
import Foundation
import SwiftUI
import WordFlowCore

@MainActor
final class AppModel: ObservableObject {
    let client = BackendClient()
    let microphones = MicrophoneListModel()
    let controller: DictationController
    let supervisor: BackendSupervisor
    private let pillController = PillController()

    @Published var hotkeyKind: HotkeyKind {
        didSet {
            HotkeyPreference(store: UserDefaults.standard).save(hotkeyKind)
            controller.setHotkey(hotkeyKind)
        }
    }
    @Published var paused = false {
        didSet { controller.setPaused(paused, hotkey: hotkeyKind) }
    }
    @Published private(set) var activeModel = "parakeet"
    @Published private(set) var backendState: BackendSupervisor.State = .starting
    @Published var settingsTab: SettingsTab = .general

    enum SettingsTab: Hashable {
        case general, microphone, model, cleanup, dictationData
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        let defaultKind = Hotkey.defaultKind(hasSectionKey: KeyboardLayout.hasSectionKey())
        let kind = HotkeyPreference(store: UserDefaults.standard).restore(defaultKind: defaultKind)
        self.hotkeyKind = kind

        let configPath = AppSetup.ensure()
        self.controller = DictationController(client: client, microphones: microphones)
        self.supervisor = BackendSupervisor(client: client, configPath: configPath.path)

        controller.start(hotkey: kind)
        supervisor.start()
        pillController.attach(to: controller)

        supervisor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.backendState = state
                if case .running(let model, _) = state { self?.activeModel = model }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.stop()
                self?.supervisor.stop()
            }
        }
    }

    func switchModel(_ name: String) {
        activeModel = name
        Task { try? await client.switchModel(name) }
    }

    /// A one-line summary of the backend for the menu bar.
    var backendSummary: String {
        switch backendState {
        case .starting: return "Starting the backend…"
        case .running(let model, let loaded):
            return loaded ? "Ready with \(model)" : "Loading \(model)…"
        case .down(let message): return message
        }
    }
}
