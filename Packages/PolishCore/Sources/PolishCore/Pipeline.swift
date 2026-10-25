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
        /// True when a restyle tone merged this chunk's lines and it was rewritten in parts.
        public var splitAfterMerge = false
    }

    public struct Attempt: Sendable {
        public var temperature: Double
        public var raw: String
        public var mistakes: [String]
        public var failures: [ValidationFailure]
        public var usage: TokenUsage?
        /// Time spent in the model for this attempt.
        public var duration: Duration
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

    /// - Parameters:
    ///   - progress: called as parts of a long draft finish, so the panel can show how far along it is
    ///     (FR-12). A short draft is one part; the total grows when a part is split again.
    ///   - preview: called with the part being written so far, placeholders restored, as the model streams
    ///     it. Not validated yet: for display while loading only. Without it the model doesn't stream.
    public func polish(
        text original: String,
        tone: Tone = .keep,
        withChanges: Bool = false,
        progress: (@Sendable (PolishProgress) -> Void)? = nil,
        preview: (@Sendable (String) -> Void)? = nil
    ) async throws -> PolishResult {
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
        let tracker = ProgressTracker(total: chunks.count, report: progress, preview: preview)
        for chunk in chunks {
            try Task.checkCancellation()
            let rewritten = try await rewrite(chunk.text, protected: protected, tone: tone, withChanges: withChanges,
                                              budget: budget, allowRechunk: true, allowLineSplit: true, progress: tracker)
            tracker.finish()
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
        let attempts = traces.flatMap(\.attempts)
        let usage = attempts.compactMap(\.usage).reduce(TokenUsage(input: 0, output: 0), +)
        Log.engine.info("""
            Polished: \(chunks.count, privacy: .public) chunk(s), \(attempts.count, privacy: .public) attempt(s), \
            \(fallbacks.count, privacy: .public) fallback(s), \
            \(usage.input, privacy: .public) tokens in, \(usage.output, privacy: .public) out, \
            \(trace.duration.formatted(.units(allowed: [.milliseconds], width: .narrow)), privacy: .public)
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
        allowRechunk: Bool,
        allowLineSplit: Bool,
        progress: ProgressTracker
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
            let generationStart = ContinuousClock.now
            do {
                if let preview = progress.preview {
                    response = try await model.generate(attempt) { partial in
                        preview(Self.displayable(protected.restore(partial)))
                    }
                } else {
                    response = try await model.generate(attempt)
                }
            } catch {
                guard let polishError = PolishError(modelError: error) else { throw error }
                Log.engine.error("Generation failed: \(polishError.code, privacy: .public)")
                if polishError == .tooLong, allowRechunk {
                    return try await rechunk(source, protected: protected, tone: tone, withChanges: withChanges, budget: budget,
                                             progress: progress)
                }
                throw polishError
            }
            if let usage = response.usage {
                Log.engine.debug("""
                    Attempt at temperature \(temperature, format: .fixed(precision: 1), privacy: .public): \(usage.input, privacy: .public) tokens in, \
                    \(usage.output, privacy: .public) out (cap \(attempt.maximumResponseTokens, privacy: .public), \
                    context \(self.model.contextSize, privacy: .public))
                    """)
            }
            let failures = validator.validate(response.text, source: source)
            attempts.append(.init(temperature: temperature, raw: response.text, mistakes: response.mistakes,
                                  failures: failures, usage: response.usage, duration: .now - generationStart))
            if failures.isEmpty {
                // Other tones change contractions on purpose (Professional writes them out), so only Keep undoes that.
                let keepStyle = configuration.keepWriterStyle && tone == .keep
                let text = Restorer.apply(response.text, source: source, keepWriterStyle: keepStyle)
                return Rewritten(text: text, changes: response.changes, fallbacks: [],
                                 trace: .init(attempts: attempts, rechunked: false))
            }
            Log.engine.info("Validation failed: \(failures.map(\.description).joined(separator: ", "), privacy: .public)")
            // Restyle tones merge lines they see together, and a retry rarely fixes that (eval/RESULTS.md).
            if tone != .keep, allowLineSplit, failures.contains(.lines) {
                return try await rewriteInParts(source, protected: protected, tone: tone, withChanges: withChanges,
                                               budget: budget, firstAttempt: attempts, progress: progress)
            }
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
        budget: Int,
        progress: ProgressTracker
    ) async throws -> Rewritten {
        let pieces = try await Chunker.split(source, budget: budget / 2) { try await model.tokenCount(prompt: $0) }
        guard pieces.count > 1 else { throw PolishError.tooLong }
        var result = Rewritten(text: "", changes: [], fallbacks: [], trace: .init(attempts: [], rechunked: true))
        // The caller counts this chunk as one finished part; each piece but the last is a new one.
        progress.grow(pieces.count - 1)
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            let rewritten = try await rewrite(piece.text, protected: protected, tone: tone, withChanges: withChanges,
                                              budget: budget / 2, allowRechunk: false, allowLineSplit: true,
                                              progress: progress)
            if index < pieces.count - 1 { progress.finish() }
            result.text += rewritten.text + piece.separator
            result.changes += rewritten.changes
            result.fallbacks += rewritten.fallbacks
            result.trace.attempts += rewritten.trace.attempts
        }
        return result
    }

    /// A restyle tone merged lines: rewrite each paragraph on its own, and a paragraph that merges again
    /// line by line. Paragraphs first, because every call repeats the mistakes list and schema overhead:
    /// a draft rewritten line by line wrote 2.5–6× the tokens of one call (eval/RESULTS.md, FR-12).
    /// A part without words (a code block, an emoji or a link alone) stays as it is. A part of three words
    /// or fewer gets Keep my tone: a restyle of a short line alone (`todo for release:`) tends to invent
    /// text or echo the format prompt.
    private func rewriteInParts(
        _ source: String,
        protected: ProtectedText,
        tone: Tone,
        withChanges: Bool,
        budget: Int,
        firstAttempt: [PolishResult.Attempt],
        progress: ProgressTracker
    ) async throws -> Rewritten {
        var result = Rewritten(text: "", changes: [], fallbacks: [],
                               trace: .init(attempts: firstAttempt, rechunked: false, splitAfterMerge: true))
        let paragraphs = Chunker.paragraphs(source)
        let byParagraph = paragraphs.count > 1
        let parts = byParagraph ? paragraphs : Chunker.lines(Chunk(text: source))
        // As in `rechunk`: the caller counts the chunk; every part sent to the model but the last is a new one.
        var partsLeft = parts.filter { Self.hasWords($0.text) }.count
        progress.grow(partsLeft - 1)
        for part in parts {
            try Task.checkCancellation()
            guard Self.hasWords(part.text) else {
                result.text += part.text + part.separator
                continue
            }
            let words = Placeholder.pattern.replacing(in: part.text, with: "").split(whereSeparator: \.isWhitespace).count
            let rewritten = try await rewrite(part.text, protected: protected, tone: words <= 3 ? .keep : tone,
                                              withChanges: withChanges, budget: budget, allowRechunk: false,
                                              allowLineSplit: byParagraph, progress: progress)
            partsLeft -= 1
            if partsLeft > 0 { progress.finish() }
            result.text += rewritten.text + part.separator
            result.changes += rewritten.changes
            result.fallbacks += rewritten.fallbacks
            result.trace.attempts += rewritten.trace.attempts
        }
        return result
    }

    /// Streamed text can end inside a placeholder (`⟦T`); hide that until it's complete.
    static func displayable(_ partial: String) -> String {
        guard let open = partial.lastIndex(of: "⟦"), !partial[open...].contains("⟧") else { return partial }
        return String(partial[..<open])
    }

    /// Whether a piece has any words outside its placeholders.
    static func hasWords(_ text: String) -> Bool {
        Placeholder.pattern.replacing(in: text, with: "").contains(where: \.isLetter)
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

/// How far a polish has got, in parts: chunks of a long draft, or lines of a chunk rewritten one by one.
public struct PolishProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

/// Counts finished parts for one polish and reports each change; also carries the preview callback.
final class ProgressTracker: Sendable {
    private let state: Mutex<PolishProgress>
    private let report: (@Sendable (PolishProgress) -> Void)?
    let preview: (@Sendable (String) -> Void)?

    init(total: Int, report: (@Sendable (PolishProgress) -> Void)?, preview: (@Sendable (String) -> Void)? = nil) {
        state = Mutex(PolishProgress(completed: 0, total: total))
        self.report = report
        self.preview = preview
        report?(PolishProgress(completed: 0, total: total))
    }

    func grow(_ parts: Int) {
        guard parts > 0 else { return }
        report?(state.withLock { $0.total += parts; return $0 })
    }

    func finish() {
        report?(state.withLock { $0.completed += 1; return $0 })
    }
}
