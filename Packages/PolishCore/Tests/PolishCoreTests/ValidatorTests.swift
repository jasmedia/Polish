import Testing
@testable import PolishCore

struct ValidatorTests {
    let source = "⟦x ⟦T1⟧ and ⟦T2⟧ are here"

    @Test(arguments: ["⟦x ⟦T1⟧ and ⟦T2⟧ are here", "⟦x ⟦T2⟧ and ⟦T1⟧ are there"])
    func acceptsValidOutput(output: String) {
        #expect(Validator().validate(output, source: source).isEmpty)
    }

    @Test(arguments: [
        ("⟦T1⟧ and are here now", ValidationFailure.missing(2)),
        ("⟦T1⟧ ⟦T1⟧ ⟦T2⟧ are here", .duplicated(1)),
        ("⟦T1⟧ ⟦T2⟧ ⟦T3⟧ are here", .unknown(3)),
        ("⟦T1⟧ and [T2] are here", .missing(2)),
    ])
    func flagsPlaceholderProblems(output: String, failure: ValidationFailure) {
        let failures = Validator().validate(output, source: source)
        #expect(failures.contains(failure))
        #expect(failure.isPlaceholderFailure)
    }

    @Test func flagsMangledPlaceholders() {
        #expect(Validator().validate("Ask [T1] or T1 now.", source: "ask ⟦T1⟧ now").contains(.mangled))
        #expect(Validator().validate("Ask ⟦T1⟧ now ⟦.", source: "ask ⟦T1⟧ now").contains(.mangled))
    }

    @Test func descriptionsMatchThePythonPrototype() {
        #expect(ValidationFailure.missing(2).description == "missing ⟦T2⟧")
        #expect(ValidationFailure.duplicated(1).description == "duplicated ⟦T1⟧")
        #expect(ValidationFailure.unknown(3).description == "unknown ⟦T3⟧")
        #expect(ValidationFailure.mangled.description == "mangled placeholder")
    }

    @Test func chunkOnlyNeedsItsOwnPlaceholders() {
        #expect(Validator().validate("Ask ⟦T4⟧ now.", source: "ask ⟦T4⟧ now").isEmpty)
        #expect(Validator().validate("Ask ⟦T1⟧ now.", source: "ask ⟦T4⟧ now") == [.missing(4), .unknown(1)])
    }

    @Test(arguments: ["", "   ", "\n\n"])
    func rejectsEmptyOutput(output: String) {
        #expect(Validator().validate(output, source: "hello there") == [.empty])
    }

    @Test func rejectsEchoedFormatPrompt() {
        let source = "Retro notes from the project, posting here so people can catch up."
        let output = "Retro notes from the project, posting here so people can catch up. Respond using the following JSON format: {"
        #expect(Validator().validate(output, source: source).contains(.leak))
        #expect(Validator().validate("Can you send it in JSON format?", source: "can u send it in JSON format").isEmpty)
    }

    @Test func lengthLimits() {
        let source = String(repeating: "a", count: 100)
        #expect(Validator().validate(String(repeating: "a", count: 60), source: source).isEmpty)
        #expect(Validator().validate(String(repeating: "a", count: 59), source: source) == [.length])
        #expect(Validator().validate(String(repeating: "a", count: 160), source: source).isEmpty)
        #expect(Validator().validate(String(repeating: "a", count: 161), source: source) == [.length])
        #expect(Validator(tone: .concise).validate(String(repeating: "a", count: 40), source: source).isEmpty)
        #expect(Validator(tone: .concise).validate(String(repeating: "a", count: 39), source: source) == [.length])
    }

    @Test func singleWordAndEmojiOnly() {
        #expect(Validator().validate("Thanks", source: "thanks").isEmpty)
        // Expanding very short shorthand breaks the length limit, as in the Python prototype.
        #expect(Validator().validate("Thanks", source: "thx") == [.length])
        #expect(Validator().validate("⟦T1⟧", source: "⟦T1⟧").isEmpty)
    }

    @Test func mergedLinesFail() {
        #expect(Validator().validate("One. Two.", source: "one\n\ntwo") == [.lines])
        #expect(Validator().validate("One.\nTwo.\nThree.", source: "one\n\ntwo three").isEmpty)
    }
}
