// Fires a callback when the host window closes. SwiftUI does not reliably
// deliver `.onDisappear` to the visible tab when the Settings window itself is
// closed, so a side effect started on `.onAppear` — notably a metering
// microphone session — would keep running, and the macOS microphone indicator
// would stay lit, until the app quit. Observing the window's own close
// notification is the signal that always arrives.

import AppKit
import SwiftUI

struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView { TrackingView(onClose: onClose) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        private let onClose: () -> Void
        private var token: NSObjectProtocol?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Re-subscribe to whichever window we now belong to (or none, on a
            // tab switch, which tears the observer down cleanly).
            if let token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
