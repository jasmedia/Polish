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

    @Test func restyleTemplateIsForTheOtherTonesOnly() {
        let restyle = InstructionsBuilder.Restyle(template: "Restyle. {tone}\n{placeholders}\n", tones: [.casual: "Tone: chatty."])
        let builder = InstructionsBuilder(restyle: restyle)
        #expect(builder.build(tone: .keep, placeholders: []) == InstructionsBuilder(restyle: nil).build(tone: .keep, placeholders: []))
        #expect(builder.build(tone: .casual, placeholders: []) == "Restyle. Tone: chatty.\n")
        // A tone the restyle prompt doesn't cover stays on the keep template.
        #expect(builder.build(tone: .concise, placeholders: []) == InstructionsBuilder(restyle: nil).build(tone: .concise, placeholders: []))
    }

    @Test func loadsAPromptVersionWithItsToneTexts() throws {
        let restyle = try InstructionsBuilder.Restyle(contentsOf: Golden.repoRoot.appending(path: "prompts/v2.txt"))
        #expect(restyle.template.contains("{tone}"))
        #expect(Set(restyle.tones.keys) == [.casual, .professional, .concise])
        #expect(restyle.tones.values.allSatisfy { $0.hasPrefix("Tone: ") && !$0.hasSuffix("\n") })
    }

    @Test func v2MatchesItsPromptFiles() throws {
        let files = try InstructionsBuilder.Restyle(contentsOf: Golden.repoRoot.appending(path: "prompts/v2.txt"))
        #expect(Prompt.v2.template == files.template)
        #expect(Prompt.v2.tones[.casual] == files.tones[.casual])
        #expect(Prompt.v2.tones[.professional] == files.tones[.professional])
    }

    @Test func shipsV2ForCasualAndProfessionalOnly() {
        let builder = InstructionsBuilder()
        let v1 = InstructionsBuilder(restyle: nil)
        #expect(builder.build(tone: .keep, placeholders: []) == v1.build(tone: .keep, placeholders: []))
        #expect(builder.build(tone: .concise, placeholders: []) == v1.build(tone: .concise, placeholders: []))
        #expect(builder.build(tone: .casual, placeholders: []).hasPrefix("You rewrite a Slack message that was typed quickly and may contain mistakes. The writer"))
        #expect(builder.build(tone: .professional, placeholders: []).contains("Tone: professional and polite"))
    }
}
