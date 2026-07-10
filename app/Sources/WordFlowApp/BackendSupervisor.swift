// The backend runs as a supervised child process of the app. The supervisor
// launches it, health-checks it, replaces an orphan holding the port, and
// restarts it if it dies (AC-11.1). Ported from Polenta, retargeted at the
// WordFlow module and port 8770.

import Foundation
import WordFlowCore

@MainActor
final class BackendSupervisor: ObservableObject {
    enum State: Equatable {
        case starting
        case running(model: String, loaded: Bool)
        case down(String)
    }

    @Published private(set) var state: State = .starting

    private var process: Process?
    private let client: BackendClient
    private let configPath: String
    private var monitorTask: Task<Void, Never>?

    init(client: BackendClient, configPath: String) {
        self.client = client
        self.configPath = configPath
    }

    /// The Python interpreter to run the backend with: an explicit dev override,
    /// then the provisioned runtime in Application Support.
    static func pythonExecutable() -> String? {
        if let override = ProcessInfo.processInfo.environment["WORDFLOW_BACKEND_PYTHON"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let provisioned = RuntimeLocation.runtimeDirectory()
            .appendingPathComponent("venv/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: provisioned) {
            return provisioned
        }
        return nil
    }

    /// The backend package directory, for development runs from the repo.
    static func backendDirectory() -> String? {
        ProcessInfo.processInfo.environment["WORDFLOW_BACKEND_DIR"]
    }

    func start() {
        terminateOrphan()
        launchProcess()
        monitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.checkHealth()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// A previous app run may have left its backend serving on the port. It runs
    /// stale code, so it is replaced, never adopted.
    private func terminateOrphan() {
        guard process == nil else { return }
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(client.port)"]
        let stdout = Pipe()
        lsof.standardOutput = stdout
        lsof.standardError = Pipe()
        guard (try? lsof.run()) != nil else { return }
        lsof.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespaces)),
               pid != ProcessInfo.processInfo.processIdentifier {
                kill(pid, SIGTERM)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        process?.terminate()
        process = nil
    }

    func checkHealth() async {
        do {
            let health = try await client.health()
            state = .running(model: health.active_model, loaded: health.model_loaded)
        } catch {
            if case .running = state {
                state = .down("The backend stopped answering. Restarting it.")
                launchProcess()
            } else if process == nil || process?.isRunning != true {
                state = .down(
                    "The backend is not running. Complete first-run setup, or start the app "
                    + "from a checkout with WORDFLOW_BACKEND_PYTHON set.")
            }
        }
    }

    private func launchProcess() {
        guard process?.isRunning != true else { return }
        guard let python = Self.pythonExecutable() else {
            state = .down("No backend runtime found. First-run setup installs it into Application Support.")
            return
        }
        let backendProcess = Process()
        backendProcess.executableURL = URL(fileURLWithPath: python)
        backendProcess.arguments = ["-m", "wordflow", configPath]
        if let backendDir = Self.backendDirectory() {
            backendProcess.currentDirectoryURL = URL(fileURLWithPath: backendDir)
        }
        backendProcess.environment = ProcessInfo.processInfo.environment
        do {
            try backendProcess.run()
            process = backendProcess
            state = .starting
        } catch {
            state = .down("The backend could not be launched: \(error.localizedDescription)")
        }
    }
}
