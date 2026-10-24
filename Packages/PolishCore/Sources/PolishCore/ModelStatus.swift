import FoundationModels

/// Availability of the on-device Apple Foundation Model, mapped to the states the UI shows (FR-7).
public enum ModelStatus: Equatable, Sendable {
    case ready
    case unavailable(Reason)

    public enum Reason: Equatable, Sendable {
        /// This Mac can't run Apple Intelligence.
        case deviceNotEligible
        /// Apple Intelligence is turned off in System Settings.
        case appleIntelligenceNotEnabled
        /// The model is still downloading or preparing.
        case modelNotReady
        /// A reason added by a later OS that this build doesn't know about.
        case other(String)
    }

    /// Reads the current availability of the on-device model.
    public static func current(model: SystemLanguageModel = .default) -> ModelStatus {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.other(String(describing: reason)))
            }
        @unknown default:
            return .unavailable(.other(String(describing: model.availability)))
        }
    }

    /// Short status line for the menu bar menu.
    public var menuTitle: String {
        switch self {
        case .ready:
            "Ready · on-device"
        case .unavailable(.deviceNotEligible):
            "This Mac can't run Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings"
        case .unavailable(.modelNotReady):
            "Model is downloading…"
        case .unavailable(.other):
            "Model unavailable"
        }
    }

    public var isReady: Bool { self == .ready }
}
