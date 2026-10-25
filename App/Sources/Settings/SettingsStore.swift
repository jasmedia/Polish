import Foundation
import Observation
import PolishCore
import ServiceManagement

/// App preferences. The hotkey itself is stored by KeyboardShortcuts in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    /// Set once the first-run window has been closed.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboardingCompleted) }
    }

    /// The tone each polish starts with (FR-8). Tab in the review panel changes it for one message only.
    var tone: Tone {
        didSet { defaults.set(tone.rawValue, forKey: Keys.tone) }
    }

    /// Asks the model for a short list of the fixes with a reason each, shown under the diff (FR-9). Off by
    /// default: the model writes the list after the text, which adds time to every polish.
    var showChanges: Bool {
        didSet { defaults.set(showChanges, forKey: Keys.showChanges) }
    }

    /// Words and names Polish never changes (FR-11), in the order added. Ships empty.
    private(set) var dictionary: [String] {
        didSet {
            defaults.set(dictionary, forKey: Keys.dictionary)
            onDictionaryChange?(dictionary)
        }
    }

    /// The Polish shortcut works in every app, ignoring `enabledApps` (FR-15). Off by default.
    var allApps: Bool {
        didSet { defaults.set(allApps, forKey: Keys.allApps) }
    }

    /// Bundle IDs of the apps where the Polish shortcut works (FR-15), in the order added. Slack by default.
    private(set) var enabledApps: [String] {
        didSet { defaults.set(enabledApps, forKey: Keys.enabledApps) }
    }

    static let slackBundleID = "com.tinyspeck.slackmacgap"

    /// Called with the new list after every change, to hand it to the pipeline.
    @ObservationIgnored var onDictionaryChange: (([String]) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
        static let tone = "tone"
        static let dictionary = "dictionary"
        static let showChanges = "showChanges"
        static let allApps = "allApps"
        static let enabledApps = "enabledApps"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
        tone = defaults.string(forKey: Keys.tone).flatMap(Tone.init(rawValue:)) ?? .keep
        showChanges = defaults.bool(forKey: Keys.showChanges)
        dictionary = defaults.stringArray(forKey: Keys.dictionary) ?? []
        allApps = defaults.bool(forKey: Keys.allApps)
        enabledApps = defaults.stringArray(forKey: Keys.enabledApps) ?? [Self.slackBundleID]
    }

    /// Whether the Polish shortcut should act in the app with this bundle ID. Elsewhere it does nothing.
    func isEnabled(bundleID: String?) -> Bool {
        if allApps { return true }
        guard let bundleID else { return false }
        return enabledApps.contains(bundleID)
    }

    func addEnabledApp(_ bundleID: String) {
        guard !enabledApps.contains(bundleID) else { return }
        enabledApps.append(bundleID)
    }

    func removeEnabledApp(_ bundleID: String) {
        enabledApps.removeAll { $0 == bundleID }
    }

    enum DictionaryEntryProblem: Equatable {
        case empty, duplicate, unsupported

        var message: String {
            switch self {
            case .empty: "Type a word or name first."
            case .duplicate: "That's already in your dictionary."
            case .unsupported: "Entries must be on one line and can't contain ⟦ or ⟧."
            }
        }
    }

    /// Adds an entry, trimmed. Matching is exact and case-sensitive, so `Kubeflow` and `kubeflow` are different entries.
    @discardableResult
    func addDictionaryEntry(_ entry: String) -> DictionaryEntryProblem? {
        let word = entry.trimmingCharacters(in: .whitespaces)
        if word.isEmpty { return .empty }
        if word.contains(where: \.isNewline) || word.contains("⟦") || word.contains("⟧") { return .unsupported }
        if dictionary.contains(word) { return .duplicate }
        dictionary.append(word)
        return nil
    }

    func removeDictionaryEntries(_ entries: Set<String>) {
        dictionary.removeAll { entries.contains($0) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            Log.ui.error("Launch at login change failed: \(String(describing: error), privacy: .public)")
            launchAtLoginError = "Couldn't change this setting. Try again from System Settings › General › Login Items."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
