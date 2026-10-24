import KeyboardShortcuts
import PolishCore
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let status: ModelStatusModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(settings: settings)
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSettingsView(status: status)
            }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Polish shortcut:", name: .polish)
            TonePicker(tone: $settings.tone, title: "Default tone")
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PermissionsSettingsView: View {
    let status: ModelStatusModel

    var body: some View {
        // Accessibility trust has no change notification, so re-check every second while the tab is open.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let trusted = Accessibility.isTrusted
            Form {
                Section {
                    LabeledContent("Accessibility", value: trusted ? "Allowed" : "Not allowed")
                    if !trusted {
                        Button("Open Accessibility Settings") {
                            Accessibility.requestTrust()
                            SystemSettings.open(.accessibility)
                        }
                    }
                } footer: {
                    Text("Polish uses Accessibility to read the message you're typing and put the corrected text back.")
                }
                Section {
                    LabeledContent("On-device model", value: status.status.menuTitle)
                } footer: {
                    Text("Text never leaves this Mac.")
                }
            }
            .formStyle(.grouped)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
