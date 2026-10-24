import Foundation
import Testing
@testable import Polish
import PolishCore

@MainActor
struct OnboardingTests {
    @Test func samplePolishShowsTheRewrite() async {
        let model = OnboardingModel(pipeline: Pipeline(model: FixedModel(["Hey team, I will send the report tomorrow."])))
        model.sample = "hey team, i will send the report tmrw"
        await model.polishSample()
        guard case .result(let result) = model.state else {
            Issue.record("Expected a result, got \(model.state)")
            return
        }
        #expect(result.text == "Hey team, I will send the report tomorrow.")
    }

    @Test func sampleExplainsWhenTheModelIsOff() async {
        let model = OnboardingModel(pipeline: Pipeline(model: FixedModel([], status: .unavailable(.appleIntelligenceNotEnabled))))
        await model.polishSample()
        guard case .failed(let message) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(message == ModelStatus.unavailable(.appleIntelligenceNotEnabled).menuTitle)
    }

    @Test func onboardingIsRememberedAcrossLaunches() throws {
        let suite = "PolishTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!SettingsStore(defaults: defaults).hasCompletedOnboarding)
        SettingsStore(defaults: defaults).hasCompletedOnboarding = true
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding)
    }
}
