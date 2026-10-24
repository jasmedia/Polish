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
    /// The plain-text path turns Slack mentions into ordinary words; the panel says so.
    let pastesMentionsAsText: Bool
    var showRemovals = false
    var isEditing = false
    var editedText = ""

    init(draft: String, state: State = .loading) {
        self.state = state
        pastesMentionsAsText = draft.contains(/(?:^|\s)@[A-Za-z]/)
    }

    var result: PolishResult? {
        if case .result(let result) = state { result } else { nil }
    }

    var failure: Failure? {
        if case .failed(let failure) = state { failure } else { nil }
    }

    /// The text Accept puts back: the edit when the user edited, else the rewrite.
    var acceptedText: String? {
        guard let result else { return nil }
        return isEditing ? editedText : result.text
    }
}
