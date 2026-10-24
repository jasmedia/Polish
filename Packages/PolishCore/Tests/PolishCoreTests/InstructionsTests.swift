import Foundation
import Testing
@testable import PolishCore

struct InstructionsTests {
    @Test func v1MatchesThePromptFile() throws {
        let file = try String(contentsOf: Golden.repoRoot.appending(path: "prompts/v1.txt"), encoding: .utf8)
        #expect(Prompt.v1 == file)
    }

    @Test func noPlaceholderRuleWithoutPlaceholders() {
        let text = InstructionsBuilder().build(tone: .keep, placeholders: [])
        #expect(!text.contains("⟦"))
        #expect(!text.contains("{placeholders}"))
        #expect(text.contains("Tone: keep the writer's tone."))
    }

    @Test func namesEveryPlaceholder() {
        let text = InstructionsBuilder().build(tone: .keep, placeholders: [1, 2])
        #expect(text.contains(
            "When the message starts by addressing someone, put a comma after their name or placeholder.\n"
                + "The message contains placeholders: ⟦T1⟧, ⟦T2⟧. Copy each one exactly once, unchanged, in a natural position.\n"
                + "If the text is already clear and correct"
        ))
    }

    @Test func leadingMentionRule() {
        let text = InstructionsBuilder().build(tone: .keep, placeholders: [3], leading: .init(number: 3, isMention: true))
        #expect(text.contains("The message starts with ⟦T3⟧, which addresses someone: keep ⟦T3⟧ at the start.\n"))
    }

    @Test func leadingTokenRule() {
        let text = InstructionsBuilder().build(tone: .keep, placeholders: [1], leading: .init(number: 1, isMention: false))
        #expect(text.contains("The message starts with ⟦T1⟧: keep ⟦T1⟧ at the start.\n"))
    }

    @Test(arguments: Tone.allCases)
    func everyToneFillsTheSlot(tone: Tone) {
        #expect(!InstructionsBuilder().build(tone: tone, placeholders: []).contains("{tone}"))
    }
}
