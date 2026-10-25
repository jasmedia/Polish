import Foundation
import Testing
@testable import Polish
import PolishCore

/// History (FR-14) and the per-app enable list (FR-15).
@MainActor
struct PrivacyTests {
    /// The controller holds its presenter unowned, so the test keeps it alive.
    let presenter = RecordingPresenter()
    let directory = URL.temporaryDirectory.appending(path: "PolishTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var fileURL: URL { directory.appending(path: "history.json") }

    func defaults(_ name: String) throws -> UserDefaults {
        let suite = "PrivacyTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func historyIsOffByDefaultAndRecordsNothing() throws {
        let history = HistoryStore(fileURL: fileURL, defaults: try defaults("off"))
        #expect(!history.isEnabled)
        history.record(original: "teh", rewrite: "the", tone: .keep, app: "Slack")
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func historyKeepsTheNewest50AndPersists() throws {
        let defaults = try defaults("persist")
        let history = HistoryStore(fileURL: fileURL, defaults: defaults)
        history.isEnabled = true
        for i in 1...52 {
            history.record(original: "draft \(i)", rewrite: "Draft \(i).", tone: .casual, app: "Slack")
        }
        #expect(history.entries.count == 50)
        #expect(history.entries.first?.rewrite == "Draft 52.")
        #expect(history.entries.last?.rewrite == "Draft 3.")

        let reloaded = HistoryStore(fileURL: fileURL, defaults: defaults)
        #expect(reloaded.entries == history.entries)
        #expect(reloaded.entries.first?.tone == "casual")
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func clearAndTurningOffDeleteTheFile() throws {
        let defaults = try defaults("clear")
        let history = HistoryStore(fileURL: fileURL, defaults: defaults)
        history.isEnabled = true
        history.record(original: "teh", rewrite: "the", tone: .keep, app: nil)
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        history.record(original: "teh", rewrite: "the", tone: .keep, app: nil)
        history.isEnabled = false
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!HistoryStore(fileURL: fileURL, defaults: defaults).isEnabled)
    }

    @Test func acceptAndCopyAreRecorded() async {
        let bridge = FakeBridge("i will send the report tmrw")
        var recorded: [(String, String, Tone)] = []
        let controller = PolishController(
            bridge: bridge, pipeline: Pipeline(model: FixedModel(["I will send the report tomorrow.", "I will send the report tomorrow."])),
            presenter: presenter, defaultTone: { .professional },
            record: { recorded.append(($0.text, $1, $2)) }
        )
        controller.polishFocusedField()
        await controller.work?.value
        controller.accept()
        await controller.work?.value
        controller.polishFocusedField()
        await controller.work?.value
        controller.copy()
        #expect(recorded.count == 2)
        #expect(recorded.allSatisfy {
            $0 == ("i will send the report tmrw", "I will send the report tomorrow.", .professional)
        })
    }

    @Test func cancelledPolishIsNotRecorded() async {
        var recorded = 0
        let controller = PolishController(
            bridge: FakeBridge("i will send the report tmrw"),
            pipeline: Pipeline(model: FixedModel(["I will send the report tomorrow."])),
            presenter: presenter, record: { _, _, _ in recorded += 1 }
        )
        controller.polishFocusedField()
        await controller.work?.value
        controller.cancel()
        #expect(recorded == 0)
    }

    @Test func quickWindowCopyIsRecordedWithItsTone() async {
        var recorded: [(String, String, Tone)] = []
        let model = QuickWindowModel(pipeline: Pipeline(model: FixedModel(["I will send the report tomorrow."])),
                                     tone: .casual, record: { recorded.append(($0, $1, $2)) }) { _ in }
        model.text = "i will send the report tmrw"
        model.polish()
        await model.work?.value
        model.tone = .concise
        model.copyResult()
        #expect(recorded.count == 1)
        #expect(recorded.first.map { $0 == ("i will send the report tmrw", "I will send the report tomorrow.", .casual) } == true)
    }

    @Test func shortcutWorksOnlyInSlackByDefault() throws {
        let settings = SettingsStore(defaults: try defaults("apps"))
        #expect(settings.enabledApps == [SettingsStore.slackBundleID])
        #expect(settings.isEnabled(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(!settings.isEnabled(bundleID: "com.apple.Notes"))
        #expect(!settings.isEnabled(bundleID: nil))
    }

    @Test func enabledAppsPersistAndAllAppsOverrides() throws {
        let defaults = try defaults("appsPersist")
        let settings = SettingsStore(defaults: defaults)
        settings.addEnabledApp("com.apple.Notes")
        settings.addEnabledApp("com.apple.Notes")
        settings.removeEnabledApp(SettingsStore.slackBundleID)
        #expect(SettingsStore(defaults: defaults).enabledApps == ["com.apple.Notes"])

        settings.removeEnabledApp("com.apple.Notes")
        // An emptied list stays empty; it doesn't fall back to Slack.
        #expect(SettingsStore(defaults: defaults).enabledApps.isEmpty)
        #expect(!settings.isEnabled(bundleID: SettingsStore.slackBundleID))

        settings.allApps = true
        #expect(SettingsStore(defaults: defaults).isEnabled(bundleID: "com.apple.TextEdit"))
        #expect(settings.isEnabled(bundleID: nil))
    }
}
