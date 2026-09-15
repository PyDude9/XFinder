import Foundation
import AppKit

// MARK: - Command Result Types

/// Base protocol cho mọi kết quả trong command palette
protocol CommandResult: Identifiable {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var icon: NSImage? { get }
    var resultType: CommandResultType { get }
    func execute()
}

enum CommandResultType: String {
    case app
    case file
    case calculation
    case quicklink
    case raycastExtension
}

// MARK: - App Result

struct AppResult: CommandResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let resultType: CommandResultType = .app
    let app: NSRunningApplication?
    let bundlePath: String

    func execute() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundlePath),
                                          configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - File Result

struct FileResult: CommandResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let resultType: CommandResultType = .file
    let url: URL

    func execute() {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Calculator Result

struct CalculatorResult: CommandResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let resultType: CommandResultType = .calculation
    let expression: String
    let result: String

    func execute() {
        // Copy result to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
    }
}

// MARK: - Quicklink Result

struct QuicklinkResult: CommandResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let resultType: CommandResultType = .quicklink
    let url: URL

    func execute() {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Raycast Extension Result

struct RaycastExtensionResult: CommandResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let resultType: CommandResultType = .raycastExtension
    let action: () -> Void

    func execute() {
        action()
    }
}
