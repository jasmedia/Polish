import Testing
import FoundationModels
@testable import PolishCore

struct ModelStatusTests {
    @Test(arguments: [
        (ModelStatus.ready, "Ready · on-device"),
        (.unavailable(.deviceNotEligible), "This Mac can't run Apple Intelligence"),
        (.unavailable(.appleIntelligenceNotEnabled), "Turn on Apple Intelligence in System Settings"),
        (.unavailable(.modelNotReady), "Model is downloading…"),
        (.unavailable(.other("x")), "Model unavailable"),
    ])
    func menuTitle(status: ModelStatus, expected: String) {
        #expect(status.menuTitle == expected)
    }

    @Test func readingAvailabilityNeverCrashes() {
        // Runs everywhere, including CI where the model is unavailable.
        _ = ModelStatus.current()
    }
}

/// Tests that call the real model. They skip themselves wherever the model isn't ready
/// (GitHub runners, Macs without Apple Intelligence) and run on the dev Mac.
@Suite(.enabled(if: ModelStatus.current().isReady, "On-device model not available"))
struct OnDeviceModelSmokeTests {
    @Test func modelAnswersAShortPrompt() async throws {
        let session = LanguageModelSession(instructions: "Reply with one short sentence.")
        let response = try await session.respond(to: "Say hello.")
        #expect(!response.content.isEmpty)
    }
}
