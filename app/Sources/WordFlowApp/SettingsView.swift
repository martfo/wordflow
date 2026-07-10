// The Settings window: General, Microphone, Model, Cleanup, and Dictation data
// (History and the Personal Dictionary together), styled plainly in Polenta's
// key (AC-8.3).

import ServiceManagement
import SwiftUI
import WordFlowCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(AppModel.SettingsTab.general)
            MicrophoneSettings()
                .tabItem { Label("Microphone", systemImage: "mic") }
                .tag(AppModel.SettingsTab.microphone)
            ModelSettingsView()
                .tabItem { Label("Model", systemImage: "waveform") }
                .tag(AppModel.SettingsTab.model)
            CleanupSettings()
                .tabItem { Label("Cleanup", systemImage: "text.badge.checkmark") }
                .tag(AppModel.SettingsTab.cleanup)
            DictationDataView()
                .tabItem { Label("Dictation data", systemImage: "tray.full") }
                .tag(AppModel.SettingsTab.dictationData)
        }
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Hotkey", selection: $model.hotkeyKind) {
                ForEach(HotkeyKind.allCases, id: \.self) { kind in
                    Text(kind.display).tag(kind)
                }
            }
            Text("Hold the hotkey and speak. Double-tap to lock hands-free; press Esc to cancel.")
                .font(.footnote).foregroundStyle(.secondary)

            Toggle("Pause dictation", isOn: $model.paused)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
        }
    }
}

private struct MicrophoneSettings: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var meter = MicMeter()

    var body: some View {
        Form {
            Picker("Input device", selection: Binding(
                get: { model.microphones.selection },
                set: { model.microphones.choose($0); restartMeter() })) {
                ForEach(model.microphones.devices) { device in
                    Text(device.name).tag(device)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Input level").font(.footnote).foregroundStyle(.secondary)
                MeterBar(level: meter.level)
            }
        }
        .onAppear { model.microphones.refresh(); restartMeter() }
        .onDisappear { meter.stop() }
    }

    private func restartMeter() {
        meter.stop()
        meter.start(deviceID: model.microphones.captureDeviceID)
    }
}

private struct MeterBar: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, level * 3))))
            }
        }
        .frame(height: 8)
    }
}

private struct CleanupSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var toggles: [String: Bool] = [:]

    private let order: [(String, String)] = [
        ("punctuation", "Punctuation and capitalisation"),
        ("filler", "Remove filler words (um, uh, you know)"),
        ("dictionary", "Personal dictionary corrections"),
        ("british", "British English spelling"),
        ("emdash", "Remove em dashes"),
    ]

    var body: some View {
        Form {
            ForEach(order, id: \.0) { key, label in
                Toggle(label, isOn: Binding(
                    get: { toggles[key] ?? true },
                    set: { toggles[key] = $0; save() }))
            }
            Text("Passes run in this order. Each protects the ones before it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task {
            if let fetched = try? await model.client.cleanupToggles() { toggles = fetched }
        }
    }

    private func save() {
        let snapshot = toggles
        Task { try? await model.client.setCleanupToggles(snapshot) }
    }
}
