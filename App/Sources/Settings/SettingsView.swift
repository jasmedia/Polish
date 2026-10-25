import KeyboardShortcuts
import PolishCore
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let history: HistoryStore
    let status: ModelStatusModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(settings: settings)
            }
            Tab("Dictionary", systemImage: "character.book.closed") {
                DictionarySettingsView(settings: settings)
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettingsView(settings: settings, history: history)
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
            KeyboardShortcuts.Recorder("Quick Polish shortcut:", name: .quickPolish)
            TonePicker(tone: $settings.tone, title: "Default tone")
            Toggle(isOn: $settings.showChanges) {
                Text("Show a list of changes")
                Text("A reason for each fix, under the rewrite. Polishing takes a little longer.")
            }
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

/// Words and names Polish never changes (FR-11).
private struct DictionarySettingsView: View {
    let settings: SettingsStore
    @State private var entry = ""
    @State private var problem: SettingsStore.DictionaryEntryProblem?
    @State private var selection: Set<String> = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words and names Polish never changes, such as product names, people's names and team jargon. Matching is exact, including capitals.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Add a word or name", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(add)
                    .onChange(of: entry) { problem = nil }
                Button("Add", action: add)
                    .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem {
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            List(settings.dictionary, id: \.self, selection: $selection) { word in
                Text(word)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 180)
            .overlay {
                if settings.dictionary.isEmpty {
                    Text("No words yet")
                        .foregroundStyle(.secondary)
                }
            }
            .onDeleteCommand(perform: remove)
            .accessibilityLabel("Dictionary entries")
            HStack {
                Button("Remove", action: remove)
                    .disabled(selection.isEmpty)
                    .help("Remove the selected entries (Delete)")
                Spacer()
                Text(settings.dictionary.count == 1 ? "1 entry" : "\(settings.dictionary.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func add() {
        problem = settings.addDictionaryEntry(entry)
        if problem == nil {
            entry = ""
        }
        fieldFocused = true
    }

    private func remove() {
        settings.removeDictionaryEntries(selection)
        selection = []
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
