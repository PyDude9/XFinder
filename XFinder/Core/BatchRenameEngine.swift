import Foundation

/// Pure rename-planning logic, shared by the Batch Rename page. Given files +
/// options it returns (current, proposed) pairs; the view executes via
/// FileManager and logs to ActionHistoryStore.
enum BatchRenameEngine {

    enum Mode: String, CaseIterable, Identifiable {
        case prefix, suffix, replace, sequence, lowercase, uppercase
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .prefix: return L10n.t("Thêm tiền tố")
            case .suffix: return L10n.t("Thêm hậu tố")
            case .replace: return L10n.t("Thay thế chữ")
            case .sequence: return L10n.t("Đánh số thứ tự")
            case .lowercase: return L10n.t("Chữ thường")
            case .uppercase: return L10n.t("Chữ HOA")
            }
        }
    }

    struct Options {
        var mode: Mode = .prefix
        var affix: String = ""        // prefix / suffix text
        var find: String = ""         // replace: tìm
        var replaceWith: String = ""  // replace: thay bằng
        var sequenceStart: Int = 1
        var sequenceDigits: Int = 2   // zero-padding width
        var sequenceSeparator: String = "_"
        var keepExtension: Bool = true
    }

    struct Plan: Equatable, Identifiable {
        var source: URL
        var proposed: URL
        var collides: Bool            // proposed already exists
        var id: String { source.path }
    }

    static func plan(files: [URL], options: Options) -> [Plan] {
        var seen = Set<String>()
        var counter = options.sequenceStart
        return files.map { url in
            let ext = url.pathExtension
            var stem = url.deletingPathExtension().lastPathComponent
            switch options.mode {
            case .prefix:
                stem = options.affix + stem
            case .suffix:
                stem = stem + options.affix
            case .replace:
                if !options.find.isEmpty {
                    stem = stem.replacingOccurrences(of: options.find, with: options.replaceWith)
                }
            case .sequence:
                let num = String(format: "%0\(max(1, options.sequenceDigits))d", counter)
                stem = stem + options.sequenceSeparator + num
                counter += 1
            case .lowercase:
                stem = stem.lowercased()
            case .uppercase:
                stem = stem.uppercased()
            }
            let newName = (options.keepExtension && !ext.isEmpty) ? "\(stem).\(ext)" : stem
            let proposed = url.deletingLastPathComponent().appendingPathComponent(newName)
            // Blocked = an invalid name (XF-T37 L1), a target that exists on disk and is NOT this same item (the default
            // volume ignores case, so "report.txt" → "REPORT.txt" finds itself — measured 2026-11-08; that is a legal
            // case-only rename, not a collision), or a name already claimed by an earlier row (same case-folded key).
            let key = url.deletingLastPathComponent().path + "/" + RenameRules.nameKey(newName)
            let invalid = RenameRules.problem(for: newName) != nil
            let takenOnDisk = FileManager.default.fileExists(atPath: proposed.path)
                && !RenameRules.isSameName(newName, url.lastPathComponent)
            let collides = invalid || takenOnDisk || seen.contains(key)
            seen.insert(key)
            return Plan(source: url, proposed: proposed, collides: collides)
        }
    }

    /// Executes a collision-free subset; returns (moved, failed) pairs for logging.
    static func execute(_ plans: [Plan]) -> (moved: [(old: URL, new: URL)], failed: Int) {
        var moved: [(old: URL, new: URL)] = []
        var failed = 0
        let fm = FileManager.default
        for p in plans where !p.collides && p.source != p.proposed {
            do {
                try fm.moveItem(at: p.source, to: p.proposed)
                moved.append((p.source, p.proposed))
            } catch { failed += 1 }
        }
        return (moved, failed)
    }
}
