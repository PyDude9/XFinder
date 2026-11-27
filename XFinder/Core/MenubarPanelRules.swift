import Foundation

/// Pure rules for XFinder's Menu Bar Popover (`MenubarPanelView`) and shared
/// Unsleep presets / compact metric formatters used by Notch and Sidebar views.
enum MenubarPanelRules {
    static let panelWidth: Double = 300
    static let panelHeight: Double = 180

    struct UnsleepPreset: Equatable, Identifiable, Sendable {
        /// `0` means indefinite; positive values are minutes.
        let minutes: Int
        let labelKey: String
        var id: Int { minutes }
    }

    static let unsleepPresets: [UnsleepPreset] = [
        UnsleepPreset(minutes: 5, labelKey: "5 phút"),
        UnsleepPreset(minutes: 10, labelKey: "10 phút"),
        UnsleepPreset(minutes: 15, labelKey: "15 phút"),
        UnsleepPreset(minutes: 30, labelKey: "30 phút"),
        UnsleepPreset(minutes: 60, labelKey: "1 giờ"),
        UnsleepPreset(minutes: 120, labelKey: "2 giờ"),
        UnsleepPreset(minutes: 240, labelKey: "4 giờ"),
        UnsleepPreset(minutes: 480, labelKey: "8 giờ"),
        UnsleepPreset(minutes: 0, labelKey: "Vô hạn"),
    ]

    /// Format remaining seconds for the Unsleep countdown (`"1h 25m"`, `"14:05"`, or `nil` when <= 0).
    static func formatRemaining(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    static func parseCollapsedHeaders(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    static func encodeCollapsedHeaders(_ headers: Set<String>) -> String {
        headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted().joined(separator: "\n")
    }

    static func formatTemp(_ celsius: Double?) -> String? {
        celsius.map { String(format: "%.0f °C", $0) }
    }

    static func formatBatteryRemaining(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        }
        return "\(mins)m"
    }

    /// Format a network throughput rate that is already in KB/s (matching `NetworkDetailView.rateString`).
    static func formatRateKBs(_ kbs: Double) -> String {
        let clamped = max(0, kbs)
        if clamped >= 1024 {
            return String(format: "%.1f MB/s", clamped / 1024.0)
        }
        return String(format: "%.0f KB/s", clamped)
    }

    /// Zero-allocation compact byte formatting for live SwiftUI views (avoids per-tick `ByteCountFormatter` allocs).
    static func formatBytes(_ bytes: Int64) -> String {
        let safe = max(0, bytes)
        let b = Double(safe)
        if safe >= 1_000_000_000_000 { return String(format: "%.2f TB", b / 1e12) }
        if safe >= 1_000_000_000 { return String(format: "%.1f GB", b / 1e9) }
        if safe >= 1_000_000 { return String(format: "%.0f MB", b / 1e6) }
        if safe >= 1_000 { return String(format: "%.0f KB", b / 1e3) }
        return "\(safe) B"
    }
}
