import AppKit
import SwiftUI

/// Shows the quick window (FR-10, Flow B). Closing it stops a running polish; the text is kept for next time.
@MainActor
final class QuickWindowController: NSObject, NSWindowDelegate {
    private let model: QuickWindowModel
    private var window: NSWindow?

    init(model: QuickWindowModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Quick Polish"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: QuickWindowView(model: model))
            window.setFrameAutosaveName("QuickPolish")
            if !window.setFrameUsingName("QuickPolish") { window.center() }
            window.delegate = self
            self.window = window
        }
        // A menu bar app isn't active, so the window would open behind other apps.
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        window = nil
    }
}
