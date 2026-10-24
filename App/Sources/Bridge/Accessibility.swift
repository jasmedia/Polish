import AppKit
import ApplicationServices

/// The Accessibility permission (FR-6). It is tied to the code signature; see scripts/bundle.sh.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Polish to the Accessibility list (once per signature).
    static func requestTrust() {
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6 flags as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

enum SystemSettings {
    enum Pane {
        case accessibility
        case appleIntelligence

        var url: URL {
            switch self {
            case .accessibility:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .appleIntelligence:
                URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
            }
        }
    }

    @MainActor
    static func open(_ pane: Pane) {
        NSWorkspace.shared.open(pane.url)
    }
}

extension AXUIElement {
    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func axValue(_ attribute: String) -> AXValue? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    /// The element's frame in Accessibility coordinates (top-left origin of the primary screen).
    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(kAXPositionAttribute), AXValueGetValue(position, .cgPoint, &origin),
              let extent = axValue(kAXSizeAttribute), AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Bounds of the selected text, or of the caret when nothing is selected.
    var selectionBounds: CGRect? {
        guard let range = axValue(kAXSelectedTextRangeAttribute) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            self, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
            let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return rect
    }

    @discardableResult
    func set(_ attribute: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    private func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
