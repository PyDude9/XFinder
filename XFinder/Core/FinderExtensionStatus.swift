import Foundation

/// What macOS actually thinks of our Finder Sync extension.
///
/// This exists because the page used to hard-code "Chưa có" for the right-click
/// menu row. That was true when the appex never registered, and became a lie the
/// moment the registration bugs were fixed (deployment target, debug dylib,
/// dropped sandbox entitlement). A status row must read the system, not a fact
/// somebody typed — same rule as the metrics pages.
///
/// `pluginkit` is the only public way to ask. Measured values of its first
/// column on macOS 27:
///
/// | Mark | Meaning                                                        |
/// |------|----------------------------------------------------------------|
/// | `+`  | registered and enabled                                         |
/// | `-`  | registered and explicitly disabled by the user                  |
/// | `!`  | registered but never enabled (the default for a new extension)  |
/// | none | not registered at all — Finder will not offer the menu          |
enum FinderExtensionStatus: Equatable {
    case enabled
    case disabled
    case registeredNotEnabled
    case notRegistered
    /// The probe could not run at all; the UI must say "unknown", never guess.
    case unknown

    static let identifier = "com.xfinder.app.XFinderSync"

    /// Runs `pluginkit -m -i <id> -v`, which prints one line when the plug-in is
    /// known and nothing when it is not. Off the main thread and with a timeout,
    /// because a page open must never stall on a subprocess.
    static func probe() async -> FinderExtensionStatus {
        await Task.detached(priority: .userInitiated) {
            probeSync()
        }.value
    }

    /// Synchronous variant, so a test or a harness can call it directly.
    static func probeSync() -> FinderExtensionStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", identifier, "-v"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return .unknown
        }

        // Read BEFORE waiting: a full pipe buffer deadlocks the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return .unknown }
        // Match the identifier as a whole token so a longer identifier cannot
        // match by prefix and report the wrong extension's state.
        let line = text
            .split(separator: "\n")
            .first { $0.contains(identifier) }
        guard let line else { return .notRegistered }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") { return .enabled }
        if trimmed.hasPrefix("-") { return .disabled }
        if trimmed.hasPrefix("!") { return .registeredNotEnabled }
        return .unknown
    }
}
