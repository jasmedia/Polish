import Foundation

/// The shared golden set (`golden/golden.jsonl`) and repo files, read from the source tree.
enum Golden {
    struct Row: Decodable, Sendable {
        var id: String
        var input: String
        var expected: String
        var tags: [String]
    }

    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // PolishCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // PolishCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()

    static let rows: [Row] = {
        let url = repoRoot.appending(path: "golden/golden.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
    }()
}
