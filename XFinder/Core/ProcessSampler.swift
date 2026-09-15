import Foundation
import AppKit

/// Top CPU-consuming processes, sampled with `/usr/bin/top`.
///
/// Why `top` and not `ps`: `ps`'s `%CPU` is an **average over the process's
/// whole lifetime**, so a process that burned CPU an hour ago still reports a
/// high number while idle now. `top -l 2` prints two samples and the second is
/// a true delta over the interval — the same distinction CLAUDE.md records for
/// measuring XFinder's own idle CPU. Showing a lifetime average under the
/// heading "đang dùng nhiều CPU" would be misleading, so the slower call is the
/// honest one.
///
/// Both binaries are public and need no entitlement.
struct ProcessSampler {

    struct Row: Identifiable, Equatable {
        let id: Int32          // pid
        let name: String
        let cpuPercent: Double
        /// Set when the pid belongs to a real app, so the UI can show its icon.
        let bundleURL: URL?

        static func == (a: Row, b: Row) -> Bool {
            a.id == b.id && a.cpuPercent == b.cpuPercent && a.name == b.name
        }
    }

    /// One sample. Takes ~2 s (top's own interval), so callers should run it on
    /// a cadence, not per frame.
    static func topCPU(limit: Int = 10) async -> [Row] {
        let raw = await Task.detached(priority: .background) {
            runTop(limit: limit)
        }.value
        // Resolving the app name/icon touches NSRunningApplication, which is
        // main-actor work — do it here rather than inside the detached task.
        return await MainActor.run {
            raw.map { entry in
                let app = NSRunningApplication(processIdentifier: entry.pid)
                return Row(id: entry.pid,
                           name: app?.localizedName ?? entry.name,
                           cpuPercent: entry.cpu,
                           bundleURL: app?.bundleURL)
            }
        }
    }

    private struct RawEntry {
        let pid: Int32
        let name: String
        let cpu: Double
    }

    private nonisolated static func runTop(limit: Int) -> [RawEntry] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -l 2 : two samples; only the second carries real interval deltas.
        // -o cpu, -n : let top do the sorting and truncation for us.
        proc.arguments = ["-l", "2", "-n", "\(max(limit, 1))",
                          "-o", "cpu", "-stats", "pid,cpu,command"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }

        // Read BEFORE waiting: top's output can exceed the pipe buffer, and a
        // full pipe would block the child forever while we wait on it.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""

        // Keep only the LAST block of rows. The first sample is top's own
        // lifetime-average pass; the second is the delta we want.
        var blocks: [[RawEntry]] = []
        var current: [RawEntry] = []
        var inRows = false

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("PID") {
                if !current.isEmpty { blocks.append(current); current = [] }
                inRows = true
                continue
            }
            guard inRows else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cols = trimmed.split(separator: " ", maxSplits: 2,
                                     omittingEmptySubsequences: true)
            guard cols.count >= 3,
                  let pid = Int32(cols[0]),
                  let cpu = Double(cols[1]) else { continue }
            let name = cols[2].trimmingCharacters(in: .whitespaces)
            current.append(RawEntry(pid: pid, name: name, cpu: cpu))
        }
        if !current.isEmpty { blocks.append(current) }

        guard let rows = blocks.last else { return [] }
        return Array(rows
            .filter { $0.cpu > 0 }
            .sorted { $0.cpu > $1.cpu }
            .prefix(limit))
    }
}
