import Testing
@testable import Polish
import PolishCore

@MainActor
struct QuickWindowTests {
    final class Clipboard {
        var copied: [String] = []
    }

    func model(_ replies: [String], tone: Tone = .keep, clipboard: Clipboard = Clipboard()) -> (QuickWindowModel, FixedModel) {
        let fixed = FixedModel(replies)
        let model = QuickWindowModel(pipeline: Pipeline(model: fixed), tone: tone) { clipboard.copied.append($0) }
        return (model, fixed)
    }

    @Test func polishesAndCopiesTheRewrite() async {
        let clipboard = Clipboard()
        let (model, _) = model(["I will send the report tomorrow."], clipboard: clipboard)
        model.text = "i will send the report tmrw"
        model.polish()
        await model.work?.value
        #expect(model.result?.text == "I will send the report tomorrow.")

        model.copyResult()
        #expect(clipboard.copied == ["I will send the report tomorrow."])
    }

    @Test func usesThePickedTone() async {
        let (model, fixed) = model(["Hey, I'll send the report tomorrow!"])
        model.text = "i will send the report tmrw"
        model.tone = .professional
        model.polish()
        await model.work?.value
        #expect(fixed.requests.last?.instructions.contains("Tone: professional") == true)
    }

    @Test func showsTheChangeListWhenItIsOn() async {
        let fixed = FixedModel(["I will send the report tomorrow."])
        let model = QuickWindowModel(pipeline: Pipeline(model: fixed), tone: .keep, showChanges: { true }) { _ in }
        model.text = "i will send the report tmrw"
        model.polish()
        await model.work?.value
        #expect(model.showsChanges)
        #expect(model.result?.changes.map(\.reason) == [.capitalization, .shorthand])
    }

    @Test func editingTheTextClearsAStaleResult() async {
        let clipboard = Clipboard()
        let (model, _) = model(["I will send the report tomorrow."], clipboard: clipboard)
        model.text = "i will send the report tmrw"
        model.polish()
        await model.work?.value
        model.text += " pls"
        #expect(model.result == nil)
        model.copyResult()
        #expect(clipboard.copied.isEmpty)
    }

    @Test func emptyTextCantBePolished() {
        let (model, fixed) = model([])
        model.text = "   \n"
        #expect(!model.canPolish)
        model.polish()
        #expect(model.work == nil)
        #expect(fixed.requests.isEmpty)
    }

    @Test func modelErrorsShowAMessage() async {
        let fixed = FixedModel([], status: .unavailable(.appleIntelligenceNotEnabled))
        let model = QuickWindowModel(pipeline: Pipeline(model: fixed), tone: .keep) { _ in }
        model.text = "i will send the report tmrw"
        model.polish()
        await model.work?.value
        guard case .failed = model.state else {
            Issue.record("expected a failure, got \(model.state)")
            return
        }
    }
}
