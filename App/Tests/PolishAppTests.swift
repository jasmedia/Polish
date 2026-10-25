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

    @Test func dictionaryStartsEmptyAndPersists() throws {
        let suite = "PolishAppTests.dictionary"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.dictionary.isEmpty)
        var pushed: [[String]] = []
        settings.onDictionaryChange = { pushed.append($0) }

        #expect(settings.addDictionaryEntry("  Kubeflow ") == nil)
        #expect(settings.addDictionaryEntry("de la Cruz") == nil)
        #expect(SettingsStore(defaults: defaults).dictionary == ["Kubeflow", "de la Cruz"])

        settings.removeDictionaryEntries(["Kubeflow"])
        #expect(SettingsStore(defaults: defaults).dictionary == ["de la Cruz"])
        #expect(pushed == [["Kubeflow"], ["Kubeflow", "de la Cruz"], ["de la Cruz"]])
    }

    @Test(arguments: [
        ("   ", SettingsStore.DictionaryEntryProblem.empty),
        ("Kubeflow", .duplicate),
        ("two\nlines", .unsupported),
        ("a ⟦T1⟧", .unsupported),
    ])
    func dictionaryRejects(entry: String, problem: SettingsStore.DictionaryEntryProblem) throws {
        let suite = "PolishAppTests.dictionaryRejects"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.addDictionaryEntry("Kubeflow")
        #expect(settings.addDictionaryEntry(entry) == problem)
        #expect(settings.dictionary == ["Kubeflow"])
    }
}
