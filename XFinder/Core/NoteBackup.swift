import Foundation

/// XF-T24 (2026-10-18) — automatic dated backups of the notes, the mechanism Antinote uses (measured: dated copies of its
/// database, `cd-v1-notes_cdbackup_<date>.sqlite`, six on this Mac). Pure naming/retention rules here (symlinked into the test
/// package); `NoteStore` writes the files.
///
/// One backup per calendar day, written on the first save of that day — no timer. Each day leaves `notes-YYYY-MM-DD.json` (the
/// exact format "Nhập JSON" reads back) and `notes-YYYY-MM-DD.md` (readable by eye). The newest `keepDays` days are kept; older
/// ones go to the Trash, never `rm`.
enum NoteBackup {
    static let enabledKey = "notes.autoBackup"
    static let keepDays = 14
    static let prefix = "notes-"

    /// `notes-2026-10-18` for a date in the given time zone (the person's day, not UTC).
    static func stem(for date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%@%04d-%02d-%02d", prefix, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day a backup file belongs to, or nil for a file that is not one of ours.
    static func day(ofFile name: String) -> String? {
        guard name.hasPrefix(prefix), name.hasSuffix(".json") || name.hasSuffix(".md") else { return nil }
        let stem = (name as NSString).deletingPathExtension
        let day = String(stem.dropFirst(prefix.count))
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return day
    }

    /// Files to move to the Trash: every backup file whose day is not among the newest `keep` days. Unknown files are never
    /// touched (the folder may hold something the person put there).
    static func filesToPrune(_ names: [String], keep: Int = keepDays) -> [String] {
        let days = Set(names.compactMap(day(ofFile:))).sorted(by: >)
        let kept = Set(days.prefix(keep))
        return names.filter { n in day(ofFile: n).map { !kept.contains($0) } ?? false }.sorted()
    }
}
