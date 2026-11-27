import SwiftUI
import AppKit
import Darwin

/// Khay thả — a Drop-app-style shelf. The user comes here to see and act on the files they are
/// holding, and to choose how the tray opens while dragging files. Drag files onto the tray (or add
/// via the button); the tray holds them as staged entries, then one click applies a shared action to
/// selected or all items: share, copy/move into the browser's active pane, move/copy via the shared
/// file operation queue, compress (ZIP), Quick Look, batch rename, move-to-trash, or open. Persisted
/// in UserDefaults so the shelf survives relaunch. The notch SURFACE itself (master switch, hover,
/// shape, pages) is owned by Giao diện notch (`NotchInterfaceDetailView`).
struct DropTrayDetailView: View {
    @State private var tray = DropTrayStore.shared
    @State private var history = ActionHistoryStore.shared
    @State private var queue = FileOperationQueue.shared
    @State private var selection = DropTraySelection()
    @State private var isTargeted = false
    @State private var outcome: String? = nil
    @State private var showDetailGrid = true

    // Read-only here: Giao diện notch owns the master switch (Part 0 §4 — one key, one control).
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    // The two file-drag ways to open the tray. Read at point of use by NotchSurfaceController; defaults
    // must equal its reader (FeatureKeyDefaultsTests).
    @AppStorage("dropTray.notchDropEnabled") private var notchDropEnabled = true
    @AppStorage("dropTray.shakeEnabled") private var shakeEnabled = true
    @AppStorage("dropTray.shakeSensitivity") private var shakeSensitivity = "medium"

    private var selectedItems: [DropTrayStore.Item] {
        tray.items.filter { selection.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Khay thả"),
                    subtitle: L10n.t("Giữ file tạm để xử lý hàng loạt.")
                )

                if !notchEnabled {
                    SettingsSection {
                        SettingsLinkRow(
                            title: L10n.t("Notch đang tắt"),
                            subtitle: L10n.t("Khay sẽ không hiện ở notch cho tới khi bạn bật lại ở Giao diện notch."),
                            destination: .notchInterface
                        )
                    }
                }

                // Drop zone — generous target when empty, compact drop bar when items are staged.
                VStack(spacing: XFinderTokens.Space.tight) {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "arrow.down.doc.fill")
                        .font(XFinderTokens.Font.pageIcon)
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text(tray.items.isEmpty
                         ? L10n.t("Kéo thả nhiều tập tin vào đây để giữ tạm")
                         : "\(tray.items.count)\(L10n.t(" mục trong khay"))")
                        .font(XFinderTokens.Font.sectionTitle)
                    Text(tray.items.isEmpty
                         ? L10n.t("Có thể kéo ra bất kỳ lúc nào, hoặc chép/chuyển thẳng vào ngăn trình duyệt.")
                         : L10n.t("Thả thêm tệp vào đây, hoặc bấm chọn nhiều mục bên dưới để thao tác."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(L10n.t("Thêm tập tin…")) { pickFiles() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: tray.items.isEmpty ? 148 : 88)
                .padding(.vertical, XFinderTokens.Space.inline)
                .padding(.horizontal, XFinderTokens.Space.inline)
                .background(isTargeted ? XFinderTokens.Fill.focus : XFinderTokens.Fill.inset)
                .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
                .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5)))
                .padding(.horizontal, XFinderTokens.Space.page)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    tray.add(providers: providers)
                    return true
                }

                openingSection

                if !tray.items.isEmpty {
                    SettingsSection(
                        title: "\(L10n.t("Trong khay ("))\(tray.items.count))",
                        footer: L10n.t("Giữ ⌘ hoặc ⇧ khi bấm để chọn nhiều tệp. Tệp đã di chuyển, mất quyền hoặc chuyển thất bại vẫn được giữ lại kèm lý do.")
                    ) {
                        HStack(spacing: XFinderTokens.Space.tight) {
                            if selection.isMultiSelection {
                                Text("\(L10n.t("Đã chọn "))\(selection.count)\(L10n.t(" mục"))")
                                    .font(XFinderTokens.Font.rowValue)
                                    .foregroundColor(.accentColor)
                                Button(L10n.t("Bỏ chọn")) { selection.clear() }
                                    .buttonStyle(.plain)
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Button(L10n.t("Chọn tất cả")) { selection.selectAll(tray.items.map(\.id)) }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button(L10n.t("Kiểm tra trạng thái")) { tray.refreshStatuses() }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                            Spacer()
                            Button(showDetailGrid ? L10n.t("Thu gọn") : L10n.t("Xem chi tiết")) { showDetailGrid.toggle() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        .settingsRow()

                        if selection.isMultiSelection {
                            SettingsDivider()
                            multiSelectionActionBar
                                .settingsRow()
                        }

                        SettingsDivider()

                        if showDetailGrid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: XFinderTokens.Space.row)], spacing: XFinderTokens.Space.row) {
                                ForEach(tray.items) { item in
                                    DropTraySettingsTile(
                                        item: item,
                                        selected: selection.contains(item.id),
                                        dragPaths: dragPaths(startingFrom: item),
                                        onClick: { handleTileClick(item) },
                                        onQuickLook: { NotchSurfaceController.shared.quickLookTrayItems([item]) },
                                        onCopyToPane: { sendToPane(items: [item], copy: true) },
                                        onMoveToPane: { sendToPane(items: [item], copy: false) },
                                        onShare: { NotchSurfaceController.shared.shareTrayItems([item]) },
                                        onRemove: {
                                            tray.remove(item)
                                            selection.prune(validIDs: Set(tray.items.map(\.id)))
                                        }
                                    )
                                }
                            }
                            .settingsRow()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(tray.items.prefix(20)) { item in
                                    HStack(spacing: XFinderTokens.Space.tight) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                        VStack(alignment: .leading, spacing: XFinderTokens.Space.hairline) {
                                            Text(item.name)
                                                .font(XFinderTokens.Font.rowValue)
                                                .fileNameRowSafe()
                                            if let statusKey = item.status.statusKey {
                                                Text(statusText(for: item, key: statusKey))
                                                    .font(XFinderTokens.Font.caption)
                                                    .foregroundColor(item.status.isUnavailable ? .red : .orange)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            tray.remove(item)
                                            selection.prune(validIDs: Set(tray.items.map(\.id)))
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.vertical, XFinderTokens.Space.tight)
                                    .padding(.horizontal, XFinderTokens.Space.tight)
                                    .background(selection.contains(item.id) ? XFinderTokens.Fill.focus : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                                    .contentShape(Rectangle())
                                    .onTapGesture { handleTileClick(item) }
                                    Divider()
                                }
                                if tray.items.count > 20 {
                                    Text("\(L10n.t("…và "))\(tray.items.count - 20)\(L10n.t(" mục nữa"))")
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                        .padding(.top, XFinderTokens.Space.tight)
                                }
                            }
                            .settingsRow()
                        }
                    }

                    SettingsSection(title: L10n.t("Thao tác cho cả khay")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: XFinderTokens.Space.row)], spacing: XFinderTokens.Space.row) {
                            if let paneName = DropTrayBrowserBridge.activePaneName {   // XF-T41: the browser Shelf's two actions
                                trayButton("\(L10n.t("Chép vào ngăn: "))\(paneName)", icon: "doc.on.doc") { sendToPane(items: liveItemsStruct(), copy: true) }
                                trayButton("\(L10n.t("Chuyển vào ngăn: "))\(paneName)", icon: "folder") { sendToPane(items: liveItemsStruct(), copy: false) }
                            }
                            trayButton(L10n.t("Chia sẻ"), icon: "square.and.arrow.up") {
                                NotchSurfaceController.shared.shareTrayItems(liveItemsStruct())
                            }
                            trayButton(L10n.t("Xem nhanh"), icon: "eye") {
                                NotchSurfaceController.shared.quickLookTrayItems(liveItemsStruct())
                            }
                            trayButton(L10n.t("Đổi tên hàng loạt"), icon: "pencil") { DropTrayBrowserBridge.batchRename(liveItems().map(\.path)) }
                            trayButton(L10n.t("Di chuyển…"), icon: "folder.fill") { moveOrCopy(move: true) }
                            trayButton(L10n.t("Sao chép…"), icon: "doc.on.doc.fill") { moveOrCopy(move: false) }
                            trayButton(L10n.t("Nén ZIP"), icon: "archivebox.fill") { zipTray() }
                            trayButton(L10n.t("Mở tất cả"), icon: "arrow.up.forward.app.fill") { openAll() }
                            trayButton(L10n.t("Bỏ vào Rác"), icon: "trash.fill", destructive: true) { trashAll() }
                            trayButton(L10n.t("Dọn khay"), icon: "xmark.circle", destructive: true) {
                                tray.clear()
                                selection.clear()
                            }
                        }
                        .settingsRow()
                    }
                }

                if let activeJob = queue.queue.active {
                    let jobFraction: Double = activeJob.bytesTotal > 0
                        ? min(1, max(0, Double(activeJob.bytesDone) / Double(activeJob.bytesTotal)))
                        : (activeJob.itemsTotal > 0 ? min(1, max(0, Double(activeJob.itemsDone) / Double(activeJob.itemsTotal))) : 0)
                    SettingsSection(title: L10n.t("Hàng đợi thao tác tệp")) {
                        HStack(spacing: XFinderTokens.Space.inline) {
                            ProgressView(value: jobFraction)
                                .progressViewStyle(.linear)
                            Text("\(activeJob.itemsDone)/\(activeJob.itemsTotal)")
                                .font(XFinderTokens.Font.mono)
                                .foregroundColor(.secondary)
                        }
                        .settingsRow()
                    }
                }

                if let msg = outcome {
                    SettingsSection(title: L10n.t("Kết quả")) {
                        Text(msg)
                            .font(XFinderTokens.Font.rowValue)
                            .settingsRow()
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { tray.refreshStatuses() }
        .onChange(of: tray.items.map(\.id)) { _, ids in
            selection.prune(validIDs: Set(ids))
        }
    }

    private var multiSelectionActionBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Button {
                NotchSurfaceController.shared.shareTrayItems(selectedItems)
            } label: {
                Label(L10n.t("Chia sẻ"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)

            if let paneName = DropTrayBrowserBridge.activePaneName {
                Button {
                    sendToPane(items: selectedItems, copy: true)
                } label: {
                    Label("\(L10n.t("Chép vào ngăn: "))\(paneName)", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    sendToPane(items: selectedItems, copy: false)
                } label: {
                    Label("\(L10n.t("Chuyển vào ngăn: "))\(paneName)", systemImage: "folder")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            Button {
                NotchSurfaceController.shared.quickLookTrayItems(selectedItems)
            } label: {
                Label(L10n.t("Xem nhanh"), systemImage: "eye")
            }
            .buttonStyle(.bordered).controlSize(.small)

            Spacer()

            Button(L10n.t("Bỏ khỏi khay")) {
                tray.removePaths(selectedItems.map(\.path))
                selection.clear()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    /// The user comes here to choose how the tray appears when they need it while dragging files. Hover is owned
    /// by Giao diện notch (it drives every notch surface, not only the tray) — see `dropTray.hoverEnabled` there.
    private var openingSection: some View {
        SettingsSection(title: L10n.t("Mở khay")) {
            ToggleRow(title: L10n.t("Kéo file vào notch để mở khay"),
                      subtitle: L10n.t("Chỉ phản ứng với thao tác kéo tệp thật, không phải kéo chữ hay kéo cửa sổ."),
                      isOn: $notchDropEnabled)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Lắc khi đang kéo file để mở khay tại con trỏ"),
                      subtitle: L10n.t("Khay mở ngay dưới tay bạn và không tự đóng khi đang giữ tệp."),
                      isOn: $shakeEnabled)
                .settingsRow()
            if shakeEnabled {
                SettingsDivider()
                PickerRow(title: L10n.t("Độ nhạy lắc"), selection: $shakeSensitivity, width: 120) {
                    Text(L10n.t("Thấp")).tag("low")
                    Text(L10n.t("Vừa")).tag("medium")
                    Text(L10n.t("Cao")).tag("high")
                }
                .settingsRow()
            }
        }
    }

    private func handleTileClick(_ item: DropTrayStore.Item) {
        let flags = NSEvent.modifierFlags
        selection.click(
            item.id,
            in: tray.items.map(\.id),
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }

    private func dragPaths(startingFrom item: DropTrayStore.Item) -> [String] {
        if selection.contains(item.id) {
            return selectedItems.filter { $0.status.isActionable }.map(\.path)
        }
        return item.status.isActionable ? [item.path] : []
    }

    private func statusText(for item: DropTrayStore.Item, key: String) -> String {
        if let detail = item.status.failureDetail {
            return "\(L10n.t(key)): \(detail)"
        }
        return L10n.t(key)
    }

    private func trayButton(_ title: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(XFinderTokens.Font.rowValue)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, XFinderTokens.Space.hairline)
        }
        .buttonStyle(.bordered)
        .foregroundColor(destructive ? .red : .primary)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { tray.add(urls: panel.urls) }
    }

    private func liveItemsStruct() -> [DropTrayStore.Item] {
        tray.refreshStatuses()
        return tray.items.filter { $0.status.isActionable }
    }

    private func liveItems() -> [URL] {
        liveItemsStruct().map { URL(fileURLWithPath: $0.path) }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// XF-T41 — into the browser's active pane through `FileOperationQueue` (conflict sheet, progress, undo);
    /// moved items leave the tray ONLY after succeeding; failed/skipped/cancelled items stay in the tray.
    private func sendToPane(items: [DropTrayStore.Item], copy: Bool) {
        let paths = items.filter { $0.status.isActionable }.map(\.path)
        guard !paths.isEmpty else {
            outcome = L10n.t("Không có tệp hợp lệ để thao tác.")
            return
        }
        let started = DropTrayBrowserBridge.send(paths, copy: copy) { completion in
            let done = completion.succeededSources.count
            let failed = completion.failedReasons.count + completion.skippedSources.count
            let verb = copy ? L10n.t("đã sao chép") : L10n.t("đã di chuyển")
            if failed > 0 || completion.state == .cancelled {
                self.outcome = "\(verb) \(done)/\(paths.count)\(L10n.t(" mục — các mục thất bại vẫn được giữ trong khay."))"
            } else {
                self.outcome = "\(verb) \(done)\(L10n.t(" mục"))."
            }
        }
        if !started {
            outcome = L10n.t(FileOperationQueue.shared.lastErrorKey ?? "Không thể gửi sang ngăn trình duyệt hiện tại.")
        }
    }

    private func moveOrCopy(move: Bool) {
        guard let dest = chooseFolder() else { return }
        let paths = liveItems().map(\.path)
        guard !paths.isEmpty else {
            outcome = L10n.t("Không có tệp hợp lệ để thao tác.")
            return
        }
        let started = DropTrayBrowserBridge.enqueueDirect(move ? .move : .copy, paths: paths, destination: dest.path) { completion in
            let done = completion.succeededSources.count
            let failed = completion.failedReasons.count + completion.skippedSources.count
            self.history.record(kind: "other",
                                summary: "\(move ? L10n.t("Di chuyển") : L10n.t("Sao chép")) \(done) \(L10n.t("mục từ khay")) → “\(dest.lastPathComponent)”",
                                reversible: false)
            let verb = move ? L10n.t("đã di chuyển") : L10n.t("đã sao chép")
            self.outcome = "\(verb) \(done)\(L10n.t(" mục"))"
                + (failed > 0 ? ", \(failed)\(L10n.t(" thất bại (giữ lại trong khay)."))" : ".")
        }
        if !started {
            outcome = L10n.t(FileOperationQueue.shared.lastErrorKey ?? "Không thể gửi sang ngăn trình duyệt hiện tại.")
        }
    }

    private func zipTray() {
        guard let dest = chooseFolder() else { return }
        let items = liveItems()
        guard !items.isEmpty else { return }
        let base = dest.appendingPathComponent("Khay-\(Int(Date().timeIntervalSince1970)).zip")
        guard case .write(let archive) = ArchiveEngine.destination(
            base: base, policy: .keepBoth, exists: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        Task {
            // The shared runner: the old `ditto … src1 src2 dst` refused every tray with 2+ items.
            let result = await ArchiveRunner.compress(sources: items, format: .zip, output: archive)
            let ok: Bool
            if case .success = result { ok = true } else { ok = false }
            self.history.record(kind: "compress",
                           summary: ok ? "\(L10n.t("Nén "))\(items.count)\(L10n.t(" mục từ khay → "))\(archive.lastPathComponent)" : L10n.t("Nén khay thất bại"),
                           reversible: false)
            switch result {
            case .success: self.outcome = "\(L10n.t("Đã nén "))\(items.count)\(L10n.t(" mục → "))\(archive.lastPathComponent)."
            case .failure(let f): self.outcome = "\(L10n.t("Nén thất bại.")) \(L10n.t(f.messageKey)) \(f.detail ?? "")"
            }
        }
    }

    private func openAll() {
        let items = liveItems().prefix(10)
        for url in items { NSWorkspace.shared.open(url) }
        outcome = "\(L10n.t("Đã mở "))\(items.count)\(L10n.t(" mục."))"
    }

    private func trashAll() {
        let paths = liveItems().map(\.path)
        guard !paths.isEmpty else { return }
        let started = DropTrayBrowserBridge.enqueueDirect(.trash, paths: paths, destination: nil) { completion in
            let done = completion.succeededSources.count
            self.outcome = "\(L10n.t("Đã chuyển "))\(done)/\(paths.count)\(L10n.t(" mục vào Thùng rác."))"
        }
        if !started {
            outcome = L10n.t(FileOperationQueue.shared.lastErrorKey ?? "Không thể gửi sang ngăn trình duyệt hiện tại.")
        }
    }
}

/// Thumbnail + name + truthful status card inside `DropTrayDetailView`, reusing Quick Look thumbnails
/// and multi-file drag-out via `MultiFileDragSource`.
private struct DropTraySettingsTile: View {
    let item: DropTrayStore.Item
    let selected: Bool
    let dragPaths: [String]
    let onClick: () -> Void
    let onQuickLook: () -> Void
    let onCopyToPane: () -> Void
    let onMoveToPane: () -> Void
    let onShare: () -> Void
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        let url = URL(fileURLWithPath: item.path)
        VStack(spacing: XFinderTokens.Space.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(XFinderTokens.Fill.inset)
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 56, height: 56)
            .opacity(item.status.isUnavailable ? 0.45 : 1)
            .overlay {
                if !dragPaths.isEmpty {
                    MultiFileDragSource(paths: dragPaths, onClick: onClick)
                }
            }

            Text(item.name)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            if let statusKey = item.status.statusKey {
                Text(L10n.t(statusKey))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(item.status.isUnavailable ? .red : .orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(XFinderTokens.Space.tight)
        .background(selected ? XFinderTokens.Fill.focus : XFinderTokens.Fill.inset)
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile)
                .strokeBorder(selected ? Color.accentColor : XFinderTokens.Fill.hairline, lineWidth: selected ? 1.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(XFinderTokens.Space.hairline)
            .help(L10n.t("Bỏ khỏi khay"))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .contextMenu {
            if item.status.isActionable {
                Button(L10n.t("Xem nhanh"), action: onQuickLook)
                Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
                Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button(L10n.t("Chia sẻ"), action: onShare)
                if let paneName = DropTrayBrowserBridge.activePaneName {
                    Divider()
                    Button("\(L10n.t("Chép vào ngăn: "))\(paneName)", action: onCopyToPane)
                    Button("\(L10n.t("Chuyển vào ngăn: "))\(paneName)", action: onMoveToPane)
                }
                Divider()
            }
            Button(L10n.t("Bỏ khỏi khay"), action: onRemove)
        }
        .help(helpText)
        .task(id: item.path) {
            guard item.status.isActionable else { thumb = nil; return }
            thumb = await FileThumbnailer.thumbnail(for: url)
        }
    }

    private var helpText: String {
        guard let key = item.status.statusKey else { return item.path }
        if let detail = item.status.failureDetail {
            return "\(item.path)\n\(L10n.t(key)): \(detail)"
        }
        return "\(item.path)\n\(L10n.t(key))"
    }
}

/// Persisted shelf of staged file paths. Missing, unreadable, or failed-transfer files are kept
/// and flagged with an explicit reason so no file disappears silently.
@MainActor
@Observable
final class DropTrayStore {
    static let shared = DropTrayStore()

    struct Item: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var path: String
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
        var isDir: Bool
        var isMissing: Bool
        var status: DropTrayItemStatus = .ready

        init(id: UUID = UUID(), path: String, isDir: Bool, isMissing: Bool, status: DropTrayItemStatus = .ready) {
            self.id = id
            self.path = path
            self.isDir = isDir
            self.isMissing = isMissing
            self.status = status
        }

        private enum CodingKeys: String, CodingKey { case id, path, isDir, isMissing, status }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            path = try c.decode(String.self, forKey: .path)
            isDir = try c.decodeIfPresent(Bool.self, forKey: .isDir) ?? false
            isMissing = try c.decodeIfPresent(Bool.self, forKey: .isMissing) ?? false
            status = try c.decodeIfPresent(DropTrayItemStatus.self, forKey: .status) ?? (isMissing ? .movedOrMissing : .ready)
        }
    }

    /// Observation has no publishers; the Notch surface needs a plain callback to learn the count
    /// changed (same pattern as `NoteStore.onChange`).
    var onItemsChanged: (@MainActor (Int) -> Void)?
    private(set) var items: [Item] = [] {
        didSet { onItemsChanged?(items.count) }
    }
    private let key = "XFinder.DropTray"

    private init() { load() }

    /// Adds in ONE assignment: `items` has a `didSet` that tells the Notch surface the count changed,
    /// and appending per file fired one surface render per file (1 000 files ⇒ 1 000 passes, B1 review).
    /// Also de-duplicates within the batch itself, not only against what is already held.
    func add(urls: [URL]) {
        var seen = Set(items.map(\.path))
        var next = items
        let fm = FileManager.default
        for url in urls where seen.insert(url.path).inserted {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            next.append(Item(path: url.path, isDir: isDir.boolValue, isMissing: false, status: .ready))
        }
        items = Self.evaluatingStatuses(next)
        persist()
    }

    /// `NSItemProvider.loadObject` is asynchronous: the URLs arrive after the drop returns. Collect
    /// them all, add them in one batch, THEN call `completion` — so a caller that needs the new count
    /// (the Notch surface's "dropped" event) reads the real one, not the count from before the drop.
    func add(providers: [NSItemProvider], completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor in
            var urls: [URL] = []
            for p in providers {
                let url: URL? = await withCheckedContinuation { c in
                    _ = p.loadObject(ofClass: URL.self) { url, _ in c.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty {
                self.add(urls: urls)
            }
            completion?()
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func removePaths(_ paths: [String]) {
        let set = Set(paths)
        items.removeAll { set.contains($0.path) }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    /// Re-probes filesystem existence and read permission for every staged item, keeping prior
    /// transfer failure reasons intact while the file itself still exists and is readable.
    func refreshStatuses() {
        let updated = Self.evaluatingStatuses(items)
        if updated != items {
            items = updated
            persist()
        }
    }

    /// Reconciles the tray after a queued copy/move/trash job completes: ONLY succeeded moves/trashes
    /// leave the tray; failed, skipped, or cancelled items remain in the tray with their reason attached.
    func applyTransferOutcome(
        requestedPaths: [String],
        copy: Bool,
        completion: FileOperationQueue.JobCompletion
    ) {
        let outcome = DropTrayTransferReconciler.reconcile(
            requestedPaths: requestedPaths,
            copy: copy,
            succeededPaths: Set(completion.succeededSources),
            skippedPaths: Set(completion.skippedSources),
            failedReasons: completion.failedReasons,
            cancelled: completion.state == .cancelled
        )
        var next = items.filter { !outcome.pathsToRemove.contains($0.path) }
        for idx in next.indices {
            let path = next[idx].path
            if let reason = outcome.failureReasonsByPath[path] {
                next[idx].status = .transferFailed(L10n.t(reason))
            } else if outcome.clearedErrorPaths.contains(path) {
                next[idx].status = .ready
            }
        }
        items = Self.evaluatingStatuses(next)
        persist()
    }

    /// Evaluates existence, POSIX access denial, and readability in one pass so callers assign
    /// `items` once (one `didSet`), never once per element.
    private static func evaluatingStatuses(_ list: [Item]) -> [Item] {
        let fm = FileManager.default
        return list.map { item in
            var copy = item
            var st = stat()
            let statOK = lstat(item.path, &st) == 0
            let err = statOK ? 0 : errno
            let accessDenied = !statOK && (err == EACCES || err == EPERM)
            let exists = statOK || fm.fileExists(atPath: item.path)
            let readable = exists && fm.isReadableFile(atPath: item.path)
            if statOK {
                copy.isDir = (st.st_mode & S_IFMT) == S_IFDIR
            }
            let status = DropTrayStatusEvaluator.evaluate(
                exists: exists,
                isReadable: readable,
                accessDenied: accessDenied,
                transferError: item.status.failureDetail
            )
            copy.status = status
            copy.isMissing = status.isUnavailable
            return copy
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = Self.evaluatingStatuses(decoded)
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
