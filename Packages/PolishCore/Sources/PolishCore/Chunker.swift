import Foundation
import NaturalLanguage

/// One piece of a long draft, rewritten on its own.
public struct Chunk: Equatable, Sendable {
    public var text: String
    /// The whitespace that followed this piece in the draft; rejoining is `text + separator` for each chunk.
    public var separator: String

    public init(text: String, separator: String = "") {
        self.text = text
        self.separator = separator
    }
}

/// Splits protected text under a token budget (FR-12): on paragraph boundaries first, then on sentence
/// boundaries. Never splits inside a placeholder. Joining the chunks gives back the input exactly.
public enum Chunker {
    /// `count` returns the token count of a piece of text (the model's tokenizer, or a stand-in in tests).
    public static func split(
        _ text: String,
        budget: Int,
        count: (String) async throws -> Int
    ) async rethrows -> [Chunk] {
        if try await count(text) <= budget {
            return [Chunk(text: text)]
        }
        var chunks: [Chunk] = []
        for paragraph in paragraphs(text) {
            if try await count(paragraph.text) <= budget {
                chunks.append(paragraph)
            } else {
                // A paragraph alone over the budget: pack its sentences. A single sentence over the budget
                // stays whole; the Rewriter reports it as too long if the model can't take it.
                chunks += try await pack(sentences(paragraph), budget: budget, count: count)
            }
        }
        return try await pack(chunks, budget: budget, count: count)
    }

    /// Greedily merges neighboring pieces while the merged text stays within the budget.
    static func pack(_ pieces: [Chunk], budget: Int, count: (String) async throws -> Int) async rethrows -> [Chunk] {
        var packed: [Chunk] = []
        for piece in pieces {
            if let last = packed.last {
                let merged = Chunk(text: last.text + last.separator + piece.text, separator: piece.separator)
                if try await count(merged.text) <= budget {
                    packed[packed.count - 1] = merged
                    continue
                }
            }
            packed.append(piece)
        }
        return packed
    }

    private static let paragraphBreak = Pattern(#"\n(?:[ \t]*\n)+"#)
    private static let sentenceEnd = Pattern(#"[.!?]+["'’”)\]]*\s+"#)

    /// Paragraphs separated by one or more blank lines; the blank lines become the separator.
    static func paragraphs(_ text: String) -> [Chunk] {
        let source = text as NSString
        var pieces: [Chunk] = []
        var last = 0
        for match in paragraphBreak.matches(in: text) {
            pieces.append(Chunk(
                text: source.substring(with: NSRange(location: last, length: match.range.location - last)),
                separator: source.substring(with: match.range)
            ))
            last = match.range.location + match.range.length
        }
        pieces.append(Chunk(text: source.substring(from: last)))
        if let first = pieces.first, first.text.isEmpty, pieces.count > 1 {
            // Leading blank lines: fold them into the next piece so no chunk is empty.
            pieces.removeFirst()
            pieces[0].text = first.separator + pieces[0].text
        }
        return pieces
    }

    /// Sentences of one paragraph; the whitespace after each sentence becomes its separator.
    static func sentences(_ paragraph: Chunk) -> [Chunk] {
        let text = paragraph.text
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        // NLTokenizer misses sentences that start lowercase, common in quick drafts, so end punctuation
        // followed by whitespace also counts as a boundary.
        let punctuated = sentenceEnd.matches(in: text).compactMap { Range($0.range, in: text)?.upperBound }
        let placeholders = Placeholder.pattern.matches(in: text).compactMap { Range($0.range, in: text) }
        var starts = Set(tokenizer.tokens(for: text.startIndex..<text.endIndex).map(\.lowerBound) + punctuated)
            .filter { start in start < text.endIndex && !placeholders.contains { $0.lowerBound < start && start < $0.upperBound } }
            .sorted()
        if starts.first != text.startIndex {
            starts.insert(text.startIndex, at: 0)
        }

        var pieces: [Chunk] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : text.endIndex
            let piece = text[start..<end]
            let body = piece.reversed().drop { $0.isWhitespace }.reversed()
            pieces.append(Chunk(text: String(body), separator: String(piece.dropFirst(body.count))))
        }
        pieces[pieces.count - 1].separator += paragraph.separator
        return pieces.filter { !$0.text.isEmpty || !$0.separator.isEmpty }
    }
}
