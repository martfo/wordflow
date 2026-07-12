// A plain window for first-run setup, shown when the installed app has no
// provisioned backend yet. Managed in code (like the pill) so it does not fight
// the menu bar app's scene lifecycle.

import AppKit
import SwiftUI

@MainActor
final class SetupWindowController {
    private var window: NSWindow?

    func present(model: AppModel) {
        if window == nil {
            let hosting = NSHostingView(rootView: SetupView().environmentObject(model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Welcome to WordFlow"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)  // show in the Dock while setting up
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
        // Back to a menu-bar-only app with no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
