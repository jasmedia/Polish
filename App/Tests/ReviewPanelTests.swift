import AppKit
import Testing
@testable import Polish
import PolishCore

@MainActor
struct ReviewPanelTests {
    /// The panel follows its content and keeps its top edge. (The layout loop this sizing replaced only
    /// happened in the app's display cycle, which a test process doesn't run, so it can't be reproduced here.)
    @Test func growsDownwardWhenTheResultArrives() async throws {
        _ = NSApplication.shared
        let presenter = RecordingPresenter()
        let controller = PolishController(bridge: FakeBridge("x"), pipeline: Pipeline(model: FixedModel([])),
                                          presenter: presenter)
        let review = ReviewModel()
        let panel = ReviewPanel(content: ReviewView(model: review, controller: controller))
        // Inside the screen: AppKit moves a panel that sits above it (CI's screen is 768 points tall).
        let visible = try #require(NSScreen.main?.visibleFrame)
        panel.setFrameTopLeftPoint(CGPoint(x: visible.minX + 100, y: visible.maxY - 50))
        panel.orderFront(nil)
        let top = panel.frame.maxY
        let loadingHeight = panel.frame.height

        let rewrite = "@Athul, I will continue developing it tomorrow, and I will share an update with the team by Friday."
        let result = try await Pipeline(model: FixedModel([rewrite]))
            .polish(text: "@Athul i will continu developing it tmrw and share update with team by friday")
        review.state = .result(result)
        for _ in 0..<25 {
            panel.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(panel.frame.height > loadingHeight)
        #expect(panel.frame.maxY == top, "frame \(panel.frame), top \(top), scale \(panel.backingScaleFactor)")
        panel.orderOut(nil)
    }
}
