import Foundation
import AppKit

/// Tìm file qua Spotlight (mdfind)
final class FileSearch {
    static let shared = FileSearch()

    private init() {}

    func search(query: String) -> [CommandResult] {
        guard !query.isEmpty, query.count >= 2 else { return [] }

        // mdfind với limit 10 kết quả, tìm trong home + /Applications
        let homeDir = NSHomeDirectory()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", homeDir,
            "-limit", "10",
            "kMDItemFSName == '*\(query)*'c"
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

                return CommandResult(
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
