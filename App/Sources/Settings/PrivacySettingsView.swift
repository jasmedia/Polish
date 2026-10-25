import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where the Polish shortcut works (FR-15) and whether rewrites are kept (FR-14).
struct PrivacySettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var history: HistoryStore

    var body: some View {
        Form {
            Section {
                Toggle("Polish in every app", isOn: $settings.allApps)
                if !settings.allApps {
                    ForEach(settings.enabledApps, id: \.self) { bundleID in
                        AppRow(app: InstalledApp(bundleID: bundleID)) {
                            settings.removeEnabledApp(bundleID)
                        }
                    }
                    if settings.enabledApps.isEmpty {
                        Text("No apps yet")
                            .foregroundStyle(.secondary)
                    }
                    Button("Add App…", action: addApp)
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Elsewhere the Polish shortcut does nothing. Polish Clipboard, Quick Polish and Services › Polish Text work in every app.")
            }
            Section {
                Toggle(isOn: $history.isEnabled) {
                    Text("Keep a history of rewrites")
                    Text("The last \(HistoryStore.limit) rewrites you accepted or copied, stored only on this Mac. Turning this off deletes them.")
                }
                if history.isEnabled {
                    HistoryList(entries: history.entries)
                    HStack {
                        Text(history.entries.count == 1 ? "1 rewrite" : "\(history.entries.count) rewrites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History", role: .destructive, action: history.clear)
                            .disabled(history.entries.isEmpty)
                    }
                }
                if let error = history.saveError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose the apps where the Polish shortcut should work."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { settings.addEnabledApp(bundleID) }
        }
    }
}

/// An app on the enable list, resolved for display. An app that isn't installed shows its bundle ID.
private struct InstalledApp {
    let bundleID: String
    let name: String
    let icon: NSImage?

    init(bundleID: String) {
        self.bundleID = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            name = bundleID
            icon = nil
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let remove: () -> Void

    var body: some View {
        HStack {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            Text(app.name)
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove \(app.name)")
            .accessibilityLabel("Remove \(app.name)")
        }
    }
}

/// Newest first; the context menu copies either side.
private struct HistoryList: View {
    let entries: [HistoryEntry]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.rewrite)
                    .lineLimit(2)
                Text(Self.detail(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .contextMenu {
                Button("Copy Rewrite") { Self.copy(entry.rewrite) }
                Button("Copy Original") { Self.copy(entry.original) }
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 180)
        .overlay {
            if entries.isEmpty {
                Text("No rewrites yet")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("History")
    }

    static func detail(_ entry: HistoryEntry) -> String {
        let date = entry.date.formatted(date: .abbreviated, time: .shortened)
        return [date, entry.app].compactMap(\.self).joined(separator: " · ")
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
