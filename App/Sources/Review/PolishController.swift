import Observation
import PolishCore
import CoreGraphics

/// Shows and hides the review panel. The AppKit panel in the app; a recorder in tests.
@MainActor
protocol ReviewPresenting: AnyObject {
    func show(_ review: ReviewModel, near anchor: CGRect?)
    func close()
}

/// One hotkey press end to end: read the draft, polish it, review, put the rewrite back (Flow A).
/// Every error path leaves the user's text as it was.
@MainActor
@Observable
final class PolishController {
    private(set) var review: ReviewModel?

    @ObservationIgnored private let bridge: any TextBridging
    @ObservationIgnored private let pipeline: Pipeline
    @ObservationIgnored private unowned let presenter: any ReviewPresenting
    @ObservationIgnored private var draft: Draft?
    /// The running read, polish or replace. Internal so tests can await it.
    @ObservationIgnored private(set) var work: Task<Void, Never>?
    @ObservationIgnored var unchangedCloseDelay: Duration = .seconds(1.5)

    init(bridge: any TextBridging, pipeline: Pipeline, presenter: any ReviewPresenting) {
        self.bridge = bridge
        self.pipeline = pipeline
        self.presenter = presenter
    }

    func polishFocusedField() {
        start { try await $0.readFocusedField() }
    }

    func polishClipboard() {
        start { try $0.readClipboard() }
    }

    func accept() {
        guard let review, let draft, let text = review.acceptedText else { return }
        dismiss()
        work = Task {
            do {
                try await bridge.replace(draft, with: text)
            } catch {
                let failure = (error as? BridgeError).map(ReviewModel.Failure.init)
                    ?? ReviewModel.Failure(message: "Couldn't put the rewrite back. Your text wasn't changed.")
                Log.bridge.error("Replace failed: \(String(describing: error), privacy: .public)")
                show(ReviewModel(draft: "", state: .failed(failure)), near: draft.anchor)
            }
        }
    }

    func copy() {
        guard let text = review?.acceptedText else { return }
        bridge.copyToClipboard(text)
        dismiss()
    }

    func cancel() {
        work?.cancel()
        work = nil
        dismiss()
    }

    func perform(_ action: ReviewModel.Failure.Action) {
        switch action {
        case .openAccessibilitySettings:
            Accessibility.requestTrust()
            SystemSettings.open(.accessibility)
        case .openAppleIntelligenceSettings:
            SystemSettings.open(.appleIntelligence)
        }
        cancel()
    }

    /// Retries a request that failed because the model was still downloading (FR-7).
    func modelStatusChanged(_ status: ModelStatus) {
        guard status.isReady, let review, review.failure?.retriesWhenReady == true, let draft else { return }
        Log.ui.info("Model became ready; retrying")
        work = Task { await polish(draft.text, into: review) }
    }

    // MARK: Steps

    private func start(read: @escaping @MainActor (any TextBridging) async throws -> Draft) {
        cancel()
        pipeline.prewarm()
        let clock = ContinuousClock()
        let pressed = clock.now
        work = Task {
            let draft: Draft
            do {
                draft = try await read(bridge)
            } catch {
                guard !Task.isCancelled else { return }
                let failure = (error as? BridgeError).map(ReviewModel.Failure.init)
                    ?? ReviewModel.Failure(message: "Couldn't read the text.")
                Log.bridge.error("Read failed: \(String(describing: error), privacy: .public)")
                show(ReviewModel(draft: "", state: .failed(failure)), near: nil)
                return
            }
            guard !Task.isCancelled else { return }
            self.draft = draft
            let review = ReviewModel(draft: draft.text)
            show(review, near: draft.anchor)
            Log.ui.info("Hotkey to panel: \((clock.now - pressed).milliseconds, privacy: .public)")
            await polish(draft.text, into: review, pressed: pressed)
        }
    }

    /// `pressed` is when the hotkey fired; when given, the time to the result or error is logged.
    private func polish(_ text: String, into review: ReviewModel, pressed: ContinuousClock.Instant? = nil) async {
        review.state = .loading
        do {
            let result = try await pipeline.polish(text: text)
            guard !Task.isCancelled, self.review === review else { return }
            logResultTime(since: pressed)
            if result.isUnchanged {
                review.state = .unchanged
                try await Task.sleep(for: unchangedCloseDelay)
                if self.review === review { dismiss() }
            } else {
                review.editedText = result.text
                review.state = .result(result)
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.review === review else { return }
            let polishError = error as? PolishError ?? .generationFailed(code: String(describing: type(of: error)))
            Log.engine.error("Polish failed: \(polishError.code, privacy: .public)")
            logResultTime(since: pressed)
            review.state = .failed(ReviewModel.Failure(polishError))
        }
    }

    private func logResultTime(since pressed: ContinuousClock.Instant?) {
        guard let pressed else { return }
        Log.ui.info("Hotkey to result: \((ContinuousClock.now - pressed).milliseconds, privacy: .public)")
    }

    private func show(_ review: ReviewModel, near anchor: CGRect?) {
        self.review = review
        presenter.show(review, near: anchor)
    }

    private func dismiss() {
        review = nil
        presenter.close()
    }
}

private extension Duration {
    /// Whole milliseconds ("142ms"), to check the latency targets: < 150 ms to panel, < 3 s to result.
    var milliseconds: String {
        formatted(.units(allowed: [.milliseconds], width: .narrow))
    }
}
