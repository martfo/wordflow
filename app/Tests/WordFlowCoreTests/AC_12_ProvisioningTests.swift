// Section 12: first-run provisioning is idempotent and only a complete run
// writes the marker, so a partial install is always run over (AC-12.1-b).

import Foundation
import Testing
@testable import WordFlowCore

private final class FakeInstaller: RuntimeInstalling {
    var failOn: String?
    private(set) var steps: [String] = []

    func fetchPython(into runtime: URL) throws { try record("python") }
    func createEnvironment(at runtime: URL) throws { try record("env") }
    func installDependencies(at runtime: URL) throws { try record("deps") }
    func verifyBackendStarts(at runtime: URL) throws { try record("verify") }

    private func record(_ step: String) throws {
        steps.append(step)
        if failOn == step { throw NSError(domain: "test", code: 1) }
    }
}

struct AC_12_ProvisioningTests {
    private func tempRuntime() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordflow-provision-\(UUID().uuidString)")
        return url.appendingPathComponent("runtime")
    }

    @Test("AC-12.1-b a complete run writes the marker and is not a first run after")
    func test_complete_run_writes_marker() {
        let runtime = tempRuntime()
        defer { try? FileManager.default.removeItem(at: runtime.deletingLastPathComponent()) }
        let installer = FakeInstaller()
        let provisioner = Provisioner(runtime: runtime, installer: installer)

        #expect(Provisioner.isFirstRun(runtime: runtime))
        #expect(provisioner.provision() == .ready)
        #expect(installer.steps == ["python", "env", "deps", "verify"])
        #expect(!Provisioner.isFirstRun(runtime: runtime))
    }

    @Test("a failed step leaves it retryable and still a first run")
    func test_failed_step_is_retryable() {
        let runtime = tempRuntime()
        defer { try? FileManager.default.removeItem(at: runtime.deletingLastPathComponent()) }
        let installer = FakeInstaller()
        installer.failOn = "deps"
        let provisioner = Provisioner(runtime: runtime, installer: installer)

        if case .failed = provisioner.provision() {} else { Issue.record("expected a failed state") }
        #expect(Provisioner.isFirstRun(runtime: runtime), "no marker after a partial run")
    }
}
