import SwiftUI
import PolishCore

/// Menu bar only app (`LSUIElement = YES` in Info.plist): no Dock icon, no main window.
@main
struct PolishApp: App {
    @State private var model = ModelStatusModel()

    var body: some Scene {
        MenuBarExtra("Polish", systemImage: "text.badge.checkmark") {
            Text(model.status.menuTitle)
            Divider()
            Button("Quit Polish") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
