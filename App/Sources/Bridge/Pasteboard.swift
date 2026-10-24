import AppKit

extension NSPasteboard.PasteboardType {
    /// Tells clipboard managers to skip items Polish writes only for a moment (nspasteboard.org).
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

/// Every item and type on the pasteboard, so the clipboard fallback can put back what the user had.
@MainActor
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        })
    }
}
