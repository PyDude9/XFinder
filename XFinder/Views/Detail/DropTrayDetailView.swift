import SwiftUI
import AppKit

/// Khay thả — a Drop-app-style shelf. The user comes here to see and act on the files they are
/// holding, and to choose how the tray opens while dragging files. Drag files onto the tray (or add
/// via the button); the tray holds them as staged bookmarks, then one click applies a shared action to
/// all: move, copy, compress (ZIP), move-to-trash, or open. Persisted in UserDefaults so the shelf
/// survives relaunch. The notch SURFACE itself (master switch, hover, shape, pages) is a separate job —
/// see Giao diện notch (`NotchInterfaceDetailView`).
struct DropTrayDetailView: View {
    @State private var tray = DropTrayStore.shared
    @State private var history = ActionHistoryStore.shared
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(
                    icon: "tray.and.arrow.down",
                    title: L10n.t("Khay thả"),
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

                // Drop zone
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(XFinderTokens.Font.pageIcon)
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text(tray.items.isEmpty
                         ? L10n.t("Kéo tập tin vào đây")
                         : "\(tray.items.count)\(L10n.t(" mục trong khay"))")
                        .font(XFinderTokens.Font.sectionTitle)
                    Text(L10n.t("hoặc"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Button(L10n.t("Thêm tập tin…")) { pickFiles() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(isTargeted ? Color.accentColor.opacity(0.12) : XFinderTokens.Fill.inset)
                .cornerRadius(XFinderTokens.Radius.tile)
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
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(
                            icon: "tray.full",
                            title: "\(L10n.t("Trong khay ("))\(tray.items.count))",
                            subtitle: "\(tray.items.count)\(L10n.t(" mục"))"
                        )
                        HStack {
                            Spacer()
                            Button(showDetailGrid ? L10n.t("Thu gọn") : L10n.t("Xem chi tiết")) { showDetailGrid.toggle() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }

                        // Inline grid ngay dưới header — không mở window lung tung.
                        if showDetailGrid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(tray.items) { item in
                                    VStack(spacing: 6) {
                                        Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                            .font(XFinderTokens.Font.sectionTitle).foregroundColor(.secondary)
                                        Text(item.name)
                                            .font(XFinderTokens.Font.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                        if item.isMissing {
                                            Text(L10n.t("(không còn tồn tại)")).font(XFinderTokens.Font.caption).foregroundColor(.red)
                                        }
                                    }
                                    .frame(maxWidth: .infinity).padding(8)
                                    .background(XFinderTokens.Fill.inset)
                                    .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
                                    .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile)
                                        .strokeBorder(XFinderTokens.Fill.hairline, lineWidth: 1))
                                    .overlay(
                                        HStack {
                                            Spacer()
                                            Button { tray.remove(item) } label: {
                                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                            }.buttonStyle(.plain).padding(4)
                                        }.frame(maxHeight: .infinity, alignment: .top)
                                    )
                                }
                            }
                        } else {
                            // Compact list fallback khi thu gọn.
                            VStack(spacing: 0) {
                                ForEach(tray.items.prefix(15)) { item in
                                    HStack {
                                        Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                            .foregroundColor(.secondary).font(XFinderTokens.Font.caption)
                                        Text(item.name)
                                            .font(XFinderTokens.Font.rowValue)
                                            .fileNameRowSafe()
                                        if item.isMissing {
                                            Text(L10n.t("(không còn tồn tại)"))
                                                .font(XFinderTokens.Font.caption).foregroundColor(.red)
                                        }
                                        Spacer()
                                        Button { tray.remove(item) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                                if tray.items.count > 15 {
                                    Text("\(L10n.t("…và "))\(tray.items.count - 15)\(L10n.t(" mục nữa"))")
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "bolt.fill", title: L10n.t("Thao tác cho cả khay"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            trayButton(L10n.t("Di chuyển…"), icon: "folder.fill") { moveOrCopy(move: true) }
                            trayButton(L10n.t("Sao chép…"), icon: "doc.on.doc.fill") { moveOrCopy(move: false) }
                            trayButton(L10n.t("Nén ZIP"), icon: "archivebox.fill") { zipTray() }
                            trayButton(L10n.t("Mở tất cả"), icon: "arrow.up.forward.app.fill") { openAll() }
                            trayButton(L10n.t("Bỏ vào Rác"), icon: "trash.fill", destructive: true) { trashAll() }
                            trayButton(L10n.t("Dọn khay"), icon: "xmark.circle", destructive: true) { tray.clear() }
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                if let msg = outcome {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "checkmark.circle", title: L10n.t("Kết quả"))
                        Text(msg)
                            .font(XFinderTokens.Font.rowValue)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
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

    private func trayButton(_ title: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(XFinderTokens.Font.rowValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
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

    private func liveItems() -> [URL] {
        tray.items.compactMap { item -> URL? in
            guard !item.isMissing else { return nil }
            return URL(fileURLWithPath: item.path)
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func moveOrCopy(move: Bool) {
        guard let dest = chooseFolder() else { return }
        let items = liveItems()
        var done = 0, failed = 0
        let fm = FileManager.default
        for src in items {
            let target = dest.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: target.path) { failed += 1; continue }
            do {
                if move { try fm.moveItem(at: src, to: target) }
                else { try fm.copyItem(at: src, to: target) }
                done += 1
            } catch { failed += 1 }
        }
        history.record(kind: "other",
                       summary: "\(move ? L10n.t("Di chuyển") : L10n.t("Sao chép")) \(done) \(L10n.t("mục từ khay")) → “\(dest.lastPathComponent)”",
                       reversible: false)
        if move { tray.removePaths(items.map(\.path)) }
        let verb = move ? L10n.t("đã di chuyển") : L10n.t("đã sao chép")
        outcome = "\(verb) \(done)\(L10n.t(" mục"))"
            + (failed > 0 ? ", \(failed)\(L10n.t(" thất bại (trùng tên/lỗi)."))" : ".")
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
        let items = liveItems()
        var done = 0
        for url in items {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                done += 1
            } catch { continue }
        }
        history.recordTrash(urls: items)
        tray.removePaths(items.map(\.path))
        outcome = "\(L10n.t("Đã chuyển "))\(done)/\(items.count)\(L10n.t(" mục vào Thùng rác."))"
    }
}

/// Persisted shelf of staged file paths. Missing files are kept but flagged.
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
            next.append(Item(path: url.path, isDir: isDir.boolValue, isMissing: false))
        }
        items = Self.markingMissing(next)
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
            self.add(urls: urls)
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

    private func refreshMissing() {
        items = Self.markingMissing(items)
    }

    /// Mutates a copy, so the caller assigns `items` once (one `didSet`), never once per element.
    private static func markingMissing(_ list: [Item]) -> [Item] {
        let fm = FileManager.default
        return list.map { var i = $0; i.isMissing = !fm.fileExists(atPath: i.path); return i }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
            refreshMissing()
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Synchronous ZIP via ditto (small tray ops; runs on main-thread caller —
    /// view calls it after picking a folder, files are few).
}
