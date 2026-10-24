import Testing
@testable import PolishCore

// Same cases as eval/test_protect.py.
struct RestorerTests {
    @Test(arguments: [
        ("I'm sure it's \"done\"", "I’m sure it’s “done”", true),
        ("I’m sure it’s “done”", "I'm sure it's \"done\"", false),
        ("the '90s and 'quoted' word", "the ’90s and ‘quoted’ word", true),
    ])
    func quoteStyle(output: String, expected: String, curly: Bool) {
        #expect(Restorer.matchQuoteStyle(output, source: curly ? "’" : "'") == expected)
    }

    @Test func noQuotesInDraftMeansStraight() {
        #expect(Restorer.matchQuoteStyle("It’s “fine”", source: "its fine") == "It's \"fine\"")
    }

    @Test(arguments: [
        ("I will post the doc.", "i'll post the doc", "I'll post the doc."),
        ("I will send the configuration. It is done.", "I’ll send the config, it’s done", "I’ll send the config. It’s done."),
        ("Do not merge yet.", "dont merge yet", "Do not merge yet."),  // no contraction in the draft
        ("That is the document I wrote.", "That's the docs i wrote", "That's the document I wrote."),
    ])
    func writerStyle(output: String, source: String, expected: String) {
        #expect(Restorer.keepWriterStyle(output, source: source) == expected)
    }

    @Test(arguments: [
        ("One.\nTwo.", "one\n\ntwo", "One.\n\nTwo."),
        ("Intro:\n- a\n- b", "intro:\n  - a\n  - b", "Intro:\n  - a\n  - b"),
        ("One. Two.", "one\n\ntwo", "One. Two."),  // merged lines: left for validation to reject
    ])
    func layout(output: String, source: String, expected: String) {
        #expect(Restorer.keepLayout(output, source: source) == expected)
    }

    @Test func placeholdersKeepTheirQuotes() throws {
        let protected = try Protector().protect("it’s `echo 'hi'`")
        let output = Restorer.matchQuoteStyle("It's ⟦T1⟧", source: protected.text)
        #expect(protected.restore(output) == "It’s `echo 'hi'`")
    }
}
