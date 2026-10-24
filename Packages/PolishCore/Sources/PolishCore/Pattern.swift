import Foundation

/// A compiled ICU regular expression. The engine's patterns are ports of the Python prototype in `eval/`,
/// so they use `NSRegularExpression` syntax and UTF-16 offsets rather than Swift `Regex`.
///
/// `NSRegularExpression` is immutable and documented as safe to share between threads.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid pattern \(pattern): \(error)")
        }
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }

    func firstMatch(in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }

    /// First match at or after UTF-16 offset `location`. Lookbehinds still see the text before it,
    /// like Python's `pattern.search(text, pos)`.
    func firstMatch(in text: String, from location: Int) -> NSTextCheckingResult? {
        let length = text.utf16.count
        guard location <= length else { return nil }
        return regex.firstMatch(
            in: text,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: location, length: length - location)
        )
    }

    func contains(in text: String) -> Bool {
        firstMatch(in: text) != nil
    }

    func count(in text: String) -> Int {
        regex.numberOfMatches(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }

    /// Replaces every match with a template (`$1` refers to the first group).
    func replacing(in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: template
        )
    }

    /// Replaces every match with the string `replacement` returns for it.
    func replacing(in text: String, using replacement: (NSTextCheckingResult, NSString) -> String) -> String {
        let source = text as NSString
        var out = ""
        var last = 0
        for match in matches(in: text) {
            out += source.substring(with: NSRange(location: last, length: match.range.location - last))
            out += replacement(match, source)
            last = match.range.location + match.range.length
        }
        out += source.substring(from: last)
        return out
    }

    static func escaped(_ literal: String) -> String {
        NSRegularExpression.escapedPattern(for: literal)
    }
}

extension NSTextCheckingResult {
    /// The text of capture group `index`, or nil when the group didn't take part in the match.
    func group(_ index: Int, in text: NSString) -> String? {
        let range = range(at: index)
        return range.location == NSNotFound ? nil : text.substring(with: range)
    }

    func didMatch(group name: String) -> Bool {
        range(withName: name).location != NSNotFound
    }
}
