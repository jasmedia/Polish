import Synchronization
import Testing
@testable import PolishCore

/// A model that answers from a script, one entry per `generate` call.
final class ScriptedModel: RewriteModel {
    enum Reply: Sendable {
        case text(String)
        case echo(@Sendable (String) -> String)
        case fail(any Error)
    }

    let status: ModelStatus
    let contextSize: Int
    private let replies: Mutex<[Reply]>
    private let log = Mutex<[GenerationRequest]>([])

    init(_ replies: [Reply], status: ModelStatus = .ready, contextSize: Int = 8192) {
        self.replies = Mutex(replies)
        self.status = status
        self.contextSize = contextSize
    }

    var requests: [GenerationRequest] { log.withLock { $0 } }

    func tokenCount(prompt: String) async throws -> Int { prompt.split(whereSeparator: \.isWhitespace).count }
    func tokenCount(instructions: String, withChanges: Bool) async throws -> Int { 100 }
    func prewarm(instructions: String) {}

    func generate(_ request: GenerationRequest) async throws -> GenerationResponse {
        log.withLock { $0.append(request) }
        let reply = replies.withLock { $0.isEmpty ? Reply.echo { $0 } : $0.removeFirst() }
        switch reply {
        case .text(let text):
            return GenerationResponse(text: text, mistakes: ["x"], usage: TokenUsage(input: 100, output: text.count / 4))
        case .echo(let transform): return GenerationResponse(text: transform(request.prompt))
        case .fail(let error): throw error
        }
    }

    /// Streams each reply in two pieces: up to its middle, then whole.
    func generate(_ request: GenerationRequest, partialText: @escaping @Sendable (String) -> Void) async throws -> GenerationResponse {
        let response = try await generate(request)
        partialText(String(response.text.prefix(response.text.count / 2)))
        partialText(response.text)
        return response
    }
}

struct PipelineTests {
    @Test func recordsTokenUsagePerAttempt() async throws {
        let model = ScriptedModel([.text("I will send you the report tomorrow.")])
        let result = try await Pipeline(model: model).polish(text: "i will send u the report tmrw")
        #expect(result.trace.chunks.flatMap(\.attempts).map(\.usage) == [TokenUsage(input: 100, output: 9)])
    }

    @Test func protectsGeneratesAndRestores() async throws {
        let model = ScriptedModel([.text("⟦T1⟧, I will send you the report tomorrow.")])
        let result = try await Pipeline(model: model).polish(text: "<@U1> i will send u the report tmrw")
        #expect(result.text == "<@U1>, I will send you the report tomorrow.")
        #expect(!result.didFallBack)
        #expect(model.requests.count == 1)
        #expect(model.requests[0].prompt == "⟦T1⟧ i will send u the report tmrw")
        #expect(model.requests[0].temperature == 0.2)
        #expect(model.requests[0].instructions.contains("keep ⟦T1⟧ at the start"))
        #expect(model.requests[0].maximumResponseTokens == "⟦T1⟧ i will send u the report tmrw".unicodeScalars.count / 2 + 200)
    }

    @Test func retriesOnceAtTemperatureZero() async throws {
        let model = ScriptedModel([.text("I will send it."), .text("⟦T1⟧, I will send it.")])
        let result = try await Pipeline(model: model).polish(text: "<@U1> i will send it")
        #expect(result.text == "<@U1>, I will send it.")
        #expect(model.requests.map(\.temperature) == [0.2, 0])
        #expect(result.trace.chunks[0].attempts.map(\.failures) == [[.missing(1)], []])
    }

    @Test func fallsBackToTheOriginalAfterTwoFailures() async throws {
        let model = ScriptedModel([.text("Sent."), .text("")])
        let draft = "<@U1> i will send it"
        let result = try await Pipeline(model: model).polish(text: draft)
        #expect(result.text == draft)
        #expect(result.isUnchanged)
        #expect(result.fallbacks == [[.empty]])
    }

    @Test func appliesLayoutStyleAndQuotes() async throws {
        let model = ScriptedModel([.text("I will post the doc.\nIt is “ready”.")])
        let result = try await Pipeline(model: model).polish(text: "i'll post the doc\n\nits 'ready'")
        #expect(result.text == "I'll post the doc.\n\nIt is \"ready\".")
    }

    @Test func otherTonesSendTheWholeDraftFirst() async throws {
        let model = ScriptedModel([])
        _ = try await Pipeline(model: model).polish(text: "todo for the sprint:\n- fix the bug", tone: .casual)
        #expect(model.requests.map(\.prompt) == ["todo for the sprint:\n- fix the bug"])
    }

    @Test func mergedLinesAreRewrittenByParagraph() async throws {
        let model = ScriptedModel([.text("Todo for the sprint: fix the bug ⟦T1⟧ ⟦T2⟧ thanks all")])
        let draft = "todo for the sprint:\n- fix the bug\n\n```\nmake test\n```\n:tada:\n\nthanks all"
        let result = try await Pipeline(model: model).polish(text: draft, tone: .casual)
        // The code block and emoji paragraph has no words, so it isn't sent.
        #expect(model.requests.map(\.prompt).dropFirst() == ["todo for the sprint:\n- fix the bug", "thanks all"])
        // Three words or fewer: Keep my tone, since short lines restyled alone invent text.
        #expect(model.requests.map { $0.instructions.contains("Tone: casual") } == [true, true, false])
        #expect(result.trace.chunks[0].splitAfterMerge)
        #expect(result.text == draft)
    }

    @Test func aParagraphThatMergesAgainGoesLineByLine() async throws {
        let model = ScriptedModel([
            .text("Todo for the sprint: fix the bug. Thanks all"),
            .text("Todo for the sprint: fix the bug"),
        ])
        let draft = "todo for the sprint:\n- fix the bug\n\nthanks all"
        _ = try await Pipeline(model: model).polish(text: draft, tone: .casual)
        #expect(model.requests.map(\.prompt) == [
            draft, "todo for the sprint:\n- fix the bug", "todo for the sprint:", "- fix the bug", "thanks all",
        ])
        #expect(model.requests.map(\.temperature).allSatisfy { $0 == 0.2 })
    }

    @Test func reportsProgressAsPartsFinish() async throws {
        let model = ScriptedModel([.text("Todo for the sprint: fix the bug ⟦T1⟧ ⟦T2⟧ thanks all")])
        let draft = "todo for the sprint:\n- fix the bug\n\n```\nmake test\n```\n:tada:\n\nthanks all"
        let events = Mutex<[PolishProgress]>([])
        _ = try await Pipeline(model: model).polish(text: draft, tone: .casual) { progress in
            events.withLock { $0.append(progress) }
        }
        // One part until the merge, then the two paragraphs with words.
        #expect(events.withLock { $0 }.map { [$0.completed, $0.total] } == [[0, 1], [0, 2], [1, 2], [2, 2]])
    }

    @Test func previewStreamsTheRewriteWithPlaceholdersRestored() async throws {
        let model = ScriptedModel([.text("⟦T1⟧, I will send you the report tomorrow.")])
        let previews = Mutex<[String]>([])
        _ = try await Pipeline(model: model).polish(text: "<@U1> i will send u the report tmrw", preview: { text in
            previews.withLock { $0.append(text) }
        })
        let seen = previews.withLock { $0 }
        #expect(seen.last == "<@U1>, I will send you the report tomorrow.")
        #expect(seen.count == 2)
        #expect(seen.allSatisfy { !$0.contains("⟦") })
    }

    @Test(arguments: [("Hi ⟦T", "Hi "), ("Hi ⟦T12", "Hi "), ("Hi ⟦T1⟧ there", "Hi ⟦T1⟧ there"), ("⟦T1⟧ and ⟦", "⟦T1⟧ and ")])
    func displayableHidesAHalfWrittenPlaceholder(partial: String, shown: String) {
        #expect(Pipeline.displayable(partial) == shown)
    }

    @Test func dictionaryWordsNeverReachTheModel() async throws {
        let model = ScriptedModel([.text("Ask ⟦T1⟧ about the deploy."), .text("Ask Kubeflo about the deploy.")])
        let pipeline = Pipeline(model: model)
        pipeline.dictionary = ["Kubeflo"]
        let result = try await pipeline.polish(text: "ask Kubeflo abt the deploy")
        #expect(model.requests[0].prompt == "ask ⟦T1⟧ abt the deploy")
        #expect(result.text == "Ask Kubeflo about the deploy.")

        pipeline.dictionary = []
        _ = try await pipeline.polish(text: "ask Kubeflo abt the deploy")
        #expect(model.requests[1].prompt == "ask Kubeflo abt the deploy")
    }

    @Test func shortDraftIsOnePart() async throws {
        let events = Mutex<[PolishProgress]>([])
        _ = try await Pipeline(model: ScriptedModel([])).polish(text: "i will send it tmrw") { progress in
            events.withLock { $0.append(progress) }
        }
        #expect(events.withLock { $0 } == [PolishProgress(completed: 0, total: 1), PolishProgress(completed: 1, total: 1)])
    }

    @Test func keepSendsLinesTogether() async throws {
        let model = ScriptedModel([])
        _ = try await Pipeline(model: model).polish(text: "todo:\n- fix the bug\n- add tests")
        #expect(model.requests.map(\.prompt) == ["todo:\n- fix the bug\n- add tests"])
    }

    @Test func otherTonesKeepWrittenOutContractions() async throws {
        let model = ScriptedModel([.text("I will post the doc.\nIt is “ready”.")])
        let result = try await Pipeline(model: model).polish(text: "i'll post the doc\n\nits 'ready'", tone: .professional)
        #expect(result.text == "I will post the doc.\n\nIt is \"ready\".")
    }

    @Test func unchangedDraftComesBackByteForByte() async throws {
        let draft = "Thanks, I'll take a look.   \r\nSee you."
        let model = ScriptedModel([.echo { $0 }])
        let result = try await Pipeline(model: model).polish(text: draft)
        #expect(result.text == draft)
        #expect(model.requests[0].prompt == "Thanks, I'll take a look.\nSee you.")
    }

    @Test func emptyDraftNeverCallsTheModel() async throws {
        let model = ScriptedModel([])
        let result = try await Pipeline(model: model).polish(text: "  \n ")
        #expect(result.isUnchanged)
        #expect(model.requests.isEmpty)
    }

    @Test func unavailableModelThrows() async {
        let model = ScriptedModel([], status: .unavailable(.appleIntelligenceNotEnabled))
        await #expect(throws: PolishError.modelUnavailable(.appleIntelligenceNotEnabled)) {
            try await Pipeline(model: model).polish(text: "hello")
        }
    }

    @Test func draftWithPlaceholderTextThrows() async {
        await #expect(throws: PolishError.unsupportedText) {
            try await Pipeline(model: ScriptedModel([])).polish(text: "a ⟦T1⟧ b")
        }
    }

    @Test func generationErrorsBecomePolishErrors() async {
        let model = ScriptedModel([.fail(PolishError.guardrail)])
        await #expect(throws: PolishError.guardrail) {
            try await Pipeline(model: model).polish(text: "hello there")
        }
    }

    @Test func longDraftsAreChunkedAndRejoined() async throws {
        // Context 400 → budget (280 − 100) / 2.6 = 69 words per chunk.
        let paragraph = Array(repeating: "word", count: 50).joined(separator: " ")
        let draft = "\(paragraph)\n\n<@U1> \(paragraph)\n\n\(paragraph)"
        let model = ScriptedModel([], contextSize: 400)
        let result = try await Pipeline(model: model).polish(text: draft)
        #expect(model.requests.count == 3)
        #expect(model.requests[1].instructions.contains("⟦T1⟧"))
        #expect(!model.requests[0].instructions.contains("⟦T1⟧"))
        #expect(result.text == draft)
    }

    @Test func contextOverflowRechunksOnce() async throws {
        let sentence = Array(repeating: "word", count: 20).joined(separator: " ") + "."
        let draft = Array(repeating: sentence, count: 3).joined(separator: " ")
        let model = ScriptedModel([.fail(PolishError.tooLong)], contextSize: 400)
        let result = try await Pipeline(model: model).polish(text: draft)
        #expect(result.trace.chunks[0].rechunked)
        #expect(model.requests.count == 4)  // the overflow, then three sentences
        #expect(result.text == draft)
    }

    @Test func secondOverflowIsAnError() async {
        let sentence = Array(repeating: "word", count: 20).joined(separator: " ") + "."
        let draft = Array(repeating: sentence, count: 3).joined(separator: " ")
        let model = ScriptedModel([.fail(PolishError.tooLong), .fail(PolishError.tooLong)], contextSize: 400)
        await #expect(throws: PolishError.tooLong) {
            try await Pipeline(model: model).polish(text: draft)
        }
    }

    @Test func cancellationStopsTheRequest() async {
        let model = ScriptedModel([.fail(CancellationError())])
        await #expect(throws: CancellationError.self) {
            try await Pipeline(model: model).polish(text: "hello there")
        }
    }

    @Test func changesHavePlaceholdersRestored() async throws {
        final class ChangesModel: RewriteModel {
            let status = ModelStatus.ready
            let contextSize = 8192
            func tokenCount(prompt: String) async throws -> Int { 1 }
            func tokenCount(instructions: String, withChanges: Bool) async throws -> Int { 100 }
            func prewarm(instructions: String) {}
            func generate(_ request: GenerationRequest) async throws -> GenerationResponse {
                GenerationResponse(text: "Ask ⟦T1⟧ to review it.",
                                   changes: [Change(from: "ask ⟦T1⟧ 2", to: "Ask ⟦T1⟧ to", reason: "wrong word")])
            }
        }
        let result = try await Pipeline(model: ChangesModel()).polish(text: "ask @Sam 2 review it", withChanges: true)
        #expect(result.changes == [Change(from: "ask @Sam 2", to: "Ask @Sam to", reason: "wrong word")])
    }

    @Test func budgetComesFromTheContextSize() async throws {
        let small = try await Pipeline(model: ScriptedModel([], contextSize: 4096)).inputBudget(tone: .keep, withChanges: false)
        let large = try await Pipeline(model: ScriptedModel([], contextSize: 8192)).inputBudget(tone: .keep, withChanges: false)
        #expect(small == Int((4096 * 0.7 - 100) / 2.6))
        #expect(large == Int((8192 * 0.7 - 100) / 2.6))
    }
}

struct PolishErrorTests {
    @Test func mapsCancellationToNil() {
        #expect(PolishError(modelError: CancellationError()) == nil)
    }

    @Test func unknownErrorsKeepOnlyTheirTypeName() {
        struct Strange: Error {}
        #expect(PolishError(modelError: Strange()) == .generationFailed(code: "Strange"))
    }

    @Test func everyErrorHasAMessage() {
        let errors: [PolishError] = [.modelUnavailable(.modelNotReady), .tooLong, .guardrail, .refusal,
                                     .unsupportedLanguage, .busy, .unsupportedText, .generationFailed(code: "x")]
        for error in errors {
            #expect(!error.message.isEmpty)
        }
    }
}
