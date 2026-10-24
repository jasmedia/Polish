import FoundationModels

// Guided-generation types. Listing mistakes before the text makes the model look before it rewrites,
// which keeps it from editing correct text (eval/RESULTS.md); the list itself is not shown.

@Generable(description: "A Slack message's mistakes and its rewrite")
struct RewriteWithMistakes {
    @Guide(
        description: "Each misspelled word, wrong word, grammar error, missing punctuation or shorthand, copied exactly from the message. Empty if the message is already clear and correct.",
        .maximumCount(10)
    )
    var mistakes: [String]

    @Guide(description: "The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")
    var text: String
}

/// The change list variant (FR-9). Not scored yet; Phase 4 measures its latency cost.
@Generable(description: "A Slack message's mistakes, its rewrite and the notable fixes")
struct RewriteWithChanges {
    @Guide(
        description: "Each misspelled word, wrong word, grammar error, missing punctuation or shorthand, copied exactly from the message. Empty if the message is already clear and correct.",
        .maximumCount(10)
    )
    var mistakes: [String]

    @Guide(description: "The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")
    var text: String

    @Guide(description: "Up to 5 notable fixes, most important first", .maximumCount(5))
    var changes: [GeneratedChange]
}

@Generable(description: "One fix made to the message")
struct GeneratedChange {
    @Guide(description: "The original words")
    var from: String
    @Guide(description: "The new words")
    var to: String
    @Guide(description: "Short reason: spelling, grammar, wrong word, punctuation, clarity")
    var reason: String
}

/// A fix the model reports, with placeholders restored.
public struct Change: Equatable, Sendable {
    public var from: String
    public var to: String
    public var reason: String
}
