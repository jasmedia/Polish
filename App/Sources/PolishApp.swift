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
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?

    init() {
        let pipeline = Pipeline()
        controller = PolishController(bridge: AccessibilityBridge(), pipeline: pipeline, presenter: presenter,
                                      defaultTone: { [settings] in settings.tone })
        presenter.controller = controller
        status = ModelStatusModel(updates: ModelAvailability.updates())
        status.onChange = { [controller] in controller.modelStatusChanged($0) }
        let onboardingModel = OnboardingModel(pipeline: pipeline)
        onboarding = OnboardingWindowController(
            makeView: { [status] done in
                AnyView(OnboardingView(model: onboardingModel, status: status, done: done))
            },
            onFinish: { [settings] in settings.hasCompletedOnboarding = true }
        )
        if !settings.hasCompletedOnboarding {
            // After launch finishes; the app can't activate or show windows from inside App.init.
            Task { [weak self] in self?.showOnboarding() }
        }
        hotkeyTask = Task { [controller] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: .polish) {
                controller.polishFocusedField()
            }
        }
    }

    func showOnboarding() {
        onboarding?.show()
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
        @Bindable var settings = app.settings
        TonePicker(tone: $settings.tone, title: "Tone")
        Divider()
        Button("Welcome Guide…") {
            app.showOnboarding()
        }
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
