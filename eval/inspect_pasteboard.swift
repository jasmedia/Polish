// Mention spike: what does Slack put on the clipboard when you copy a draft?
//
// Run with: swift eval/inspect_pasteboard.swift
// Then, within 60 s, select a Slack draft that contains a mention and press ⌘C.
// Prints every pasteboard type and its contents. Output stays in your terminal; nothing is saved.

import AppKit

let pasteboard = NSPasteboard.general
let start = pasteboard.changeCount
print("Waiting for a copy (⌘C in Slack)…")

let deadline = Date().addingTimeInterval(60)
while pasteboard.changeCount == start {
    if Date() > deadline {
        print("Nothing copied in 60 s.")
        exit(1)
    }
    Thread.sleep(forTimeInterval: 0.2)
}

for item in pasteboard.pasteboardItems ?? [] {
    for type in item.types {
        print("\n=== \(type.rawValue) ===")
        if let string = item.string(forType: type) {
            print(string.prefix(4000))
        } else if let data = item.data(forType: type) {
            print("<\(data.count) bytes of binary data>")
        }
    }
}
