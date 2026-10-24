import CoreGraphics
import Synchronization
import Testing
@testable import Polish
import PolishCore

/// A model that returns fixed rewrites, so the controller runs without Apple Intelligence.
final class FixedModel: RewriteModel {
    private let state: Mutex<(status: ModelStatus, replies: [String], requests: [GenerationRequest])>
    let contextSize = 8192

    init(_ replies: [String], status: ModelStatus = .ready) {
        state = Mutex((status, replies, []))
    }

    var status: ModelStatus {
        get { state.withLock { $0.status } }
        set { state.withLock { $0.status = newValue } }
    }

    var requests: [GenerationRequest] { state.withLock { $0.requests } }

    func tokenCount(prompt: String) async throws -> Int { prompt.split(whereSeparator: \.isWhitespace).count }
    func tokenCount(instructions: String, withChanges: Bool) async throws -> Int { 100 }
    func prewarm(instructions: String) {}

    func generate(_ request: GenerationRequest) async throws -> GenerationResponse {
        let text = state.withLock {
            $0.requests.append(request)
            return $0.replies.isEmpty ? request.prompt : $0.replies.removeFirst()
        }
        return GenerationResponse(text: text, mistakes: ["x"])
    }
}

@MainActor
final class FakeBridge: TextBridging {
    var draft: Result<Draft, BridgeError>
    var replaceError: BridgeError?
    private(set) var replaced: [String] = []
    private(set) var copied: [String] = []

    init(_ text: String) {
        draft = .success(Draft(text: text, source: .focusedField, processID: 1))
    }

    func readFocusedField() async throws -> Draft { try draft.get() }
    func readClipboard() throws -> Draft { try draft.get() }

    func replace(_ draft: Draft, with text: String) async throws {
        if let replaceError { throw replaceError }
        replaced.append(text)
    }

    func copyToClipboard(_ text: String) {
        copied.append(text)
    }
}

@MainActor
final class RecordingPresenter: ReviewPresenting {
    private(set) var shown: [ReviewModel] = []
    private(set) var isOpen = false

    func show(_ review: ReviewModel, near anchor: CGRect?) {
        shown.append(review)
        isOpen = true
    }

    func close() {
        isOpen = false
    }
}

@MainActor
struct PolishControllerTests {
    let presenter = RecordingPresenter()

    func controller(_ bridge: FakeBridge, _ model: FixedModel, tone: Tone = .keep) -> PolishController {
        let controller = PolishController(bridge: bridge, pipeline: Pipeline(model: model), presenter: presenter,
                                          defaultTone: { tone })
        controller.unchangedCloseDelay = .zero
        return controller
    }

    @Test func acceptPutsTheRewriteBack() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let controller = controller(bridge, FixedModel(["I will send the report tomorrow."]))
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review?.result?.text == "I will send the report tomorrow.")

        controller.accept()
        await controller.work?.value
        #expect(bridge.replaced == ["I will send the report tomorrow."])
        #expect(!presenter.isOpen)
    }

    @Test func acceptUsesTheEditedText() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let controller = controller(bridge, FixedModel(["I will send the report tomorrow."]))
        controller.polishFocusedField()
        await controller.work?.value
        controller.review?.isEditing = true
        controller.review?.editedText = "I'll send the report tomorrow."

        controller.accept()
        await controller.work?.value
        #expect(bridge.replaced == ["I'll send the report tomorrow."])
    }

    @Test func unchangedClosesWithoutReplacing() async {
        let bridge = FakeBridge("The report is ready.")
        let controller = controller(bridge, FixedModel(["The report is ready."]))
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review == nil)
        #expect(!presenter.isOpen)
        #expect(bridge.replaced.isEmpty)
    }

    @Test func cancelLeavesTheTextAlone() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let controller = controller(bridge, FixedModel(["I will send the report tomorrow."]))
        controller.polishFocusedField()
        await controller.work?.value
        controller.cancel()
        controller.accept()
        await controller.work?.value
        #expect(bridge.replaced.isEmpty)
        #expect(!presenter.isOpen)
    }

    @Test func modelErrorShowsAMessageAndNeverReplaces() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let controller = controller(bridge, FixedModel([], status: .unavailable(.appleIntelligenceNotEnabled)))
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review?.failure?.action == .openAppleIntelligenceSettings)

        controller.accept()
        await controller.work?.value
        #expect(bridge.replaced.isEmpty)
    }

    @Test func missingPermissionOffersSettings() async {
        let bridge = FakeBridge("")
        bridge.draft = .failure(.notTrusted)
        let controller = controller(bridge, FixedModel([]))
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review?.failure?.action == .openAccessibilitySettings)
        #expect(presenter.isOpen)
    }

    @Test func retriesWhenTheModelFinishesDownloading() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let model = FixedModel(["I will send the report tomorrow."], status: .unavailable(.modelNotReady))
        let controller = controller(bridge, model)
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review?.failure?.retriesWhenReady == true)

        model.status = .ready
        controller.modelStatusChanged(.ready)
        await controller.work?.value
        #expect(controller.review?.result?.text == "I will send the report tomorrow.")
    }

    @Test func failedReplaceSaysSo() async {
        let bridge = FakeBridge("i will send the report tmrw")
        bridge.replaceError = .targetChanged
        let controller = controller(bridge, FixedModel(["I will send the report tomorrow."]))
        controller.polishFocusedField()
        await controller.work?.value
        controller.accept()
        await controller.work?.value
        #expect(controller.review?.failure?.message == BridgeError.targetChanged.message)
        #expect(bridge.replaced.isEmpty)
    }

    @Test func copyPutsTheRewriteOnTheClipboard() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let controller = controller(bridge, FixedModel(["I will send the report tomorrow."]))
        controller.polishFocusedField()
        await controller.work?.value
        controller.copy()
        #expect(bridge.copied == ["I will send the report tomorrow."])
        #expect(bridge.replaced.isEmpty)
    }

    @Test func polishesInTheDefaultTone() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let model = FixedModel(["Hey, I'll send the report tomorrow!"])
        let controller = controller(bridge, model, tone: .casual)
        controller.polishFocusedField()
        await controller.work?.value
        #expect(controller.review?.tone == .casual)
        #expect(model.requests.map(\.instructions).allSatisfy { $0.contains("Tone: casual") })
    }

    @Test func tabPolishesAgainInTheNextTone() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let model = FixedModel(["I will send the report tomorrow.", "Hey, I'll send the report tomorrow!"])
        let controller = controller(bridge, model)
        controller.polishFocusedField()
        await controller.work?.value
        controller.cycleTone()
        await controller.work?.value
        #expect(controller.review?.tone == .casual)
        #expect(model.requests.last?.instructions.contains("Tone: casual") == true)
        #expect(controller.review?.result?.text == "Hey, I'll send the report tomorrow!")

        controller.accept()
        await controller.work?.value
        #expect(bridge.replaced == ["Hey, I'll send the report tomorrow!"])
    }

    @Test func tabDoesNothingAfterAnError() async {
        let bridge = FakeBridge("i will send the report tmrw")
        let model = FixedModel([], status: .unavailable(.appleIntelligenceNotEnabled))
        let controller = controller(bridge, model)
        controller.polishFocusedField()
        await controller.work?.value
        controller.cycleTone()
        await controller.work?.value
        #expect(controller.review?.tone == .keep)
        #expect(controller.review?.failure != nil)
    }

    @Test func toneCyclesThroughAllAndWraps() {
        #expect(Tone.allCases.map(\.next) == [.casual, .professional, .concise, .keep])
    }
}
