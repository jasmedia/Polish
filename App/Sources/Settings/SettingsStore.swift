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

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
        static let tone = "tone"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
        tone = defaults.string(forKey: Keys.tone).flatMap(Tone.init(rawValue:)) ?? .keep
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
