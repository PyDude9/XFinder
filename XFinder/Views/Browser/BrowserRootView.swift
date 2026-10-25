import SwiftUI
import UniformTypeIdentifiers

/// XF-T28 cluster E / XF-T30 W1 — the file browser window's root chrome: sidebar + pane grid, Shelf strip, and the
/// sheets/overlays everything else in the window funnels through (conflict, batch rename, recovery, command
/// palette, a one-line auto-hiding banner, and the workspace sheets, now driven by `model.sheet` since the native
/// `NSToolbar` — builder C's `BrowserToolbarController` — replaces the old SwiftUI toolbar row entirely: this view
/// no longer draws a toolbar of its own).
struct BrowserRootView: View {
    static let minimumSize = CGSize(width: 720, height: 460)
    private static let sidebarWidth: CGFloat = 200
    private static let bannerAutoHide: TimeInterval = 4

    let model: BrowserWindowModel

    @State private var workspaceName = ""
    @State private var bannerWorkItem: DispatchWorkItem?
    @State private var isSyncing = false
    @AppStorage("fileBrowser.showSidebar") private var showSidebar = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showSidebar {
                    BrowserSidebarView(model: model)
                        .frame(width: Self.sidebarWidth)
                    Rectangle().fill(XFinderTokens.Fill.hairline).frame(width: 1)
                }
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
        .sheet(isPresented: Binding(
            get: { model.sheet == .saveWorkspace },
            set: { if !$0 { model.sheet = nil } }
        )) {
            saveWorkspaceSheet
        }
        .sheet(isPresented: Binding(
            get: { model.sheet == .openWorkspace },
            set: { if !$0 { model.sheet = nil } }
        )) {
            openWorkspaceSheet
        }
        .sheet(isPresented: Binding(
            get: { model.sheet == .manageWorkspaces },
            set: { if !$0 { model.sheet = nil } }
        )) {
            ManageWorkspacesSheet(model: model)
        }
        .onChange(of: model.banner) { _, newValue in
            scheduleBannerAutoHide(newValue)
        }
    }

    /// Names the current window's layout and persists it via `model.saveWorkspace(named:)` (Pro-gated: Free gets a
    /// banner from the model itself and no workspace is written). `workspaceName` is `BrowserRootView`'s own
    /// long-lived `@State` (the window stays open across many save attempts), so it must be reset to empty every
    /// time this sheet appears, not just once when the window itself first appears (CLAUDE.md rule 9: "store
    /// @State trong view sống lâu (popover/panel) phải reset trước khi fetch") — otherwise reopening the sheet after
    /// a previous save/cancel pre-fills the field with the last-typed name.
    private var saveWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Lưu Workspace"))
                .font(XFinderTokens.Font.sectionTitle)
            TextField(L10n.t("Tên Workspace"), text: $workspaceName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSaveWorkspace() }
            HStack {
                Spacer()
                Button(L10n.t("Dừng")) { model.sheet = nil }
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
        .onAppear {
            workspaceName = ""
        }
    }

    private func commitSaveWorkspace() {
        _ = model.saveWorkspace(named: workspaceName)
        model.sheet = nil
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
                        model.sheet = nil
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
                Button(L10n.t("Dừng")) { model.sheet = nil }
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
