import Foundation

/// The rewrite tones (FR-8). Only `keep` is scored on the golden set so far; Phase 4 tunes the others.
public enum Tone: String, CaseIterable, Sendable {
    case keep
    case casual
    case professional
    case concise

    /// The text for the prompt's `{tone}` slot.
    var instruction: String {
        switch self {
        case .keep: "keep the writer's tone"
        case .casual: "casual and friendly"
        case .professional: "professional"
        case .concise: "concise: cut filler words and repetition"
        }
    }
}

/// Builds the model instructions for one request from a versioned prompt template.
public struct InstructionsBuilder: Sendable {
    /// Keep my tone: correct in place and leave correct text alone.
    public var template: String
    /// The other tones restyle the whole message, so they use their own template when one is given.
    public var restyle: Restyle?

    /// A template for Casual, Professional and Concise, and the text for its `{tone}` slot per tone.
    public struct Restyle: Sendable {
        public var template: String
        public var tones: [Tone: String]

        public init(template: String, tones: [Tone: String]) {
            self.template = template
            self.tones = tones
        }

        /// `prompts/vN.txt` plus one `{tone}` text per tone in `prompts/vN-tones/<tone>.txt`.
        public init(contentsOf url: URL) throws {
            let directory = URL(filePath: url.deletingPathExtension().path() + "-tones")
            var tones: [Tone: String] = [:]
            for tone in Tone.allCases where tone != .keep {
                let text = try String(contentsOf: directory.appending(path: "\(tone.rawValue).txt"), encoding: .utf8)
                tones[tone] = text.trimmingCharacters(in: .newlines)
            }
            self.init(template: try String(contentsOf: url, encoding: .utf8), tones: tones)
        }
    }

    public init(template: String = Prompt.v1, restyle: Restyle? = nil) {
        self.template = template
        self.restyle = restyle
    }

    static let placeholderRule = "The message contains placeholders: {list}. Copy each one exactly once, unchanged, in a natural position."
    static let leadingMentionRule = "The message starts with {name}, which addresses someone: keep {name} at the start."
    static let leadingRule = "The message starts with {name}: keep {name} at the start."

    /// The placeholder a text starts with; the model's most common placeholder failure is dropping it.
    public struct Leading: Equatable, Sendable {
        public var number: Int
        /// The placeholder is a mention, so the text addresses someone.
        public var isMention: Bool

        public init(number: Int, isMention: Bool) {
            self.number = number
            self.isMention = isMention
        }
    }

    /// - Parameters:
    ///   - placeholders: the placeholder numbers in the text sent to the model.
    ///   - leading: the placeholder the text starts with, if any.
    public func build(tone: Tone, placeholders: [Int], leading: Leading? = nil) -> String {
        // Only mention placeholders when the text has some (otherwise the model invents them), and name each one.
        var rule = ""
        if !placeholders.isEmpty {
            let names = placeholders.map(Placeholder.name).joined(separator: ", ")
            rule = Self.placeholderRule.replacingOccurrences(of: "{list}", with: names) + "\n"
        }
        if let leading {
            let template = leading.isMention ? Self.leadingMentionRule : Self.leadingRule
            rule += template.replacingOccurrences(of: "{name}", with: Placeholder.name(leading.number)) + "\n"
        }
        var template = template
        var toneText = tone.instruction
        if tone != .keep, let restyle {
            template = restyle.template
            toneText = restyle.tones[tone] ?? toneText
        }
        return template
            .replacingOccurrences(of: "{tone}", with: toneText)
            .replacingOccurrences(of: "{placeholders}\n", with: rule)
    }
}

/// Versioned prompt templates. Each must match its file in `prompts/` (checked by `InstructionsTests`).
public enum Prompt {
    /// `prompts/v1.txt`: 100% placeholder integrity, 97.9% unchanged-when-correct (eval/RESULTS.md).
    public static let v1 = """
        You rewrite a Slack message that was typed quickly and may contain mistakes, so it reads clearly and professionally.
        Fix spelling, grammar, punctuation, capitalization and wrong words.
        Rephrase broken or awkward sentences into natural, fluent English, the way a careful colleague would write them.
        Expand chat shorthand such as u, pls, thx, tmrw, org, env, prod and approx. Keep common work words such as doc, PR, repo, config and deploy.
        Keep the meaning, facts, names, numbers and requests exactly. Do not add new information, greetings, sign-offs or emoji.
        Leave correct sentences alone: keep contractions (I'll, don't, it's), keep casual words that are correct (Congrats, thanks!), and do not swap correct words for synonyms.
        Keep existing line breaks, paragraphs and list markers. You may split a long run-on message into short paragraphs.
        When the message starts by addressing someone, put a comma after their name or placeholder.
        {placeholders}
        If the text is already clear and correct, return it exactly unchanged.
        Use US English spelling.
        Tone: {tone}.

        """
}
