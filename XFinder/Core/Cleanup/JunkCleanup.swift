import Foundation
import Darwin

/// F1 — "I am about to zip / send / copy this folder to a USB stick or a Windows machine: clear out the system junk
/// inside it, show me first, and only move things to the Trash."
///
/// Only KNOWN metadata is ever selected — never "temporary files" in general. The list was taken from what the
/// reference app (MFinder) itself promises (its own string: "only matches known Finder, AppleDouble, archive, and
/// Windows metadata. Generic temporary files are never selected. Finder may recreate .DS_Store later.") and checked
/// against real bytes:
/// * an AppleDouble file made by `ditto --sequesterRsrc` + `unzip` starts `00 05 16 07 00 02 00 00 "Mac OS X"`
///   (measured 2026-10-13). A file merely NAMED `._x` on APFS can be someone's data, so `._*` counts only with that
///   magic;
/// * `__MACOSX` counts only when everything inside it is AppleDouble metadata (that is what zip tools put there).
///
/// Never touched: volume-level system folders (`.Spotlight-V100`, `.fseventsd`, `.Trashes`…), anything behind a
/// symlink, the inside of packages (`.app`, `.photoslibrary`), and iCloud items that are not downloaded.
enum JunkCleanup {

    enum Kind: String, CaseIterable, Equatable {
        case dsStore, appleDouble, macosxFolder, windowsThumbs, desktopIni

        /// Store keys (the page wraps them in `L10n.t`; `JunkCleanupTests` resolves each one).
        var titleKey: String {
            switch self {
            case .dsStore: return "Thiết lập hiển thị của Finder (.DS_Store)"
            case .appleDouble: return "Siêu dữ liệu AppleDouble (._tên)"
            case .macosxFolder: return "Thư mục __MACOSX trong file nén"
            case .windowsThumbs: return "Ảnh thu nhỏ của Windows (Thumbs.db)"
            case .desktopIni: return "Thiết lập thư mục của Windows (desktop.ini)"
            }
        }

        var explanationKey: String {
            switch self {
            case .dsStore: return "Finder ghi vị trí biểu tượng và kiểu xem. Vô hại khi xoá; Finder có thể tạo lại khi bạn mở thư mục."
            case .appleDouble: return "Nhãn, xattr của macOS khi chép sang ổ không phải APFS (USB, ổ mạng). Chỉ chọn file có đầu AppleDouble thật."
            case .macosxFolder: return "Do công cụ nén để lại khi giải nén trên máy khác. Chỉ chọn khi bên trong toàn là siêu dữ liệu."
            case .windowsThumbs: return "Windows tự tạo để hiện ảnh thu nhỏ. Windows tạo lại khi cần."
            case .desktopIni: return "Windows ghi biểu tượng và tên hiển thị của thư mục. Chỉ có tác dụng trên Windows."
            }
        }
    }

    struct Item: Equatable {
        let url: URL
        let kind: Kind
        let bytes: Int64
    }

    struct Report: Equatable {
        var items: [Item] = []
        var scannedEntries = 0
        var skippedPackages = 0
        var skippedCloud = 0
        /// The walk stopped at `maxEntries` — the page says the list is partial.
        var truncated = false
        var cancelled = false
    }

    static let appleDoubleMagic: [UInt8] = [0x00, 0x05, 0x16, 0x07]
    static let maxEntries = 200_000

    /// Folders the system owns on a mounted volume. Never descended into, never listed.
    static let systemFolders: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems", ".DocumentRevisions-V100",
        ".PKInstallSandboxManager", ".PKInstallSandboxManager-SystemSoftware", ".MobileBackups", ".vol",
    ]

    // MARK: Classification

    /// Name-only verdict. `.appleDouble` from here is a CANDIDATE — `isAppleDouble(header:)` decides.
    static func candidate(name: String, isDirectory: Bool) -> Kind? {
        if isDirectory { return name == "__MACOSX" ? .macosxFolder : nil }
        switch name.lowercased() {
        case ".ds_store": return .dsStore
        case "thumbs.db", "ehthumbs.db": return .windowsThumbs
        case "desktop.ini": return .desktopIni
        default: break
        }
        return name.hasPrefix("._") && name.count > 2 ? .appleDouble : nil
    }

    static func isAppleDouble(header: Data) -> Bool {
        header.count >= 4 && Array(header.prefix(4)) == appleDoubleMagic
    }

    static func readHeader(_ url: URL) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return try? h.read(upToCount: 8)
    }

    // MARK: Scanning

    /// Walks `root` physically: never follows a link, never crosses into another volume, never enters a package.
    /// The caller runs it off the main thread.
    ///
    /// `fts`, not `FileManager`: measured on macOS 27, EVERY FileManager listing API — `contentsOfDirectory(atPath:)`,
    /// `contentsOfDirectory(at:)`, `enumerator(at:)`, `enumerator(atPath:)` — hides REGULAR FILES whose name starts with
    /// "._" (with or without the AppleDouble header, even empty ones), while `readdir` lists them. Links and folders
    /// named "._…" are still listed. AppleDouble files are regular files, so a FileManager scan can never find them.
    /// (`stat`, `fileExists` and `trashItem` do work on them — only listing hides them.)
    static func scan(_ root: URL, limit: Int = maxEntries, isCancelled: () -> Bool = { false }) -> Report {
        var report = Report()
        let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else { return report }
        let walked = walk(root, limit: limit, isCancelled: isCancelled) { url, isDir, size in
            let name = url.lastPathComponent
            if isDir, systemFolders.contains(name) { return .skip }
            if isDir, name.contains("."), (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
                report.skippedPackages += 1
                return .skip
            }
            guard let kind = candidate(name: name, isDirectory: isDir) else { return .descend }
            if isNotDownloaded(url) { report.skippedCloud += 1; return .skip }
            switch kind {
            case .macosxFolder:
                if let bytes = macosxFolderBytes(url) { report.items.append(Item(url: url, kind: kind, bytes: bytes)) }
                return .skip
            case .appleDouble:
                if readHeader(url).map(isAppleDouble) ?? false { report.items.append(Item(url: url, kind: kind, bytes: size)) }
            default:
                report.items.append(Item(url: url, kind: kind, bytes: size))
            }
            return .descend
        }
        report.scannedEntries = walked.entries
        report.truncated = walked.truncated
        report.cancelled = walked.cancelled
        return report
    }

    /// An iCloud item whose bytes are not on this Mac: reading its header would download it, and it is not junk here.
    static func isNotDownloaded(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              v.isUbiquitousItem == true, let s = v.ubiquitousItemDownloadingStatus else { return false }
        return s != .current
    }

    /// The folder's size when EVERY file inside is AppleDouble metadata or `.DS_Store`; nil otherwise (a `__MACOSX`
    /// holding anything else is not what zip tools make, so it is not called junk).
    static func macosxFolderBytes(_ folder: URL) -> Int64? {
        var total: Int64 = 0
        var clean = true
        let walked = walk(folder, limit: 50_000, isCancelled: { false }, onOther: { clean = false }) { url, isDir, size in
            guard clean else { return .skip }
            if isDir { return .descend }
            let name = url.lastPathComponent
            if name == ".DS_Store" || (name.hasPrefix("._") && (readHeader(url).map(isAppleDouble) ?? false)) {
                total += size
            } else {
                clean = false
            }
            return .descend
        }
        return clean && !walked.truncated ? total : nil
    }

    enum Visit { case descend, skip }

    /// `fts` with `FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`. The root itself is not visited. Links, unreadable folders
    /// and stat errors are never handed to `body`; `onOther` hears about them (a `__MACOSX` holding a link is not junk).
    private static func walk(_ root: URL, limit: Int, isCancelled: () -> Bool, onOther: () -> Void = {},
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
            guard info == FTS_D || info == FTS_F, let cpath = ent.pointee.fts_path else { onOther(); continue }
            let isDir = info == FTS_D
            let size = isDir ? 0 : Int64(ent.pointee.fts_statp?.pointee.st_size ?? 0)
            let url = URL(fileURLWithPath: String(cString: cpath), isDirectory: isDir)
            if body(url, isDir, size) == .skip, isDir { fts_set(fts, ent, FTS_SKIP) }
        }
        return (entries, false, false)
    }

    // MARK: Moving to the Trash

    struct TrashOutcome: Equatable {
        var trashed: [URL] = []
        /// Items that changed since the scan (gone, now a link, no longer junk) — skipped, not an error.
        var changed = 0
        var failed: [String] = []
    }

    /// Re-checks every item right before moving it (the folder may have changed since the preview), then moves it
    /// with `trash` — `FileManager.trashItem` in the app, an injected mover in tests. Nothing is ever deleted.
    static func moveToTrash(_ items: [Item], trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> TrashOutcome {
        var out = TrashOutcome()
        for item in items {
            guard stillJunk(item) else { out.changed += 1; continue }
            do {
                try trash(item.url)
                out.trashed.append(item.url)
            } catch {
                out.failed.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return out
    }

    static func stillJunk(_ item: Item) -> Bool {
        guard let v = try? item.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              v.isSymbolicLink != true else { return false }
        let isDir = v.isDirectory == true
        guard candidate(name: item.url.lastPathComponent, isDirectory: isDir) == item.kind else { return false }
        switch item.kind {
        case .appleDouble: return readHeader(item.url).map(isAppleDouble) ?? false
        case .macosxFolder: return macosxFolderBytes(item.url) != nil
        default: return true
        }
    }

    // MARK: Summaries for the page

    struct Group: Equatable {
        let kind: Kind
        let count: Int
        let bytes: Int64
    }

    /// One row per kind that was found, in `Kind.allCases` order.
    static func groups(_ items: [Item]) -> [Group] {
        Kind.allCases.compactMap { k in
            let mine = items.filter { $0.kind == k }
            return mine.isEmpty ? nil : Group(kind: k, count: mine.count, bytes: mine.reduce(0) { $0 + $1.bytes })
        }
    }

    /// Path shown under a group: relative to the scanned folder, so the row stays short.
    static func relativePath(_ url: URL, root: URL) -> String {
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        guard p.hasPrefix(r + "/") else { return p }
        return String(p.dropFirst(r.count + 1))
    }
}
