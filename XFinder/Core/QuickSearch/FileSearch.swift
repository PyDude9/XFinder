import Foundation
import AppKit

/// Tìm file qua Spotlight (mdfind)
/// `Sendable`: không có trạng thái dùng chung.
final class FileSearch: Sendable {
    static let shared = FileSearch()

    private init() {}

    func search(query: String) -> [QuickSearchResult] {
        guard !query.isEmpty, query.count >= 2 else { return [] }

        // mdfind KHÔNG có option -limit (đã đo: "Unknown option -limit", tiến
        // trình fail → luôn trả rỗng — đây là bug Tìm nhanh không ra file).
        // Giới hạn số lượng bằng prefix() bên dưới.
        let homeDir = NSHomeDirectory()
        let escaped = query.replacingOccurrences(of: "'", with: "\\'")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", homeDir,
            "kMDItemFSName == '*\(escaped)*'c"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let paths = output
                .split(separator: "\n")
                .map { String($0) }
                .filter { !$0.isEmpty }

            return paths.prefix(8).map { path in
                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: path)

                return QuickSearchResult(
                    type: .file,
                    title: name,
                    subtitle: path,
                    icon: icon,
                    action: {
                        NSWorkspace.shared.open(url)
                    }
                )
            }
        } catch {
            return []
        }
    }
}
