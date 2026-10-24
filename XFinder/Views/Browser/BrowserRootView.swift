import SwiftUI
import UniformTypeIdentifiers

/// XF-T28 cluster E — the file browser window's root chrome: toolbar, sidebar + pane grid, Shelf strip, and the
/// sheets/overlays everything else in the window funnels through (conflict, batch rename, recovery, command
/// palette, a one-line auto-hiding banner).
struct BrowserRootView: View {
    static let minimumSize = CGSize(width: 720, height: 460)
    private static let sidebarWidth: CGFloat = 200
    private static let bannerAutoHide: TimeInterval = 4

    let model: BrowserWindowModel

    @State private var showingWorkspaceSaveSheet = false
    @State private var showingOpenWorkspaceSheet = false
    @State private var showingManageWorkspacesSheet = false
    @State private var showingOperationsPopover = false
    @State private var workspaceName = ""
    @State private var bannerWorkItem: DispatchWorkItem?
    @State private var license = LicenseManager.shared
    @State private var isSyncing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)

            HStack(spacing: 0) {
                BrowserSidebarView(model: model)
                    .frame(width: Self.sidebarWidth)
                Rectangle().fill(XFinderTokens.Fill.hairline).frame(width: 1)
                VStack(spacing: 0) {
                    if let pair = model.activeSyncPair {
                        syncBar(pair)
                        Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)
                    }
                    PaneGridView(model: model)
                }
            }

            if model.shelfVisible {
                ShelfBarView(model: model)
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                bannerView(banner)
            }
        }
        .overlay {
            if let mode = model.palette {
                CommandPaletteView(model: model, mode: mode)
            }
        }
        .sheet(isPresented: Binding(
            get: { FileOperationQueue.shared.pendingConflict != nil },
            set: { if !$0 { } }
        )) {
            if let prompt = FileOperationQueue.shared.pendingConflict {
                ConflictSheet(prompt: prompt, queue: FileOperationQueue.shared)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.batchRenameSources != nil },
            set: { if !$0 { model.batchRenameSources = nil } }
        )) {
            if let sources = model.batchRenameSources {
                BrowserBatchRenameSheet(sources: sources, model: model)
            }
        }
        .sheet(isPresented: Binding(
            get: { !FileOperationQueue.shared.recovery.isEmpty },
            set: { _ in }
        )) {
            RecoveryReportSheet(queue: FileOperationQueue.shared)
        }
        .sheet(isPresented: $showingWorkspaceSaveSheet) {
            saveWorkspaceSheet
        }
        .sheet(isPresented: $showingOpenWorkspaceSheet) {
            openWorkspaceSheet
        }
        .sheet(isPresented: $showingManageWorkspacesSheet) {
            ManageWorkspacesSheet(model: model)
        }
        .onChange(of: model.banner) { _, newValue in
            scheduleBannerAutoHide(newValue)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            HStack(spacing: 2) {
                Button { model.active.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.active.history.canGoBack)
                Button { model.active.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.active.history.canGoForward)
            }

            Picker("", selection: Binding(
                get: { model.active.viewMode },
                set: { model.active.viewMode = $0 }
            )) {
                Image(systemName: "list.bullet").tag(BrowserViewMode.list)
                Image(systemName: "square.grid.2x2").tag(BrowserViewMode.icons)
                Image(systemName: "rectangle.split.3x1").tag(BrowserViewMode.columns)
                Image(systemName: "rectangle.grid.1x2").tag(BrowserViewMode.gallery)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            presetMenu

            Spacer()

            Button {
                _ = model.perform(.toggleShelf)
            } label: {
                Image(systemName: model.shelfVisible ? "tray.full.fill" : "tray")
            }

            operationsButton

            workspaceMenu
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, XFinderTokens.Space.tight)
    }

    /// True once the pane count has reached what Free allows (`ProLimit.browserPanes`, default 2) — the split/preset
    /// items still work (an already-open layout keeps working per XF-T29 rule 3), they just carry a PRO tag so the
    /// surface says why a further split needs Pro rather than silently doing nothing.
    private var paneLimitReachedInFree: Bool {
        guard let limit = license.limit(.browserPanes) else { return false }
        return model.tree.count >= limit
    }

    private var presetMenu: some View {
        Menu {
            Button(L10n.t("Một ngăn")) { _ = model.perform(.presetSingle) }
            Button(L10n.t("Cạnh nhau")) { _ = model.perform(.presetSideBySide) }
            Button(L10n.t("Chồng lên nhau")) { _ = model.perform(.presetStacked) }
            Button(L10n.t("Lưới 2×2")) { _ = model.perform(.presetGrid) }
            Divider()
            splitMenuItem(L10n.t("Chia ngăn sang phải")) { _ = model.perform(.splitRight) }
            splitMenuItem(L10n.t("Chia ngăn sang trái")) { _ = model.perform(.splitLeft) }
            splitMenuItem(L10n.t("Chia ngăn xuống dưới")) { _ = model.perform(.splitDown) }
            splitMenuItem(L10n.t("Chia ngăn lên trên")) { _ = model.perform(.splitUp) }
            Divider()
            Button(L10n.t("Chia đều các ngăn")) { _ = model.perform(.equalizePanes) }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
    }

    /// A split item: disabled past `PaneTree.maxPanes` same as before, and additionally labelled PRO (still
    /// clickable, since a menu label can't host `.proGated`'s own disable — the pane limit itself already blocks the
    /// split once Free's cap is hit via `canPerform`/`PaneTree.canSplit` upstream) once Free's own lower cap is reached.
    private func splitMenuItem(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            if paneLimitReachedInFree {
                Text(title + " (" + L10n.t("Pro") + ")")
            } else {
                Text(title)
            }
        }
        .disabled(!model.tree.canSplit || paneLimitReachedInFree)
    }

    private var operationsButton: some View {
        let activeCount = FileOperationQueue.shared.queue.jobs.filter { !$0.isFinished }.count
        return Button {
            showingOperationsPopover = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right.circle")
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(XFinderTokens.Font.caption)
                }
            }
        }
        .popover(isPresented: $showingOperationsPopover) {
            OperationsPanelView(queue: FileOperationQueue.shared)
        }
    }

    private var workspaceMenu: some View {
        Menu {
            Button {
                workspaceName = ""
                showingWorkspaceSaveSheet = true
            } label: {
                HStack {
                    Text(L10n.t("Lưu Workspace…"))
                    if !license.allows(.browserWorkspaces) { ProBadge() }
                }
            }
            Button {
                showingOpenWorkspaceSheet = true
            } label: {
                HStack {
                    Text(L10n.t("Mở"))
                    if !license.allows(.browserWorkspaces) { ProBadge() }
                }
            }
            .disabled(model.workspaces.isEmpty)
            Divider()
            Button(L10n.t("Quản lý Workspace…")) {
                showingManageWorkspacesSheet = true
            }
            .disabled(model.workspaces.isEmpty)
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
    }

    /// Names the current window's layout and persists it via `model.saveWorkspace(named:)` (Pro-gated: Free gets a
    /// banner from the model itself and no workspace is written).
    private var saveWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Lưu Workspace"))
                .font(XFinderTokens.Font.sectionTitle)
            TextField(L10n.t("Tên Workspace"), text: $workspaceName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSaveWorkspace() }
            HStack {
                Spacer()
                Button(L10n.t("Dừng")) { showingWorkspaceSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("Lưu Workspace")) {
                    commitSaveWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 320)
    }

    private func commitSaveWorkspace() {
        _ = model.saveWorkspace(named: workspaceName)
        showingWorkspaceSaveSheet = false
    }

    /// Picks one of `model.workspaces` to replace this window's layout with (`model.openWorkspace(_:)`).
    private var openWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Mở Workspace"))
                .font(XFinderTokens.Font.sectionTitle)
            if model.workspaces.isEmpty {
                Text(L10n.t("Chưa có Workspace nào"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.secondary)
            } else {
                List(model.workspaces) { workspace in
                    Button {
                        model.openWorkspace(workspace.id)
                        showingOpenWorkspaceSheet = false
                    } label: {
                        HStack {
                            Text(workspace.name)
                            Spacer()
                            Text(workspace.savedAt, style: .date)
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 160)
            }
            HStack {
                Spacer()
                Button(L10n.t("Dừng")) { showingOpenWorkspaceSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 360)
    }

    // MARK: - Folder sync bar

    /// A slim bar above the grid while `model.activeSyncPair` is set: names source → destination, runs the pair
    /// (`model.syncNow()`, Pro-gated via `.folderSync` — Free still sees the pair and the bar, just not a working
    /// button), shows the last result, and links to the pair's own settings page.
    private func syncBar(_ pair: FolderSyncController.Pair) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.secondary)
            Text(L10n.t("Đồng bộ ") + pair.sourceName + " → " + pair.destName)
                .font(XFinderTokens.Font.rowValue)

            if let lastResult = pair.lastResult {
                Text(lastResult)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isSyncing = true
                Task {
                    _ = await model.syncNow()
                    isSyncing = false
                }
            } label: {
                HStack(spacing: 4) {
                    if isSyncing { ProgressView().controlSize(.small) }
                    Text(L10n.t("Đồng bộ ngay"))
                }
            }
            .disabled(isSyncing)
            .proGated(.folderSync)

            Button(L10n.t("Cài đặt cặp này…")) {
                AppState.shared.navigate(to: .sync)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, XFinderTokens.Space.tight)
        .background(XFinderTokens.Fill.surface)
    }

    // MARK: - Banner

    private func bannerView(_ text: String) -> some View {
        Text(L10n.t(text))
            .font(XFinderTokens.Font.rowValue)
            .padding(.horizontal, XFinderTokens.Space.row)
            .padding(.vertical, XFinderTokens.Space.tight)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.surface))
            .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).stroke(XFinderTokens.Fill.hairline))
            .shadow(radius: 6)
            .padding(.top, XFinderTokens.Space.row)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func scheduleBannerAutoHide(_ text: String?) {
        bannerWorkItem?.cancel()
        guard text != nil else { return }
        let work = DispatchWorkItem { [weak model] in
            model?.banner = nil
        }
        bannerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerAutoHide, execute: work)
    }
}

/// "Quản lý Workspace…" — a list with inline rename, duplicate, delete (behind a confirmation), and an export to a
/// JSON file the person picks with `NSSavePanel` (`model.exportWorkspaces()`). Rename/duplicate/delete work the same
/// in Free and Pro (XF-T29: `.browserWorkspaces` only gates saving a NEW one and opening one into a window); this
/// sheet never creates a workspace, so it carries no gate of its own.
private struct ManageWorkspacesSheet: View {
    let model: BrowserWindowModel
    @Environment(\.dismiss) private var dismiss

    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var pendingDeleteID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Quản lý Workspace"))
                .font(XFinderTokens.Font.sectionTitle)

            if model.workspaces.isEmpty {
                Text(L10n.t("Chưa có Workspace nào"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.secondary)
            } else {
                List(model.workspaces) { workspace in
                    row(for: workspace)
                }
                .frame(minHeight: 200)
            }

            HStack {
                Button(L10n.t("Xuất JSON…")) {
                    exportToFile()
                }
                .disabled(model.workspaces.isEmpty)
                Spacer()
                Button(L10n.t("Xong")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 420)
        .confirmationDialog(
            L10n.t("Xoá Workspace này?"),
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("Xoá"), role: .destructive) {
                if let id = pendingDeleteID { model.deleteWorkspace(id) }
                pendingDeleteID = nil
            }
            Button(L10n.t("Dừng"), role: .cancel) { pendingDeleteID = nil }
        }
    }

    @ViewBuilder
    private func row(for workspace: Workspace) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            if renamingID == workspace.id {
                TextField(L10n.t("Tên Workspace"), text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(workspace.id) }
                Button(L10n.t("Xong")) { commitRename(workspace.id) }
                Button(L10n.t("Dừng")) { renamingID = nil }
            } else {
                Text(workspace.name)
                    .font(XFinderTokens.Font.rowValue)
                Spacer()
                Button(L10n.t("Đổi tên")) {
                    renameText = workspace.name
                    renamingID = workspace.id
                }
                .buttonStyle(.plain)
                Button(L10n.t("Nhân đôi")) {
                    model.duplicateWorkspace(workspace.id)
                }
                .buttonStyle(.plain)
                Button(L10n.t("Xoá")) {
                    pendingDeleteID = workspace.id
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .settingsRow()
    }

    private func commitRename(_ id: UUID) {
        _ = model.renameWorkspace(id, to: renameText)
        renamingID = nil
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "workspaces.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.exportWorkspaces().write(to: url, options: .atomic)
    }
}
