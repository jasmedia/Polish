import Observation
import PolishCore

/// The quick window (FR-10, Flow B): type or paste text, pick a tone, polish, copy. The text is typed
/// in Polish's own window, so it goes straight to the pipeline, never through the text bridge.
@MainActor
@Observable
final class QuickWindowModel {
    enum State {
        case idle
        case running
        case result(PolishResult)
        case failed(String)
    }

    var text = "" {
        // An edit makes the old result stale.
        didSet { if text != oldValue, !isRunning { state = .idle } }
    }
    var tone: Tone
    var showRemovals = false
    private(set) var state: State = .idle
    private(set) var progress: PolishProgress?
    private(set) var preview: String?

    @ObservationIgnored private let pipeline: Pipeline
    @ObservationIgnored private let copy: (String) -> Void
    /// The running polish. Internal so tests can await it.
    @ObservationIgnored private(set) var work: Task<Void, Never>?
    @ObservationIgnored private var run = 0

    init(pipeline: Pipeline, tone: Tone, copy: @escaping (String) -> Void) {
        self.pipeline = pipeline
        self.tone = tone
        self.copy = copy
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var canPolish: Bool {
        !isRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var result: PolishResult? {
        if case .result(let result) = state { result } else { nil }
    }

    func polish() {
        guard canPolish else { return }
        cancel()
        run += 1
        let run = run
        let text = text
        let tone = tone
        state = .running
        progress = nil
        preview = nil
        pipeline.prewarm(tone: tone)
        work = Task {
            do {
                let result = try await pipeline.polish(text: text, tone: tone, progress: { progress in
                    Task { @MainActor in if run == self.run { self.progress = progress } }
                }, preview: { partial in
                    Task { @MainActor in if run == self.run { self.preview = partial } }
                })
                guard !Task.isCancelled, run == self.run else { return }
                state = .result(result)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), run == self.run else { return }
                let polishError = error as? PolishError ?? .generationFailed(code: String(describing: type(of: error)))
                Log.engine.error("Quick window polish failed: \(polishError.code, privacy: .public)")
                state = .failed(polishError.message)
            }
        }
    }

    /// Stops a running polish (the window closed); the text stays as typed.
    func cancel() {
        work?.cancel()
        work = nil
        run += 1
        if isRunning { state = .idle }
    }

    func copyResult() {
        guard let result else { return }
        copy(result.text)
    }

    /// What the progress line says while running: the part, when the text has more than one.
    var runningTitle: String {
        PolishProgress.title(progress)
    }
}
