// Permission status and the readiness check used before recording. The app
// requests Microphone and Accessibility at the moment each is first needed
// (AC-9.1); this pure logic turns their statuses into a plain message.

import Foundation

public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

public enum CaptureReadiness: Equatable {
    case ready
    case awaitingConsent
    case blocked(String)

    /// Microphone drives capture; Accessibility drives the hotkey and insertion.
    public static func evaluate(
        microphone: PermissionStatus, accessibility: PermissionStatus
    ) -> CaptureReadiness {
        var missing: [String] = []
        if microphone == .denied { missing.append("Microphone") }
        if accessibility == .denied { missing.append("Accessibility") }
        if !missing.isEmpty {
            let list = missing.joined(separator: " and ")
            return .blocked(
                "\(list) access is off, so dictation cannot run. Turn it on in "
                + "System Settings, then try again.")
        }
        if microphone == .undetermined || accessibility == .undetermined {
            return .awaitingConsent
        }
        return .ready
    }
}
