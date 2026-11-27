import Foundation

/// Pure rules for the Dynamic Island `fileBrowser` destination (XF-ISLAND-FILES).
///
/// Pure `Foundation` only (no `AppKit` / `SwiftUI`), symlinked into `XFinderLogicTests`.
/// Keeps `files` for the Drop Tray (`Khay`); this destination uses `fileBrowser`.
/// Never scans the filesystem or requests TCC permissions — callers inject a lightweight
/// per-path `probe` (`stat` + `access(R_OK)`).
enum NotchFileBrowserRules {

    /// Catalog/router ID for the new destination (`files` remains the Drop Tray).
    static let pageID = "fileBrowser"

    static let defaultMaxFolders = 6
    static let defaultMaxWorkspaces = 6
    static let defaultMaxLabelLength = 24

    enum PathAccess: Equatable, Sendable {
        case accessible
        case missing
        case inaccessible
    }

    enum EntryPoint: Equatable, Sendable {
        case enabled
        case disabled
    }

    enum Action: Equatable, Sendable {
        case openBrowser
        case openFolder(path: String)
        case openWorkspace(id: UUID)
    }

    struct FolderInput: Equatable, Sendable {
        let path: String
        let displayName: String?
        let isPinned: Bool

        init(path: String, displayName: String? = nil, isPinned: Bool = true) {
            self.path = path
            self.displayName = displayName
            self.isPinned = isPinned
        }
    }

    struct FolderRow: Equatable, Identifiable, Sendable {
        var id: String { path }
        let path: String
        let fullName: String
        let displayName: String
        let isPinned: Bool
        let access: PathAccess

        var canOpen: Bool { access == .accessible }
    }

    struct WorkspaceInput: Equatable, Sendable {
        let id: UUID
        let name: String
        let folderPaths: [String]
        let windowCount: Int
    }

    struct WorkspaceRow: Equatable, Identifiable, Sendable {
        let id: UUID
        let fullName: String
        let displayName: String
        let windowCount: Int
        let missingFolderCount: Int
        let inaccessibleFolderCount: Int

        var canOpen: Bool { windowCount > 0 }
        var hasUnavailableFolders: Bool { missingFolderCount > 0 || inaccessibleFolderCount > 0 }
    }

    // MARK: - Feature entry point

    /// Respects `fileBrowser.enabled`: when off, the destination is unavailable in the hub.
    static func isDestinationAvailable(browserEnabled: Bool) -> Bool {
        browserEnabled
    }

    static func entryPoint(browserEnabled: Bool) -> EntryPoint {
        browserEnabled ? .enabled : .disabled
    }

    // MARK: - Label formatting

    /// Produces a compact single-line label for narrow/wide notch rows while keeping both
    /// prefix and suffix recognizable on long folder/workspace names.
    static func compactLabel(_ raw: String, maxLength: Int = defaultMaxLabelLength, fallback: String = "/") -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let limit = max(4, maxLength)
        guard trimmed.count > limit else { return trimmed }

        let ellipsis = "…"
        let budget = limit - ellipsis.count
        let headCount = (budget + 1) / 2
        let tailCount = budget - headCount
        let head = trimmed.prefix(headCount)
        let tail = trimmed.suffix(tailCount)
        return "\(head)\(ellipsis)\(tail)"
    }

    static func folderName(for path: String, displayName: String?) -> String {
        if let custom = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/" { return "/" }
        let last = URL(fileURLWithPath: standardized).lastPathComponent
        return last.isEmpty ? standardized : last
    }

    // MARK: - Resolution (no disk scan, probes only listed paths)

    static func resolveFolders(
        favorites: [FolderInput],
        recents: [String],
        favoritesEnabled: Bool = true,
        recentsEnabled: Bool = true,
        maxCount: Int = defaultMaxFolders,
        maxLabelLength: Int = defaultMaxLabelLength,
        probe: (String) -> PathAccess
    ) -> [FolderRow] {
        guard maxCount > 0 else { return [] }

        var rows: [FolderRow] = []
        var seen: Set<String> = []
        var cache: [String: PathAccess] = [:]

        func cachedProbe(_ normalizedPath: String) -> PathAccess {
            if let existing = cache[normalizedPath] { return existing }
            let result = probe(normalizedPath)
            cache[normalizedPath] = result
            return result
        }

        if favoritesEnabled {
            for item in favorites {
                guard rows.count < maxCount else { break }
                guard let normalized = normalizeLocalPath(item.path), !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let access = cachedProbe(normalized)
                let full = folderName(for: normalized, displayName: item.displayName)
                rows.append(FolderRow(
                    path: normalized,
                    fullName: full,
                    displayName: compactLabel(full, maxLength: maxLabelLength),
                    isPinned: item.isPinned,
                    access: access
                ))
            }
        }

        if recentsEnabled {
            for rawPath in recents {
                guard rows.count < maxCount else { break }
                guard let normalized = normalizeLocalPath(rawPath), !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let access = cachedProbe(normalized)
                // Mirrors `RecentFolders.existing`: vanished recent folders are dropped;
                // inaccessible ones remain visible with their permission status.
                if access == .missing { continue }
                let full = folderName(for: normalized, displayName: nil)
                rows.append(FolderRow(
                    path: normalized,
                    fullName: full,
                    displayName: compactLabel(full, maxLength: maxLabelLength),
                    isPinned: false,
                    access: access
                ))
            }
        }

        return rows
    }

    static func resolveWorkspaces(
        _ inputs: [WorkspaceInput],
        maxCount: Int = defaultMaxWorkspaces,
        maxLabelLength: Int = defaultMaxLabelLength,
        probe: (String) -> PathAccess
    ) -> [WorkspaceRow] {
        guard maxCount > 0 else { return [] }

        var cache: [String: PathAccess] = [:]
        func cachedProbe(_ normalizedPath: String) -> PathAccess {
            if let existing = cache[normalizedPath] { return existing }
            let result = probe(normalizedPath)
            cache[normalizedPath] = result
            return result
        }

        var rows: [WorkspaceRow] = []
        for ws in inputs.prefix(maxCount) {
            var uniquePaths: Set<String> = []
            var missing = 0
            var inaccessible = 0
            for raw in ws.folderPaths {
                guard let normalized = normalizeLocalPath(raw), uniquePaths.insert(normalized).inserted else { continue }
                switch cachedProbe(normalized) {
                case .accessible: break
                case .missing: missing += 1
                case .inaccessible: inaccessible += 1
                }
            }

            let trimmed = ws.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let full = trimmed.isEmpty ? "Workspace" : trimmed
            rows.append(WorkspaceRow(
                id: ws.id,
                fullName: full,
                displayName: compactLabel(full, maxLength: maxLabelLength, fallback: "Workspace"),
                windowCount: ws.windowCount,
                missingFolderCount: missing,
                inaccessibleFolderCount: inaccessible
            ))
        }
        return rows
    }

    // MARK: - Action gating

    static func actionForOpenBrowser(browserEnabled: Bool) -> Action? {
        browserEnabled ? .openBrowser : nil
    }

    static func actionForFolder(_ row: FolderRow, browserEnabled: Bool) -> Action? {
        guard browserEnabled, row.canOpen else { return nil }
        return .openFolder(path: row.path)
    }

    static func actionForWorkspace(_ row: WorkspaceRow, browserEnabled: Bool) -> Action? {
        guard browserEnabled, row.canOpen else { return nil }
        return .openWorkspace(id: row.id)
    }

    // MARK: - Private

    private static func normalizeLocalPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("xfinder-virtual://") else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
