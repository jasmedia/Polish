import Foundation

/// A draft with its Slack tokens replaced by `⟦Tn⟧` placeholders.
public struct ProtectedText: Equatable, Sendable {
    /// The draft with placeholders, which is all the model sees.
    public var text: String
    /// `tokens[n - 1]` is the original text behind `⟦Tn⟧`.
    public var tokens: [String]

    /// Puts the original tokens back into `output`. Unknown placeholders are left as they are;
    /// the Validator rejects them before this runs.
    public func restore(_ output: String) -> String {
        Placeholder.pattern.replacing(in: output) { match, source in
            guard let number = match.group(1, in: source).flatMap({ Int($0) }), tokens.indices.contains(number - 1)
            else { return source.substring(with: match.range) }
            return tokens[number - 1]
        }
    }
}

public enum ProtectorError: Error, Equatable, Sendable {
    /// The draft already contains text shaped like a placeholder, so restoring would be ambiguous.
    case containsPlaceholder
}

/// Replaces Slack tokens (mentions, channels, emoji, links, code, formatting spans) and
/// personal-dictionary words with placeholders, so the model never sees raw Slack syntax.
///
/// Port of `eval/protect.py`; `restore(protect(text).text) == text` for every input.
public struct Protector: Sendable {
    public var dictionary: [String]

    public init(dictionary: [String] = []) {
        self.dictionary = dictionary
    }

    public func protect(_ text: String) throws(ProtectorError) -> ProtectedText {
        if Placeholder.pattern.contains(in: text) {
            throw .containsPlaceholder
        }
        let source = text as NSString

        var spans: [NSRange] = []
        var position = 0
        while let match = Self.token.firstMatch(in: text, from: position) {
            var span = match.range
            if match.didMatch(group: "mention") {
                span.length = (Self.trimMention(source.substring(with: span)) as NSString).length
            }
            spans.append(span)
            position = span.location + span.length
        }

        if let dictionaryPattern = Self.dictionaryPattern(dictionary) {
            for match in dictionaryPattern.matches(in: text)
            where !spans.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                spans.append(match.range)
            }
            spans.sort { ($0.location, $0.length) < ($1.location, $1.length) }
        }

        var out = ""
        var tokens: [String] = []
        var last = 0
        for span in spans {
            out += source.substring(with: NSRange(location: last, length: span.location - last))
            tokens.append(source.substring(with: span))
            out += Placeholder.name(tokens.count)
            last = span.location + span.length
        }
        out += source.substring(from: last)
        return ProtectedText(text: out, tokens: tokens)
    }

    // Order matters: at the same start position the first alternative wins.
    private static let nameWord = #"[A-Z][\w'’-]*"#
    private static let token = Pattern(
        [
            #"(?<codeblock>```.*?```)"#,                                              // fenced code, may span lines
            #"(?<code>`[^`\n]+`)"#,                                                   // inline code
            #"(?<angle><[@#!][^>\s]*(?:\|[^>]*)?>|<https?://[^>\s]+(?:\|[^>]*)?>)"#,  // <@U1>, <#C1|x>, <!here>, <url|label>
            #"(?<url>https?://[^\s<>]*[^\s<>.,;:!?)\]'"’”])"#,                        // bare URL, minus trailing punctuation
            #"(?<email>[\w.+-]+@[\w-]+(?:\.[\w-]+)+)"#,
            #"(?<emoji>(?::[a-z0-9_+'-]+:)+)"#,                                       // :wave::skin-tone-3: is one token
            #"(?<broadcast>@(?:here|channel|everyone)\b)"#,
            #"(?<mention>@\w[\w'’-]*(?:[ ]"# + nameWord + #"){0,2})"#,                // trimmed in trimMention
            #"(?<channel>(?<![\w&])#[a-z0-9][a-z0-9_-]*)"#,
            #"(?<format>(?<![\w*_~])(?<mark>~~|[*_~])(?=\S)[^\n]*?(?<=\S)\k<mark>(?![\w*_~]))"#,  // *bold*, _italic_, ~strike~ span
        ].joined(separator: "|"),
        options: [.dotMatchesLineSeparators]
    )

    /// Words that start a sentence rather than continue a display name: `@Sam We can…` protects `@Sam`.
    private static let nameStopwords: Set<String> = [
        "a", "all", "also", "an", "and", "any", "are", "as", "but", "can", "could", "did", "do", "does",
        "for", "fyi", "good", "great", "has", "have", "here", "hey", "hi", "how", "i", "i'd", "i'll", "i'm",
        "i've", "if", "in", "is", "it", "it's", "its", "just", "kindly", "let", "let's", "my", "nice", "no",
        "not", "ok", "okay", "on", "once", "our", "please", "pls", "quick", "should", "so", "sorry", "sure",
        "thank", "thanks", "that", "the", "there", "these", "this", "we", "what", "when", "where", "who",
        "why", "will", "would", "yes", "you", "your",
    ]

    private static func trimMention(_ token: String) -> String {
        let words = token.split(separator: " ", omittingEmptySubsequences: false)
        var kept = [words[0]]
        for word in words.dropFirst() {
            if nameStopwords.contains(word.lowercased().replacingOccurrences(of: "’", with: "'")) {
                break
            }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    private static func dictionaryPattern(_ words: [String]) -> Pattern? {
        guard !words.isEmpty else { return nil }
        let alternatives = words.sorted { $0.count > $1.count }.map(Pattern.escaped).joined(separator: "|")
        return Pattern(#"(?<![\w@#])(?:"# + alternatives + #")(?!\w)"#)
    }
}
