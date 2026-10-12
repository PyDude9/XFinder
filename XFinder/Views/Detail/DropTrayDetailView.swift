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

    // Master switch of the Notch surface (also the Features hub entry for this feature).
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    // The three ways to open the tray. Read at point of use by NotchSurfaceController; defaults
    // must equal its reader (FeatureKeyDefaultsTests). Two of these were dead keys until B1.
    @AppStorage("dropTray.hoverEnabled") private var hoverEnabled = true
    @AppStorage("dropTray.notchDropEnabled") private var notchDropEnabled = true
    @AppStorage("dropTray.shakeEnabled") private var shakeEnabled = true
    @AppStorage("dropTray.shakeSensitivity") private var shakeSensitivity = "medium"
    @AppStorage("notch.clipboardOnHover") private var clipboardOnHover = false
    // B4 live activities. Reader: LiveActivityMonitor (defaults must match — FeatureKeyDefaultsTests).
    @AppStorage("notch.activities") private var activities = true
    @AppStorage("notch.activity.power") private var actPower = true
    @AppStorage("notch.activity.network") private var actNetwork = true
    @AppStorage("notch.activity.capsLock") private var actCapsLock = true
    @AppStorage("notch.activity.bluetooth") private var actBluetooth = true
    @AppStorage("notch.activity.alerts") private var actAlerts = true
    @AppStorage("notch.activity.volume") private var actVolume = true
    // B6 Now Playing. Reader: NowPlayingMonitor (default must match — FeatureKeyDefaultsTests). Off by
    // default: it runs a helper process and rides a private framework, so the user opts in.
    @AppStorage("notch.nowPlaying") private var nowPlaying = false
    @State private var nowPlayingMonitor = NowPlayingMonitor.shared
    // B7 notch behaviour. Readers: NotchSurfaceController (defaults must match — FeatureKeyDefaultsTests).
    @AppStorage("notch.hideFromCapture") private var hideFromCapture = true
    @AppStorage("notch.pillOnPlainScreens") private var pillOnPlainScreens = true
    @AppStorage("notch.hoverSpeed") private var hoverSpeed = "medium"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(
                    icon: "tray.and.arrow.down",
                    title: L10n.t("Notch & Khay thả"),
                    subtitle: L10n.t("Giữ file tạm để xử lý hàng loạt."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(notchEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            Toggle("", isOn: $notchEnabled)
                                .labelsHidden()
                                .onChange(of: notchEnabled) { NotchSurfaceController.shared.applySettings() }
                        }
                    ))

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

                if notchEnabled {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    openingSection
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    notchBehaviourSection
                    activitiesSection
                    nowPlayingSection
                }

                if !tray.items.isEmpty {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)

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
                        .padding(.horizontal, XFinderTokens.Space.page)

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
                            .padding(.horizontal, XFinderTokens.Space.page)
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
                                    .padding(.horizontal, XFinderTokens.Space.page)
                                    .padding(.vertical, 4)
                                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                                }
                                if tray.items.count > 15 {
                                    Text("\(L10n.t("…và "))\(tray.items.count - 15)\(L10n.t(" mục nữa"))")
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                        .padding(.horizontal, XFinderTokens.Space.page)
                                }
                            }
                        }
                    }

                    Divider().padding(.horizontal, XFinderTokens.Space.page)

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
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                if let msg = outcome {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "checkmark.circle", title: L10n.t("Kết quả"))
                        Text(msg)
                            .font(XFinderTokens.Font.rowValue)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
    }

    /// The user comes here to choose how the tray appears when they need it. Three triggers, one row
    /// each; the sensitivity only exists while shaking is on.
    private var openingSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "rectangle.topthird.inset.filled",
                          title: L10n.t("Mở khay từ notch"),
                          subtitle: L10n.t("Khay sống ở notch: thu gọn khi không dùng, mở ra khi bạn cần."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Kéo file vào notch để mở khay"),
                          subtitle: L10n.t("Chỉ phản ứng với thao tác kéo tệp thật, không phải kéo chữ hay kéo cửa sổ."),
                          isOn: $notchDropEnabled)
                ToggleRow(title: L10n.t("Rê chuột vào notch để xem nhanh"),
                          subtitle: L10n.t("Dừng con trỏ ở notch một chút để hiện các tệp đang giữ. Khay trống thì không hiện gì."),
                          isOn: $hoverEnabled)
                ToggleRow(title: L10n.t("Lắc khi đang kéo file để mở khay tại con trỏ"),
                          subtitle: L10n.t("Khay mở ngay dưới tay bạn và không tự đóng khi đang giữ tệp."),
                          isOn: $shakeEnabled)
                ToggleRow(title: L10n.t("Rê chuột vào notch mở Clipboard khi khay trống"),
                          subtitle: L10n.t("Mặc định tắt: khay trống không bao giờ tự mở khi rê chuột. Bật thì dừng con trỏ ở notch sẽ mở trang Clipboard thay vì không làm gì."),
                          isOn: $clipboardOnHover)
                    .disabled(!hoverEnabled)
                if shakeEnabled {
                    PickerRow(title: L10n.t("Độ nhạy lắc"), selection: $shakeSensitivity, width: 120) {
                        Text(L10n.t("Thấp")).tag("low")
                        Text(L10n.t("Vừa")).tag("medium")
                        Text(L10n.t("Cao")).tag("high")
                    }
                }
                InlineNote(text: L10n.t("Trên màn hình không có notch, XFinder vẽ một notch ảo: các bề mặt dính mép trên, ở giữa thanh menu, y như ở notch thật; rê chuột vào giữa mép trên để xem các tệp đang giữ."))
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    /// The user comes here to tune how the notch surface behaves on this Mac: how fast a hover counts,
    /// whether a notch-less screen gets a pill, and whether recordings see it.
    private var notchBehaviourSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "rectangle.topthird.inset.filled",
                          title: L10n.t("Hành vi notch"),
                          subtitle: L10n.t("Áp dụng cho mọi thứ hiện ở notch: khay, clipboard, thông báo, bài đang phát."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Độ nhạy rê chuột")).font(XFinderTokens.Font.row)
                        Text(L10n.t("Con trỏ phải đứng yên ở notch bao lâu thì tính là rê vào: 0,12 · 0,25 · 0,5 giây."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $hoverSpeed) {
                        Text(L10n.t("Nhanh")).tag("fast")
                        Text(L10n.t("Vừa")).tag("medium")
                        Text(L10n.t("Chậm")).tag("slow")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    .onChange(of: hoverSpeed) { NotchSurfaceController.shared.applySettings() }
                }
                ToggleRow(title: L10n.t("Pill trên màn hình không có notch"),
                          subtitle: L10n.t("Màn hình ngoài / iMac: tệp đang giữ, hẹn giờ và bài đang phát hiện trong một viên thuốc nhỏ dính mép trên, giữa thanh menu. Chưa đo trên màn hình thật — chỉ hình học."),
                          isOn: $pillOnPlainScreens)
                    .onChange(of: pillOnPlainScreens) { NotchSurfaceController.shared.applySettings() }
                ToggleRow(title: L10n.t("Không hiện trong ảnh chụp, quay và chia sẻ màn hình"),
                          subtitle: L10n.t("Cửa sổ notch được đánh dấu không chia sẻ (sharingType none) nên screencapture, quay màn hình và chia sẻ qua Zoom/FaceTime không thấy nó. Đo được: kCGWindowSharingState = 0."),
                          isOn: $hideFromCapture)
                    .onChange(of: hideFromCapture) { NotchSurfaceController.shared.applySettings() }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    /// The user comes here to choose which short notices the notch may show.
    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "bell.badge",
                          title: L10n.t("Thông báo trên notch"),
                          subtitle: L10n.t("Thông báo ngắn hiện dưới notch vài giây rồi tự tắt; không bao giờ chen vào khi bạn đang mở khay."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Hiện thông báo trên notch"), isOn: $activities)
                    .onChange(of: activities) { LiveActivityMonitor.shared.applySettings() }
                if activities {
                    ToggleRow(title: L10n.t("Sạc và pin"), subtitle: L10n.t("Cắm, rút sạc, pin đầy, pin yếu (20%) và rất yếu (10%)."), isOn: $actPower)
                        .onChange(of: actPower) { LiveActivityMonitor.shared.applySettings() }
                    ToggleRow(title: L10n.t("Mất và có lại mạng"), isOn: $actNetwork)
                        .onChange(of: actNetwork) { LiveActivityMonitor.shared.applySettings() }
                    ToggleRow(title: L10n.t("Caps Lock"), subtitle: L10n.t("Cần quyền Trợ năng khi XFinder không ở phía trước."), isOn: $actCapsLock)
                        .onChange(of: actCapsLock) { LiveActivityMonitor.shared.applySettings() }
                    ToggleRow(title: L10n.t("Thiết bị Bluetooth kết nối, ngắt kết nối"), subtitle: L10n.t("Cần quyền Bluetooth."), isOn: $actBluetooth)
                        .onChange(of: actBluetooth) { LiveActivityMonitor.shared.applySettings() }
                    ToggleRow(title: L10n.t("Cảnh báo hệ thống"), subtitle: L10n.t("Cảnh báo từ trang Cảnh báo hiện ở notch thay vì góc trên bên phải."), isOn: $actAlerts)
                    ToggleRow(title: L10n.t("Âm lượng"), subtitle: L10n.t("Mức âm lượng thật từ CoreAudio, hiện song song HUD của macOS. Không có HUD độ sáng: trên máy này giá trị độ sáng đọc được bị kẹt nên sẽ phải bịa số."), isOn: $actVolume)
                        .onChange(of: actVolume) { LiveActivityMonitor.shared.applySettings() }
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    /// The user comes here to decide whether the notch shows what is playing — and to read, in plain
    /// words, what that costs and what it rests on.
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "music.note",
                          title: L10n.t("Đang phát trên notch"),
                          subtitle: L10n.t("Bài đang phát hiện dưới notch; rê chuột để xem và điều khiển, bấm để mở trang Đang phát trong khay."))
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Hiện bài đang phát ở notch"),
                          subtitle: L10n.t("Tên bài, nghệ sĩ, ảnh bìa và nút điều khiển cho app đang phát — kể cả trình duyệt. Mặc định tắt."),
                          isOn: $nowPlaying)
                    .onChange(of: nowPlaying) { NotchSurfaceController.shared.applySettings() }
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Trạng thái: ")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Text(L10n.t(nowPlayingMonitor.availability.messageKey)).font(XFinderTokens.Font.caption)
                    if let np = nowPlayingMonitor.liveSnapshot, np.hasTrack {
                        Text("· \(L10n.t("Đang phát: "))\(np.headline)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                InlineNote(text: L10n.t("Đọc qua MediaRemote, API riêng của Apple. Từ macOS 15.4 chỉ tiến trình do Apple ký mới đọc được, nên khi bật, XFinder nhờ /usr/bin/perl của hệ thống nạp một thư viện nhỏ và nhận dữ liệu qua pipe: thêm một tiến trình khoảng 18 MB, không polling. Apple có thể đóng đường này ở bất kỳ bản cập nhật nào — khi đó dòng trạng thái sẽ báo không khả dụng thay vì bịa. Nút điều khiển gửi lệnh trực tiếp từ XFinder."))
            }
            .padding(.horizontal, XFinderTokens.Space.page)
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
