import Foundation
import Observation
import PolishCore

/// One accepted or copied rewrite (FR-14).
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var original: String
    var rewrite: String
    /// `Tone.rawValue`; a string so old files still load if tones change.
    var tone: String
    /// The app the draft came from; nil for the clipboard and the quick window.
    var app: String?
}

/// The last 50 rewrites, newest first, kept only when the user turns history on (FR-14). Stored as JSON in
/// Application Support, readable by the user only. Turning history off deletes the file.
@MainActor
@Observable
final class HistoryStore {
    static let limit = 50

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { clear() }
        }
    }
    private(set) var entries: [HistoryEntry] = []
    private(set) var saveError: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "historyEnabled"

    init(fileURL: URL = HistoryStore.defaultURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        if isEnabled {
            entries = Self.load(fileURL)
        } else {
            // Nothing may stay at rest while history is off.
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.jasmedia.polish", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    func record(original: String, rewrite: String, tone: Tone, app: String?) {
        guard isEnabled else { return }
        // Whole seconds, as ISO 8601 stores them, so an entry is the same after a reload.
        let date = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.down))
        entries.insert(HistoryEntry(date: date, original: original, rewrite: rewrite, tone: tone.rawValue, app: app), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func clear() {
        entries = []
        saveError = nil
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            Log.ui.error("History clear failed: \(String(describing: error), privacy: .public)")
            saveError = "Couldn't delete the history file."
        }
    }

    // MARK: File

    private static func load(_ url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            Log.ui.error("History file unreadable: \(String(describing: type(of: error)), privacy: .public)")
            return []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(entries).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            saveError = nil
        } catch {
            Log.ui.error("History save failed: \(String(describing: error), privacy: .public)")
            saveError = "Couldn't save the history."
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
