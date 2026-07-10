// Temporary entry point so the package builds while WordFlowCore is validated.
// Replaced by the full menu bar app in this phase.

import SwiftUI

@main
struct WordFlowApp: App {
    var body: some Scene {
        MenuBarExtra("WordFlow") {
            Text("WordFlow")
        }
    }
}
