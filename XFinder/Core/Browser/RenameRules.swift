import Foundation

/// XF-T37 L1 — the one name rule every rename path in the file browser uses (inline rename, Get Info, New Folder,
/// batch rename, and the old Batch Rename page): what a typed name may not be, when two names are "the same" on disk,
/// and which harmless changes deserve a note. Pure; returns L10n keys (the view calls `L10n.t`).
///
/// Measured on this Mac's APFS (2026-11-08, probe with a positive control):
/// - The length limit is **255 UTF-16 code units of the canonically decomposed (NFD) name** — "a×253+ả" (256 UTF-8
///   bytes) is created, "a×254+ả" (255 characters, 256 NFD units) fails with `ENAMETOOLONG`; "ệ×85" (255 NFD units)
///   is created, "ệ×86" fails. Neither "255 bytes" nor "255 characters" is the rule.
/// - The default volume ignores case and Unicode form: `fileExists("REPORT.txt")` is true when only "report.txt"
///   exists. A rename that only changes case is still legal (`renamex_np(RENAME_EXCL)`, `rename(2)` and `moveItem` all
///   succeed), so "the target exists" must not be read as "another item has this name" when the target IS the item.
enum RenameRules {
    static let maxNameUnits: Int = 255
    /// Prefix of the app's own temporary names (two-phase batch rename). A user may not type it, so a leftover from a
    /// crashed run can always be recognized as the app's.
    static let reservedPrefix: String = ".xfinder-"

    enum Problem: String, CaseIterable, Equatable, Sendable {
        case empty, separator, reserved, control, tooLong

        var key: String {
            switch self {
            case .empty: return "Tên không được để trống."
            case .separator: return "Tên không được chứa dấu hai chấm hoặc dấu gạch chéo."
            case .reserved: return "Tên này được dành riêng."
            case .control: return "Tên không được chứa ký tự điều khiển."
            case .tooLong: return "Tên quá dài: tối đa 255 ký tự, mỗi dấu (sắc, huyền, mũ…) tính thêm một."
            }
        }
    }

    enum Note: Equatable, Sendable {
        case caseOnly
        case hidden
        case extensionChanged(from: String, to: String)
        case extensionRemoved(String)
        case extensionAdded(String)

        /// The L10n key of the note's label; the extension(s) themselves are shown after it, untranslated.
        var key: String {
            switch self {
            case .caseOnly: return "Chỉ đổi chữ hoa/thường."
            case .hidden: return "Tên bắt đầu bằng dấu chấm sẽ bị ẩn."
            case .extensionChanged: return "Đổi đuôi:"
            case .extensionRemoved: return "Bỏ đuôi:"
            case .extensionAdded: return "Thêm đuôi:"
            }
        }

        /// ".pdf → .txt" etc., or "" for the notes that carry no extension.
        var detail: String {
            switch self {
            case .caseOnly, .hidden: return ""
            case .extensionChanged(let from, let to): return ".\(from) → .\(to)"
            case .extensionRemoved(let ext): return ".\(ext)"
            case .extensionAdded(let ext): return ".\(ext)"
            }
        }
    }

    /// Why `name` cannot be given to an item, or nil. Leading/trailing whitespace only matters for emptiness — a name
    /// of spaces is empty, but "File " stays as typed (Finder's own default custom format ends with a space).
    static func problem(for name: String) -> Problem? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if name.contains("/") || name.contains(":") { return .separator }
        if name == "." || name == ".." || name.hasPrefix(reservedPrefix) { return .reserved }
        if name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return .control }
        if name.decomposedStringWithCanonicalMapping.utf16.count > maxNameUnits { return .tooLong }
        return nil
    }

    /// The comparison key of a name on a case- and normalization-insensitive volume: NFD, then case folded.
    static func nameKey(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Two names the default volume treats as one item ("report.txt" / "Report.txt", NFC / NFD spellings).
    static func isSameName(_ a: String, _ b: String) -> Bool {
        nameKey(a) == nameKey(b)
    }

    /// "a.tar.gz" → ("a.tar", "gz"); ".zshrc" → (".zshrc", ""); "Report." → ("Report.", ""); a folder has no extension.
    static func splitExtension(_ name: String, isFolder: Bool) -> (stem: String, ext: String) {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty else { return (name, "") }
        return (String(name[name.startIndex..<dot]), ext)
    }

    /// Notes for a rename that is allowed but worth a second look. Empty for an unchanged name.
    static func notes(old: String, new: String, isFolder: Bool) -> [Note] {
        guard old != new else { return [] }
        var notes: [Note] = []
        if isSameName(old, new) { notes.append(.caseOnly) }
        if new.hasPrefix("."), !old.hasPrefix(".") { notes.append(.hidden) }
        guard !isFolder else { return notes }
        let oldExt = splitExtension(old, isFolder: false).ext
        let newExt = splitExtension(new, isFolder: false).ext
        if oldExt.isEmpty, !newExt.isEmpty {
            notes.append(.extensionAdded(newExt))
        } else if !oldExt.isEmpty, newExt.isEmpty {
            notes.append(.extensionRemoved(oldExt))
        } else if !oldExt.isEmpty, !isSameName(oldExt, newExt) {
            notes.append(.extensionChanged(from: oldExt, to: newExt))
        }
        return notes
    }
}
