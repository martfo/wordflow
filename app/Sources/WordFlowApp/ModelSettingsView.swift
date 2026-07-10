// Settings → Model: choose the speech model, run the first-run-style bake-off on
// your own voice (AC-9.3), and run the accuracy harness against the reference
// script, with past runs kept so they stay comparable (AC-9.5).

import CoreAudio
import SwiftUI
import WordFlowCore

@MainActor
final class BakeoffModel: ObservableObject {
    enum Phase: Equatable { case idle, recording, working }

    @Published var phase: Phase = .idle
    @Published var bakeoff: [BackendClient.BakeoffResult] = []
    @Published var scores: [BackendClient.AccuracyScore] = []
    @Published var runs: [BackendClient.AccuracyRun] = []
    @Published var message: String?

    private let capture = MicCapture()
    private var mode: Mode = .bakeoff
    private enum Mode { case bakeoff, accuracy }

    func startRecording(deviceID: AudioDeviceID?, mode: String) async {
        self.mode = mode == "accuracy" ? .accuracy : .bakeoff
        var granted = MicCapture.microphonePermission() == .granted
        if !granted { granted = await MicCapture.requestMicrophoneAccess() }
        guard granted else {
            message = "Turn on Microphone access for WordFlow in System Settings."
            return
        }
        do {
            try await capture.start(deviceID: deviceID)
            phase = .recording
            message = nil
        } catch {
            message = "The microphone could not start: \(error.localizedDescription)"
        }
    }

    func stopAndRun(client: BackendClient) async {
        let samples = await capture.stop()
        phase = .working
        let audio = AudioWAV.wav(from: samples).base64EncodedString()
        do {
            switch mode {
            case .bakeoff:
                bakeoff = try await client.bakeoff(audioBase64: audio, sampleRate: AudioWAV.targetSampleRate)
            case .accuracy:
                scores = try await client.accuracy(
                    audioBase64: audio, referenceText: ReferenceScript.text,
                    sampleRate: AudioWAV.targetSampleRate)
                await loadRuns(client: client)
            }
        } catch {
            message = "The models could not be run. They may still be downloading."
        }
        phase = .idle
    }

    func loadRuns(client: BackendClient) async {
        runs = (try? await client.accuracyRuns()) ?? runs
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var bakeoff = BakeoffModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Speech model", selection: Binding(
                    get: { model.activeModel }, set: { model.switchModel($0) })) {
                    Text("Parakeet TDT 0.6B (primary)").tag("parakeet")
                    Text("Whisper large-v3-turbo").tag("whisper")
                }
                Text("The previous model keeps working until the new one has loaded, so no dictation is lost.")
                    .font(.footnote).foregroundStyle(.secondary)

                if let message = bakeoff.message {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }

                Divider()
                bakeoffSection
                Divider()
                accuracySection
            }
            .padding(4)
        }
        .task { await bakeoff.loadRuns(client: model.client) }
    }

    private var bakeoffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bake-off").font(.headline)
            Text("Record a few sentences in your own voice, then compare the models side by side.")
                .font(.footnote).foregroundStyle(.secondary)
            recordButton(mode: "bakeoff")
            ForEach(bakeoff.bakeoff) { result in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(displayName(result.model)).font(.subheadline).bold()
                        Text(result.error ?? result.text).font(.callout)
                            .foregroundStyle(result.error == nil ? .primary : .secondary)
                    }
                    Spacer()
                    Button("Use this model") { model.switchModel(result.model) }
                        .disabled(model.activeModel == result.model)
                }
            }
        }
    }

    private var accuracySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy harness").font(.headline)
            Text("Read the reference script aloud; WordFlow scores each model's word error rate and keeps the run.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Reference script") {
                Text(ReferenceScript.sentences.joined(separator: "\n"))
                    .font(.footnote).textSelection(.enabled)
            }
            recordButton(mode: "accuracy")
            ForEach(bakeoff.scores) { score in
                HStack {
                    Text(displayName(score.model))
                    Spacer()
                    Text(score.error ?? String(format: "WER %.1f%%", score.wer * 100))
                        .foregroundStyle(score.error == nil ? .primary : .secondary)
                }
            }
            if !bakeoff.runs.isEmpty {
                Text("Past runs").font(.subheadline).padding(.top, 4)
                ForEach(bakeoff.runs) { run in
                    HStack {
                        Text(displayName(run.model)).font(.caption)
                        Spacer()
                        Text(String(format: "WER %.1f%%", run.wer * 100)).font(.caption)
                        Text(run.created_at.prefix(10)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func recordButton(mode: String) -> some View {
        Group {
            switch bakeoff.phase {
            case .idle:
                Button("Record") { Task { await bakeoff.startRecording(deviceID: model.microphones.captureDeviceID, mode: mode) } }
            case .recording:
                Button("Stop and compare") { Task { await bakeoff.stopAndRun(client: model.client) } }
                    .tint(.red)
            case .working:
                HStack { ProgressView().controlSize(.small); Text("Running the models…") }
            }
        }
    }

    private func displayName(_ name: String) -> String {
        name == "parakeet" ? "Parakeet" : "Whisper large-v3-turbo"
    }
}
