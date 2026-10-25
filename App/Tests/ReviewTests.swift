import CoreGraphics
import Testing
@testable import Polish
import PolishCore

@MainActor
struct ReviewTests {
    @Test func diffShowsTheRewriteWithoutRemovals() {
        let diff = Differ.diff(original: "i will send it tmrw", rewritten: "I will send it tomorrow.")
        let hidden = DiffText.attributed(diff, showRemovals: false)
        #expect(String(hidden.characters) == "I will send it tomorrow.")

        let shown = String(DiffText.attributed(diff, showRemovals: true).characters)
        #expect(shown.contains("tmrw") && shown.contains("tomorrow."))
    }

    @Test func announcesEachStateForVoiceOver() async throws {
        let review = ReviewModel()
        #expect(review.announcement == "Polishing")
        review.state = .unchanged
        #expect(review.announcement == "Looks good. No changes needed.")
        review.state = .failed(.init(.notTrusted))
        #expect(review.announcement == BridgeError.notTrusted.message)

        let result = try await Pipeline(model: FixedModel(["I will send it tomorrow."])).polish(text: "i will send it tmrw")
        review.state = .result(result)
        #expect(review.announcement == "Rewrite ready: I will send it tomorrow. Return to accept, Escape to cancel.")
    }

    // Primary screen 1000 pt tall; visible frame leaves room for the menu bar.
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 975)]
    let size = CGSize(width: 420, height: 200)

    @Test func placesThePanelBelowTheSelection() {
        let anchor = CGRect(x: 100, y: 300, width: 200, height: 20)  // top-left origin
        let point = PanelPlacement.topLeft(anchor: anchor, mouse: .zero, size: size, screens: screens, primaryHeight: 1000)
        #expect(point == CGPoint(x: 100, y: 1000 - 320 - PanelPlacement.gap))
    }

    @Test func flipsAboveWhenThereIsNoRoomBelow() {
        let anchor = CGRect(x: 100, y: 900, width: 200, height: 20)  // near the bottom of the screen
        let point = PanelPlacement.topLeft(anchor: anchor, mouse: .zero, size: size, screens: screens, primaryHeight: 1000)
        #expect(point.y == 1000 - 900 + PanelPlacement.gap + size.height)
    }

    @Test func staysOnScreenAtTheRightEdge() {
        let anchor = CGRect(x: 1400, y: 300, width: 20, height: 20)
        let point = PanelPlacement.topLeft(anchor: anchor, mouse: .zero, size: size, screens: screens, primaryHeight: 1000)
        #expect(point.x == 1440 - size.width - PanelPlacement.margin)
    }

    @Test func fallsBackToTheMouse() {
        let point = PanelPlacement.topLeft(anchor: nil, mouse: CGPoint(x: 500, y: 600), size: size, screens: screens, primaryHeight: 1000)
        #expect(point == CGPoint(x: 500, y: 584))
    }

    @Test func progressShowsThePartBeingPolished() {
        let review = ReviewModel()
        let run = review.startRun()
        #expect(review.loadingTitle == "Polishing…")
        review.update(PolishProgress(completed: 0, total: 1), run: run)
        #expect(review.loadingTitle == "Polishing…")
        review.update(PolishProgress(completed: 1, total: 4), run: run)
        #expect(review.loadingTitle == "Polishing… part 2 of 4")
        // An older report arriving late doesn't move it back.
        review.update(PolishProgress(completed: 0, total: 4), run: run)
        #expect(review.progress == PolishProgress(completed: 1, total: 4))
    }

    @Test func reportsFromAnEarlierRunAreDropped() {
        let review = ReviewModel()
        let first = review.startRun()
        review.update(PolishProgress(completed: 1, total: 3), run: first)
        let second = review.startRun()
        review.update(PolishProgress(completed: 2, total: 3), run: first)
        #expect(review.progress == nil)
        review.update(PolishProgress(completed: 0, total: 1), run: second)
        #expect(review.progress == PolishProgress(completed: 0, total: 1))
    }

    @Test func previewIsClearedAndTiedToItsRun() {
        let review = ReviewModel()
        let first = review.startRun()
        review.updatePreview("I will send", run: first)
        #expect(review.preview == "I will send")
        let second = review.startRun()
        #expect(review.preview == nil)
        review.updatePreview("I will send the report", run: first)
        #expect(review.preview == nil)
        review.updatePreview("Hey, I'll", run: second)
        #expect(review.preview == "Hey, I'll")
    }
}
