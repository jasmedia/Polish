import Foundation

/// One run of the word-level diff between the draft and the rewrite.
public struct DiffSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case same
        case inserted
        case removed
    }

    public var kind: Kind
    public var text: String
    /// Where the run sits in the draft (`same` and `removed`).
    public var originalRange: Range<String.Index>?
    /// Where the run sits in the rewrite (`same` and `inserted`).
    public var rewrittenRange: Range<String.Index>?
}

/// Word-level diff for the review panel, built on `CollectionDifference`.
public enum Differ {
    /// Segments in reading order: removed runs come before the inserted runs that replace them.
    /// Concatenating `same` + `removed` gives the draft; `same` + `inserted` gives the rewrite.
    public static func diff(original: String, rewritten: String) -> [DiffSegment] {
        let old = words(original)
        let new = words(rewritten)
        let difference = new.map(\.text).difference(from: old.map(\.text))

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var segments: [DiffSegment] = []
        func append(_ kind: DiffSegment.Kind, _ text: Substring, old: Range<String.Index>?, new: Range<String.Index>?) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text += text
                if let old { segments[segments.count - 1].originalRange = last.originalRange!.lowerBound..<old.upperBound }
                if let new { segments[segments.count - 1].rewrittenRange = last.rewrittenRange!.lowerBound..<new.upperBound }
            } else {
                segments.append(DiffSegment(kind: kind, text: String(text), originalRange: old, rewrittenRange: new))
            }
        }

        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                append(.removed, old[i].text, old: old[i].range, new: nil)
                i += 1
            } else if j < new.count, inserted.contains(j) {
                append(.inserted, new[j].text, old: nil, new: new[j].range)
                j += 1
            } else {
                append(.same, old[i].text, old: old[i].range, new: new[j].range)
                i += 1
                j += 1
            }
        }
        return segments
    }

    /// Runs of non-whitespace and of whitespace, so spacing and line breaks diff like words.
    static func words(_ text: String) -> [(text: Substring, range: Range<String.Index>)] {
        var result: [(Substring, Range<String.Index>)] = []
        var start = text.startIndex
        while start < text.endIndex {
            let isSpace = text[start].isWhitespace
            let end = text[start...].firstIndex { $0.isWhitespace != isSpace } ?? text.endIndex
            result.append((text[start..<end], start..<end))
            start = end
        }
        return result
    }
}
