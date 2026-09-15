import Foundation
import AppKit

/// Kết quả tìm kiếm trong Command Palette
struct CommandResult: Identifiable {
    let id = UUID()
    let type: ResultType
    let title: String
    let subtitle: String
    let icon: NSImage?
    let action: () -> Void

    enum ResultType {
        case app
        case file
        case calculator
        case quicklink
        case extension_
    }
}

/// Score cho fuzzy matching (càng nhỏ càng khớp)
struct SearchScore {
    let score: Int
    let result: CommandResult
}
