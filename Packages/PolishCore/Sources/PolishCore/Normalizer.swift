import Foundation

/// Step 1 of the pipeline. Runs on protected text, so code blocks (placeholders by then) keep their whitespace.
enum Normalizer {
    private static let trailingSpace = Pattern(#"[ \t]+$"#, options: .anchorsMatchLines)

    /// Unix line endings and no trailing spaces or tabs on any line. Line breaks, indents and list markers stay.
    static func normalize(_ text: String) -> String {
        let unix = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return trailingSpace.replacing(in: unix, with: "")
    }
}
