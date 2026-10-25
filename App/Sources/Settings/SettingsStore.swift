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

    /// Words and names Polish never changes (FR-11), in the order added. Ships empty.
    private(set) var dictionary: [String] {
        didSet {
            defaults.set(dictionary, forKey: Keys.dictionary)
            onDictionaryChange?(dictionary)
        }
    }

    /// Called with the new list after every change, to hand it to the pipeline.
    @ObservationIgnored var onDictionaryChange: (([String]) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
        static let tone = "tone"
        static let dictionary = "dictionary"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
        tone = defaults.string(forKey: Keys.tone).flatMap(Tone.init(rawValue:)) ?? .keep
        dictionary = defaults.stringArray(forKey: Keys.dictionary) ?? []
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
