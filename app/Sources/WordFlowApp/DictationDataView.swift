// Dictation data: History and the Personal Dictionary together, because they
// feed each other (AC-8.3-b). Correcting a history entry offers a dictionary
// entry; a learned entry links back to the dictation that taught it.

import AppKit
import SwiftUI

struct DictationDataView: View {
    @EnvironmentObject var model: AppModel

    @State private var history: [HistoryEntry] = []
    @State private var dictionary: [DictionaryEntryDTO] = []
    @State private var search = ""
    @State private var newCanonical = ""
    @State private var newHint = ""
    @State private var correctionOffer: (dictationID: Int, heard: String, corrected: String)?

    var body: some View {
        HSplitView {
            historyColumn
            dictionaryColumn
        }
        .task { await reload() }
        .alert("Add to the dictionary?", isPresented: offerBinding) {
            Button("Always transcribe it") { acceptOffer() }
            Button("Just this once", role: .cancel) { correctionOffer = nil }
        } message: {
            if let offer = correctionOffer {
                Text("Always transcribe \u{201C}\(offer.heard)\u{201D} as \u{201C}\(offer.corrected)\u{201D}?")
            }
        }
    }

    // MARK: - History

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button("Clear all") { Task { try? await model.client.clearHistory(); await reload() } }
            }
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await reload() } }
            List(history) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.cleaned_text).lineLimit(3)
                    HStack(spacing: 8) {
                        Text(entry.target_app ?? "Unknown app").font(.caption).foregroundStyle(.secondary)
                        Text(entry.model).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") { copy(entry.cleaned_text) }
                        Button("Correct") { correct(entry) }
                        Button("Delete") { Task { try? await model.client.deleteHistory(entry.id); await reload() } }
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minWidth: 320)
        .padding(8)
    }

    private func correct(_ entry: HistoryEntry) {
        let alert = NSAlert()
        alert.messageText = "Correct this dictation"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = entry.cleaned_text
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let corrected = field.stringValue
        Task {
            if let offer = try? await model.client.correct(entry.id, text: corrected) {
                correctionOffer = (entry.id, offer.heard, offer.corrected)
            }
            await reload()
        }
    }

    // MARK: - Dictionary

    private var dictionaryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal dictionary").font(.headline)
            List(dictionary) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.canonical)
                        if !entry.hints.isEmpty {
                            Text("sounds like: \(entry.hints.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if entry.source_dictation_id != nil {
                        Image(systemName: "link").foregroundStyle(.secondary)
                            .help("Learned from a correction")
                    }
                    Button("Delete") {
                        Task { try? await model.client.deleteDictionaryEntry(entry.canonical); await reload() }
                    }
                    .buttonStyle(.link)
                }
            }
            HStack {
                TextField("Word", text: $newCanonical).textFieldStyle(.roundedBorder)
                TextField("sounds like (optional)", text: $newHint).textFieldStyle(.roundedBorder)
                Button("Add") { addEntry() }
                    .disabled(newCanonical.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(minWidth: 260)
        .padding(8)
    }

    private func addEntry() {
        let canonical = newCanonical.trimmingCharacters(in: .whitespaces)
        let hints = newHint.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        newCanonical = ""; newHint = ""
        Task { try? await model.client.addDictionaryEntry(canonical: canonical, hints: hints, sourceDictationID: nil); await reload() }
    }

    // MARK: - Shared

    private var offerBinding: Binding<Bool> {
        Binding(get: { correctionOffer != nil }, set: { if !$0 { correctionOffer = nil } })
    }

    private func acceptOffer() {
        guard let offer = correctionOffer else { return }
        correctionOffer = nil
        Task {
            try? await model.client.addDictionaryEntry(
                canonical: offer.corrected, hints: [offer.heard], sourceDictationID: offer.dictationID)
            await reload()
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func reload() async {
        let query = search.trimmingCharacters(in: .whitespaces)
        history = (try? await model.client.history(query: query.isEmpty ? nil : query)) ?? history
        dictionary = (try? await model.client.dictionary()) ?? dictionary
    }
}
