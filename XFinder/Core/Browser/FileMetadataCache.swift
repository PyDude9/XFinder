import AppKit
import CoreServices
import Darwin
import Observation

/// XF-T30 W2 — Finder tags, Date Last Opened and the default application of files, read in the background in batches
/// and cached (LRU 20 000). `version` changes whenever a batch lands so views can refresh. W2 builder (reader).
///
/// Measured (this machine, `probe_metadata.swift` in this builder's scratch folder, positive control: a file tagged
/// via `URLResourceValues.tagNames` decodes back to the same two tags, an untagged sibling decodes to none):
/// `getxattr` + plist-decode ≈ 0.12 ms/call, `MDItemCreate` + `kMDItemLastUsedDate` ≈ 1.5 ms/call,
/// `NSWorkspace.urlForApplication(toOpen:)` ≈ 0.7 ms/call. The two Spotlight/LaunchServices calls are the expensive
/// ones (over a second for 1 000 files) — every read here runs off the main thread, queued and coalesced into
/// batches so a fast scroll through a huge folder does not fire one dispatch per row.
@MainActor @Observable
final class FileMetadataCache {
    static let shared = FileMetadataCache()

    private(set) var version = 0

    /// Per-path cached values. `nil` stored explicitly (vs. absent) marks "looked up, nothing there" so a
    /// path already known to have no tags/last-opened/app is never re-queued by `prefetch`.
    private var tagsByPath: [String: [FinderTag]] = [:]
    private var lastOpenedByPath: [String: Date?] = [:]
    private var appNameByPath: [String: String?] = [:]

    /// One LRU recency shared by all three maps — a path evicted here is dropped from whichever of the three
    /// maps actually holds it (most paths have all three read together via `prefetch`). Recency is a monotonic
    /// tick per path (`lastUsed`), not a reordered array: `touch` is called from `tags(for:)`/`lastOpened(for:)`/
    /// `appName(for:)` on every cache READ, which fires once per visible row on every SwiftUI re-render during a
    /// fast scroll — an array-splice-and-reindex `touch` (shift + renumber every later entry) turned a single
    /// scroll through a warm 20 000-entry cache into O(n) per row, O(n²) overall, blowing the W2 contract's
    /// "mở List ≤ 150 ms / 100 000 hàng" budget. A tick bump is O(1); eviction (`evictIfNeeded`) only scans once
    /// it is actually over `capacity` and removes enough of the stalest entries to clear a slack margin, so a
    /// full O(n) sort happens once per `evictBatch` insertions rather than once per insertion.
    private var lastUsed: [String: UInt64] = [:]
    private var tick: UInt64 = 0
    private let capacity = 20_000
    private let evictBatch = 2_000

    /// Paths already queued for a background read, so a pane that calls `prefetch` again while the first
    /// batch is still in flight (e.g. re-rendering during a fast scroll) does not queue the same path twice.
    private var pending: Set<String> = []

    /// Batched work lands through this queue; `UInt64` is a monotonic sequence so a stale read that
    /// finishes after `purge()` can tell it is stale and drop its own result instead of repopulating a
    /// cache that was just cleared.
    private let readQueue = DispatchQueue(label: "com.xfinder.browser.filemetadata", qos: .utility)
    private var epoch: UInt64 = 0

    private init() {}

    func tags(for path: String) -> [FinderTag]? {
        touch(path)
        return tagsByPath[path]
    }

    func lastOpened(for path: String) -> Date? {
        touch(path)
        return lastOpenedByPath[path].flatMap { $0 }
    }

    func appName(for path: String) -> String? {
        touch(path)
        return appNameByPath[path].flatMap { $0 }
    }

    /// Queues a background read for `paths` (only what is missing). `tags`/`lastOpened`/`appName` select which
    /// of the three facts the caller actually needs right now (a List-view column showing only Tags has no
    /// reason to pay for `MDItemCreate`); a later call asking for a fact already cached for a path is a no-op
    /// for that path even if it asks for a different combination of facts than the first call did, UNLESS that
    /// specific fact is still missing — e.g. a first prefetch(tags: true, lastOpened: false, appName: false)
    /// followed by prefetch(tags: false, lastOpened: true, appName: false) still queues the second read.
    func prefetch(_ paths: [String], tags: Bool, lastOpened: Bool, appName: Bool) {
        guard tags || lastOpened || appName else { return }
        var toQueue: [String] = []
        toQueue.reserveCapacity(paths.count)
        for path in paths {
            guard !pending.contains(path) else { continue }
            let needsTags = tags && tagsByPath[path] == nil
            let needsLastOpened = lastOpened && lastOpenedByPath[path] == nil
            let needsAppName = appName && appNameByPath[path] == nil
            guard needsTags || needsLastOpened || needsAppName else { continue }
            pending.insert(path)
            toQueue.append(path)
        }
        guard !toQueue.isEmpty else { return }

        let currentEpoch = epoch
        readQueue.async { [weak self] in
            // Off-main: the actual syscalls / Spotlight / LaunchServices lookups.
            var batch: [(path: String, tags: [FinderTag]?, lastOpened: Date??, appName: String??)] = []
            batch.reserveCapacity(toQueue.count)
            for path in toQueue {
                let readTags: [FinderTag]? = tags ? Self.readTags(path) : nil
                let readLastOpened: Date?? = lastOpened ? .some(Self.readLastOpened(path)) : nil
                let readAppName: String?? = appName ? .some(Self.readAppName(path)) : nil
                batch.append((path, readTags, readLastOpened, readAppName))
            }
            Task { @MainActor [weak self] in
                guard let self, self.epoch == currentEpoch else { return }
                self.apply(batch)
            }
        }
    }

    func purge() {
        epoch += 1
        tagsByPath.removeAll()
        lastOpenedByPath.removeAll()
        appNameByPath.removeAll()
        lastUsed.removeAll()
        tick = 0
        pending.removeAll()
        version += 1
    }

    // MARK: - Applying a finished batch (main actor)

    private func apply(_ batch: [(path: String, tags: [FinderTag]?, lastOpened: Date??, appName: String??)]) {
        guard !batch.isEmpty else { return }
        for item in batch {
            pending.remove(item.path)
            if let readTags = item.tags {
                tagsByPath[item.path] = readTags
            }
            if let readLastOpened = item.lastOpened {
                lastOpenedByPath[item.path] = readLastOpened
            }
            if let readAppName = item.appName {
                appNameByPath[item.path] = readAppName
            }
            touch(item.path)
        }
        evictIfNeeded()
        version += 1
    }

    // MARK: - LRU bookkeeping

    private func touch(_ path: String) {
        tick += 1
        lastUsed[path] = tick
    }

    /// Only runs once `lastUsed.count` has actually exceeded `capacity`, and then evicts `evictBatch` entries
    /// (the stalest first) in one sort — not one entry per call — so inserting past capacity one path at a
    /// time (the common case: a batch lands, `apply` touches each path, count creeps past 20 000) does not
    /// re-sort the whole cache on every single insertion.
    private func evictIfNeeded() {
        guard lastUsed.count > capacity else { return }
        let toEvict = lastUsed.count - capacity + evictBatch
        let stalest = lastUsed.sorted { $0.value < $1.value }.prefix(toEvict)
        for (path, _) in stalest {
            lastUsed.removeValue(forKey: path)
            tagsByPath.removeValue(forKey: path)
            lastOpenedByPath.removeValue(forKey: path)
            appNameByPath.removeValue(forKey: path)
        }
    }

    // MARK: - Off-main reads (nonisolated, no shared state — safe to call from `readQueue`)

    private static func readTags(_ path: String) -> [FinderTag] {
        let name = "com.apple.metadata:_kMDItemUserTags"
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let readBytes = data.withUnsafeMutableBytes { buffer -> Int in
            getxattr(path, name, buffer.baseAddress, size, 0, 0)
        }
        guard readBytes == size else { return [] }
        return FinderTags.decodeXattr(data)
    }

    private static func readLastOpened(_ path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        guard let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return value as? Date
    }

    /// The display name of the application that would open `path` by default — e.g. "TextEdit", not a
    /// bundle identifier or path. `nil` when no application claims the file's type.
    private static func readAppName(_ path: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: path)) else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }
}
