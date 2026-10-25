import Testing
@testable import PolishCore

struct ChunkerTests {
    /// Stand-in tokenizer: one token per word.
    static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func split(_ text: String, budget: Int) async -> [Chunk] {
        await Chunker.split(text, budget: budget) { Self.words($0) }
    }

    func joined(_ chunks: [Chunk]) -> String {
        chunks.map { $0.text + $0.separator }.joined()
    }

    @Test func underBudgetIsOneChunk() async {
        #expect(await split("one two three", budget: 3) == [Chunk(text: "one two three")])
    }

    @Test(arguments: ["", "word", "🎉", "⟦T1⟧"])
    func edgeCasesStayWhole(text: String) async {
        #expect(await split(text, budget: 5) == [Chunk(text: text)])
    }

    @Test func splitsOnParagraphsFirst() async {
        let text = "one two three.\n\nfour five six.\n  \nseven eight."
        let chunks = await split(text, budget: 6)
        #expect(chunks.map(\.text) == ["one two three.\n\nfour five six.", "seven eight."])
        #expect(joined(chunks) == text)
    }

    @Test func linesKeepTheirBreaksAsSeparators() {
        let chunk = Chunk(text: "todo:\n- one\n- two\n\n  \nthanks", separator: "\n\n")
        let lines = Chunker.lines(chunk)
        #expect(lines.map(\.text) == ["todo:", "- one", "- two", "thanks"])
        #expect(joined(lines) == chunk.text + chunk.separator)
    }

    @Test func splitsLongParagraphsOnSentences() async {
        let text = "One two three. Four five six. Seven eight nine.\n\nTen."
        let chunks = await split(text, budget: 4)
        // Packing then merges small neighbors again, across the paragraph break.
        #expect(chunks.map(\.text) == ["One two three.", "Four five six.", "Seven eight nine.\n\nTen."])
        #expect(joined(chunks) == text)
    }

    @Test func neverSplitsInsideAPlaceholder() async {
        let text = "Ask ⟦T1⟧. Then ⟦T2⟧ will do it. Thanks a lot for that."
        let chunks = await split(text, budget: 5)
        #expect(joined(chunks) == text)
        for chunk in chunks {
            #expect(Placeholder.numbers(in: chunk.text).count == chunk.text.components(separatedBy: "⟦").count - 1)
        }
    }

    @Test func splitsSentencesThatStartLowercase() async {
        let text = "fix the build. then ship it! ok?"
        let chunks = await split(text, budget: 3)
        #expect(chunks.map(\.text) == ["fix the build.", "then ship it!", "ok?"])
        #expect(joined(chunks) == text)
    }

    @Test func oversizedSentenceStaysWhole() async {
        let text = "one two three four five six"
        #expect(await split(text, budget: 2) == [Chunk(text: text)])
    }

    @Test func codeBlockPlaceholderLineStaysWithItsParagraph() async {
        let text = "Run this:\n⟦T1⟧\nthen restart.\n\nDone now."
        let chunks = await split(text, budget: 5)
        #expect(chunks.first?.text == "Run this:\n⟦T1⟧\nthen restart.")
        #expect(joined(chunks) == text)
    }

    @Test func longGoldenRowsRejoinExactly() async throws {
        for row in Golden.rows where row.tags.contains("long") {
            let source = try Protector().protect(row.input).text
            let chunks = await split(source, budget: 40)
            #expect(chunks.count > 1, "\(row.id)")
            #expect(joined(chunks) == source, "\(row.id)")
        }
    }
}
