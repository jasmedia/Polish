import Foundation

/// Post-processing of a validated model output, still in placeholder form: layout, the writer's
/// style and quote style. Port of `eval/restore.py`. Placeholders (code, links) are never touched.
public enum Restorer {
    /// Runs every step in the order the Phase 1 pipeline used.
    static func apply(_ output: String, source: String, keepWriterStyle keepStyle: Bool = true) -> String {
        var text = keepLayout(output, source: source)
        if keepStyle {
            text = keepWriterStyle(text, source: source)
        }
        return matchQuoteStyle(text, source: source)
    }

    // MARK: Layout

    /// Puts the rewrite's lines into the draft's layout (blank lines, single breaks, indents) when the
    /// counts of non-blank lines match. The model sometimes collapses a blank line or moves a break.
    public static func keepLayout(_ output: String, source: String) -> String {
        var layout = source.components(separatedBy: "\n")
        let filled = layout.indices.filter { !layout[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lines = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == filled.count else { return output }
        for (index, line) in zip(filled, lines) {
            let indent = layout[index].prefix { $0.isWhitespace }
            layout[index] = indent + line
        }
        return layout.joined(separator: "\n")
    }

    // MARK: Writer style

    private static let contractions: [(short: String, long: String)] = [
        ("i'm", "i am"), ("i'll", "i will"), ("i've", "i have"), ("i'd", "i would"), ("you're", "you are"),
        ("you'll", "you will"), ("we're", "we are"), ("we'll", "we will"), ("we've", "we have"),
        ("they're", "they are"), ("it's", "it is"), ("it'll", "it will"), ("that's", "that is"),
        ("there's", "there is"), ("here's", "here is"), ("what's", "what is"), ("let's", "let us"),
        ("don't", "do not"), ("doesn't", "does not"), ("didn't", "did not"), ("isn't", "is not"),
        ("aren't", "are not"), ("wasn't", "was not"), ("weren't", "were not"), ("can't", "cannot"),
        ("won't", "will not"), ("haven't", "have not"), ("hasn't", "has not"), ("wouldn't", "would not"),
        ("couldn't", "could not"), ("shouldn't", "should not"),
    ]
    /// Common work words the writer chose; the model likes to expand them.
    private static let keptTerms: [(short: String, long: String)] = [
        ("doc", "document"), ("docs", "documentation"), ("config", "configuration"), ("repo", "repository"),
    ]
    private static let styleRules: [(short: Pattern, long: Pattern)] = (contractions + keptTerms).map { pair in
        let short = pair.short.replacingOccurrences(of: "'", with: "['’]")
        return (Pattern(#"\b"# + short + #"\b"#, options: .caseInsensitive),
                Pattern(#"\b"# + pair.long + #"\b"#, options: .caseInsensitive))
    }

    /// Undoes expansions of contractions and work words that the draft used and the output dropped:
    /// `i'll post the doc` keeps `I'll` and `doc` even if the model wrote `I will` and `document`.
    public static func keepWriterStyle(_ output: String, source: String) -> String {
        var output = output
        let sourceText = source as NSString
        for rule in styleRules {
            guard let found = rule.short.firstMatch(in: source), !rule.short.contains(in: output) else { continue }
            let original = sourceText.substring(with: found.range)
            output = rule.long.replacing(in: output) { match, text in
                matchCase(original, to: text.substring(with: match.range))
            }
        }
        return output
    }

    /// `original` with its first letter cased like `matched`'s (the pronoun I stays capital).
    private static func matchCase(_ original: String, to matched: String) -> String {
        guard let first = original.first else { return original }
        let lower = original.lowercased()
        if matched.first?.isUppercase == true || lower.hasPrefix("i'") || lower.hasPrefix("i’") {
            return first.uppercased() + original.dropFirst()
        }
        return first.lowercased() + original.dropFirst()
    }

    // MARK: Quotes

    private static let curly = Pattern("[‘’“”]")

    static func usesCurlyQuotes(_ text: String) -> Bool {
        curly.contains(in: text)
    }

    static func toStraight(_ text: String) -> String {
        String(text.map { character -> Character in
            switch character {
            case "‘", "’": "'"
            case "“", "”": "\""
            default: character
            }
        })
    }

    private static let apostrophe = Pattern(#"(?<=\w)'|'(?=\d)"#)  // contractions, possessives, '90s
    private static let openingSingle = Pattern(#"(^|[\s(\[{])'"#, options: .anchorsMatchLines)
    private static let openingDouble = Pattern(#"(^|[\s(\[{])""#, options: .anchorsMatchLines)

    static func toCurly(_ text: String) -> String {
        var text = apostrophe.replacing(in: text, with: "’")
        text = openingSingle.replacing(in: text, with: "$1‘")
        text = text.replacingOccurrences(of: "'", with: "’")
        text = openingDouble.replacing(in: text, with: "$1“")
        return text.replacingOccurrences(of: "\"", with: "”")
    }

    /// Converts quotes in `output` to the style of `source`: curly when the draft has any, else straight.
    /// Runs on placeholder text so code and links keep their quotes.
    public static func matchQuoteStyle(_ output: String, source: String) -> String {
        usesCurlyQuotes(source) ? toCurly(output) : toStraight(output)
    }
}
