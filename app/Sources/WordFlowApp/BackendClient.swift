// The HTTP client for the local backend on 127.0.0.1:8770.

import Foundation

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct HealthStatus: Codable {
    let status: String
    let active_model: String
    let model_loaded: Bool
    let loading: Bool
}

struct TranscriptionResult: Codable {
    let dictation_id: Int?
    let raw: String
    let text: String
    let nothing_heard: Bool
    let flags: [String]
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: Int
    let created_at: String
    let target_app: String?
    let model: String
    let raw_text: String
    let cleaned_text: String
    let inserted: Int
    let taught_entries: [String]?
}

struct DictionaryEntryDTO: Codable, Identifiable, Hashable {
    var id: String { canonical }
    let canonical: String
    let hints: [String]
    let source_dictation_id: Int?
}

final class BackendClient: @unchecked Sendable {
    let baseURL: URL
    let port: Int
    private let session: URLSession

    init(port: Int = 8770) {
        self.port = port
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: configuration)
    }

    func health() async throws -> HealthStatus {
        try await get("/health")
    }

    /// The core loop: hand the captured audio to the backend and get cleaned
    /// text back. The app inserts it and records nothing further.
    func transcribe(audioBase64: String, sampleRate: Int, targetApp: String?,
                    targetBundleID: String?, locked: Bool) async throws -> TranscriptionResult {
        struct Payload: Encodable {
            let audio_base64: String
            let sample_rate: Int
            let target_app: String?
            let target_bundle_id: String?
            let locked: Bool
        }
        return try await send("POST", "/transcribe", body: Payload(
            audio_base64: audioBase64, sample_rate: sampleRate,
            target_app: targetApp, target_bundle_id: targetBundleID, locked: locked))
    }

    func markInserted(_ dictationID: Int, inserted: Bool) async {
        struct Payload: Encodable { let inserted: Bool }
        _ = try? await sendVoid("PUT", "/history/\(dictationID)/inserted",
                                body: Payload(inserted: inserted))
    }

    func history(query: String? = nil) async throws -> [HistoryEntry] {
        let path = query.map { "/history?q=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" } ?? "/history"
        return try await get(path)
    }

    func deleteHistory(_ id: Int) async throws {
        _ = try await sendVoid("DELETE", "/history/\(id)", body: Optional<Int>.none)
    }

    func clearHistory() async throws {
        _ = try await sendVoid("POST", "/history/clear", body: Optional<Int>.none)
    }

    struct CorrectionOffer: Codable { let heard: String; let corrected: String }
    struct CorrectionResult: Codable { let saved: Bool; let offer: CorrectionOffer? }

    func correct(_ id: Int, text: String) async throws -> CorrectionOffer? {
        struct Payload: Encodable { let text: String }
        let result: CorrectionResult = try await send("POST", "/history/\(id)/correct", body: Payload(text: text))
        return result.offer
    }

    func dictionary() async throws -> [DictionaryEntryDTO] {
        try await get("/dictionary")
    }

    func addDictionaryEntry(canonical: String, hints: [String], sourceDictationID: Int?) async throws {
        struct Payload: Encodable { let canonical: String; let hints: [String]; let source_dictation_id: Int? }
        _ = try await sendVoid("POST", "/dictionary",
                               body: Payload(canonical: canonical, hints: hints, source_dictation_id: sourceDictationID))
    }

    func deleteDictionaryEntry(_ canonical: String) async throws {
        let encoded = canonical.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? canonical
        _ = try await sendVoid("DELETE", "/dictionary/\(encoded)", body: Optional<Int>.none)
    }

    func switchModel(_ name: String) async throws {
        struct Payload: Encodable { let name: String }
        _ = try await sendVoid("POST", "/model", body: Payload(name: name))
    }

    struct BakeoffResult: Codable, Identifiable { var id: String { model }; let model: String; let text: String; let error: String? }
    struct AccuracyScore: Codable, Identifiable { var id: String { model }; let model: String; let wer: Double; let reference_words: Int; let transcript: String; let error: String? }
    struct AccuracyRun: Codable, Identifiable { let id: Int; let created_at: String; let model: String; let wer: Double; let reference_words: Int }

    func bakeoff(audioBase64: String, sampleRate: Int) async throws -> [BakeoffResult] {
        struct Payload: Encodable { let audio_base64: String; let sample_rate: Int }
        struct Response: Codable { let results: [BakeoffResult] }
        let response: Response = try await send("POST", "/bakeoff", body: Payload(audio_base64: audioBase64, sample_rate: sampleRate))
        return response.results
    }

    func accuracy(audioBase64: String, referenceText: String, sampleRate: Int) async throws -> [AccuracyScore] {
        struct Payload: Encodable { let audio_base64: String; let reference_text: String; let sample_rate: Int }
        struct Response: Codable { let scores: [AccuracyScore] }
        let response: Response = try await send("POST", "/accuracy", body: Payload(audio_base64: audioBase64, reference_text: referenceText, sample_rate: sampleRate))
        return response.scores
    }

    func accuracyRuns() async throws -> [AccuracyRun] {
        try await get("/accuracy")
    }

    func cleanupToggles() async throws -> [String: Bool] {
        try await get("/cleanup")
    }

    func setCleanupToggles(_ toggles: [String: Bool]) async throws {
        struct Payload: Encodable { let toggles: [String: Bool] }
        _ = try await sendVoid("PUT", "/cleanup", body: Payload(toggles: toggles))
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        return try await perform(request, path: path)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request, path: path)
    }

    @discardableResult
    private func sendVoid<B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackendError(message: "The backend answered with an error for \(path).")
        }
        return true
    }

    private func perform<T: Decodable>(_ request: URLRequest, path: String) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackendError(message: "The backend answered with an error for \(path).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
