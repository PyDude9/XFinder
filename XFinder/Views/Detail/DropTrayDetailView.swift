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
                    title: "Khay thả",
                    subtitle: "Lắc khi đang kéo file, hoặc kéo file vào tai thỏ.",
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(notchEnabled ? "Bật" : "Tắt")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: $notchEnabled)
                                .labelsHidden()
                                .onChange(of: notchEnabled) { NotchDropController.shared.applySettings() }
                        }
                    ))

                notchSettings

                // Drop zone
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 34))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text(tray.items.isEmpty
                         ? "Kéo tập tin vào đây"
                         : "\(tray.items.count) mục trong khay")
                        .font(.headline)
                    Text("hoặc")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Thêm tập tin…") { pickFiles() }
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
                        VStack(spacing: 6) {
                            ForEach(tray.items.prefix(15)) { item in
                                HStack {
                                    Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                        .foregroundColor(.secondary).font(.caption)
                                    Text(item.name).font(.system(size: 12)).lineLimit(1)
                                        .truncationMode(.middle)
                                    if item.isMissing {
                                        Text("(không còn tồn tại)")
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
                                Text("…và \(tray.items.count - 15) mục nữa")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    SettingsCard(title: "Thao tác cho cả khay") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                            trayButton("Di chuyển…", icon: "folder.fill") { moveOrCopy(move: true) }
                            trayButton("Sao chép…", icon: "doc.on.doc.fill") { moveOrCopy(move: false) }
                            trayButton("Nén ZIP", icon: "archivebox.fill") { zipTray() }
                            trayButton("Mở tất cả", icon: "arrow.up.forward.app.fill") { openAll() }
                            trayButton("Bỏ vào Rác", icon: "trash.fill", destructive: true) { trashAll() }
                            trayButton("Dọn khay", icon: "xmark.circle", destructive: true) { tray.clear() }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let msg = outcome {
                    SettingsCard(title: "Kết quả") {
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
                          title: "Cách mở khay")

            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "Lắc để mở khay khi kéo file", isOn: $shakeEnabled)
                    .onChange(of: shakeEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)

                HStack {
                    Text("Độ nhạy khi lắc").font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $shakeSensitivity) {
                        Text("Thấp").tag("low")
                        Text("Vừa").tag("medium")
                        Text("Cao").tag("high")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(!notchEnabled || !shakeEnabled)
                }

                ToggleRow(title: "Thả vào tai thỏ",
                          subtitle: "Kéo file vào vùng tai thỏ của màn hình để mở khay.",
                          isOn: $notchDropEnabled)
                    .onChange(of: notchDropEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)

                ToggleRow(title: "Di chuột vào tai thỏ để mở khay",
                          subtitle: "Mở khay cả khi không kéo file — tiện để lấy lại file đã giữ.",
                          isOn: $hoverEnabled)
                    .onChange(of: hoverEnabled) { NotchDropController.shared.applySettings() }
                    .disabled(!notchEnabled)
            }
            .padding(.horizontal, 20)

            SectionHeader(icon: "square.on.square", title: "Giao diện")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vị trí khay").font(.system(size: 13))
                    Spacer()
                    Text("Luôn ở tai thỏ").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Text("Khay luôn mở ngay dưới tai thỏ — một vị trí cố định để bạn nhớ thao tác, thay vì bám theo con trỏ.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                HStack {
                    Text("Tự đóng sau khi rời chuột").font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $autoCloseDelay) {
                        Text("2 giây").tag(2.0)
                        Text("3 giây").tag(3.0)
                        Text("5 giây").tag(5.0)
                        Text("10 giây").tag(10.0)
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
                       summary: "\(move ? "Di chuyển" : "Sao chép") \(done) mục từ khay → “\(dest.lastPathComponent)”",
                       reversible: false)
        if move { tray.removePaths(items.map(\.path)) }
        outcome = "Đã \(move ? "di chuyển" : "sao chép") \(done) mục" + (failed > 0 ? ", \(failed) thất bại (trùng tên/lỗi)." : ".")
    }

    private func zipTray() {
        guard let dest = chooseFolder() else { return }
        let items = liveItems()
        guard !items.isEmpty else { return }
        let archive = dest.appendingPathComponent("Khay-\(Int(Date().timeIntervalSince1970)).zip")
        let ok = DropTrayStore.runZip(sources: items, dest: archive)
        history.record(kind: "compress",
                       summary: ok ? "Nén \(items.count) mục từ khay → \(archive.lastPathComponent)" : "Nén khay thất bại",
                       reversible: false)
        outcome = ok ? "Đã nén \(items.count) mục → \(archive.lastPathComponent)." : "Nén thất bại."
    }

    private func openAll() {
        let items = liveItems().prefix(10)
        for url in items { NSWorkspace.shared.open(url) }
        outcome = "Đã mở \(items.count) mục."
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
        outcome = "Đã chuyển \(done)/\(items.count) mục vào Thùng rác."
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
