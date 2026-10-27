import Foundation
import Darwin

/// XF-T30 W3 — listing a virtual location (Recents: files used in the last 30 days in the home folder; a tag: items
/// carrying it) through Spotlight with an early stop (`NulRecords`), as `DirectoryEntry` values. W3 builder (model).
///
/// Every `mdfind` call and every `lstat` happens off the main thread — `startLoad(of:)` in `BrowserWindowModel.swift`
/// runs inside a `PaneState`-isolated (`@MainActor`) `Task`, not a detached one, so `list` must hop to a background
/// queue itself (same pattern `DirectoryReader.list(_:timeout:)` already uses) rather than assume its caller already did.
enum VirtualLocations {
    /// Recents and a single tag are both capped here (contract §1: "Recents: ... ≤ 500"). The contract does not cap a
    /// tag listing explicitly; the same ceiling is reused as a defensive bound (`NulRecords` needs one to stop early).
    private static let limit = 500

    static func list(_ location: VirtualLocation) async -> Result<[DirectoryEntry], DirectoryReadError> {
        switch location {
        case .learn:
            return .success([])
        case .recents:
            let home = FileManager.default.homeDirectoryForCurrentUser
            let query = "kMDItemLastUsedDate >= $time.today(-30)"
            return await runQuery(query, scopes: [home])
        case .tag(let name):
            let query = "kMDItemUserTags == \"\(escapeForMDQuery(name))\""
            return await runQuery(query, scopes: [])
        case .allTags:
            // Every Finder tag as a folder-like entry whose path is that tag's virtual location (review 2026-10-25:
            // this returned an empty listing). TagLibrary is main-actor state; read it there, build entries here.
            let tags: [FinderTag] = await MainActor.run { TagLibrary.shared.tags }
            let now: Date = Date()
            let entries: [DirectoryEntry] = tags.map { tag in
                DirectoryEntry(name: tag.name, path: VirtualLocation.tag(tag.name).path, kind: .directory, isPackage: false,
                               isHidden: false, size: -1, modified: now, created: now, volumeID: 0)
            }
            return .success(entries)
        }
    }

    /// Runs `mdfind -0 [-onlyin scope]... query`, reading output through `NulRecords` so the child is stopped as soon
    /// as `limit` hits are in (same mechanism `FileSearchEngine` uses for a live search; duplicated here rather than
    /// shared since that type lives in a file this builder does not own and returns its own result type).
    private static func runQuery(_ query: String, scopes: [URL]) async -> Result<[DirectoryEntry], DirectoryReadError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<[DirectoryEntry], DirectoryReadError>, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let entries = runMdfindAndStat(query: query, scopes: scopes, limit: limit)
                continuation.resume(returning: .success(entries))
            }
        }
    }

    /// Blocking: must only run off the main thread (see `runQuery`).
    private static func runMdfindAndStat(query: String, scopes: [URL], limit: Int) -> [DirectoryEntry] {
        var args = ["-0"]
        for scope in scopes { args += ["-onlyin", scope.path] }
        args.append(query)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        var records = NulRecords(limit: limit)
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = autoreleasepool { reader.availableData }
            if chunk.isEmpty { break }
            records.append(chunk)
            if records.truncated { break }
        }
        // Early stop (CLAUDE.md 2026-10-23 lesson): once `limit` hits are in, kill the child instead of reading the
        // rest of a possibly-huge stream — `records.truncated` alone would leave an orphaned `mdfind` still running.
        if process.isRunning { process.terminate() }
        try? reader.close()
        process.waitUntilExit()
        records.finish()

        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(records.records.count)
        for path in records.records {
            if let entry = entry(forPath: path) { entries.append(entry) }
        }
        return entries
    }

    /// `lstat`-based entry builder — a virtual listing's hits can be anywhere on disk, not one folder's contents, so
    /// `DirectoryReader.list` (one `getattrlistbulk` call on a single directory) does not apply.
    private static func entry(forPath path: String) -> DirectoryEntry? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let name = (path as NSString).lastPathComponent
        let kind: DirectoryEntry.Kind
        switch st.st_mode & S_IFMT {
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        case S_IFREG: kind = .file
        default: kind = .other
        }
        let isPackage = kind == .directory && packageExtensions.contains((name as NSString).pathExtension.lowercased())
        let isHidden = (st.st_flags & UInt32(UF_HIDDEN)) != 0 || name.hasPrefix(".")
        let size = kind == .directory ? Int64(-1) : Int64(st.st_size)
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        let created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec) + TimeInterval(st.st_birthtimespec.tv_nsec) / 1e9)
        return DirectoryEntry(
            name: name, path: path, kind: kind, isPackage: isPackage, isHidden: isHidden,
            size: size, modified: modified, created: created, volumeID: Int32(st.st_dev)
        )
    }

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "pages", "numbers", "key", "rtfd", "photoslibrary", "xcodeproj", "playground",
    ]

    /// mdfind query-string escaping for a value interpolated inside double quotes (backslash and quote only).
    private static func escapeForMDQuery(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            if c == "\\" || c == "\"" { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
