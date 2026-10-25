import FoundationModels
import Synchronization

/// One generation call: instructions and protected text in, rewrite out.
public struct GenerationRequest: Equatable, Sendable {
    public var instructions: String
    public var prompt: String
    public var temperature: Double
    public var maximumResponseTokens: Int
    public var withChanges: Bool
}

public struct GenerationResponse: Equatable, Sendable {
    public var text: String
    public var mistakes: [String]
    public var changes: [Change]
    /// Tokens the model read (instructions, schema and prompt) and wrote, when the model reports them.
    public var usage: TokenUsage?

    public init(text: String, mistakes: [String] = [], changes: [Change] = [], usage: TokenUsage? = nil) {
        self.text = text
        self.mistakes = mistakes
        self.changes = changes
        self.usage = usage
    }
}

public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int

    public init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output)
    }
}

/// What the pipeline needs from a language model. `FoundationModelBackend` is the real one;
/// tests use a scripted stand-in, so everything but generation runs without Apple Intelligence.
public protocol RewriteModel: Sendable {
    var status: ModelStatus { get }
    /// The model's context window in tokens. Read at runtime; it differs by OS version.
    var contextSize: Int { get }
    func tokenCount(prompt: String) async throws -> Int
    /// Tokens used by the instructions plus the output schema.
    func tokenCount(instructions: String, withChanges: Bool) async throws -> Int
    /// Loads the model ahead of a request (called when the hotkey is pressed).
    func prewarm(instructions: String)
    func generate(_ request: GenerationRequest) async throws -> GenerationResponse
    /// Like `generate(_:)`, calling `partialText` with the rewrite so far as the model writes it, so the
    /// panel can show it before the result is validated (FR-12).
    func generate(_ request: GenerationRequest, partialText: @escaping @Sendable (String) -> Void) async throws -> GenerationResponse
}

extension RewriteModel {
    /// Models that can't stream return the whole response at once.
    public func generate(_ request: GenerationRequest, partialText: @escaping @Sendable (String) -> Void) async throws -> GenerationResponse {
        try await generate(request)
    }
}

/// The on-device Apple Foundation Model. A new `LanguageModelSession` per request, so no transcript builds up.
public final class FoundationModelBackend: RewriteModel {
    private let model: SystemLanguageModel
    /// Keeps the prewarmed session alive until the next request.
    private let warmSession = Mutex<LanguageModelSession?>(nil)

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public var status: ModelStatus { .current(model: model) }

    public var contextSize: Int { model.contextSize }

    public func tokenCount(prompt: String) async throws -> Int {
        try await model.tokenCount(for: prompt)
    }

    public func tokenCount(instructions: String, withChanges: Bool) async throws -> Int {
        let schema = withChanges ? RewriteWithChanges.generationSchema : RewriteWithMistakes.generationSchema
        return try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: schema)
    }

    public func prewarm(instructions: String) {
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
        warmSession.withLock { $0 = session }
    }

    public func generate(_ request: GenerationRequest) async throws -> GenerationResponse {
        let (session, options) = start(request)
        if request.withChanges {
            return GenerationResponse(try await session.respond(to: request.prompt, generating: RewriteWithChanges.self,
                                                                options: options))
        }
        return GenerationResponse(try await session.respond(to: request.prompt, generating: RewriteWithMistakes.self,
                                                            options: options))
    }

    public func generate(_ request: GenerationRequest, partialText: @escaping @Sendable (String) -> Void) async throws -> GenerationResponse {
        let (session, options) = start(request)
        // The schema puts `mistakes` first, so text arrives only once the list is written.
        if request.withChanges {
            let stream = session.streamResponse(to: request.prompt, generating: RewriteWithChanges.self, options: options)
            for try await snapshot in stream {
                if let text = snapshot.content.text { partialText(text) }
            }
            return GenerationResponse(try await stream.collect())
        }
        let stream = session.streamResponse(to: request.prompt, generating: RewriteWithMistakes.self, options: options)
        for try await snapshot in stream {
            if let text = snapshot.content.text { partialText(text) }
        }
        return GenerationResponse(try await stream.collect())
    }

    private func start(_ request: GenerationRequest) -> (LanguageModelSession, GenerationOptions) {
        warmSession.withLock { $0 = nil }
        let session = LanguageModelSession(model: model, instructions: request.instructions)
        let options = GenerationOptions(
            temperature: request.temperature,
            // Cap the response so a looping generation fails fast instead of filling the context.
            maximumResponseTokens: request.maximumResponseTokens
        )
        return (session, options)
    }
}

extension GenerationResponse {
    init(_ result: LanguageModelSession.Response<RewriteWithMistakes>) {
        self.init(text: result.content.text, mistakes: result.content.mistakes, usage: TokenUsage(result.usage))
    }

    init(_ result: LanguageModelSession.Response<RewriteWithChanges>) {
        let changes = result.content.changes.map { Change(from: $0.from, to: $0.to, reason: $0.reason) }
        self.init(text: result.content.text, mistakes: result.content.mistakes, changes: changes, usage: TokenUsage(result.usage))
    }
}

extension TokenUsage {
    init(_ usage: LanguageModelSession.Usage) {
        self.init(input: usage.input.totalTokenCount, output: usage.output.totalTokenCount)
    }
}
