import AppKit
import Observation

/// XF-T30 W3 — Finder's tag names, colours and order (follows Finder within about a second, no timer).
/// W3 builder (AppKit).
///
/// Measured (2026-10-25, this machine): `~/Library/SyncedPreferences/com.apple.finder.plist` does not exist (no
/// `FinderTagDict` key found anywhere, including `strings` on the Finder binary itself — contract's own "probe where
/// macOS keeps them first" instruction, followed here rather than assumed) — the live, present mechanism is
/// `defaults read com.apple.finder FavoriteTagNames`, an ordered array of seven names with index 0 reserved ("no
/// name" placeholder) and indices 1–7 the built-in colours in Finder's own fixed order (Red, Orange, Yellow, Green,
/// Blue, Purple, Gray) — confirmed by reading this machine's own `~/Library/Preferences/com.apple.finder.plist`.
/// Renaming a tag in Finder only ever changes the STRING at a colour's fixed index; the colour-to-index mapping
/// itself is not stored anywhere and is therefore hard-coded here, matching Finder's own fixed order. A future
/// macOS that writes `SyncedPreferences` again is covered too (tried first, since the contract names it as the
/// primary source) — this file tries both without assuming either is present.
enum TagColorOrder {
    /// `FavoriteTagNames` index → colour, Finder's own fixed order (index 0 is the "no colour" placeholder).
    static let byIndex: [TagColor] = [.none, .red, .orange, .yellow, .green, .blue, .purple, .gray]
}

@MainActor @Observable
final class TagLibrary {
    static let shared = TagLibrary()

    private(set) var tags: [FinderTag] = []

    private var legacySource: DispatchSourceFileSystemObject?
    private var syncedSource: DispatchSourceFileSystemObject?
    private var refCount = 0

    /// Plain `String` constants computed once at process start — `nonisolated(unsafe)` is safe here (never mutated
    /// after initialization) and lets the `nonisolated static` disk-reading functions below reference them without
    /// a main-actor hop, same as any other immutable global constant would need in Swift 6 strict concurrency.
    private nonisolated(unsafe) static let legacyPath = NSHomeDirectory() + "/Library/Preferences/com.apple.finder.plist"
    private nonisolated(unsafe) static let syncedPath = NSHomeDirectory() + "/Library/SyncedPreferences/com.apple.finder.plist"

    private init() {}

    func start() {
        refCount += 1
        guard refCount == 1 else { return }
        reload()
        watch(path: Self.syncedPath, keyPath: \.syncedSource)
        watch(path: Self.legacyPath, keyPath: \.legacySource)
    }

    func stop() {
        refCount = max(0, refCount - 1)
        guard refCount == 0 else { return }
        syncedSource?.cancel()
        syncedSource = nil
        legacySource?.cancel()
        legacySource = nil
    }

    private func reload() {
        Task.detached(priority: .utility) {
            let tags = Self.loadTags()
            await MainActor.run { self.tags = tags }
        }
    }

    /// `~/Library/SyncedPreferences/com.apple.finder.plist`'s `FinderTagDict` first (contract's named primary
    /// source — an array of `{name, color}` the same shape a resynced iCloud-tags machine would carry); falls back
    /// to the legacy `com.apple.finder` defaults domain's `FavoriteTagNames` (measured present on this machine);
    /// falls back again to the 7 default colour tags when neither parses.
    private nonisolated static func loadTags() -> [FinderTag] {
        if let synced = loadFromSyncedPreferences() { return synced }
        if let legacy = loadFromLegacyDefaults() { return legacy }
        return TagColorOrder.byIndex.dropFirst().map { FinderTag(name: L10n.t($0.titleKey), color: $0) }
    }

    private nonisolated static func loadFromSyncedPreferences() -> [FinderTag]? {
        guard let data = FileManager.default.contents(atPath: syncedPath) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        guard let dict = plist["FinderTagDict"] as? [[String: Any]], !dict.isEmpty else { return nil }
        var tags: [FinderTag] = []
        for entry in dict {
            guard let name = entry["name"] as? String ?? entry["n"] as? String else { continue }
            let colorRaw = (entry["color"] as? Int) ?? (entry["l"] as? Int) ?? 0
            let color = TagColor(rawValue: colorRaw) ?? .none
            tags.append(FinderTag(name: name, color: color))
        }
        return tags.isEmpty ? nil : tags
    }

    private nonisolated static func loadFromLegacyDefaults() -> [FinderTag]? {
        guard let names = UserDefaults(suiteName: "com.apple.finder")?.array(forKey: "FavoriteTagNames") as? [String],
              names.count > 1
        else { return nil }
        var tags: [FinderTag] = []
        for (index, name) in names.enumerated() where index > 0 && index < TagColorOrder.byIndex.count {
            let color = TagColorOrder.byIndex[index]
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = trimmed.isEmpty ? L10n.t(color.titleKey) : trimmed
            tags.append(FinderTag(name: displayName, color: color))
        }
        return tags.isEmpty ? nil : tags
    }

    // MARK: - Watching

    /// A plist save is usually an atomic replace (write a temp file, then rename over the original) — the original
    /// file descriptor's `.delete`/`.rename` event does not mean "gone forever" the way `DirectoryWatcher.onGone`
    /// treats a directory vanishing; it means "re-open and keep watching the new inode", else the very first Finder
    /// tag edit after launch would silently stop syncing (an edit started the watch, so no edit, no new fd).
    private func watch(path: String, keyPath: ReferenceWritableKeyPath<TagLibrary, DispatchSourceFileSystemObject?>) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let mask: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .extend, .attrib]
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.reload()
            if flags.contains(.delete) || flags.contains(.rename) {
                // Re-arm on the replaced file after Finder's atomic save — ~1 s later is still "within about a
                // second" of the edit (contract XF-T30-w3 §2).
                self[keyPath: keyPath]?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.watch(path: path, keyPath: keyPath)
                }
            }
        }
        source.setCancelHandler { [fd = descriptor] in close(fd) }
        self[keyPath: keyPath] = source
        source.resume()
    }
}
