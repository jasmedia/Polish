import AppKit
import ApplicationServices
import PolishCore

/// Text read from another app (or the clipboard), and where to put the rewrite back.
struct Draft {
    enum Source {
        case focusedField
        case clipboard
    }

    var text: String
    var source: Source
    /// The app the text came from. Replace refuses to type into any other app.
    var processID: pid_t?
    /// That app's name, for the history (FR-14).
    var appName: String?
    /// The field, when Accessibility exposes it; used to set the text back without the clipboard.
    var element: AXUIElement?
    /// Selection bounds in Accessibility coordinates (top-left origin), for placing the panel.
    var anchor: CGRect?
}

enum BridgeError: Error, Equatable {
    case notTrusted
    case secureField
    case noText
    case noClipboardText
    /// The app the text came from is no longer in front.
    case targetChanged

    var message: String {
        switch self {
        case .notTrusted: "Polish needs Accessibility permission to read and replace text."
        case .secureField: "Polish doesn't read password fields."
        case .noText: "There's no text to polish. Click in a message field first."
        case .noClipboardText: "The clipboard has no text to polish."
        case .targetChanged: "The app you were typing in is no longer in front. Your text wasn't changed."
        }
    }
}

/// Reads and replaces text in the frontmost app (FR-1, FR-6).
@MainActor
protocol TextBridging: AnyObject {
    func readFocusedField() async throws -> Draft
    func readClipboard() throws -> Draft
    /// The selection a Services request (FR-10, Flow C) handed over, tied to the app in front.
    func readService(_ text: String) throws -> Draft
    /// Puts `text` in place of the draft: the selection in its app, or the clipboard.
    func replace(_ draft: Draft, with text: String) async throws
    func copyToClipboard(_ text: String)
}

/// Accessibility first; synthetic ⌘A/⌘C/⌘V through the clipboard when an app (Electron, Slack) doesn't cooperate.
/// The user's clipboard is always restored.
@MainActor
final class AccessibilityBridge: TextBridging {
    private let pasteboard = NSPasteboard.general
    /// The last app other than Polish to come to the front. A Services request can bring Polish to the
    /// front while it's handled, so this is the app the selection came from.
    private var lastOtherApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init() {
        lastOtherApp = NSWorkspace.shared.frontmostApplication.flatMap(Self.other)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app = app.flatMap(Self.other) { self?.lastOtherApp = app }
            }
        }
    }

    nonisolated private static func other(_ app: NSRunningApplication) -> NSRunningApplication? {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
    }

    func readFocusedField() async throws -> Draft {
        guard Accessibility.isTrusted else { throw BridgeError.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { throw BridgeError.noText }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium and Electron build their accessibility tree only when asked.
        appElement.set("AXManualAccessibility", to: kCFBooleanTrue)
        let field = appElement.element(kAXFocusedUIElementAttribute)
        if let field, field.string(kAXRoleAttribute) == "AXSecureTextField"
            || field.string(kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            throw BridgeError.secureField
        }

        await Keyboard.waitForModifierRelease()
        var draft = Draft(text: "", source: .focusedField, processID: app.processIdentifier,
                          appName: app.localizedName, element: field)

        if let selected = field?.string(kAXSelectedTextAttribute), !selected.isBlank {
            Log.bridge.info("Read selection through Accessibility (\(selected.count, privacy: .public) chars)")
            draft.text = selected
        } else if field == nil || field.map(Self.isTextField) == true {
            Keyboard.press(.selectAll)
            try? await Task.sleep(for: .milliseconds(60))
            if let selected = field?.string(kAXSelectedTextAttribute), !selected.isBlank {
                Log.bridge.info("Read whole field through Accessibility (\(selected.count, privacy: .public) chars)")
                draft.text = selected
            } else if let copied = await copySelection(), !copied.isBlank {
                Log.bridge.info("Read whole field through the clipboard (\(copied.count, privacy: .public) chars)")
                draft.text = copied
            }
        }
        guard !draft.text.isBlank else { throw BridgeError.noText }
        draft.anchor = field?.selectionBounds ?? field?.frame
        return draft
    }

    func readClipboard() throws -> Draft {
        guard let text = pasteboard.string(forType: .string), !text.isBlank else { throw BridgeError.noClipboardText }
        return Draft(text: text, source: .clipboard)
    }

    func readService(_ text: String) throws -> Draft {
        // Putting the rewrite back needs Accessibility or synthetic ⌘V, the same as the hotkey.
        guard Accessibility.isTrusted else { throw BridgeError.notTrusted }
        guard !text.isBlank,
              let app = NSWorkspace.shared.frontmostApplication.flatMap(Self.other) ?? lastOtherApp
        else { throw BridgeError.noText }
        let field = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedUIElementAttribute)
        Log.bridge.info("Read selection from Services (\(text.count, privacy: .public) chars)")
        return Draft(text: text, source: .focusedField, processID: app.processIdentifier,
                     appName: app.localizedName, element: field,
                     anchor: field?.selectionBounds ?? field?.frame)
    }

    func replace(_ draft: Draft, with text: String) async throws {
        switch draft.source {
        case .clipboard:
            copyToClipboard(text)
        case .focusedField:
            await bringBack(draft.processID)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == draft.processID else {
                throw BridgeError.targetChanged
            }
            // Let the target's window take key focus back from the panel.
            try await Task.sleep(for: .milliseconds(60))
            if let field = draft.element, setSelectedText(field, to: text) {
                Log.bridge.info("Replaced through Accessibility")
                return
            }
            await paste(text)
            Log.bridge.info("Replaced through the clipboard")
        }
    }

    func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Steps

    /// After a Services request Polish can be in front; give the draft's app the front back. Any other
    /// app in front is left alone, and replace then refuses (`targetChanged`).
    private func bringBack(_ processID: pid_t?) async {
        guard NSWorkspace.shared.frontmostApplication.flatMap(Self.other) == nil, let processID,
              let app = NSRunningApplication(processIdentifier: processID)
        else { return }
        app.activate()
        for _ in 0..<15 where NSWorkspace.shared.frontmostApplication?.processIdentifier != processID {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func isTextField(_ element: AXUIElement) -> Bool {
        let role = element.string(kAXRoleAttribute)
        return [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXWebArea"].contains(role)
    }

    /// Sets the selection through Accessibility and checks the value changed. Some apps report success
    /// without applying it, so an unchanged or unreadable value counts as failure and the caller pastes.
    private func setSelectedText(_ field: AXUIElement, to text: String) -> Bool {
        guard let before = field.string(kAXValueAttribute) else { return false }
        guard field.set(kAXSelectedTextAttribute, to: text as CFString) else { return false }
        return field.string(kAXValueAttribute).map { $0 != before } ?? false
    }

    /// ⌘C, wait for the pasteboard to change, then restore what the user had.
    private func copySelection() async -> String? {
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        Keyboard.press(.copy)
        var copied: String?
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        snapshot.restore(to: pasteboard)
        return copied
    }

    /// Paste over the selection, then restore the user's clipboard.
    private func paste(_ text: String) async {
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .transient], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: .transient)
        Keyboard.press(.paste)
        // The target reads the pasteboard asynchronously; give it time before restoring.
        try? await Task.sleep(for: .milliseconds(300))
        snapshot.restore(to: pasteboard)
    }
}

extension String {
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
