import KeyboardShortcuts
import PolishCore
import SwiftUI

/// Menu bar only app (`LSUIElement = YES` in Info.plist): no Dock icon, no main window.
@main
struct PolishApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        // A template symbol, so the menu bar tints it; it echoes the app icon's bubble and check mark.
        MenuBarExtra("Polish", systemImage: "checkmark.bubble") {
            MenuContent(app: app)
        }
        Settings {
            SettingsView(settings: app.settings, history: app.history, status: app.status)
        }
    }
}

/// Owns the long-lived pieces and listens for the hotkey from launch.
@MainActor
@Observable
final class AppModel {
    let status: ModelStatusModel
    let settings = SettingsStore()
    let history = HistoryStore()
    let controller: PolishController
    @ObservationIgnored private let presenter = ReviewPanelPresenter()
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private let quickWindow: QuickWindowController
    @ObservationIgnored private let services: ServiceProvider
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var quickHotkeyTask: Task<Void, Never>?

    init() {
        let pipeline = Pipeline()
        pipeline.dictionary = settings.dictionary
        settings.onDictionaryChange = { pipeline.dictionary = $0 }
        let bridge = AccessibilityBridge()
        controller = PolishController(bridge: bridge, pipeline: pipeline, presenter: presenter,
                                      defaultTone: { [settings] in settings.tone },
                                      showChanges: { [settings] in settings.showChanges },
                                      record: { [history] draft, rewrite, tone in
                                          history.record(original: draft.text, rewrite: rewrite, tone: tone, app: draft.appName)
                                      })
        presenter.controller = controller
        status = ModelStatusModel(updates: ModelAvailability.updates())
        status.onChange = { [controller] in controller.modelStatusChanged($0) }
        quickWindow = QuickWindowController(model: QuickWindowModel(
            pipeline: pipeline, tone: settings.tone, showChanges: { [settings] in settings.showChanges },
            record: { [history] original, rewrite, tone in
                history.record(original: original, rewrite: rewrite, tone: tone, app: nil)
            },
            copy: { bridge.copyToClipboard($0) }
        ))
        services = ServiceProvider { [controller] in controller.polishServiceText($0) }
        let onboardingModel = OnboardingModel(pipeline: pipeline)
        onboarding = OnboardingWindowController(
            makeView: { [status] done in
                AnyView(OnboardingView(model: onboardingModel, status: status, done: done))
            },
            onFinish: { [settings] in settings.hasCompletedOnboarding = true }
        )
        // After launch finishes; the app can't activate or show windows from inside App.init.
        Task { [weak self, services] in
            NSApplication.shared.servicesProvider = services
            NSUpdateDynamicServices()
            if self?.settings.hasCompletedOnboarding == false { self?.showOnboarding() }
        }
        hotkeyTask = Task { [controller, settings] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: .polish) {
                // FR-15: the shortcut does nothing in apps that aren't on the list.
                let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                guard settings.isEnabled(bundleID: bundleID) else {
                    Log.ui.info("Shortcut ignored in \(bundleID ?? "unknown app", privacy: .public): not enabled")
                    continue
                }
                controller.polishFocusedField()
            }
        }
        quickHotkeyTask = Task { [quickWindow] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: .quickPolish) {
                quickWindow.show()
            }
        }
    }

    func showQuickWindow() {
        quickWindow.show()
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
        Button("Quick Polish…") {
            app.showQuickWindow()
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
