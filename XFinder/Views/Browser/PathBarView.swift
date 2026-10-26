import SwiftUI
import AppKit

/// XF-T30 W1 / XF-T32 W3 (contract XF-T32-w23 §G) — the breadcrumb at the BOTTOM of every pane (Tilde: "Home ›
/// Projects › Field Notes Journal", 12 pt, a 12 pt folder icon per component, `›` separators, 24 pt tall). Each
/// component is a plain button that navigates this tab there; the current folder is drawn in the primary colour, its
/// ancestors in secondary. Height-capped (FileOctopus 1.0.4 fix: "path bar could grow to fill most of a window").
struct PathBarView: View {
    static let height: CGFloat = XFinderTokens.PaneChrome.pathBarHeight

    let pane: PaneState
    let model: BrowserWindowModel

    var body: some View {
        HStack(spacing: XFinderTokens.PaneChrome.componentSpacing) {
            if let virtual: VirtualLocation = VirtualLocation.parse(pane.path) {
                PathBarVirtualLabel(location: virtual)
            } else {
                let paths: [String] = PathBarRules.componentPaths(for: pane.path, home: NSHomeDirectory())
                ForEach(paths.indices, id: \.self) { (index: Int) in
                    let path: String = paths[index]
                    if index > 0 {
                        PathBarSeparator()
                    }
                    PathBarSegment(path: path, isCurrent: index == paths.count - 1) {
                        navigate(to: path)
                    }
                    .layoutPriority(index == paths.count - 1 ? 1 : 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
        .padding(.horizontal, XFinderTokens.Space.tight)
    }

    private func navigate(to path: String) {
        model.focus(pane.id)
        guard path != pane.path else { return }
        pane.navigate(to: path)
    }
}

// MARK: - Pieces

/// One breadcrumb component: real Finder icon (through `FileIconCache`, never a LaunchServices call in `body`) + the
/// localized display name (through `PaneChromeNameCache`), truncated in the middle when the bar is short.
private struct PathBarSegment: View {
    let path: String
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: XFinderTokens.PaneChrome.componentSpacing) {
                Image(nsImage: FileIconCache.shared.icon(forPath: path))
                    .resizable()
                    .frame(width: XFinderTokens.PaneChrome.pathIconSize, height: XFinderTokens.PaneChrome.pathIconSize)
                Text(PaneChromeNameCache.shared.displayName(forPath: path))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(path)
    }
}

private struct PathBarSeparator: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(XFinderTokens.PaneChrome.separatorFont)
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
    }
}

/// Recents / a tag / all tags have no folder chain — one non-clickable label, the same words the sidebar uses.
private struct PathBarVirtualLabel: View {
    let location: VirtualLocation

    var body: some View {
        Text(title)
            .font(XFinderTokens.Font.rowValue)
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var title: String {
        switch location {
        case .recents: return L10n.t("Gần đây")
        case .tag(let name): return name
        case .allTags: return L10n.t("Thẻ")
        }
    }
}

// MARK: - Rules

/// Which folders the breadcrumb lists for a path. Anchor = the home folder when the path is inside it (Tilde starts
/// at "Home"), the volume root for `/Volumes/<name>/…`, else `/` (the startup disk). Every component after the
/// anchor is one ancestor, ending at the path itself. Pure; never touches the disk.
enum PathBarRules {
    static func componentPaths(for rawPath: String, home rawHome: String) -> [String] {
        let path: String = normalized(rawPath)
        let home: String = normalized(rawHome)
        guard path.hasPrefix("/") else { return path.isEmpty ? [] : [path] }

        let anchor: String = anchorPath(for: path, home: home)
        var result: [String] = [anchor]
        let rest: Substring = path.dropFirst(anchor.count)
        var accumulated: String = anchor
        for component in rest.split(separator: "/", omittingEmptySubsequences: true) {
            accumulated = (accumulated as NSString).appendingPathComponent(String(component))
            result.append(accumulated)
        }
        return result
    }

    private static func anchorPath(for path: String, home: String) -> String {
        if home != "/", home.hasPrefix("/"), path == home || path.hasPrefix(home + "/") {
            return home
        }
        let volumesPrefix: String = "/Volumes/"
        if path.hasPrefix(volumesPrefix) {
            let afterPrefix: Substring = path.dropFirst(volumesPrefix.count)
            if let volumeName: Substring = afterPrefix.split(separator: "/", omittingEmptySubsequences: true).first {
                return volumesPrefix + volumeName
            }
        }
        return "/"
    }

    /// Drops trailing slashes ("/Users/a/" → "/Users/a") and collapses "//"; keeps "/" itself.
    private static func normalized(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let parts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }
}

// MARK: - Display names

/// `FileManager.displayName(atPath:)` (localized folder names — "Downloads" reads "Tải về" — and the startup disk's
/// name for "/") asks LaunchServices, so `body` reads it through this bounded main-actor cache (CLAUDE.md §3.3 #14).
/// Shared by `PathBarView` and `RelatedItemsStrip`.
@MainActor final class PaneChromeNameCache {
    static let shared: PaneChromeNameCache = PaneChromeNameCache()

    private var names: [String: String] = [:]
    private let capacity: Int = 512

    private init() {}

    func displayName(forPath path: String) -> String {
        if let cached: String = names[path] { return cached }
        let resolved: String = FileManager.default.displayName(atPath: path)
        let name: String = resolved.isEmpty ? (path as NSString).lastPathComponent : resolved
        if names.count >= capacity { names.removeAll(keepingCapacity: true) }
        names[path] = name
        return name
    }
}
