import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// XF-T28 cluster E, Wave 4 §B/§C — the Browser window's own sidebar: Mục ưa thích + the person's own groups (both from
/// `SidebarLayout`), Vị trí (mounted volumes minus hidden ones + CloudStorage providers + iCloud Drive), and Đồng bộ
/// (the folder-sync pairs, Pro-gated). A click navigates the active pane; ejectable volumes get an eject button;
/// dropping a folder from a pane adds it to Mục ưa thích; right-click offers Đổi tên…/Đặt lại tên/Bỏ khỏi
/// sidebar/Ẩn ổ/Nhóm mới….
struct BrowserSidebarView: View {
    private static let iconSize: CGFloat = 16

    let model: BrowserWindowModel

    @State private var layout = BrowserSettings.sidebarLayout
    @State private var volumes: [VolumeRow] = []
    @State private var cloudFolders: [CloudRow] = []
    @State private var license = LicenseManager.shared
    @State private var sync = FolderSyncController.shared
    @State private var renamingItem: RenameTarget?
    @State private var renameText = ""
    @State private var creatingGroup = false
    @State private var newGroupName = ""
    @State private var isTargeted = false
    /// Set only by "Nhóm mới…" ▸ "Tạo nhóm và chuyển vào đây" on an item's own context menu, so `commitNewGroup`
    /// knows to move that one item into the group it is about to create instead of just opening the sheet.
    @State private var pendingMoveItemID: UUID?

    private struct VolumeRow: Identifiable {
        let id: String             // volume UUID when known, else the mount path (never shown, only used as a key)
        let uuid: String?
        let name: String
        let path: String
        let isEjectable: Bool
    }

    private struct CloudRow: Identifiable {
        let id: String
        let name: String
        let path: String
    }

    /// Which item a rename sheet-less inline edit is targeting — favorites have no group id, a group item does.
    private struct RenameTarget: Identifiable {
        let id: UUID
        let groupID: UUID?
        let currentDisplayName: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                section(title: L10n.t("Mục ưa thích")) {
                    ForEach(layout.favorites) { item in
                        itemRow(item, groupID: nil)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers, groupID: nil)
                    return true
                }

                ForEach(layout.groups) { group in
                    section(title: group.name) {
                        ForEach(group.items) { item in
                            itemRow(item, groupID: group.id)
                        }
                    }
                    .contextMenu { groupContextMenu(group) }
                    // Spec XF-T28 Wave 4 §B: "dropping a folder from a pane onto the sidebar adds it" names the
                    // sidebar, not just Mục ưa thích — a custom group is as much a drop target as the built-in one.
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers, groupID: group.id)
                        return true
                    }
                }

                section(title: L10n.t("Vị trí")) {
                    ForEach(volumes) { volume in
                        HStack {
                            row(name: volume.name, systemImage: "externaldrive", path: volume.path)
                            if volume.isEjectable {
                                Spacer(minLength: 0)
                                Button {
                                    eject(volume)
                                } label: {
                                    Image(systemName: "eject")
                                        .font(XFinderTokens.Font.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, XFinderTokens.Space.tight)
                            }
                        }
                        .contextMenu { volumeContextMenu(volume) }
                    }
                    ForEach(cloudFolders) { cloud in
                        row(name: cloud.name, systemImage: "cloud", path: cloud.path)
                    }
                }

                if !sync.pairs.isEmpty {
                    syncSection
                }

                newGroupRow
            }
            .padding(.vertical, XFinderTokens.Space.row)
        }
        .onAppear(perform: reload)
        .sheet(item: $renamingItem) { target in
            renameSheet(target)
        }
    }

    // MARK: - Mục ưa thích / groups

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(XFinderTokens.Settings.sidebarHeader)
                .foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.row)
            content()
        }
    }

    private func row(name: String, systemImage: String, path: String) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: systemImage)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .frame(width: Self.iconSize)
            Text(name)
                .font(XFinderTokens.Settings.sidebarRow)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            model.active.navigate(to: path)
        }
    }

    private func itemRow(_ item: SidebarLayout.Item, groupID: UUID?) -> some View {
        row(name: item.displayName ?? (item.path as NSString).lastPathComponent, systemImage: "folder", path: item.path)
            .contextMenu { itemContextMenu(item, groupID: groupID) }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: SidebarLayout.Item, groupID: UUID?) -> some View {
        Button(L10n.t("Đổi tên…")) {
            renameText = item.displayName ?? (item.path as NSString).lastPathComponent
            renamingItem = RenameTarget(id: item.id, groupID: groupID, currentDisplayName: item.displayName)
        }
        if item.displayName != nil {
            Button(L10n.t("Đặt lại tên")) {
                layout.resetDisplayName(item.id)
                persist()
            }
        }
        Divider()
        Button(L10n.t("Bỏ khỏi sidebar")) {
            layout.removeItem(item.id)
            persist()
        }
        Menu(L10n.t("Nhóm mới…")) {
            Button(L10n.t("Tạo nhóm và chuyển vào đây")) {
                pendingMoveItemID = item.id
                creatingGroup = true
                newGroupName = ""
            }
        }
    }

    @ViewBuilder
    private func groupContextMenu(_ group: SidebarLayout.Group) -> some View {
        Button(L10n.t("Đổi tên…")) {
            renameText = group.name
            renamingItem = RenameTarget(id: group.id, groupID: nil, currentDisplayName: group.name)
        }
        Divider()
        Button(L10n.t("Xoá nhóm")) {
            layout.deleteGroup(group.id)
            persist()
        }
    }

    @ViewBuilder
    private func volumeContextMenu(_ volume: VolumeRow) -> some View {
        if let uuid = volume.uuid {
            Button(L10n.t("Ẩn ổ")) {
                layout.hideVolume(uuid: uuid)
                persist()
                reload()
            }
        }
        Button(L10n.t("Nhóm mới…")) {
            pendingMoveItemID = nil
            creatingGroup = true
            newGroupName = ""
        }
    }

    private var newGroupRow: some View {
        Group {
            if creatingGroup {
                HStack(spacing: XFinderTokens.Space.tight) {
                    TextField(L10n.t("Tên nhóm"), text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .font(XFinderTokens.Font.caption)
                        .onSubmit(commitNewGroup)
                    Button(L10n.t("Tạo")) { commitNewGroup() }
                        .buttonStyle(.borderless)
                    Button(L10n.t("Huỷ")) {
                        pendingMoveItemID = nil
                        creatingGroup = false
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, XFinderTokens.Space.row)
            } else {
                Button {
                    pendingMoveItemID = nil
                    creatingGroup = true
                    newGroupName = ""
                } label: {
                    Label(L10n.t("Nhóm mới…"), systemImage: "folder.badge.plus")
                        .font(XFinderTokens.Font.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.row)
            }
        }
    }

    private func commitNewGroup() {
        guard !newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let group = layout.addGroup(named: newGroupName) else { return }
        // "Tạo nhóm và chuyển vào đây": honour the button's own label by actually moving the item that triggered
        // it into the freshly created group, not just opening the sheet and leaving the item where it was.
        if let movingID = pendingMoveItemID {
            layout.moveItem(movingID, toGroup: group.id, index: group.items.count)
        }
        persist()
        pendingMoveItemID = nil
        creatingGroup = false
    }

    @ViewBuilder
    private func renameSheet(_ target: RenameTarget) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Đổi tên hiển thị"))
                .font(XFinderTokens.Font.row.weight(.semibold))
            Text(L10n.t("Chỉ đổi tên hiện trên sidebar — thư mục thật không đổi tên."))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            TextField("", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitRename)
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { renamingItem = nil }
                Button(L10n.t("Xong")) { commitRename() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 320)
    }

    private func commitRename() {
        guard let target = renamingItem else { return }
        layout.setDisplayName(target.id, to: renameText)
        persist()
        renamingItem = nil
    }

    private func persist() {
        BrowserSettings.sidebarLayout = layout
    }

    // MARK: - Đồng bộ (XF-T28 Wave 4 §C)

    private var syncSection: some View {
        section(title: L10n.t("Đồng bộ")) {
            ForEach(sync.pairs) { pair in
                let allowed = license.allows(.folderSync)
                HStack(spacing: XFinderTokens.Space.tight) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .frame(width: Self.iconSize)
                    Text("\(pair.sourceName) → \(pair.destName)")
                        .font(XFinderTokens.Settings.sidebarRow)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(allowed ? .primary : .secondary)
                    Spacer(minLength: 0)
                    if !allowed {
                        Button {
                            AppState.shared.navigate(to: .pro)
                        } label: { ProBadge() }
                        .buttonStyle(.plain)
                        .help(L10n.t("Cần XFinder Pro — bấm để xem"))
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.row)
                .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    // XF-T29 / spec §C: Free sees the group with a PRO label and an off button — opening the pair
                    // (and from there "Đồng bộ ngay") is Pro-gated the same way FolderSyncDetailView gates it
                    // (`.proGated(.folderSync)`), not just cosmetically badged while the tap still goes through.
                    guard allowed else {
                        AppState.shared.navigate(to: .pro)
                        return
                    }
                    model.openSyncPair(pair)
                }
            }
        }
    }

    // MARK: - Reload (Vị trí)

    /// `mountedVolumeURLs` and `contentsOfDirectory` are disk I/O (stat-backed) — keep them off the main actor
    /// (CLAUDE.md: no disk I/O on main) by running the scan on a detached task and only hopping back to assign
    /// the published `@State` once results are in.
    private func reload() {
        layout = BrowserSettings.sidebarLayout
        let hidden = layout.hiddenVolumeUUIDs
        Task.detached(priority: .userInitiated) {
            let allVolumes = Self.loadVolumes()
            let cloudFolders = Self.loadCloudFolders()
            let volumes = allVolumes.filter { volume in
                guard let uuid = volume.uuid else { return true }
                return !hidden.contains(uuid)
            }
            await MainActor.run {
                self.volumes = volumes
                self.cloudFolders = cloudFolders
            }
        }
    }

    private nonisolated static func loadVolumes() -> [VolumeRow] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeUUIDStringKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            return VolumeRow(id: values.volumeUUIDString ?? url.path, uuid: values.volumeUUIDString,
                             name: name, path: url.path, isEjectable: values.volumeIsEjectable ?? false)
        }
    }

    private nonisolated static func loadCloudFolders() -> [CloudRow] {
        var rows: [CloudRow] = []
        let home = NSHomeDirectory()
        let cloudStorageRoot = home + "/Library/CloudStorage"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: cloudStorageRoot) {
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                let path = cloudStorageRoot + "/" + entry
                rows.append(CloudRow(id: path, name: entry, path: path))
            }
        }
        let iCloudPath = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if FileManager.default.fileExists(atPath: iCloudPath) {
            rows.append(CloudRow(id: iCloudPath, name: L10n.t("iCloud Drive"), path: iCloudPath))
        }
        return rows
    }

    private func eject(_ volume: VolumeRow) {
        let url = URL(fileURLWithPath: volume.path)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            // CLAUDE.md rule 9 / XF-T28 Wave 4 §B: an eject blocked by EjectGuard (a copy in flight) or any other
            // failure must say so instead of doing nothing — never silent.
            model.showBanner("Không đẩy được ổ — có việc đang chạy trên ổ này hay ổ đang bận.")
        }
    }

    // MARK: - Drop (adding a folder from a pane)

    private func handleDrop(_ providers: [NSItemProvider], groupID: UUID?) {
        let collector = SidebarDropCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                collector.set(url.path, at: index)
            }
        }
        group.notify(queue: .main) {
            let paths = collector.collected()
            guard !paths.isEmpty else { return }
            var isDirectory: ObjCBool = false
            for path in paths where FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue {
                layout.addItem(path: path, toGroup: groupID)
            }
            persist()
        }
    }
}

/// Thread-safe fixed-slot collector for `BrowserSidebarView.handleDrop` — each `NSItemProvider`'s completion handler
/// may run on a different queue (same shape as `ShelfBarView`'s own collector, kept local since that one is private).
private final class SidebarDropCollector: Sendable {
    private let slots: OSAllocatedUnfairLock<[String?]>

    init(count: Int) {
        slots = OSAllocatedUnfairLock(initialState: Array(repeating: nil, count: count))
    }

    func set(_ path: String, at index: Int) {
        slots.withLock { slots in
            guard index >= 0, index < slots.count else { return }
            slots[index] = path
        }
    }

    func collected() -> [String] {
        slots.withLock { $0.compactMap { $0 } }
    }
}
