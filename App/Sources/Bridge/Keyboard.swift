import AppKit
import Carbon.HIToolbox

/// Synthetic ⌘A / ⌘C / ⌘V for the clipboard fallback. Needs the Accessibility permission.
@MainActor
enum Keyboard {
    enum Shortcut {
        case selectAll, copy, paste

        var keyCode: CGKeyCode {
            switch self {
            case .selectAll: CGKeyCode(kVK_ANSI_A)
            case .copy: CGKeyCode(kVK_ANSI_C)
            case .paste: CGKeyCode(kVK_ANSI_V)
            }
        }
    }

    static func press(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The hotkey fires on key-up, often with ⌃⌥ still held, which would turn ⌘C into ⌃⌥⌘C.
    static func waitForModifierRelease(timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        while !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
    }
}
