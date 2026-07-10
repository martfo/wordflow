// The floating pill: a small non-activating panel near the bottom centre of the
// screen, visible only while recording or processing (AC-8.2). It never steals
// keyboard focus from the frontmost app because the panel is non-activating.
// Clicking it cancels (AC-8.2-a).

import AppKit
import Combine
import SwiftUI

@MainActor
final class PillController {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private weak var controller: DictationController?

    func attach(to controller: DictationController) {
        self.controller = controller
        controller.$pill
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)
    }

    private func update(for state: DictationController.PillState) {
        if state == .hidden {
            panel?.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let controller else { return }
        if panel == nil {
            let hosting = NSHostingView(rootView: PillView(controller: controller))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.contentView = hosting
            panel.ignoresMouseEvents = false
            self.panel = panel
        }
        position(panel!)
        panel!.orderFrontRegardless()
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 96)
        panel.setFrameOrigin(origin)
    }
}
