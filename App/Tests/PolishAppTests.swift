import Foundation
import Testing
@testable import Polish
import PolishCore

@MainActor
struct PolishAppTests {
    @Test func statusModelKeepsInjectedStatus() {
        let model = ModelStatusModel(status: .unavailable(.deviceNotEligible))
        #expect(model.status == .unavailable(.deviceNotEligible))
    }

    @Test func toneDefaultsToKeepAndPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "PolishAppTests.tone"))
        defaults.removePersistentDomain(forName: "PolishAppTests.tone")
        #expect(SettingsStore(defaults: defaults).tone == .keep)
        SettingsStore(defaults: defaults).tone = .concise
        #expect(SettingsStore(defaults: defaults).tone == .concise)
    }
}
