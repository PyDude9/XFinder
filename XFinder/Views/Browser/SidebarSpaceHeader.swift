import SwiftUI

/// XF-T32 W2 (contract XF-T32-w23 §C) — the Space title at the top of the sidebar (Tilde: bold 17 pt name on the left,
/// the sidebar-collapse button on the right of the same row). Clicking the name opens the Space menu: every Space (✓ on
/// the active one), then "Space mới…", "Đổi tên Space…", "Xoá Space" (disabled when only one Space is left).
struct SidebarSpaceHeader: View {
    let spaces: SpaceController
    let onToggleSidebar: () -> Void

    @State private var nameSheet: SidebarSpaceNameSheet.Mode?
    @State private var pendingDelete: Space?

    var body: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            spaceMenu
            Spacer(minLength: 0)
            collapseButton
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .frame(height: XFinderTokens.BrowserSidebar.headerHeight)
        .sheet(item: $nameSheet) { (mode: SidebarSpaceNameSheet.Mode) in
            SidebarSpaceNameSheet(mode: mode, spaces: spaces) { nameSheet = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteDialogShown, titleVisibility: .visible) {
            Button(L10n.t("Xoá Space"), role: .destructive) { confirmDelete() }
            Button(L10n.t("Huỷ"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L10n.t("Thanh bên của Space này sẽ mất. Tệp và thư mục trên đĩa không bị đụng tới."))
        }
    }

    // MARK: - Pieces

    private var spaceMenu: some View {
        Menu {
            ForEach(spaces.store.spaces) { (space: Space) in
                Button {
                    spaces.activate(space.id)
                } label: {
                    if space.id == spaces.active.id {
                        Label(SidebarSpaceNaming.displayName(space), systemImage: "checkmark")
                    } else {
                        Text(SidebarSpaceNaming.displayName(space))
                    }
                }
            }
            Divider()
            Button(L10n.t("Space mới…")) { nameSheet = .create }
            Button(L10n.t("Đổi tên Space…")) { nameSheet = .rename(spaces.active.id) }
            Button(L10n.t("Xoá Space")) { pendingDelete = spaces.active }
                .disabled(spaces.store.spaces.count <= 1)
        } label: {
            Text(SidebarSpaceNaming.displayName(spaces.active))
                .font(XFinderTokens.BrowserSidebar.spaceTitle)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(L10n.t("Đổi Space"))
        .accessibilityLabel(L10n.t("Đổi Space"))
    }

    private var collapseButton: some View {
        Button(action: onToggleSidebar) {
            Image(systemName: "sidebar.left")
                .font(XFinderTokens.BrowserSidebar.headerButton)
                .foregroundColor(.secondary)
                .frame(width: XFinderTokens.BrowserSidebar.rowHeight, height: XFinderTokens.BrowserSidebar.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("Ẩn/hiện thanh bên"))
        .accessibilityLabel(L10n.t("Ẩn/hiện thanh bên"))
    }

    // MARK: - Delete

    private var deleteTitle: String {
        guard let space: Space = pendingDelete else { return L10n.t("Xoá Space") }
        return L10n.t("Xoá Space “") + SidebarSpaceNaming.displayName(space) + L10n.t("”?")
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding<Bool>(get: { pendingDelete != nil }, set: { (shown: Bool) in if !shown { pendingDelete = nil } })
    }

    private func confirmDelete() {
        guard let space: Space = pendingDelete else { return }
        pendingDelete = nil
        // The last Space is refused by SpaceStore; the menu item is disabled then, so `false` only means the Space
        // vanished meanwhile — nothing to do.
        _ = spaces.delete(space.id)
    }
}

// MARK: - Shared with SidebarSpacePager

/// Display name of a Space: the migrated first Space stores its name as the L10n key `SpaceStore.migratedSpaceNameKey`
/// ("Cá nhân"), so it is translated; every other name is the person's own text, shown verbatim.
enum SidebarSpaceNaming {
    static func displayName(_ space: Space) -> String {
        space.name == SpaceStore.migratedSpaceNameKey ? L10n.t("Cá nhân") : space.name
    }
}

/// The one-field sheet used to create or rename a Space (header menu and the pager's +).
struct SidebarSpaceNameSheet: View {
    enum Mode: Identifiable, Equatable {
        case create
        case rename(UUID)

        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let spaceID): return "rename-" + spaceID.uuidString
            }
        }
    }

    let mode: Mode
    let spaces: SpaceController
    let onClose: () -> Void

    @State private var name: String = ""
    @State private var refused: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(title)
                .font(XFinderTokens.Font.sectionTitle)
            TextField(L10n.t("Tên Space"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onChange(of: name) { refused = false }
            if refused {
                Text(L10n.t("Đã có Space tên này."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }
            HStack(spacing: XFinderTokens.Space.tight) {
                Spacer(minLength: 0)
                Button(L10n.t("Huỷ"), role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(XFinderTokens.Space.page)
        .frame(width: XFinderTokens.BrowserSidebar.sheetWidth)
        .onAppear(perform: prefill)
        .task { await Task.yield(); fieldFocused = true }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var title: String {
        switch mode {
        case .create: return L10n.t("Space mới")
        case .rename: return L10n.t("Đổi tên Space")
        }
    }

    private var confirmTitle: String {
        switch mode {
        case .create: return L10n.t("Tạo")
        case .rename: return L10n.t("Đổi tên")
        }
    }

    private func prefill() {
        if case .rename(let spaceID) = mode, let space: Space = spaces.store.spaces.first(where: { $0.id == spaceID }) {
            name = SidebarSpaceNaming.displayName(space)
        } else {
            name = ""
        }
        refused = false
        fieldFocused = true
    }

    private func commit() {
        let typed: String = trimmedName
        guard !typed.isEmpty else { return }
        switch mode {
        case .create:
            // SpaceStore makes a taken name unique (" 2", " 3"…) and activates the new Space with a cloned sidebar.
            spaces.add(name: typed)
            onClose()
        case .rename(let spaceID):
            guard let space: Space = spaces.store.spaces.first(where: { $0.id == spaceID }) else {
                onClose()   // the Space was deleted while the sheet was open
                return
            }
            if typed == SidebarSpaceNaming.displayName(space) {
                onClose()   // unchanged (also keeps the migrated Space's translatable key)
                return
            }
            if spaces.rename(spaceID, to: typed) {
                onClose()
            } else {
                refused = true   // blank or taken by another Space
            }
        }
    }
}
