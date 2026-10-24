import Testing
@testable import PolishCore

struct DifferTests {
    func rebuilt(_ segments: [DiffSegment]) -> (original: String, rewritten: String) {
        (segments.filter { $0.kind != .inserted }.map(\.text).joined(),
         segments.filter { $0.kind != .removed }.map(\.text).joined())
    }

    @Test(arguments: [
        ("", ""),
        ("", "Hello"),
        ("hello", ""),
        ("thx", "Thanks"),
        ("🎉", "🎉"),
        ("i will send u the report", "I will send you the report."),
        ("one\n\ntwo", "One.\n\nTwo."),
        ("⟦T1⟧ only", "⟦T1⟧, only"),
    ])
    func rebuildsBothTexts(original: String, rewritten: String) {
        let segments = Differ.diff(original: original, rewritten: rewritten)
        #expect(rebuilt(segments) == (original, rewritten))
    }

    @Test func identicalTextIsOneSameSegment() {
        let segments = Differ.diff(original: "all good here", rewritten: "all good here")
        #expect(segments.map(\.kind) == [.same])
    }

    @Test func marksChangedWords() {
        let segments = Differ.diff(original: "send u the doc", rewritten: "send you the doc")
        #expect(segments.map(\.kind) == [.same, .removed, .inserted, .same])
        #expect(segments.filter { $0.kind == .removed }.map(\.text) == ["u"])
        #expect(segments.filter { $0.kind == .inserted }.map(\.text) == ["you"])
    }

    @Test func rangesPointIntoTheirTexts() {
        let original = "send u the doc"
        let rewritten = "send you the doc"
        for segment in Differ.diff(original: original, rewritten: rewritten) {
            if let range = segment.originalRange { #expect(String(original[range]) == segment.text) }
            if let range = segment.rewrittenRange { #expect(String(rewritten[range]) == segment.text) }
        }
    }
}
