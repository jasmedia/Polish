import Foundation
import Observation
import PolishCore

/// What the review panel shows for one hotkey press (FR-5).
@MainActor
@Observable
final class ReviewModel {
    enum State {
        case loading
        case result(PolishResult)
        /// Nothing to fix; the panel closes by itself.
        case unchanged
        case failed(Failure)
    }

    struct Failure: Equatable {
        enum Action: Equatable {
            case openAccessibilitySettings
            case openAppleIntelligenceSettings
        }

        var message: String
        var action: Action?
        /// The model is still downloading: polish again when it becomes ready.
        var retriesWhenReady = false

        init(message: String, action: Action? = nil, retriesWhenReady: Bool = false) {
            self.message = message
            self.action = action
            self.retriesWhenReady = retriesWhenReady
        }

        init(_ error: PolishError) {
            message = error.message
            switch error {
            case .modelUnavailable(.appleIntelligenceNotEnabled): action = .openAppleIntelligenceSettings
            case .modelUnavailable(.modelNotReady): retriesWhenReady = true
            default: break
            }
        }

        init(_ error: BridgeError) {
            message = error.message
            if error == .notTrusted {
                action = .openAccessibilitySettings
            }
        }
    }

    var state: State
    var tone: Tone
    /// Parts of a long draft done so far (FR-12); nil until the pipeline reports.
    private(set) var progress: PolishProgress?
    /// Counts polish runs (Tab starts a new one), so reports from a cancelled run are dropped.
    private var run = 0
    var showRemovals = false
    var isEditing = false
    var editedText = ""

    init(state: State = .loading, tone: Tone = .keep) {
        self.state = state
        self.tone = tone
    }

    /// Clears the progress for a new polish run and returns its number for `update(_:run:)`.
    func startRun() -> Int {
        run += 1
        progress = nil
        return run
    }

    /// Progress reports hop to the main actor one by one and can arrive out of order: keep the furthest.
    func update(_ progress: PolishProgress, run: Int) {
        guard run == self.run else { return }
        if let current = self.progress, progress.completed < current.completed || progress.total < current.total { return }
        self.progress = progress
    }

    /// What the loading state says: the part being worked on when the draft has more than one.
    var loadingTitle: String {
        guard let progress, progress.total > 1 else { return "Polishing…" }
        return "Polishing… part \(min(progress.completed + 1, progress.total)) of \(progress.total)"
    }

    /// Tab regenerates in the next tone; not after an error, and not while editing (Tab types there).
    var canChangeTone: Bool {
        if case .failed = state { return false }
        return !isEditing
    }

    var result: PolishResult? {
        if case .result(let result) = state { result } else { nil }
    }

    var failure: Failure? {
        if case .failed(let failure) = state { failure } else { nil }
    }

    /// What VoiceOver announces on each state change: the panel doesn't take VoiceOver focus from the
    /// app being typed in, so the result has to be spoken.
    var announcement: String {
        switch state {
        case .loading: return tone == .keep ? "Polishing" : "Polishing, \(tone.title)"
        case .result(let result):
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = text.last.map { ".?!".contains($0) } == true ? "" : "."
            return "Rewrite ready: \(text)\(end) Return to accept, Escape to cancel."
        case .unchanged: return "Looks good. No changes needed."
        case .failed(let failure): return failure.message
        }
    }

    /// The text Accept puts back: the edit when the user edited, else the rewrite.
    var acceptedText: String? {
        guard let result else { return nil }
        return isEditing ? editedText : result.text
    }
}
