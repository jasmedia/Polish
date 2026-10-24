import Testing
@testable import PolishCore

/// The real pipeline on 20 golden rows (every tenth row, so each tag group is sampled).
/// Skips where the model isn't ready; the full set runs through `polish-cli golden`.
@Suite(.enabled(if: ModelStatus.current().isReady, "On-device model not available"), .serialized)
struct GoldenModelTests {
    static let sample = Golden.rows.enumerated().filter { $0.offset % 10 == 0 }.prefix(20).map(\.element)

    @Test func sampleCoversTheTags() {
        #expect(Self.sample.count == 20)
        #expect(Self.sample.contains { $0.tags.contains("correct") })
        #expect(Self.sample.contains { $0.tags.contains("slack-syntax") })
    }

    @Test(arguments: sample.map(\.id))
    func slackTokensSurvive(id: String) async throws {
        let row = try #require(Golden.rows.first { $0.id == id })
        let result = try await Pipeline().polish(text: row.input)
        for token in try Protector().protect(row.input).tokens {
            #expect(result.text.components(separatedBy: token).count == row.input.components(separatedBy: token).count,
                    "\(token) count changed")
        }
        if row.tags.contains("correct") {
            #expect(Restorer.toStraight(result.text) == Restorer.toStraight(row.input), "correct row was changed")
        }
    }
}
