import FoundationModels

/// Errors the user sees. On every one of them the original text stays as it was.
public enum PolishError: Error, Equatable, Sendable {
    case modelUnavailable(ModelStatus.Reason)
    /// The message is too long for the model, even after splitting it again.
    case tooLong
    /// The safety guardrails blocked the message or the rewrite.
    case guardrail
    case refusal
    case unsupportedLanguage
    /// Too many requests, or another app is using the model.
    case busy
    /// The draft contains text shaped like a placeholder (`⟦T1⟧`).
    case unsupportedText
    /// Any other generation failure; `code` names it and is safe to log publicly.
    case generationFailed(code: String)

    /// A short name for logs and the eval harness.
    public var code: String {
        switch self {
        case .modelUnavailable: "modelUnavailable"
        case .tooLong: "tooLong"
        case .guardrail: "guardrail"
        case .refusal: "refusal"
        case .unsupportedLanguage: "unsupportedLanguage"
        case .busy: "busy"
        case .unsupportedText: "unsupportedText"
        case .generationFailed(let code): code
        }
    }

    /// The message the review panel shows.
    public var message: String {
        switch self {
        case .modelUnavailable(let reason): ModelStatus.unavailable(reason).menuTitle
        case .tooLong: "This message is too long to polish. Try a shorter part of it."
        case .unsupportedLanguage: "Polish only works with English text."
        case .busy: "The model is busy. Try again in a moment."
        case .guardrail, .refusal, .unsupportedText, .generationFailed: "Couldn't rewrite this message."
        }
    }

    /// Maps an error thrown by Foundation Models. Returns nil for errors that aren't the model's (cancellation).
    init?(modelError error: any Error) {
        switch error {
        case is CancellationError:
            return nil
        case let error as LanguageModelError:
            switch error {
            case .contextSizeExceeded: self = .tooLong
            case .rateLimited: self = .busy
            case .guardrailViolation: self = .guardrail
            case .refusal: self = .refusal
            case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
            case .timeout: self = .generationFailed(code: "timeout")
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                self = .generationFailed(code: "unsupported")
            @unknown default: self = .generationFailed(code: "languageModelError")
            }
        case let error as LanguageModelSession.GenerationError:
            // Pre-macOS 27 error type; the framework may still throw it for some failures.
            switch error {
            case .exceededContextWindowSize: self = .tooLong
            case .assetsUnavailable: self = .modelUnavailable(.modelNotReady)
            case .guardrailViolation: self = .guardrail
            case .refusal: self = .refusal
            case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
            case .rateLimited, .concurrentRequests: self = .busy
            case .decodingFailure: self = .generationFailed(code: "decodingFailure")
            case .unsupportedGuide: self = .generationFailed(code: "unsupportedGuide")
            @unknown default: self = .generationFailed(code: "generationError")
            }
        case let error as PolishError:
            self = error
        default:
            self = .generationFailed(code: String(describing: type(of: error)))
        }
    }
}
