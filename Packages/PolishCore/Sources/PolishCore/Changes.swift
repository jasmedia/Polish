import Foundation

/// One fix in the rewrite (FR-9), read off the word diff, so it always matches what the panel shows.
public struct Change: Equatable, Sendable {
    /// What kind of edit it is, judged from the words alone.
    public enum Reason: String, Sendable, CaseIterable {
        case capitalization
        case punctuation
        /// A commonly confused word: their → there, to → too, then → than.
        case wrongWord = "wrong word"
        /// The same word with another ending: look → looks, is → are.
        case grammar
        /// A small edit inside one word, or a word split or joined: teh → the, in to → into.
        case spelling
        /// Chat shorthand written out: u → you, pls → please.
        case shorthand
        /// Anything else: words added, removed or rephrased.
        case wording
    }

    /// The draft's words; empty when words were only added.
    public var from: String
    /// The rewrite's words; empty when words were only removed.
    public var to: String
    public var reason: Reason

    public init(from: String, to: String, reason: Reason) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}

extension PolishResult {
    /// The fixes in reading order, one per run of changed words. Empty when nothing changed.
    public var changes: [Change] { Differ.changes(diff) }
}

extension Differ {
    /// Groups each run of removed and inserted words between unchanged words into one change.
    /// Changes to spacing or line breaks alone are left out.
    public static func changes(_ diff: [DiffSegment]) -> [Change] {
        var changes: [Change] = []
        var removed = ""
        var inserted = ""
        func flush() {
            let from = removed.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
            removed = ""
            inserted = ""
            guard from != to else { return }
            changes.append(Change(from: from, to: to, reason: reason(from: from, to: to)))
        }
        for segment in diff {
            switch segment.kind {
            case .removed: removed += segment.text
            case .inserted: inserted += segment.text
            case .same: flush()
            }
        }
        flush()
        return changes
    }

    static func reason(from: String, to: String) -> Change.Reason {
        let fromLetters = letters(from)
        let toLetters = letters(to)
        if fromLetters == toLetters { return .punctuation }
        if fromLetters.lowercased() == toLetters.lowercased() { return .capitalization }
        let old = fromLetters.lowercased()
        let new = toLetters.lowercased()
        if !old.isEmpty, old.filter { $0 != " " } == new.filter { $0 != " " } { return .spelling }
        if shorthand.contains(old) { return .shorthand }
        // Several words, or words only added or removed: there's no one word to compare.
        guard !old.isEmpty, !new.isEmpty, !old.contains(" "), !new.contains(" ") else {
            return .wording
        }
        if confusables.contains(where: { $0.contains(old) && $0.contains(new) }) { return .wrongWord }
        if sameWordOtherEnding(old, new) { return .grammar }
        let distance = editDistance(Array(old), Array(new))
        // A typo rarely changes the first letter; a different first letter is more often another word (able → unable).
        if distance <= 2, distance * 2 <= old.count, old.first == new.first { return .spelling }
        return .wording
    }

    /// Letters and digits, words separated by one space: apostrophes, quotes and punctuation don't count.
    private static func letters(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { $0 != "'" && $0 != "’" }
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// The shorthand the prompt asks the model to write out, and other common chat abbreviations.
    private static let shorthand: Set<String> = [
        "u", "ur", "r", "pls", "plz", "thx", "ty", "tmrw", "tmr", "asap", "org", "env", "prod", "approx", "eod",
        "ooo", "btw", "fyi", "imo", "msg", "ppl", "b4", "w", "bc", "cuz", "abt", "wrt", "pr", "dept", "info", "k",
    ]

    /// Words people type for each other, apostrophes left out (so it's → its is punctuation, not this).
    private static let confusables: [Set<String>] = [
        ["their", "there", "theyre"], ["your", "youre"], ["to", "too", "two"], ["then", "than"],
        ["loose", "lose"], ["effect", "affect"], ["of", "have"], ["know", "now", "no"], ["where", "were", "wear"],
        ["whose", "whos"], ["accept", "except"], ["weather", "whether"], ["quite", "quiet"], ["advise", "advice"],
        ["hear", "here"], ["by", "buy", "bye"], ["right", "write"], ["peak", "peek"], ["week", "weak"],
        ["new", "knew"], ["whole", "hole"], ["principal", "principle"], ["complement", "compliment"],
        ["brake", "break"], ["passed", "past"], ["led", "lead"], ["sight", "site", "cite"], ["fill", "feel"],
    ]

    private static let forms: [Set<String>] = [
        ["is", "are", "am", "was", "were", "be", "been", "isnt", "arent", "wasnt", "werent"],
        ["has", "have", "had", "hasnt", "havent", "hadnt"], ["do", "does", "did", "done", "dont", "doesnt", "didnt"],
        ["go", "goes", "went", "gone"], ["a", "an"], ["this", "these"], ["that", "those"],
        ["run", "ran"], ["send", "sent"], ["get", "got", "gotten"], ["make", "made"], ["take", "took", "taken"],
        ["write", "wrote", "written"], ["see", "saw", "seen"], ["come", "came"], ["give", "gave", "given"],
        ["know", "knew", "known"], ["find", "found"], ["think", "thought"], ["tell", "told"], ["say", "said"],
        ["leave", "left"], ["break", "broke", "broken"], ["choose", "chose", "chosen"], ["fall", "fell", "fallen"],
        ["keep", "kept"], ["lose", "lost"], ["meet", "met"], ["pay", "paid"], ["build", "built"], ["bring", "brought"],
        ["begin", "began", "begun"], ["feel", "felt"], ["sell", "sold"], ["catch", "caught"], ["buy", "bought"],
    ]

    /// look → looks, fix → fixed, return → returns, review → reviewing; is → are.
    private static func sameWordOtherEnding(_ old: String, _ new: String) -> Bool {
        if forms.contains(where: { $0.contains(old) && $0.contains(new) }) { return true }
        let (short, long) = old.count < new.count ? (old, new) : (new, old)
        guard short.count >= 2, long.hasPrefix(short) else { return false }
        return ["s", "es", "d", "ed", "ing", "er", "est", "ly"].contains(String(long.dropFirst(short.count)))
    }

    /// Edits to turn one word into the other, with a swap of two neighbors counting as one (teh → the).
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
