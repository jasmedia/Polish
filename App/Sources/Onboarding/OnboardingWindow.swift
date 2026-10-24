import AppKit
import SwiftUI

/// Shows the first-run window. Closing it, or pressing Done, marks onboarding complete.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeView: (_ done: @escaping () -> Void) -> AnyView
    private let onFinish: () -> Void

    init(makeView: @escaping (_ done: @escaping () -> Void) -> AnyView, onFinish: @escaping () -> Void) {
        self.makeView = makeView
        self.onFinish = onFinish
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to Polish"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: makeView { [weak window] in window?.close() })
            window.center()
            window.delegate = self
            self.window = window
        }
        // A menu bar app isn't active, so the window would open behind other apps.
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onFinish()
    }
}
