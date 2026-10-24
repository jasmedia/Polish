import AppKit
import SwiftUI

/// A borderless, non-activating panel: it takes key input while the app being typed in stays active.
final class ReviewPanel: NSPanel {
    init(content: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // The hosting view must not size the window itself: moving the origin while it does (to keep
        // the top edge fixed) re-enters layout until the stack overflows. The content reports its
        // size instead, and `fit` resizes the window after the layout pass.
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        hosting.rootView = AnyView(content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                MainActor.assumeIsolated { self?.fit(size) }
            })
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Grows and shrinks downward from the top edge as the content changes (loading → result).
    private func fit(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self, size.width > 0, size.height > 0, size != frame.size else { return }
            setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                     display: true)
            invalidateShadow()
        }
    }
}

/// Places the panel under the caret, or near the mouse when Accessibility gives no bounds.
enum PanelPlacement {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// - Parameters:
    ///   - anchor: Selection bounds in Accessibility coordinates (top-left origin of the primary screen).
    ///   - mouse: Mouse location in Cocoa coordinates (bottom-left origin).
    ///   - screens: Visible frames of the screens, in Cocoa coordinates.
    ///   - primaryHeight: Height of the primary screen, to flip Accessibility coordinates.
    /// - Returns: The panel's top-left point in Cocoa coordinates.
    static func topLeft(anchor: CGRect?, mouse: CGPoint, size: CGSize, screens: [CGRect], primaryHeight: CGFloat) -> CGPoint {
        // Below the anchor first; above it when there's no room below.
        let below: CGPoint
        let aboveTop: CGFloat
        if let anchor {
            below = CGPoint(x: anchor.minX, y: primaryHeight - anchor.maxY - gap)
            aboveTop = primaryHeight - anchor.minY + gap + size.height
        } else {
            below = CGPoint(x: mouse.x, y: mouse.y - 16)
            aboveTop = mouse.y + 16 + size.height
        }
        guard let screen = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(below) }) ?? screens.first else {
            return below
        }
        var point = below
        if point.y - size.height < screen.minY + margin {
            point.y = aboveTop
        }
        point.x = min(max(point.x, screen.minX + margin), screen.maxX - size.width - margin)
        point.y = min(max(point.y, screen.minY + margin + size.height), screen.maxY - margin)
        return point
    }
}

/// Shows `ReviewView` in a `ReviewPanel`. Losing key focus (the user clicked elsewhere) cancels the request.
@MainActor
final class ReviewPanelPresenter: NSObject, ReviewPresenting, NSWindowDelegate {
    weak var controller: PolishController?
    private var panel: ReviewPanel?

    func show(_ review: ReviewModel, near anchor: CGRect?) {
        close()
        guard let controller else { return }
        let panel = ReviewPanel(content: ReviewView(model: review, controller: controller))
        panel.layoutIfNeeded()
        let topLeft = PanelPlacement.topLeft(
            anchor: anchor,
            mouse: NSEvent.mouseLocation,
            size: panel.frame.size,
            screens: NSScreen.screens.map(\.visibleFrame),
            primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0
        )
        panel.setFrameTopLeftPoint(topLeft)
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        controller?.cancel()
    }
}
