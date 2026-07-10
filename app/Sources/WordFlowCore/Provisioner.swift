// Backend provisioning at first run. The shipped app needs no Python or uv on
// the machine: on first launch it provisions the backend into Application
// Support, once per Mac, with a progress view rather than a terminal. Ported
// from Polenta; the installer steps are injected so tests drive every outcome
// without a network or a real toolchain (AC-12.1-b).

import Foundation

public enum RuntimeLocation {
    /// ~/Library/Application Support/WordFlow
    public static func applicationSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WordFlow")
    }

    /// The provisioned environment, kept separate from the data folder.
    public static func runtimeDirectory(under support: URL? = nil) -> URL {
        (support ?? applicationSupport()).appendingPathComponent("runtime")
    }

    /// The user's portable data folder (history, dictionary, config, logs).
    public static func dataDirectory(under support: URL? = nil) -> URL {
        (support ?? applicationSupport()).appendingPathComponent("data")
    }

    /// The Hugging Face model cache, rebuilt per Mac by the downloader.
    public static func modelsDirectory(under support: URL? = nil) -> URL {
        (support ?? applicationSupport()).appendingPathComponent("models")
    }

    public static func markerFile(runtime: URL) -> URL {
        runtime.appendingPathComponent(".provisioned")
    }
}

/// The marker's content; bump to force re-provisioning after a breaking runtime
/// change. Re-provisioning over a complete runtime is quick: only the backend
/// package reinstalls.
/// 1: the initial WordFlow backend (FastAPI, MLX speech models, cleanup,
///    dictionary, history).
public let runtimeVersion = "1"

public protocol RuntimeInstalling {
    /// Fetch the standalone CPython build for Apple Silicon.
    func fetchPython(into runtime: URL) throws
    /// Create the environment with uv.
    func createEnvironment(at runtime: URL) throws
    /// Install the pinned dependencies.
    func installDependencies(at runtime: URL) throws
    /// Start the backend once and check it imports.
    func verifyBackendStarts(at runtime: URL) throws
}

public final class Provisioner {
    public enum State: Equatable {
        case notStarted
        case inProgress(step: String)
        case ready
        case failed(String)
    }

    public private(set) var state: State = .notStarted
    public var onStep: ((String) -> Void)?

    private let runtime: URL
    private let installer: RuntimeInstalling

    public init(runtime: URL, installer: RuntimeInstalling) {
        self.runtime = runtime
        self.installer = installer
    }

    /// True when the runtime is absent or incomplete; false when present and
    /// valid. A directory without a matching marker is a partial install.
    public static func isFirstRun(runtime: URL) -> Bool {
        let marker = RuntimeLocation.markerFile(runtime: runtime)
        guard let content = try? String(contentsOf: marker, encoding: .utf8) else { return true }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) != runtimeVersion
    }

    /// Runs every step in order. Steps are idempotent, so a previous partial
    /// attempt is simply run over. Only a complete run writes the marker.
    @discardableResult
    public func provision() -> State {
        let steps: [(String, (URL) throws -> Void)] = [
            ("Fetching Python", installer.fetchPython(into:)),
            ("Creating the environment", installer.createEnvironment(at:)),
            ("Installing the backend", installer.installDependencies(at:)),
            ("Checking the backend starts", installer.verifyBackendStarts(at:)),
        ]
        do {
            try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
            for (name, step) in steps {
                state = .inProgress(step: name)
                onStep?(name)
                try step(runtime)
            }
            try runtimeVersion.write(
                to: RuntimeLocation.markerFile(runtime: runtime), atomically: true, encoding: .utf8)
            state = .ready
        } catch {
            state = .failed(
                "Setting up the backend did not finish: \(error.localizedDescription) "
                + "Check the network is available and press Retry.")
        }
        return state
    }
}
