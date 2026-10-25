import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// XF-T30 W3 (contract §2) — the full Browser sidebar: Gần đây, AirDrop, Mục ưa thích (+ custom groups), iCloud,
/// Vị trí (local/external/cloud/network, optionally grouped by type), Mạng (Bonjour, off by default), Thẻ (+ "Tất
/// cả thẻ…"); drag-reorder with undo, rename with Đặt lại tên, eject (single/multi-volume, busy-app naming), the
/// Đồng bộ group (XF-T28 Wave 4 §C) and Connect to Server. Every category's row visibility comes from
/// `BrowserSettings.sidebar*` (W4 draws the on/off switch; this view only reads it — contract: "W4 vẽ control; W3
/// đọc qua BrowserSettings").
///
/// XF-T30 W5b/W8 (contract): also the Tìm kiếm đã lưu section (`BrowserSettings.savedSearches`, only entries with
/// `showInSidebar`, click re-runs the query against the active tab, context menu Đổi tên…/Xoá/Bỏ khỏi
/// sidebar/Sao chép câu tìm) and cloud rows per provider/account (`SidebarSources.cloud`, one row per Google Drive
/// account with its email, one for Dropbox, one per other `~/Library/CloudStorage` provider), gated by the same
/// `fileBrowser.sidebar.cloudStorage` key the generic cloud-volume rows already use.
struct BrowserSidebarView: View {
    private static let iconSize: CGFloat = 16

    let model: BrowserWindowModel

    @State private var layout = BrowserSettings.sidebarLayout
    @State private var volumes: [VolumeRow] = []
    @State private var cloudFolders: [CloudRow] = []
    @State private var license = LicenseManager.shared
    @State private var sync = FolderSyncController.shared
    @State private var sources = SidebarSources.shared
    @State private var tagLibrary = TagLibrary.shared
    @State private var recentFolders: [String] = []
    @State private var renamingItem: RenameTarget?
    @State private var renameText = ""
    @State private var creatingGroup = false
    @State private var newGroupName = ""
    @State private var isTargeted = false
    /// XF-T30 W5b — snapshot of `BrowserSettings.savedSearches`, reloaded on `.onAppear` and after every mutation
    /// (rename/delete/toggle) the same way `layout`/`volumes` already refresh through `reload()`.
    @State private var savedSearches = BrowserSettings.savedSearches
    @State private var renamingSavedSearch: SavedSearch?
    @State private var savedSearchRenameText = ""
    /// Set only by "Nhóm mới…" ▸ "Tạo nhóm và chuyển vào đây" on an item's own context menu, so `commitNewGroup`
    /// knows to move that one item into the group it is about to create instead of just opening the sheet.
    @State private var pendingMoveItemID: UUID?
    /// Multi-volume eject prompt state ("eject this one" vs "eject all volumes on this disk" — R69).
    @State private var ejectPrompt: EjectPrompt?
    /// A busy-disk sheet: the blocking app's name (nil = could not be named) + Try Again / Force Eject, scoped to
    /// exactly the volumes the person asked to eject (R67/R70 — never cascades to a sibling or an internal disk).
    @State private var busyEjectSheet: BusyEjectSheet?
    @State private var draggingItemID: UUID?

    private struct VolumeRow: Identifiable {
        var id: String { path }
        let path: String
        let uuid: String?
        let name: String
        let kind: LocationKind
        let isEjectable: Bool
    }

    private struct CloudRow: Identifiable {
        var id: String { path }
        let name: String
        let path: String
        let kind: CloudProvider.Kind
        let account: String?
    }

    /// Which item a rename sheet-less inline edit is targeting — favorites have no group id, a group item does.
    private struct RenameTarget: Identifiable {
        let id: UUID
        let groupID: UUID?
        let currentDisplayName: String?
    }

    private struct EjectPrompt: Identifiable {
        var id: String { mountPath }
        let mountPath: String
        let siblingPaths: [String]
    }

    private struct BusyEjectSheet: Identifiable {
        var id: String { mountPaths.joined(separator: "|") }
        let mountPaths: [String]
        let appName: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                if BrowserSettings.sidebarRecents {
                    recentsSection
                }
                if BrowserSettings.sidebarAirDrop {
                    airDropSection
                }
                favoritesSection
                if sources.iCloudDrive != nil, BrowserSettings.sidebarICloud {
                    iCloudSection
                }
                locationsSection
                if BrowserSettings.sidebarBonjour {
                    networkSection
                }
                if BrowserSettings.sidebarRecentTags {
                    tagsSection
                }
                if !sidebarSavedSearches.isEmpty {
                    savedSearchesSection
                }
                if !sync.pairs.isEmpty {
                    syncSection
                }
                newGroupRow
            }
            .padding(.vertical, XFinderTokens.Space.row)
        }
        .onAppear(perform: reload)
        // ⌘E from the menu / key bindings runs the same eject flow as the row's button (EjectRequestCenter).
        .onChange(of: EjectRequestCenter.shared.pending) { _, _ in
            guard let mountPath: String = EjectRequestCenter.shared.take(for: model) else { return }
            let row: VolumeRow = volumes.first { $0.path == mountPath }
                ?? VolumeRow(path: mountPath, uuid: nil, name: (mountPath as NSString).lastPathComponent, kind: .external,
                             isEjectable: true)
            beginEject(row, force: false)
        }
        .sheet(item: $renamingItem) { target in
            renameSheet(target)
        }
        .sheet(item: $ejectPrompt) { prompt in
            multiVolumeEjectSheet(prompt)
        }
        .sheet(item: $busyEjectSheet) { sheet in
            busyEjectSheetView(sheet)
        }
        .sheet(item: $renamingSavedSearch) { search in
            renameSavedSearchSheet(search)
        }
    }

    // MARK: - Gần đây

    private var recentsSection: some View {
        section(title: L10n.t("Gần đây")) {
            row(name: L10n.t("Gần đây"), systemImage: "clock", path: VirtualLocation.recents.path,
                highlighted: isCurrentPath(VirtualLocation.recents.path))
            if !recentFolders.isEmpty {
                ForEach(recentFolders, id: \.self) { path in
                    row(name: (path as NSString).lastPathComponent, systemImage: "folder", path: path,
                       highlighted: isCurrentPath(path))
                }
                Button(L10n.t("Xoá menu")) {
                    BrowserSettings.recentFolders.clear()
                    reloadRecents()
                }
                .buttonStyle(.plain)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.row)
            }
        }
    }

    // MARK: - AirDrop

    /// Contract: dropping a file sends it via AirDrop; clicking opens Finder's own AirDrop window — macOS has no
    /// public API for another app to show nearby AirDrop devices, so the row says so plainly instead of faking a
    /// device list (CLAUDE.md Honesty Rule). Finder claims the `nwnode:` URL scheme for this (measured 2026-10-25,
    /// `lsregister -dump`: "claim id: NWNode URL … bindings: nwnode: … apple-default apple-internal"); the same
    /// `domain-AirDrop` host is the documented trick other apps use to raise exactly that window.
    private var airDropSection: some View {
        section(title: L10n.t("AirDrop")) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "airplayaudio")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .frame(width: Self.iconSize)
                Text(L10n.t("AirDrop"))
                    .font(XFinderTokens.Settings.sidebarRow)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, XFinderTokens.Space.row)
            .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
            .contentShape(Rectangle())
            .onTapGesture { openFinderAirDropWindow() }
            .help(L10n.t("macOS không cho ứng dụng khác hiện thiết bị AirDrop gần đây — bấm để mở AirDrop của Finder"))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                sendViaAirDrop(providers)
                return true
            }
        }
    }

    private func openFinderAirDropWindow() {
        guard let url = URL(string: "nwnode://domain-AirDrop") else { return }
        NSWorkspace.shared.open(url)
    }

    private func sendViaAirDrop(_ providers: [NSItemProvider]) {
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
            let urls = collector.collected().map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
            guard service.canPerform(withItems: urls) else {
                model.showBanner("AirDrop không khả dụng cho các mục này trên máy này.")
                return
            }
            service.perform(withItems: urls)
        }
    }

    // MARK: - Mục ưa thích / groups

    private var favoritesSection: some View {
        Group {
            if BrowserSettings.sidebarFavorites {
                section(title: L10n.t("Mục ưa thích")) {
                    ForEach(layout.favorites) { item in
                        favoriteRow(item, groupID: nil)
                    }
                }
                .onDrop(of: [.fileURL, .plainText], isTargeted: $isTargeted) { providers in
                    handleDrop(providers, groupID: nil, index: layout.favorites.count)
                    return true
                }

                ForEach(layout.groups) { group in
                    section(title: group.name) {
                        ForEach(group.items) { item in
                            favoriteRow(item, groupID: group.id)
                        }
                    }
                    .contextMenu { groupContextMenu(group) }
                    .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                        handleDrop(providers, groupID: group.id, index: group.items.count)
                        return true
                    }
                }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(XFinderTokens.Settings.sidebarHeader)
                .foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.row)
            content()
        }
    }

    private func isCurrentPath(_ path: String) -> Bool {
        BrowserSettings.sidebarHighlightCurrent && model.active.path == path
    }

    private func row(name: String, systemImage: String, path: String, highlighted: Bool = false) -> some View {
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
        .background(highlighted ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.active.navigate(to: path)
            BrowserWindowModel.noteRecentFolder(path)
        }
        // Spring-loaded folders: a drag held over this row for the system's own delay navigates into it, same
        // timing System Settings ▸ Trackpad/Mouse's "Spring-loading" exposes (contract §2).
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { false }, set: { targeted in
            if targeted { scheduleSpringLoad(path: path) } else { cancelSpringLoad() }
        })) { _ in false }
    }

    private func favoriteRow(_ item: SidebarLayout.Item, groupID: UUID?) -> some View {
        row(name: item.displayName ?? (item.path as NSString).lastPathComponent, systemImage: "folder", path: item.path,
           highlighted: isCurrentPath(item.path))
            .contextMenu { itemContextMenu(item, groupID: groupID) }
            .onDrag {
                draggingItemID = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            }
    }

    /// Finder-style spring-loading: hovering a drag over a sidebar folder for the system's configured delay opens
    /// it, same as dropping onto it would navigate — cancelled the instant the drag leaves (handled by SwiftUI's
    /// own `isTargeted` toggling back to `false`, which calls `cancelSpringLoad()` above).
    @State private var springLoadTask: Task<Void, Never>?

    private func scheduleSpringLoad(path: String) {
        cancelSpringLoad()
        // System Settings ▸ Accessibility ▸ Pointer Control ▸ Spring-loading decides both whether and how fast
        // (review 2026-10-25: a hard-coded 0.6 s ignored the switch and the user's delay).
        let spring: (enabled: Bool, delay: TimeInterval) = DragDropCoordinator.springLoading
        guard spring.enabled else { return }
        let delay: TimeInterval = max(0, spring.delay)
        springLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            model.active.navigate(to: path)
        }
    }

    private func cancelSpringLoad() {
        springLoadTask?.cancel()
        springLoadTask = nil
    }

    /// The exact 5-item menu the contract names: Mở trong tab mới · Mở trong cửa sổ mới · Hiện trong thư mục chứa ·
    /// Lấy thông tin · Đổi tên….
    @ViewBuilder
    private func itemContextMenu(_ item: SidebarLayout.Item, groupID: UUID?) -> some View {
        Button(L10n.t("Mở trong tab mới")) {
            _ = model.newTab(in: model.activePane, path: item.path)
        }
        Button(L10n.t("Mở trong cửa sổ mới")) {
            BrowserWindowController.shared.openWindow(path: item.path)
        }
        Button(L10n.t("Hiện trong thư mục chứa")) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        }
        Button(L10n.t("Lấy thông tin")) {
            GetInfoWindowController.shared.show(paths: [item.path], readOnly: true)
        }
        Divider()
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
            Text(L10n.t("Đổi tên…"))
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
        if target.groupID == nil, layout.groups.contains(where: { $0.id == target.id }) {
            layout.renameGroup(target.id, to: renameText)
        } else {
            layout.setDisplayName(target.id, to: renameText)
        }
        persist()
        renamingItem = nil
    }

    private func persist() {
        BrowserSettings.sidebarLayout = layout
    }

    // MARK: - iCloud

    private var iCloudSection: some View {
        section(title: L10n.t("iCloud Drive")) {
            if let path = sources.iCloudDrive {
                row(name: L10n.t("iCloud Drive"), systemImage: "cloud", path: path, highlighted: isCurrentPath(path))
            }
        }
    }

    // MARK: - Vị trí

    private var locationsSection: some View {
        Group {
            if BrowserSettings.sidebarGroupLocationsByType {
                ForEach(groupedByKind(), id: \.0) { kind, rows in
                    section(title: locationKindTitle(kind)) {
                        locationRows(rows)
                    }
                }
            } else {
                section(title: L10n.t("Vị trí")) {
                    locationRows(visibleVolumes())
                    locationRows(visibleCloudRows())
                }
            }
        }
    }

    private func locationKindTitle(_ kind: LocationKind) -> String {
        switch kind {
        case .local: return L10n.t("Cục bộ")
        case .external: return L10n.t("Ngoài")
        case .cloud: return L10n.t("Đám mây")
        case .network: return L10n.t("Mạng")
        }
    }

    private func groupedByKind() -> [(LocationKind, [VolumeRow])] {
        let all = visibleVolumes() + visibleCloudRows().map {
            VolumeRow(path: $0.path, uuid: nil, name: $0.name, kind: .cloud, isEjectable: false)
        }
        return LocationKind.allCases.compactMap { kind in
            let rows = all.filter { $0.kind == kind }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    private func visibleVolumes() -> [VolumeRow] {
        volumes.filter { volume in
            switch volume.kind {
            case .local: return BrowserSettings.sidebarHardDisks
            case .external: return BrowserSettings.sidebarExternalDisks
            case .cloud: return BrowserSettings.sidebarCloudStorage
            case .network: return BrowserSettings.sidebarConnectedServers
            }
        }
    }

    private func visibleCloudRows() -> [CloudRow] {
        BrowserSettings.sidebarCloudStorage ? cloudFolders : []
    }

    private func locationRows(_ rows: [VolumeRow]) -> some View {
        ForEach(rows) { volume in
            HStack {
                row(name: volume.name, systemImage: icon(for: volume.kind), path: volume.path,
                   highlighted: isCurrentPath(volume.path))
                if volume.isEjectable {
                    Spacer(minLength: 0)
                    Button {
                        beginEject(volume, force: false)
                    } label: {
                        Image(systemName: "eject")
                            .font(XFinderTokens.Font.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, XFinderTokens.Space.tight)
                    .help(L10n.t("Đẩy ra"))
                }
            }
            .contextMenu { volumeContextMenu(volume) }
        }
    }

    private func locationRows(_ rows: [CloudRow]) -> some View {
        ForEach(rows) { cloud in
            cloudRow(cloud)
        }
    }

    /// XF-T30 W8 — one row per cloud provider/account: Google Drive gets one row per signed-in account (email in
    /// the name, contract §W8), Dropbox and other `~/Library/CloudStorage` entries get one row each. Shows the
    /// provider's own installed app icon (`CloudProviderIcon`) when found, falling back to the generic cloud glyph
    /// `row(name:systemImage:path:)` already draws for every other location row — never guesses an icon that isn't
    /// actually on this Mac (CLAUDE.md Honesty Rule).
    private func cloudRow(_ cloud: CloudRow) -> some View {
        Group {
            if let appIcon = CloudProviderIcon.shared.icon(for: cloud.kind) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    Text(cloud.name)
                        .font(XFinderTokens.Settings.sidebarRow)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, XFinderTokens.Space.row)
                .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
                .background(isCurrentPath(cloud.path) ? Color.accentColor.opacity(0.14) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.active.navigate(to: cloud.path)
                    BrowserWindowModel.noteRecentFolder(cloud.path)
                }
            } else {
                row(name: cloud.name, systemImage: "cloud", path: cloud.path, highlighted: isCurrentPath(cloud.path))
            }
        }
    }

    /// Google Drive shows the signed-in account's email (contract: "Google Drive một hàng mỗi tài khoản có email");
    /// every other provider (Dropbox, OneDrive, generic `~/Library/CloudStorage` entries) just shows its own name.
    private func cloudRowName(for provider: CloudProvider) -> String {
        if provider.kind == .googleDrive, let account = provider.account, !account.isEmpty {
            return "\(provider.displayName) (\(account))"
        }
        return provider.displayName
    }

    private func icon(for kind: LocationKind) -> String {
        switch kind {
        case .local: return "internaldrive"
        case .external: return "externaldrive"
        case .cloud: return "cloud"
        case .network: return "network"
        }
    }

    @ViewBuilder
    private func volumeContextMenu(_ volume: VolumeRow) -> some View {
        if volume.isEjectable {
            Button(L10n.t("Đẩy ra")) { beginEject(volume, force: false) }
        }
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

    // MARK: - Mạng (Bonjour)

    private var networkSection: some View {
        section(title: L10n.t("Mạng")) {
            ForEach(sources.bonjourHosts, id: \.self) { host in
                row(name: host, systemImage: "network", path: "smb://\(host)/")
            }
        }
    }

    // MARK: - Thẻ

    private var tagsSection: some View {
        section(title: L10n.t("Thẻ")) {
            ForEach(tagLibrary.tags.filter { $0.color != .none }, id: \.name) { tag in
                HStack(spacing: XFinderTokens.Space.tight) {
                    Circle()
                        .fill(Self.swiftUIColor(for: tag.color))
                        .frame(width: 10, height: 10)
                    Text(tag.name)
                        .font(XFinderTokens.Settings.sidebarRow)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, XFinderTokens.Space.row)
                .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    let path = VirtualLocation.tag(tag.name).path
                    model.active.navigate(to: path)
                }
            }
            row(name: L10n.t("Tất cả thẻ…"), systemImage: "tag", path: VirtualLocation.allTags.path)
        }
    }

    private static func swiftUIColor(for color: TagColor) -> Color {
        switch color {
        case .none: return .clear
        case .gray: return .gray
        case .green: return .green
        case .purple: return .purple
        case .blue: return .blue
        case .yellow: return .yellow
        case .red: return .red
        case .orange: return .orange
        }
    }

    // MARK: - Tìm kiếm đã lưu (XF-T30 W5b)

    /// Only entries the person chose to pin (`showInSidebar`), newest last — same ordering `SavedSearchStore.add`
    /// appends in, so a newly saved search shows up at the bottom instead of jumping around.
    private var sidebarSavedSearches: [SavedSearch] {
        savedSearches.searches.filter(\.showInSidebar)
    }

    private var savedSearchesSection: some View {
        section(title: L10n.t("Tìm kiếm đã lưu")) {
            ForEach(sidebarSavedSearches) { search in
                HStack(spacing: XFinderTokens.Space.tight) {
                    Image(systemName: "magnifyingglass")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .frame(width: Self.iconSize)
                    Text(search.name)
                        .font(XFinderTokens.Settings.sidebarRow)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, XFinderTokens.Space.row)
                .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
                .contentShape(Rectangle())
                .onTapGesture { runSavedSearch(search) }
                .contextMenu { savedSearchContextMenu(search) }
            }
        }
    }

    /// Click runs the saved query against the active tab (contract: "click runs the search in the active tab").
    /// `.folder` scope re-navigates the active pane to the saved folder first — a saved search's folder may not be
    /// where the active tab is sitting right now, and `PaneState.runSearch(.folder)` only ever searches its own
    /// current path, never a path supplied separately.
    private func runSavedSearch(_ search: SavedSearch) {
        guard let scope = PaneSearchState.Scope(rawValue: search.scope) else { return }
        if scope == .folder, let folder = search.folder, folder != model.active.path {
            model.active.navigate(to: folder)
        }
        model.runSearch(search.query, scope: scope)
    }

    /// Contract §W5b: Đổi tên / Xoá / Bỏ khỏi sidebar / Sao chép câu tìm.
    @ViewBuilder
    private func savedSearchContextMenu(_ search: SavedSearch) -> some View {
        Button(L10n.t("Đổi tên…")) {
            savedSearchRenameText = search.name
            renamingSavedSearch = search
        }
        Button(L10n.t("Xoá tìm kiếm đã lưu")) {
            var store = savedSearches
            store.delete(search.id)
            savedSearches = store
            BrowserSettings.savedSearches = store
        }
        Button(L10n.t("Bỏ khỏi sidebar")) {
            var store = savedSearches
            store.setShowInSidebar(search.id, false)
            savedSearches = store
            BrowserSettings.savedSearches = store
        }
        Divider()
        Button(L10n.t("Sao chép câu tìm")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(search.query, forType: .string)
        }
    }

    private func renameSavedSearchSheet(_ search: SavedSearch) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Đổi tên…"))
                .font(XFinderTokens.Font.row.weight(.semibold))
            TextField("", text: $savedSearchRenameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSavedSearchRename(search) }
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { renamingSavedSearch = nil }
                Button(L10n.t("Xong")) { commitSavedSearchRename(search) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 320)
    }

    /// `SavedSearchStore.rename` refuses an empty name, or a name another saved search already has, by returning
    /// `false` and leaving the store untouched (CLAUDE.md rule 7's "one key one control" idiom, mirroring
    /// `BrowserWindowModel.commitRename`'s own `banner = "Đã có mục khác tên này"` for the equivalent file-rename
    /// case) — dismissing the sheet unconditionally would silently drop the rejected rename with no sign anything
    /// went wrong, so the sheet stays open and the owner sees why on a failed attempt.
    private func commitSavedSearchRename(_ search: SavedSearch) {
        var store = savedSearches
        guard store.rename(search.id, to: savedSearchRenameText) else {
            // `model.banner` carries the raw key — `BrowserRootView.bannerView` is the one place that wraps it
            // through `L10n.t`, same as `BrowserWindowModel.commitRename` does for the equivalent file-rename
            // conflict (that one's own literal is itself an unregistered L10n gap, so this uses its own key
            // instead of reusing one with no English translation).
            model.banner = "Đã có tìm kiếm đã lưu khác tên này"
            return
        }
        savedSearches = store
        BrowserSettings.savedSearches = store
        renamingSavedSearch = nil
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
                    guard allowed else {
                        AppState.shared.navigate(to: .pro)
                        return
                    }
                    model.openSyncPair(pair)
                }
            }
        }
    }

    // MARK: - Reload

    /// `mountedVolumeURLs`/`contentsOfDirectory` are disk I/O — kept off the main actor (CLAUDE.md: no disk I/O on
    /// main) by reading through `SidebarSources` (already off-main) and only hopping back for the filtered result.
    private func reload() {
        layout = BrowserSettings.sidebarLayout
        savedSearches = BrowserSettings.savedSearches
        sources.start()
        tagLibrary.start()
        reloadRecents()
        applySources()
    }

    private func reloadRecents() {
        recentFolders = BrowserSettings.recentFolders.existing { FileManager.default.fileExists(atPath: $0) }
    }

    /// Mirrors `SidebarSources`' published volumes/cloud into this view's own filtered rows (hidden volumes excluded).
    private func applySources() {
        let hidden = layout.hiddenVolumeUUIDs
        volumes = sources.volumes.compactMap { volume in
            if let uuid = volume.uuid, hidden.contains(uuid) { return nil }
            return VolumeRow(path: volume.path, uuid: volume.uuid, name: volume.name, kind: volume.kind,
                             isEjectable: volume.ejectable)
        }
        cloudFolders = sources.cloud.map { provider in
            CloudRow(name: cloudRowName(for: provider), path: provider.rootPath, kind: provider.kind,
                     account: provider.account)
        }
    }

    // MARK: - Eject (R66–R70)

    /// ⌘E / the row's own eject button / "Đẩy ra" in the context menu all land here. A disk with more than one
    /// mounted volume asks first (R69); Option = eject every volume on the disk, Control = just this one — the
    /// same modifier convention as the sheet's own buttons for someone who didn't hold a key down.
    private func beginEject(_ volume: VolumeRow, force: Bool) {
        let siblings = EjectGuard.shared.siblingVolumes(of: volume.path).map(\.mountPath)
        if !siblings.isEmpty {
            let modifiers = NSEvent.modifierFlags
            if modifiers.contains(.option) {
                performEject(mountPaths: [volume.path] + siblings, force: force)
            } else if modifiers.contains(.control) {
                performEject(mountPaths: [volume.path], force: force)
            } else {
                ejectPrompt = EjectPrompt(mountPath: volume.path, siblingPaths: siblings)
            }
            return
        }
        performEject(mountPaths: [volume.path], force: force)
    }

    private func multiVolumeEjectSheet(_ prompt: EjectPrompt) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Đẩy ổ đĩa này?"))
                .font(XFinderTokens.Font.row.weight(.semibold))
            Text(L10n.t("Ổ này có nhiều phân vùng. Bạn muốn đẩy chỉ phân vùng này hay mọi phân vùng trên ổ?"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { ejectPrompt = nil }
                Button(L10n.t("Chỉ phân vùng này")) {
                    performEject(mountPaths: [prompt.mountPath], force: false)
                    ejectPrompt = nil
                }
                Button(L10n.t("Đẩy mọi phân vùng")) {
                    performEject(mountPaths: [prompt.mountPath] + prompt.siblingPaths, force: false)
                    ejectPrompt = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 380)
    }

    private func performEject(mountPaths: [String], force: Bool) {
        Task {
            let refusals = await EjectGuard.shared.attemptEject(mountPaths: mountPaths, force: force)
            await MainActor.run {
                reload()
                guard !refusals.isEmpty else { return }
                if refusals.values.contains(where: { if case .xfinderBusy = $0 { return true }; return false }) {
                    model.showBanner("Không đẩy được — XFinder đang thực hiện một thao tác tệp trên ổ này.")
                    return
                }
                if let appBusy = refusals.first(where: { if case .appBusy = $0.value { return true }; return false }) {
                    let appName: String?
                    if case .appBusy(let name) = appBusy.value { appName = name } else { appName = nil }
                    busyEjectSheet = BusyEjectSheet(mountPaths: Array(refusals.keys), appName: appName)
                }
            }
        }
    }

    private func busyEjectSheetView(_ sheet: BusyEjectSheet) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Ổ đĩa đang bận"))
                .font(XFinderTokens.Font.row.weight(.semibold))
            if let appName = sheet.appName {
                Text(L10n.t("Ứng dụng ") + appName + L10n.t(" đang dùng ổ này. Đẩy ngay có thể làm mất dữ liệu chưa lưu của ứng dụng đó."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(L10n.t("Một ứng dụng đang dùng ổ này. Đẩy ngay có thể làm mất dữ liệu chưa lưu."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { busyEjectSheet = nil }
                Button(L10n.t("Thử lại")) {
                    performEject(mountPaths: sheet.mountPaths, force: false)
                    busyEjectSheet = nil
                }
                Button(L10n.t("Buộc đẩy")) {
                    performEject(mountPaths: sheet.mountPaths, force: true)
                    busyEjectSheet = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 380)
    }

    // MARK: - Drop (adding a folder from a pane, or reordering a sidebar item)

    private static let sidebarItemUTI = "com.xfinder.browser.sidebaritem"

    private func handleDrop(_ providers: [NSItemProvider], groupID: UUID?, index: Int) {
        // A reorder (dragging an existing sidebar item) carries its own UUID string, no file URL to resolve.
        if let draggingItemID {
            layout.moveItem(draggingItemID, toGroup: groupID, index: index)
            persist()
            self.draggingItemID = nil
            return
        }
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

/// XF-T30 W8 — the installed app icon for a cloud provider's sidebar row, when that provider's own app is on this
/// Mac (CLAUDE.md rule 14: every AppKit/LaunchServices lookup in a SwiftUI `body` goes through a `@MainActor`
/// cache, never a bare lookup per render). iCloud Drive never goes through here — it has no separate app, and its
/// row already uses the generic "cloud" glyph via `BrowserSidebarView.iCloudSection`.
///
/// Bundle identifiers are the provider's own published desktop-app IDs; a provider that isn't installed, or whose
/// ID doesn't resolve, falls back to nil so the caller draws the same generic cloud glyph every other location row
/// uses — never a guessed or placeholder icon (Honesty Rule: no claim of "this app is installed" without measuring
/// `NSWorkspace.urlForApplication(withBundleIdentifier:)` actually resolving).
@MainActor private final class CloudProviderIcon {
    static let shared = CloudProviderIcon()

    private static let bundleIDs: [CloudProvider.Kind: String] = [
        .googleDrive: "com.google.GoogleDrive",
        .dropbox: "com.getdropbox.dropbox",
        .oneDrive: "com.microsoft.OneDrive",
    ]

    /// One lookup per `Kind` per app launch — a provider's app doesn't appear/disappear mid-session often enough to
    /// justify re-probing `NSWorkspace` on every sidebar reload, and a stale "not found" only costs a generic glyph
    /// instead of a crash or wrong icon.
    private var cache: [CloudProvider.Kind: NSImage?] = [:]

    private init() {}

    func icon(for kind: CloudProvider.Kind) -> NSImage? {
        if let cached = cache[kind] { return cached }
        let image = Self.bundleIDs[kind].flatMap { bundleID -> NSImage? in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        cache[kind] = image
        return image
    }
}

/// Thread-safe fixed-slot collector for `BrowserSidebarView`'s drop handlers — each `NSItemProvider`'s completion
/// handler may run on a different queue (same shape as `ShelfBarView`'s own collector, kept local since that one
/// is private).
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
