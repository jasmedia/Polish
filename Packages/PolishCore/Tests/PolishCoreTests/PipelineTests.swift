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
