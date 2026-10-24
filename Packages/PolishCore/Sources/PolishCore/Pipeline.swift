import Foundation
import Synchronization

/// The outcome of one polish request.
public struct PolishResult: Sendable {
    public var original: String
    /// The rewrite, or `original` exactly when nothing changed or validation fell back.
    public var text: String
    public var diff: [DiffSegment]
    /// Notable fixes, when the change list was requested.
    public var changes: [Change]
    /// Validation failures of chunks that kept their original text. Empty when the rewrite was accepted.
    public var fallbacks: [[ValidationFailure]]
    public var trace: Trace

    public var isUnchanged: Bool { text == original }
    /// True when at least one part of the message kept its original text because no rewrite passed validation.
    public var didFallBack: Bool { !fallbacks.isEmpty }

    /// What happened inside the pipeline, for the eval harness and logs. Texts are in placeholder form.
    public struct Trace: Sendable {
        public var placeholders: Int
        public var chunks: [ChunkTrace]
        public var duration: Duration
    }

    public struct ChunkTrace: Sendable {
        public var attempts: [Attempt]
        /// True when this chunk had to be split again after overflowing the context.
        public var rechunked: Bool
    }

    public struct Attempt: Sendable {
        public var temperature: Double
        public var raw: String
        public var mistakes: [String]
        public var failures: [ValidationFailure]
    }
}

/// The rewrite pipeline: normalize, protect, budget and chunk, generate, validate (retry once at
/// temperature 0), restore. The model never sees raw Slack syntax, and any output that fails
/// validation is replaced by the original text.
public final class Pipeline: Sendable {
    public struct Configuration: Sendable {
        public var temperature: Double = 0.2
        /// Undo expansions of contractions and work words the draft used.
        public var keepWriterStyle = true
        /// Share of the context a request may use before the draft is chunked.
        public var budgetShare = 0.7

        public init() {}
    }

    private let model: any RewriteModel
    private let protector: Protector
    private let instructions: InstructionsBuilder
    private let configuration: Configuration
    /// Input budget in tokens per (tone, change list) pair, computed once from the model's context size.
    private let budgets = Mutex<[String: Int]>([:])

    public init(
        model: any RewriteModel = FoundationModelBackend(),
        dictionary: [String] = [],
        instructions: InstructionsBuilder = InstructionsBuilder(),
        configuration: Configuration = Configuration()
    ) {
        self.model = model
        protector = Protector(dictionary: dictionary)
        self.instructions = instructions
        self.configuration = configuration
    }

    /// Call when the hotkey is pressed, before the text is read, to hide model load time.
    public func prewarm(tone: Tone = .keep) {
        model.prewarm(instructions: instructions.build(tone: tone, placeholders: []))
    }

    public func polish(text original: String, tone: Tone = .keep, withChanges: Bool = false) async throws -> PolishResult {
        let clock = ContinuousClock()
        let start = clock.now
        if case .unavailable(let reason) = model.status {
            throw PolishError.modelUnavailable(reason)
        }

        let protected: ProtectedText
        do {
            protected = try protector.protect(original)
        } catch {
            throw PolishError.unsupportedText
        }
        let source = Normalizer.normalize(protected.text)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let trace = PolishResult.Trace(placeholders: protected.tokens.count, chunks: [], duration: clock.now - start)
            return PolishResult(original: original, text: original, diff: Differ.diff(original: original, rewritten: original),
                                changes: [], fallbacks: [], trace: trace)
        }

        let budget = try await inputBudget(tone: tone, withChanges: withChanges)
        let chunks = try await split(source, budget: budget)

        var output = ""
        var changes: [Change] = []
        var fallbacks: [[ValidationFailure]] = []
        var traces: [PolishResult.ChunkTrace] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let rewritten = try await rewrite(chunk.text, protected: protected, tone: tone, withChanges: withChanges,
                                              budget: budget, allowRechunk: true)
            output += rewritten.text + chunk.separator
            changes += rewritten.changes
            fallbacks += rewritten.fallbacks
            traces.append(rewritten.trace)
        }

        var text = protected.restore(output)
        if text == protected.restore(source) {
            text = original  // only normalization changed: give back the draft byte for byte
        }
        let changeList = changes.map {
            Change(from: protected.restore($0.from), to: protected.restore($0.to), reason: $0.reason)
        }
        let trace = PolishResult.Trace(placeholders: protected.tokens.count, chunks: traces, duration: clock.now - start)
        Log.engine.info("""
            Polished: \(chunks.count, privacy: .public) chunk(s), \
            \(traces.map(\.attempts.count).reduce(0, +), privacy: .public) attempt(s), \
            \(fallbacks.count, privacy: .public) fallback(s), \(trace.duration.formatted(), privacy: .public)
            """)
        return PolishResult(original: original, text: text, diff: Differ.diff(original: original, rewritten: text),
                            changes: changeList, fallbacks: fallbacks, trace: trace)
    }

    // MARK: Steps

    private struct Rewritten {
        var text: String
        var changes: [Change]
        var fallbacks: [[ValidationFailure]]
        var trace: PolishResult.ChunkTrace
    }

    /// Rewrites one chunk of protected text. Returns the chunk unchanged when no attempt passes validation.
    private func rewrite(
        _ source: String,
        protected: ProtectedText,
        tone: Tone,
        withChanges: Bool,
        budget: Int,
        allowRechunk: Bool
    ) async throws -> Rewritten {
        let numbers = Array(Set(Placeholder.numbers(in: source))).sorted()
        let request = GenerationRequest(
            instructions: instructions.build(tone: tone, placeholders: numbers, leading: leadingPlaceholder(source, protected)),
            prompt: source,
            temperature: configuration.temperature,
            maximumResponseTokens: source.unicodeScalars.count / 2 + 200,
            withChanges: withChanges
        )
        let validator = Validator(tone: tone)
        var attempts: [PolishResult.Attempt] = []

        for temperature in [configuration.temperature, 0] {
            var attempt = request
            attempt.temperature = temperature
            let response: GenerationResponse
            do {
                response = try await model.generate(attempt)
            } catch {
                guard let polishError = PolishError(modelError: error) else { throw error }
                Log.engine.error("Generation failed: \(polishError.code, privacy: .public)")
                if polishError == .tooLong, allowRechunk {
                    return try await rechunk(source, protected: protected, tone: tone, withChanges: withChanges, budget: budget)
                }
                throw polishError
            }
            let failures = validator.validate(response.text, source: source)
            attempts.append(.init(temperature: temperature, raw: response.text, mistakes: response.mistakes, failures: failures))
            if failures.isEmpty {
                let text = Restorer.apply(response.text, source: source, keepWriterStyle: configuration.keepWriterStyle)
                return Rewritten(text: text, changes: response.changes, fallbacks: [],
                                 trace: .init(attempts: attempts, rechunked: false))
            }
            Log.engine.info("Validation failed: \(failures.map(\.description).joined(separator: ", "), privacy: .public)")
        }
        return Rewritten(text: source, changes: [], fallbacks: [attempts.last?.failures ?? []],
                         trace: .init(attempts: attempts, rechunked: false))
    }

    /// The context overflowed: split the chunk under half the budget and rewrite the pieces, once.
    private func rechunk(
        _ source: String,
        protected: ProtectedText,
        tone: Tone,
        withChanges: Bool,
        budget: Int
    ) async throws -> Rewritten {
        let pieces = try await Chunker.split(source, budget: budget / 2) { try await model.tokenCount(prompt: $0) }
        guard pieces.count > 1 else { throw PolishError.tooLong }
        var result = Rewritten(text: "", changes: [], fallbacks: [], trace: .init(attempts: [], rechunked: true))
        for piece in pieces {
            try Task.checkCancellation()
            let rewritten = try await rewrite(piece.text, protected: protected, tone: tone, withChanges: withChanges,
                                              budget: budget / 2, allowRechunk: false)
            result.text += rewritten.text + piece.separator
            result.changes += rewritten.changes
            result.fallbacks += rewritten.fallbacks
            result.trace.attempts += rewritten.trace.attempts
        }
        return result
    }

    /// Splits only when the text could exceed the budget; short drafts skip the token count.
    private func split(_ source: String, budget: Int) async throws -> [Chunk] {
        // A token covers at least half a character, even for emoji and non-Latin scripts.
        if source.unicodeScalars.count * 2 <= budget {
            return [Chunk(text: source)]
        }
        return try await Chunker.split(source, budget: budget) { try await model.tokenCount(prompt: $0) }
    }

    /// Tokens left for the draft: the output is about as long as the input (up to +60%) and shares the
    /// context with the instructions and schema, so the input gets (share × context − fixed) / 2.6.
    func inputBudget(tone: Tone, withChanges: Bool) async throws -> Int {
        let key = "\(tone.rawValue)-\(withChanges)"
        if let cached = budgets.withLock({ $0[key] }) {
            return cached
        }
        // Instructions with a three-placeholder rule, as measured by eval/tokens.py.
        let sample = instructions.build(tone: tone, placeholders: [1, 2, 3])
        let fixed = try await model.tokenCount(instructions: sample, withChanges: withChanges)
        let budget = max(Int((Double(model.contextSize) * configuration.budgetShare - Double(fixed)) / 2.6), 1)
        budgets.withLock { $0[key] = budget }
        Log.engine.info("Input budget: \(budget, privacy: .public) tokens (context \(self.model.contextSize, privacy: .public))")
        return budget
    }

    /// The placeholder a chunk starts with, and whether it is a mention addressing someone.
    private func leadingPlaceholder(_ source: String, _ protected: ProtectedText) -> InstructionsBuilder.Leading? {
        guard let match = Placeholder.pattern.firstMatch(in: source), match.range.location == 0,
              let number = match.group(1, in: source as NSString).flatMap({ Int($0) }),
              protected.tokens.indices.contains(number - 1)
        else { return nil }
        let token = protected.tokens[number - 1]
        return .init(number: number, isMention: token.hasPrefix("@") || token.hasPrefix("<@"))
    }
}
