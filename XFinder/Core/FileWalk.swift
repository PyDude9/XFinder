import Foundation
import Darwin

/// A physical directory walk that sees every entry — the one walker for code that must not miss files.
///
/// `fts`, not `FileManager`: measured on macOS 27, EVERY FileManager listing API — `contentsOfDirectory(atPath:)`,
/// `contentsOfDirectory(at:)`, `enumerator(at:)`, `enumerator(atPath:)` — hides REGULAR FILES whose name starts with
/// "._" (with or without an AppleDouble header, even empty ones), while `readdir` lists them. Links and folders named
/// "._…" are still listed; `stat`, `fileExists` and `trashItem` work on them. (F1, 2026-10-13.)
enum FileWalk {
    enum Visit { case descend, skip }

    /// `FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`: never follows a link, never crosses into another volume. The root itself
    /// is not visited. Links, unreadable folders and stat errors are never handed to `body`; `onOther` hears about them.
    /// `onLink`, when given, hears about symbolic links instead of `onOther` — for callers where a link that is
    /// deliberately not followed is not a gap in the result (Storage Analyzer). Without it links go to `onOther`.
    static func walk(_ root: URL, limit: Int, isCancelled: () -> Bool = { false }, onOther: () -> Void = {},
                     onLink: (() -> Void)? = nil,
                     _ body: (_ url: URL, _ isDirectory: Bool, _ size: Int64) -> Visit)
        -> (entries: Int, truncated: Bool, cancelled: Bool) {
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(root.path), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return (0, false, false) }
        defer { fts_close(fts) }
        var entries = 0
        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            if info == FTS_DP || ent.pointee.fts_level == 0 { continue }
            if isCancelled() { return (entries, false, true) }
            entries += 1
            if entries > limit { return (entries, true, false) }
            if info == FTS_SL || info == FTS_SLNONE, let onLink { onLink(); continue }
            guard info == FTS_D || info == FTS_F, let cpath = ent.pointee.fts_path else { onOther(); continue }
            let isDir = info == FTS_D
            let size = isDir ? 0 : Int64(ent.pointee.fts_statp?.pointee.st_size ?? 0)
            let url = URL(fileURLWithPath: String(cString: cpath), isDirectory: isDir)
            if body(url, isDir, size) == .skip, isDir { fts_set(fts, ent, FTS_SKIP) }
        }
        return (entries, false, false)
    }

    /// Total size of a file or a folder tree; nil when the root cannot be read at all (a protected container).
    static func totalSize(_ url: URL, limit: Int = 500_000) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        guard isDir.boolValue else {
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        }
        guard access(url.path, R_OK | X_OK) == 0 else { return nil }
        var total: Int64 = 0
        _ = walk(url, limit: limit) { _, _, size in total += size; return .descend }
        return total
    }
}
