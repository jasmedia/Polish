import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Polish the focused text field (FR-1). Default ⌃⌥G; the user can change it in Settings.
    static let polish = Self("polish", initial: .init(.g, modifiers: [.control, .option]))
    /// Open the quick window (FR-10, Flow B). Default ⌃⌥⇧G.
    static let quickPolish = Self("quickPolish", initial: .init(.g, modifiers: [.control, .option, .shift]))
}
