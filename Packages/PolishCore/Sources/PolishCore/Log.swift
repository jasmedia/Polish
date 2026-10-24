import os

/// Shared loggers. Message text must always be logged with `privacy: .private`;
/// only timings, token counts and error codes may be public.
public enum Log {
    public static let subsystem = "com.jasmedia.polish"

    /// Rewrite pipeline: protect, chunk, generate, validate, restore.
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    /// Text bridge: Accessibility reads and writes, clipboard fallback.
    public static let bridge = Logger(subsystem: subsystem, category: "bridge")
    /// Menu bar, review panel, settings.
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
