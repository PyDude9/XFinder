import SwiftUI
import AppKit
import Darwin

/// Dynamic Island `fileBrowser` destination (XF-ISLAND-FILES).
///
/// Surfaces XFinder's existing frequent folders (`BrowserSettings.sidebarLayout` + `recentFolders`),
/// saved workspaces (`WorkspaceStore`), and a direct "Open Browser" button. Selecting any item
/// dismisses the Island first, then opens the exact folder, workspace, or browser window in XFinder.
/// Never scans the disk and never triggers TCC permission prompts on open.
struct NotchFileBrowserPage: View {
    /// Snapshot loaders & action hooks default to XFinder's existing browser APIs and are
    /// injectable for previews or tests.
    var isBrowserEnabled: @MainActor () -> Bool = { BrowserSettings.isEnabled }
    var loadFolders: @MainActor () -> [NotchFileBrowserRules.FolderRow] = NotchFileBrowserPage.defaultLoadFolders
    var loadWorkspaces: @MainActor () -> [NotchFileBrowserRules.WorkspaceRow] = NotchFileBrowserPage.defaultLoadWorkspaces
    var onDismiss: @MainActor () -> Void = { NotchSurfaceController.shared.dismiss() }
    var onOpenBrowser: @MainActor () -> Void = { BrowserWindowController.shared.showBrowser() }
    var onOpenFolder: @MainActor (String) -> Void = { path in _ = BrowserWindowController.shared.openWindow(path: path) }
    var onOpenWorkspace: @MainActor (UUID) -> Void = NotchFileBrowserPage.defaultOpenWorkspace
    var onOpenSettings: @MainActor () -> Void = NotchFileBrowserPage.defaultOpenSettings

    @Environment(\.notchAccent) private var accent
    @State private var browserEnabled = true
    @State private var folders: [NotchFileBrowserRules.FolderRow] = []
    @State private var workspaces: [NotchFileBrowserRules.WorkspaceRow] = []

    private typealias N = XFinderTokens.Notch

    var body: some View {
        Group {
            if NotchFileBrowserRules.entryPoint(browserEnabled: browserEnabled) == .disabled {
                disabledState
            } else {
                enabledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refresh)
    }

    // MARK: - Disabled state (`fileBrowser.enabled == false`)

    private var disabledState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "folder.badge.minus")
                .font(XFinderTokens.Font.pageIcon)
                .foregroundColor(.white.opacity(0.65))
            Text(L10n.t("Trình duyệt tệp đang tắt"))
                .font(XFinderTokens.Font.row)
            Text(L10n.t("Bật Trình duyệt tệp trong Cài đặt để mở thư mục và workspace từ đây."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(L10n.t("Mở cài đặt")) {
                onDismiss()
                onOpenSettings()
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Enabled state

    private var enabledState: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            HStack(alignment: .top, spacing: XFinderTokens.Space.row) {
                foldersColumn
                workspacesColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "square.split.2x2")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.8))
            Text(L10n.t("Trình duyệt tệp"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)
            Spacer(minLength: XFinderTokens.Space.tight)
            Button(L10n.t("Mở trình duyệt")) {
                perform(.openBrowser)
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
        }
    }

    // MARK: - Folders column

    private var foldersColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Thư mục quen dùng"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)

            if folders.isEmpty {
                Text(L10n.t("Chưa có thư mục quen dùng."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(folders) { row in
                            folderRowView(row)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func folderRowView(_ row: NotchFileBrowserRules.FolderRow) -> some View {
        Button {
            if let action = NotchFileBrowserRules.actionForFolder(row, browserEnabled: browserEnabled) {
                perform(action)
            }
        } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: folderSymbol(for: row.access))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(folderIconColor(for: row.access))
                    .frame(width: 14)
                Text(row.displayName)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(row.canOpen ? .white : .white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let badge = accessBadge(for: row.access) {
                    Text(badge)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(N.cardStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!row.canOpen)
        .help(row.fullName)
        .accessibilityLabel(row.fullName)
    }

    // MARK: - Workspaces column

    private var workspacesColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Workspace đã lưu"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)

            if workspaces.isEmpty {
                Text(L10n.t("Chưa có workspace nào."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(workspaces) { row in
                            workspaceRowView(row)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func workspaceRowView(_ row: NotchFileBrowserRules.WorkspaceRow) -> some View {
        Button {
            if let action = NotchFileBrowserRules.actionForWorkspace(row, browserEnabled: browserEnabled) {
                perform(action)
            }
        } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "rectangle.3.group")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(row.canOpen ? accent : .white.opacity(0.4))
                    .frame(width: 14)
                Text(row.displayName)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(row.canOpen ? .white : .white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if row.missingFolderCount > 0 {
                    Text("\(row.missingFolderCount)\(L10n.t(" thiếu"))")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if row.inaccessibleFolderCount > 0 {
                    Text(L10n.t("Không có quyền"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(N.cardStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!row.canOpen)
        .help(row.fullName)
        .accessibilityLabel(row.fullName)
    }

    // MARK: - Helpers & defaults

    private func refresh() {
        let enabled = isBrowserEnabled()
        browserEnabled = enabled
        guard enabled else {
            folders = []
            workspaces = []
            return
        }
        folders = loadFolders()
        workspaces = loadWorkspaces()
    }

    /// Always dismisses the Island first, then opens the chosen destination in XFinder.
    private func perform(_ action: NotchFileBrowserRules.Action) {
        guard browserEnabled else { return }
        onDismiss()
        switch action {
        case .openBrowser:
            onOpenBrowser()
        case .openFolder(let path):
            onOpenFolder(path)
        case .openWorkspace(let id):
            onOpenWorkspace(id)
        }
    }

    private func folderSymbol(for access: NotchFileBrowserRules.PathAccess) -> String {
        switch access {
        case .accessible: return "folder.fill"
        case .missing: return "exclamationmark.triangle"
        case .inaccessible: return "lock.fill"
        }
    }

    private func folderIconColor(for access: NotchFileBrowserRules.PathAccess) -> Color {
        switch access {
        case .accessible: return accent
        case .missing, .inaccessible: return .orange
        }
    }

    private func accessBadge(for access: NotchFileBrowserRules.PathAccess) -> String? {
        switch access {
        case .accessible: return nil
        case .missing: return L10n.t("Không tồn tại")
        case .inaccessible: return L10n.t("Không có quyền")
        }
    }

    /// Non-prompting path probe: `stat` + POSIX `access(R_OK)` on the exact listed path only.
    /// Never lists directory contents and never scans the disk, so macOS never raises a TCC dialog.
    private static func probePathAccess(_ path: String) -> NotchFileBrowserRules.PathAccess {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .missing
        }
        guard Darwin.access(path, R_OK) == 0 else {
            return .inaccessible
        }
        return .accessible
    }

    @MainActor
    private static func defaultLoadFolders() -> [NotchFileBrowserRules.FolderRow] {
        let layout = BrowserSettings.sidebarLayout
        let favorites = layout.favorites.map {
            NotchFileBrowserRules.FolderInput(path: $0.path, displayName: $0.displayName, isPinned: true)
        }
        let recents = BrowserSettings.recentFolders.paths
        return NotchFileBrowserRules.resolveFolders(
            favorites: favorites,
            recents: recents,
            favoritesEnabled: BrowserSettings.sidebarFavorites,
            recentsEnabled: BrowserSettings.sidebarRecents,
            probe: probePathAccess
        )
    }

    @MainActor
    private static func defaultLoadWorkspaces() -> [NotchFileBrowserRules.WorkspaceRow] {
        let stored = WorkspaceStore.decode(WorkspaceStore.load()).store.workspaces
        let inputs = stored.map { ws in
            let paths = ws.windows.flatMap { window in
                window.panes.flatMap { pane in
                    pane.allTabs.map(\.path)
                }
            }
            return NotchFileBrowserRules.WorkspaceInput(
                id: ws.id,
                name: ws.name,
                folderPaths: paths,
                windowCount: ws.windows.count
            )
        }
        return NotchFileBrowserRules.resolveWorkspaces(inputs, probe: probePathAccess)
    }

    @MainActor
    private static func defaultOpenWorkspace(_ id: UUID) {
        guard BrowserSettings.isEnabled else { return }
        let stored = WorkspaceStore.decode(WorkspaceStore.load()).store.workspaces
        guard let workspace = stored.first(where: { $0.id == id }) else { return }
        BrowserWindowController.shared.openWorkspaceWindows(workspace.windows)
    }

    @MainActor
    private static func defaultOpenSettings() {
        if let url = URL(string: "xfinder://settings?page=fileBrowser") {
            NSWorkspace.shared.open(url)
        }
    }
}
