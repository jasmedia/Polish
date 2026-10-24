import Foundation

/// Why a model output was rejected. The descriptions match `eval/restore.py` and `eval/run.py`,
/// so `eval/metrics.py` can score Swift results.
public enum ValidationFailure: Equatable, Hashable, Sendable, CustomStringConvertible {
    case empty
    case missing(Int)
    case duplicated(Int)
    case unknown(Int)
    /// A placeholder rewritten as `[T1]`, `T1` or a stray `⟦`.
    case mangled
    case length
    /// Fewer non-blank lines than the draft: lines were merged or dropped.
    case lines

    public var description: String {
        switch self {
        case .empty: "empty"
        case .missing(let n): "missing \(Placeholder.name(n))"
        case .duplicated(let n): "duplicated \(Placeholder.name(n))"
        case .unknown(let n): "unknown \(Placeholder.name(n))"
        case .mangled: "mangled placeholder"
        case .length: "length"
        case .lines: "lines"
        }
    }

    public var isPlaceholderFailure: Bool {
        switch self {
        case .missing, .duplicated, .unknown, .mangled: true
        case .empty, .length, .lines: false
        }
    }
}

/// Decides whether a model output may be shown. Placeholder integrity is enforced here, never trusted to the model.
public struct Validator: Sendable {
    /// Allowed output length as a share of the input's length.
    public var lengthRange: ClosedRange<Double>

    public init(tone: Tone = .keep) {
        lengthRange = tone == .concise ? 0.4...1.6 : 0.6...1.6
    }

    /// Empty when `output` can replace `source`. Both are placeholder text; `source` defines which placeholders must appear.
    public func validate(_ output: String, source: String) -> [ValidationFailure] {
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.empty]
        }
        var failures = Self.placeholderFailures(output, source: source)
        let ratio = Double(output.unicodeScalars.count) / Double(max(source.unicodeScalars.count, 1))
        if !lengthRange.contains(ratio) {
            failures.append(.length)
        }
        // Line breaks are Slack syntax too (FR-4): a merged or dropped line fails, so the draft is kept.
        if Self.nonBlankLines(output) < Self.nonBlankLines(source) {
            failures.append(.lines)
        }
        return failures
    }

    /// Every placeholder of `source` exactly once in `output`, and no others.
    static func placeholderFailures(_ output: String, source: String) -> [ValidationFailure] {
        let expected = Set(Placeholder.numbers(in: source))
        let found = Placeholder.numbers(in: output)
        var counts: [Int: Int] = [:]
        for number in found { counts[number, default: 0] += 1 }

        var failures: [ValidationFailure] = []
        for number in expected.sorted() {
            switch counts[number, default: 0] {
            case 0: failures.append(.missing(number))
            case 1: break
            default: failures.append(.duplicated(number))
            }
        }
        var seen = Set<Int>()
        for number in found where !expected.contains(number) && seen.insert(number).inserted {
            failures.append(.unknown(number))
        }
        // A model that rewrites ⟦T1⟧ as [T1] or T1 has broken the token even if the count is right.
        let stripped = { (text: String) in mangled.count(in: Placeholder.pattern.replacing(in: text, with: "")) }
        if stripped(output) > stripped(source) {
            failures.append(.mangled)
        }
        return failures
    }

    static func nonBlankLines(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private static let mangled = Pattern(#"[⟦⟧]|\bT\d+\b"#)
}
