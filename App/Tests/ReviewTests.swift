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
}
