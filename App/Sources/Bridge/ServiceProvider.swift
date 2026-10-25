import AppKit
import PolishCore

/// Services › Polish Text (FR-10, Flow C), declared under `NSServices` in Info.plist. The selection
/// goes to the review panel like a hotkey press; nothing is written back through the Services
/// pasteboard, so the target's text changes only on Accept.
@MainActor
final class ServiceProvider: NSObject {
    private let polish: (String) -> Void

    init(polish: @escaping (String) -> Void) {
        self.polish = polish
    }

    /// `NSMessage` = `polishText`: AppKit calls `polishText:userData:error:`.
    @objc func polishText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isBlank else {
            error.pointee = "Select some text to polish."
            return
        }
        polish(text)
    }
}
