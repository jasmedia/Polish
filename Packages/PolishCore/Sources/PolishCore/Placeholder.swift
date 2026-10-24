import Foundation

/// The `⟦Tn⟧` placeholders that stand in for Slack tokens while the model works.
public enum Placeholder {
    static let pattern = Pattern("⟦T(\\d+)⟧")

    /// `⟦T3⟧` for 3.
    public static func name(_ number: Int) -> String {
        "⟦T\(number)⟧"
    }

    /// Placeholder numbers in order of appearance, repeats included.
    static func numbers(in text: String) -> [Int] {
        let source = text as NSString
        return pattern.matches(in: text).compactMap { $0.group(1, in: source).flatMap { Int($0) } }
    }
}
