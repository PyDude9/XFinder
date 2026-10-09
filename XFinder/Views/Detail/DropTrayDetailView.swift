import SwiftUI
import AppKit

/// Khay thả — a Drop-app-style shelf. Drag files onto the tray (or add via the
/// button); the tray holds them as staged bookmarks, then one click applies a
/// shared action to all: move, copy, compress (ZIP), move-to-trash, or open.
/// Persisted in UserDefaults so the shelf survives relaunch.
struct DropTrayDetailView: View {
    @State private var tray = DropTrayStore.shared
    @State private var history = ActionHistoryStore.shared
    @State private var isTargeted = false
    @State private var outcome: String? = nil
    @State private var showDetailGrid = true

    // Tai thỏ / notch — tạm ẩn theo yêu cầu (giữ key để bật lại sau).
    // Các @AppStorage này vẫn persist nhưng không render trong UI.
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("dropTray.shakeEnabled") private var shakeEnabled = true
    @AppStorage("dropTray.shakeSensitivity") private var shakeSensitivity = "medium"
    @AppStorage("dropTray.notchDropEnabled") private var notchDropEnabled = true
    @AppStorage("dropTray.hoverEnabled") private var hoverEnabled = true
    @AppStorage("dropTray.autoCloseDelay") private var autoCloseDelay = 3.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    icon: "tray.and.arrow.down",
                    title: L10n.t("Khay thả"),
                    subtitle: L10n.t("Giữ file tạm để xử lý hàng loạt."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(notchEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: $notchEnabled)
                                .labelsHidden()
                                .onChange(of: notchEnabled) { NotchDropController.shared.applySettings() }
                        }
                    ))

                // notchSettings — tạm ẩn (giữ engine, ẩn UI)

                // Drop zone
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 34))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text(tray.items.isEmpty
                         ? L10n.t("Kéo tập tin vào đây")
                         : "\(tray.items.count)\(L10n.t(" mục trong khay"))")
                        .font(.headline)
                    Text(L10n.t("hoặc"))
                        .font(.caption).foregroundColor(.secondary)
                    Button(L10n.t("Thêm tập tin…")) { pickFiles() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(isTargeted ? Color.accentColor.opacity(0.12)
                                       : Color(.controlBackgroundColor).opacity(0.6))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5)))
                .padding(.horizontal, 20)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    tray.add(providers: providers)
                    return true
                }

                if !tray.items.isEmpty {
                    SettingsCard(title: "Trong khay (\(tray.items.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(tray.items.count)\(L10n.t(" mục"))").font(.system(size: 11)).foregroundColor(.secondary)
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
                                                .font(.system(size: 22)).foregroundColor(.secondary)
                                            Text(item.name).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center)
                                            if item.isMissing {
                                                Text(L10n.t("(không còn tồn tại)")).font(.caption2).foregroundColor(.red)
                                            }
                                        }
                                        .frame(maxWidth: .infinity).padding(8)
                                        .background(Color(.controlBackgroundColor).opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                                VStack(spacing: 6) {
                                    ForEach(tray.items.prefix(15)) { item in
                                        HStack {
                                            Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                                .foregroundColor(.secondary).font(.caption)
                                            Text(item.name).font(.system(size: 12)).lineLimit(1)
                                                .truncationMode(.middle)
                                            if item.isMissing {
                                                Text(L10n.t("(không còn tồn tại)"))
                                                    .font(.caption2).foregroundColor(.red)
                                            }
                                            Spacer()
                                            Button { tray.remove(item) } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                    if tray.items.count > 15 {
                                        Text("\(L10n.t("…và "))\(tray.items.count - 15)\(L10n.t(" mục nữa"))")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SettingsCard(title: L10n.t("Thao tác cho cả khay")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            trayButton(L10n.t("Di chuyển…"), icon: "folder.fill") { moveOrCopy(move: true) }
                            trayButton(L10n.t("Sao chép…"), icon: "doc.on.doc.fill") { moveOrCopy(move: false) }
                            trayButton(L10n.t("Nén ZIP"), icon: "archivebox.fill") { zipTray() }
                            trayButton(L10n.t("Mở tất cả"), icon: "arrow.up.forward.app.fill") { openAll() }
                            trayButton(L10n.t("Bỏ vào Rác"), icon: "trash.fill", destructive: true) { trashAll() }
                            trayButton(L10n.t("Dọn khay"), icon: "xmark.circle", destructive: true) { tray.clear() }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let msg = outcome {
                    SettingsCard(title: L10n.t("Kết quả")) {
                        Text(msg).font(.system(size: 12))
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                } else {
                    Spacer().padding(.bottom, 20)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func trayButton(_ title: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .foregroundColor(destructive ? .red : .primary)
    }

    /// ShakePin-style summoning options.
    private var notchSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "cursorarrow.motionlines",
                          title: L10n.t("Cách mở khay"))

            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: L10n.t("Lắc để mở khay khi kéo file"), isOn: $shakeEnabled)
                    .onChange(of: shakeEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)

                HStack {
                    Text(L10n.t("Độ nhạy khi lắc")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $shakeSensitivity) {
                        Text(L10n.t("Thấp")).tag("low")
                        Text(L10n.t("Vừa")).tag("medium")
                        Text("Cao").tag("high")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(!notchEnabled || !shakeEnabled)
                }

                ToggleRow(title: L10n.t("Thả vào tai thỏ"),
                          subtitle: L10n.t("Kéo file vào vùng tai thỏ của màn hình để mở khay."),
                          isOn: $notchDropEnabled)
                    .onChange(of: notchDropEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)

                ToggleRow(title: L10n.t("Di chuột vào tai thỏ để mở khay"),
                          subtitle: L10n.t("Mở khay cả khi không kéo file — tiện để lấy lại file đã giữ."),
                          isOn: $hoverEnabled)
                    .onChange(of: hoverEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)
            }
            .padding(.horizontal, 20)

            SectionHeader(icon: "square.on.square", title: L10n.t("Giao diện"))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t("Vị trí khay")).font(.system(size: 13))
                    Spacer()
                    Text(L10n.t("Luôn ở tai thỏ")).font(.system(size: 12)).foregroundColor(.secondary)
                }
                Text(L10n.t("Khay luôn mở ngay dưới tai thỏ — một vị trí cố định để bạn nhớ thao tác, thay vì bám theo con trỏ."))
                    .font(.system(size: 11)).foregroundColor(.secondary)

                HStack {
                    Text(L10n.t("Tự đóng sau khi rời chuột")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $autoCloseDelay) {
                        Text(L10n.t("2 giây")).tag(2.0)
                        Text(L10n.t("3 giây")).tag(3.0)
                        Text(L10n.t("5 giây")).tag(5.0)
                        Text(L10n.t("10 giây")).tag(10.0)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .disabled(!notchEnabled)
                }
            }
            .padding(.horizontal, 20)
        }
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
        let archive = dest.appendingPathComponent("Khay-\(Int(Date().timeIntervalSince1970)).zip")
        Task {
            let ok = await Task.detached {
                DropTrayStore.runZip(sources: items, dest: archive)
            }.value
            self.history.record(kind: "compress",
                           summary: ok ? "\(L10n.t("Nén "))\(items.count)\(L10n.t(" mục từ khay → "))\(archive.lastPathComponent)" : L10n.t("Nén khay thất bại"),
                           reversible: false)
            self.outcome = ok ? "\(L10n.t("Đã nén "))\(items.count)\(L10n.t(" mục → "))\(archive.lastPathComponent)." : L10n.t("Nén thất bại.")
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

    private(set) var items: [Item] = []
    private let key = "XFinder.DropTray"

    private init() { load() }

    func add(urls: [URL]) {
        let existing = Set(items.map(\.path))
        let fm = FileManager.default
        for url in urls where !existing.contains(url.path) {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            items.append(Item(path: url.path, isDir: isDir.boolValue, isMissing: false))
        }
        refreshMissing()
        persist()
    }

    func add(providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.add(urls: [url]) }
            }
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
        let fm = FileManager.default
        for i in items.indices {
            items[i].isMissing = !fm.fileExists(atPath: items[i].path)
        }
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
    nonisolated static func runZip(sources: [URL], dest: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
            + sources.map(\.path) + [dest.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch { return false }
    }
}
