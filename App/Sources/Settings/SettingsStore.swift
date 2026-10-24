import Observation
import PolishCore
import ServiceManagement

/// App preferences. The hotkey itself is stored by KeyboardShortcuts in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
