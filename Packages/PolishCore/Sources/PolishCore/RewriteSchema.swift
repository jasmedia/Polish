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
