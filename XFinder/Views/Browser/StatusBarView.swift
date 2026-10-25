import SwiftUI

/// XF-T30 W1 — the Status Bar (⌘/): "N mục, X còn trống" like Finder; with a selection "M trên N mục được chọn".
/// Trash without Full Disk Access shows "Cần quyền Full Disk Access" instead. Free space comes from
/// `FreeSpaceCache`, refreshed off the main thread (never `statfs` inside `body` — CLAUDE.md "no disk I/O on the
/// main thread").
struct StatusBarView: View {
    let pane: PaneState

    @State private var freeSpace: Int64?

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(statusText)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if let trailing = trailingText {
                Text(trailing)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, 4)
        .task(id: pane.path) {
            freeSpace = await FreeSpaceCache.shared.freeSpace(of: pane.path)
        }
    }

    private var statusText: String {
        let count = pane.entries.count
        let itemsLabel = "\(count)\(L10n.t(" mục"))"
        guard !pane.selection.isEmpty else { return itemsLabel }
        return "\(pane.selection.count)\(L10n.t(" trên "))\(count)\(L10n.t(" mục được chọn"))"
    }

    /// `nil` while the free-space read hasn't completed yet (new pane, new path) — the status bar then shows just
    /// the item count until the cache answers, rather than a flash of "Đang tính…" the contract never asked for.
    private var trailingText: String? {
        if TrashLocation.isTrash(pane.path) && !FullDiskAccess.isGranted {
            return L10n.t("Cần quyền Full Disk Access")
        }
        guard let freeSpace else { return nil }
        return "\(L10n.t("Còn trống: "))\(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))"
    }
}

/// Minimal Trash-path check + Full Disk Access probe, split out so `StatusBarView` doesn't need to know their
/// mechanism. `TrashLocation`/`FullDiskAccess` may already exist elsewhere in the codebase under other names; this
/// file defines its own narrow, private copies rather than guessing at a shared one it cannot see from this
/// builder's file set (contract §6: W1 view builder owns only the seven `Views/Browser` files listed).
private enum TrashLocation {
    static func isTrash(_ path: String) -> Bool {
        path == FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
    }
}

private enum FullDiskAccess {
    /// Full Disk Access is granted when this process can list the protected `~/Library/Safari` folder — the same
    /// cheap, no-prompt probe TCC itself treats as evidence (listing it without the entitlement throws `EPERM`).
    /// Read once per launch (it lists a folder — not something `body` may do on every render); a grant only takes
    /// effect after XFinder is reopened anyway (FileOctopus documents the same).
    static let isGranted: Bool = {
        let safari = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: safari.path)) != nil
    }()
}

/// Off-main, per-volume free-space cache (contract §4: "Dung lượng trống qua cache @MainActor đọc nền (≥ 10 s mới
/// đọc lại một volume)"). Keyed by volume root (not the pane's own path) so sibling panes/tabs on the same disk
/// share one read.
@MainActor
final class FreeSpaceCache {
    static let shared = FreeSpaceCache()

    private struct Entry {
        let value: Int64?
        let fetchedAt: Date
    }

    private static let refreshInterval: TimeInterval = 10
    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    /// Returns the last known value immediately when it is fresh enough; otherwise kicks off (at most one
    /// concurrent) background refresh and returns whatever was cached before (possibly `nil` on the very first
    /// call for a volume).
    func freeSpace(of path: String) async -> Int64? {
        let volume = await Task.detached(priority: .utility) { DirectoryReader.volumePath(of: path) ?? path }.value
        if let entry = entries[volume], Date().timeIntervalSince(entry.fetchedAt) < Self.refreshInterval {
            return entry.value
        }
        let stale = entries[volume]?.value
        guard !inFlight.contains(volume) else { return stale }
        inFlight.insert(volume)
        let fresh = await Task.detached(priority: .utility) { DirectoryReader.freeSpace(of: volume) }.value
        inFlight.remove(volume)
        entries[volume] = Entry(value: fresh, fetchedAt: Date())
        return fresh
    }
}
