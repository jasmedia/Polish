import KeyboardShortcuts
import PolishCore
import SwiftUI

/// Menu bar only app (`LSUIElement = YES` in Info.plist): no Dock icon, no main window.
@main
struct PolishApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        MenuBarExtra("Polish", systemImage: "text.badge.checkmark") {
            MenuContent(app: app)
        }
        Settings {
            SettingsView(settings: app.settings, status: app.status)
        }
    }
}

/// Owns the long-lived pieces and listens for the hotkey from launch.
@MainActor
@Observable
final class AppModel {
    let status: ModelStatusModel
    let settings = SettingsStore()
    let controller: PolishController
    @ObservationIgnored private let presenter = ReviewPanelPresenter()
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?

    init() {
        controller = PolishController(bridge: AccessibilityBridge(), pipeline: Pipeline(), presenter: presenter)
        presenter.controller = controller
        status = ModelStatusModel(updates: ModelAvailability.updates())
        status.onChange = { [controller] in controller.modelStatusChanged($0) }
        hotkeyTask = Task { [controller] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: .polish) {
                controller.polishFocusedField()
            }
        }
    }
}

private struct MenuContent: View {
    let app: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(app.status.status.menuTitle)
        Divider()
        Button("Polish Clipboard") {
            app.controller.polishClipboard()
        }
        Divider()
        Button("Settings…") {
            // A menu bar app isn't active, so its Settings window would open behind other apps.
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Polish") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
