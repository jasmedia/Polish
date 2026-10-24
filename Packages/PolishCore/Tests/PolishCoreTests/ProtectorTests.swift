import Testing
@testable import PolishCore

struct ProtectorTests {
    // Same cases as eval/test_protect.py: (input, tokens protect() must find, in order).
    static let cases: [(String, [String])] = [
        ("<@U02ABC123> can u check", ["<@U02ABC123>"]),
        ("see <#C0123ABC|general> and #platform-eng", ["<#C0123ABC|general>", "#platform-eng"]),
        ("<!here> deploy at 5", ["<!here>"]),
        ("@Alex Morgan is it required", ["@Alex Morgan"]),
        ("@Maria Lopez Garcia and @Tom Becker pls sync", ["@Maria Lopez Garcia", "@Tom Becker"]),
        ("@Jordan can you check", ["@Jordan"]),
        ("@Sam We can remove it", ["@Sam"]),
        ("thanks for the fix @Chris Park.", ["@Chris Park"]),
        ("@here the env is down", ["@here"]),
        ("mail dev@example.com today", ["dev@example.com"]),
        ("docs at https://example.com/a?b=1. thanks", ["https://example.com/a?b=1"]),
        ("(see https://example.com/x)", ["https://example.com/x"]),
        ("<https://example.com/doc|the doc> is up", ["<https://example.com/doc|the doc>"]),
        ("nice :tada::skin-tone-2: and :+1:", [":tada::skin-tone-2:", ":+1:"]),
        ("run `kubectl get pods` now", ["`kubectl get pods`"]),
        ("try:\n```\nfoo = 'bar'\n```\nthen tell me", ["```\nfoo = 'bar'\n```"]),
        ("this is *really* urgent", ["*really*"]),
        ("_please_ check ~old~ ~~older~~", ["_please_", "~old~", "~~older~~"]),
        ("*@Sam* look", ["*@Sam*"]),
        ("snake_case and 5 * 3 and ~5 min", []),
        ("- item one\n• item two\n1. item three", []),
        ("issue #42 and C# code", ["#42"]),
        ("ratio 3:2 at 10:30", []),
        // Emoji and links inside code stay inside the one code token.
        ("run `echo :tada: https://x.io`", ["`echo :tada: https://x.io`"]),
        ("```\n:wave: <@U1>\n```", ["```\n:wave: <@U1>\n```"]),
        // Overlapping candidates: the earliest token wins and swallows the rest.
        ("*see https://example.com/a*", ["*see https://example.com/a*"]),
        ("<https://a.io|*bold*>", ["<https://a.io|*bold*>"]),
        ("👍🏽 emoji only 🎉", []),
        ]

    @Test(arguments: cases)
    func findsTokens(text: String, expected: [String]) throws {
        #expect(try Protector().protect(text).tokens == expected)
    }

    @Test func placeholdersAreNumberedInOrder() throws {
        let protected = try Protector().protect("hi <@U1>, see #a and `b`")
        #expect(protected.text == "hi ⟦T1⟧, see ⟦T2⟧ and ⟦T3⟧")
    }

    @Test func dictionaryWordsAreProtected() throws {
        let protected = try Protector(dictionary: ["Kubeflow"]).protect("ask Kubeflow and kubeflow-ui")
        #expect(protected.tokens == ["Kubeflow"])
    }

    @Test func dictionaryNeverSplitsAnotherToken() throws {
        let protected = try Protector(dictionary: ["Cruz", "de la Cruz"]).protect("@Ana de la Cruz and de la Cruz")
        #expect(protected.tokens == ["@Ana", "de la Cruz", "de la Cruz"])
    }

    @Test func refusesTextWithPlaceholders() {
        #expect(throws: ProtectorError.containsPlaceholder) { try Protector().protect("a ⟦T1⟧ b") }
    }

    @Test func restoreLeavesUnknownPlaceholders() throws {
        let protected = try Protector().protect("<@U1> hi")
        #expect(protected.restore("⟦T1⟧ ⟦T2⟧") == "<@U1> ⟦T2⟧")
    }

    @Test func goldenRowsRoundTripByteForByte() throws {
        #expect(Golden.rows.count >= 200)
        for row in Golden.rows {
            for text in [row.input, row.expected] {
                let protected = try Protector().protect(text)
                #expect(protected.restore(protected.text) == text, "\(row.id)")
            }
        }
    }

    @Test func protectedInputTokensSurviveInExpected() throws {
        for row in Golden.rows {
            for token in try Protector().protect(row.input).tokens {
                #expect(row.expected.contains(token), "\(row.id): \(token)")
            }
        }
    }
}
