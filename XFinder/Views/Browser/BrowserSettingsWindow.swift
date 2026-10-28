import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Compatibility entry point: browser commands now navigate to the unified XFinder settings page.
@MainActor
final class BrowserSettingsWindowController {
    static let shared = BrowserSettingsWindowController()
    fileprivate let state = BrowserSettingsState()
    private init() {}

    enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, sidebar, cloud, advanced, keyboard, inspector, search, privacy
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .general: return "Chung"
            case .appearance: return "Giao diện"
            case .sidebar: return "Sidebar"
            case .cloud: return "Đám mây"
            case .advanced: return "Nâng cao"
            case .keyboard: return "Bàn phím"
            case .inspector: return "Ngăn thông tin"
            case .search: return "Tìm kiếm"
            case .privacy: return "Quyền riêng tư"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .sidebar: return "sidebar.left"
            case .cloud: return "cloud"
            case .advanced: return "slider.horizontal.3"
            case .keyboard: return "keyboard"
            case .inspector: return "sidebar.right"
            case .search: return "magnifyingglass"
            case .privacy: return "hand.raised"
            }
        }
    }

    func show(tab: Tab? = nil) {
        if let tab { state.selected = tab }
        AppState.shared.navigate(to: .fileBrowser)
    }
}

@MainActor @Observable
fileprivate final class BrowserSettingsState {
    var selected: BrowserSettingsWindowController.Tab = .general
}

/// Embedded in the File Browser page; no nested sidebar or independently managed window.
struct BrowserSettingsContentView: View {
    private let state = BrowserSettingsWindowController.shared.state

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
            Picker(L10n.t("Nhóm cài đặt"), selection: Binding(
                get: { state.selected }, set: { state.selected = $0 }
            )) {
                ForEach(BrowserSettingsWindowController.Tab.allCases) { tab in
                    Label(L10n.t(tab.titleKey), systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.menu)
            .font(XFinderTokens.Font.row)
            .padding(.horizontal, XFinderTokens.Space.page)
            switch state.selected {
            case .general: GeneralSettingsTab()
            case .appearance: AppearanceSettingsTab()
            case .sidebar: SidebarSettingsTab()
            case .cloud: CloudSettingsTab()
            case .advanced: AdvancedSettingsTab()
            case .keyboard: KeyboardSettingsTab()
            case .inspector: InspectorSettingsTab()
            case .search: SearchSettingsTab()
            case .privacy: PrivacySettingsTab()
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("fileBrowser.newWindowTarget") private var newWindowTarget = "home"
    @AppStorage("fileBrowser.newWindowCustomPath") private var newWindowCustomPath = ""
    @AppStorage("fileBrowser.reopenWindows") private var reopenWindows = true
    @AppStorage("fileBrowser.returnOpens") private var returnOpens = false
    @AppStorage("fileBrowser.downloadsHotkey") private var downloadsHotkey = false
    @AppStorage("fileBrowser.cutWithCmdX") private var cutWithCmdX = false

    var body: some View {
        SettingsSection(title: L10n.t("Cửa sổ mới hiện")) {
            HStack {
                Text(L10n.t("Cửa sổ mới hiện")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $newWindowTarget) {
                    Text(L10n.t("Thư mục nhà")).tag("home")
                    Text(L10n.t("Màn hình nền")).tag("desktop")
                    Text(L10n.t("Tài liệu")).tag("documents")
                    Text(L10n.t("Thư mục Tải về")).tag("downloads")
                    Text(L10n.t("Mục gần đây")).tag("recents")
                    Text(L10n.t("Thư mục khác…")).tag("custom")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .settingsRow()
            if newWindowTarget == "custom" {
                SettingsDivider()
                HStack {
                    Text(newWindowCustomPath.isEmpty ? L10n.t("Chưa chọn thư mục") : newWindowCustomPath)
                        .font(XFinderTokens.Font.rowValue)
                        .foregroundColor(newWindowCustomPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.t("Chọn…")) { chooseCustomPath() }
                        .controlSize(.small)
                }
                .settingsRow()
            }
        }

        SettingsSection(title: L10n.t("Khi mở")) {
            ToggleRow(title: L10n.t("Mở lại cửa sổ…"),
                      subtitle: L10n.t("Cửa sổ, tab, ngăn và lịch sử Lùi/Tiến quay lại khi XFinder mở. Giữ Shift khi mở để bỏ qua lần đó."),
                      isOn: $reopenWindows)
                .settingsRow()
        }

        SettingsSection(title: L10n.t("Thói quen Windows (tuỳ chọn)")) {
            ToggleRow(title: L10n.t("Return đổi tên / mở"),
                      subtitle: L10n.t("Bật: Return mở mục đã chọn, đổi tên chuyển sang F2 hoặc menu Sửa. Tắt: Return đổi tên như Finder."),
                      isOn: $returnOpens)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("⌘X để cắt"),
                      subtitle: L10n.t("Kiểu Windows: ⌘X đánh dấu cắt, ⌘V nơi khác sẽ chuyển thay vì chép."),
                      isOn: $cutWithCmdX)
                .settingsRow()
        }

        SettingsSection(title: L10n.t("Khay Tải về")) {
            ToggleRow(title: L10n.t("Mở khay Tải về bằng ⌃⌥⌘D"), isOn: $downloadsHotkey)
                .settingsRow()
                .onChange(of: downloadsHotkey) { _, _ in BrowserDownloadsController.shared.applySettings() }
            if downloadsHotkey && !BrowserDownloadsController.shared.hotkeyRegistered {
                Text(L10n.t("Không đăng ký được phím tắt. Một ứng dụng khác có thể đang dùng tổ hợp này."))
                    .font(XFinderTokens.Font.caption).foregroundStyle(.secondary).settingsRow()
            }
            SettingsDivider()
            Button(L10n.t("Mở khay Tải về")) { BrowserDownloadsController.shared.togglePanel() }.settingsRow()
        }

        SettingsSection(title: L10n.t("Cập nhật phần mềm")) {
            HStack {
                Text(L10n.t("Cập nhật phần mềm trong bản này theo XFinder")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                Spacer()
            }
            .settingsRow()
        }
    }

    private func chooseCustomPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("Chọn thư mục cửa sổ mới sẽ mở.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newWindowCustomPath = url.path
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @AppStorage("fileBrowser.showLocationBar") private var showLocationBar = true
    @AppStorage("fileBrowser.showPathBar") private var showPathBar = true
    @AppStorage("fileBrowser.showStatusBar") private var showStatusBar = true
    /// XF-T32 W3 — same key/default as `BrowserSettings.paneFocusStyle`.
    @AppStorage("fileBrowser.paneFocusStyle") private var paneFocusStyle = "dim"
    @AppStorage("fileBrowser.showLearnButton") private var showLearnButton = true

    var body: some View {
        SettingsSection(title: L10n.t("Hiện trong cửa sổ")) {
            ToggleRow(title: L10n.t("Location Bar"), isOn: $showLocationBar).settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Path Bar"), isOn: $showPathBar).settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Status Bar"), isOn: $showStatusBar).settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Hiện nút Học sử dụng"), isOn: $showLearnButton).settingsRow()
            SettingsDivider()
            PickerRow(title: L10n.t("Làm nổi ngăn đang dùng"), selection: $paneFocusStyle, width: XFinderTokens.PaneChrome.focusPickerWidth) {
                Text(L10n.t("Làm mờ ngăn khác")).tag("dim")
                Text(L10n.t("Viền ngăn đang dùng")).tag("outline")
            }
            .settingsRow()
        }

    }
}

// MARK: - Inspector

private struct InspectorSettingsTab: View {
    @AppStorage("fileBrowser.showPreview") private var inspectorVisible = false
    @AppStorage("fileBrowser.previewShowMore") private var inspectorShowMore = false

    var body: some View {
        SettingsSection(title: L10n.t("Ngăn thông tin")) {
            ToggleRow(title: L10n.t("Hiện ngăn xem trước"), isOn: $inspectorVisible)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Hiện thêm thông tin"),
                      subtitle: L10n.t("Áp dụng trong thẻ Thông tin của ngăn xem trước."),
                      isOn: $inspectorShowMore)
                .disabled(!inspectorVisible)
                .settingsRow()
        }
    }
}

// MARK: - Sidebar

private struct SidebarSettingsTab: View {
    @AppStorage("fileBrowser.sidebar.favorites") private var favorites = true
    @AppStorage("fileBrowser.sidebar.iCloud") private var iCloud = true
    @AppStorage("fileBrowser.sidebar.recents") private var recents = true
    @AppStorage("fileBrowser.sidebar.airDrop") private var airDrop = true
    @AppStorage("fileBrowser.sidebar.hardDisks") private var hardDisks = true
    @AppStorage("fileBrowser.sidebar.externalDisks") private var externalDisks = true
    @AppStorage("fileBrowser.sidebar.cloudStorage") private var cloudStorage = true
    @AppStorage("fileBrowser.sidebar.connectedServers") private var connectedServers = true
    @AppStorage("fileBrowser.sidebar.bonjour") private var bonjour = false
    @AppStorage("fileBrowser.sidebar.recentTags") private var recentTags = true
    @AppStorage("fileBrowser.sidebar.groupLocationsByType") private var groupByType = false
    @AppStorage("fileBrowser.sidebar.highlightCurrent") private var highlightCurrent = false
    @State private var sidebarLayout = BrowserSettings.sidebarLayout
    @State private var hiddenVolumeNames: [String: String] = [:]

    var body: some View {
        Group {
            SettingsSection(title: L10n.t("Hiện trong sidebar")) {
                ToggleRow(title: L10n.t("Mục ưa thích"), isOn: $favorites).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("iCloud Drive"), isOn: $iCloud).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Mục gần đây"), isOn: $recents).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("AirDrop"), isOn: $airDrop).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Ổ trong máy"), isOn: $hardDisks).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Ổ ngoài"), isOn: $externalDisks).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Đám mây"), isOn: $cloudStorage).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Máy chủ đã nối"), isOn: $connectedServers).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Máy Bonjour"), isOn: $bonjour).settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Thẻ gần đây"), isOn: $recentTags).settingsRow()
            }

            SettingsSection(title: L10n.t("Tuỳ chọn")) {
                ToggleRow(title: L10n.t("Nhóm Vị trí theo loại"),
                          subtitle: L10n.t("Tách Vị trí thành Trong máy / Ngoài / Đám mây / Mạng."),
                          isOn: $groupByType)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Tô sáng vị trí chứa thư mục hiện tại"), isOn: $highlightCurrent)
                    .settingsRow()
            }

            if !sidebarLayout.hiddenVolumeUUIDs.isEmpty {
                SettingsSection(title: L10n.t("Ổ đã ẩn"),
                                footer: L10n.t("Ổ bị ẩn khỏi mục Vị trí của sidebar — vẫn gắn vào máy bình thường.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        let sorted = Array(sidebarLayout.hiddenVolumeUUIDs).sorted()
                        ForEach(sorted, id: \.self) { uuid in
                            HStack {
                                Image(systemName: "externaldrive").foregroundColor(.secondary).font(XFinderTokens.Font.caption)
                                Text(SidebarSources.shared.volumes.first { $0.uuid == uuid }?.name
                                     ?? hiddenVolumeNames[uuid] ?? L10n.t("Ổ chưa gắn vào máy")).font(XFinderTokens.Font.rowValue)
                                Spacer()
                                Button(L10n.t("Khôi phục")) {
                                    var layout = BrowserSettings.sidebarLayout
                                    layout.showVolume(uuid: uuid)
                                    BrowserSettings.sidebarLayout = layout
                                    SpaceController.shared.sidebarDidChange(layout)
                                    sidebarLayout = layout
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .settingsRow()
                            if uuid != sorted.last { SettingsDivider() }
                        }
                    }
                }
            }
        }
        .onChange(of: SpaceController.shared.active.sidebar, initial: true) { _, layout in
            sidebarLayout = layout
        }
    }
}

// MARK: - Cloud

/// XF-T30 W8 — Settings ▸ Cloud: per-provider status (installed / running / account), Open app, Check Again, Hide in
/// XFinder. Contract §W8 "không OAuth, không đọc token" — every state below comes from LaunchServices (bundle id →
/// installed app URL) and `NSRunningApplication` (process list), never a provider SDK/login. "Hide in XFinder" never
/// disconnects the provider's own app or touches its sync folder — it only removes that provider's sidebar rows,
/// same spirit as the master "Hiện đám mây trong sidebar" toggle but scoped to one provider.
private struct CloudProviderStatus: Equatable {
    enum State: Equatable { case notInstalled, installedNoAccount(running: Bool), connected(running: Bool) }
    let bundleID: String
    let name: String
    var state: State
    /// Non-nil only for a provider the folder scan under `~/Library/CloudStorage` actually found (the closest this
    /// app comes to "has an account", since it never logs into the provider itself — contract: "không đọc token").
    var accountLabel: String?
}

private struct CloudSettingsTab: View {
    @AppStorage("fileBrowser.sidebar.cloudStorage") private var showInSidebar = true
    @State private var googleDrive = CloudProviderStatus(bundleID: "com.google.drivefs", name: "Google Drive", state: .notInstalled, accountLabel: nil)
    @State private var dropbox = CloudProviderStatus(bundleID: "com.getdropbox.dropbox", name: "Dropbox", state: .notInstalled, accountLabel: nil)
    @State private var otherProviderFolders: [String] = []
    @State private var hiddenProviders: Set<String> = CloudHiddenProviders.load()

    var body: some View {
        SettingsSection(title: L10n.t("Đám mây trong sidebar")) {
            ToggleRow(title: L10n.t("Hiện đám mây trong sidebar"),
                      subtitle: L10n.t("Cùng công tắc với Sidebar ▸ Đám mây."),
                      isOn: $showInSidebar)
                .settingsRow()
        }

        SettingsSection(title: "Google Drive") {
            providerRow(googleDrive) { toggleHidden(googleDrive.bundleID) }
        }

        SettingsSection(title: "Dropbox") {
            providerRow(dropbox) { toggleHidden(dropbox.bundleID) }
        }

        SettingsSection(title: L10n.t("Nhà cung cấp đám mây khác"),
                        footer: L10n.t("Đọc từ ~/Library/CloudStorage — đăng nhập và đồng bộ qua ứng dụng riêng của mỗi hãng, XFinder không có OAuth riêng.")) {
            if otherProviderFolders.isEmpty {
                Text(L10n.t("Chưa phát hiện nhà cung cấp đám mây nào khác."))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    .settingsRow()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(otherProviderFolders, id: \.self) { name in
                        HStack {
                            Image(systemName: "cloud").foregroundColor(.secondary).font(XFinderTokens.Font.caption)
                            Text(name).font(XFinderTokens.Font.rowValue).lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .settingsRow()
                        if name != otherProviderFolders.last { SettingsDivider() }
                    }
                }
            }
        }
        .onAppear(perform: reloadAll)
    }

    @ViewBuilder
    private func providerRow(_ status: CloudProviderStatus, onToggleHidden: @escaping () -> Void) -> some View {
        let isHidden = hiddenProviders.contains(status.bundleID)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(statusLineText(status, isHidden: isHidden))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                Spacer()
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                switch status.state {
                case .notInstalled:
                    Button(L10n.t("Tải ") + status.name + L10n.t("…")) { openDownloadPage(for: status) }
                        .controlSize(.small)
                case .installedNoAccount:
                    Button(L10n.t("Mở ") + status.name) { openApp(bundleID: status.bundleID) }
                        .controlSize(.small)
                case .connected:
                    Button(L10n.t("Mở ") + status.name) { openApp(bundleID: status.bundleID) }
                        .controlSize(.small)
                    Button(isHidden ? L10n.t("Hiện") : L10n.t("Ẩn trong XFinder")) { onToggleHidden() }
                        .controlSize(.small)
                }
                Button(L10n.t("Kiểm lại")) { reloadAll() }
                    .controlSize(.small)
                Spacer()
            }
            .settingsRow()
        }
    }

    /// Spec §4: not-installed / installed-no-account / connected, each with a plain-language status line — never a
    /// "Disconnect" control anywhere (contract: "never disconnects").
    private func statusLineText(_ status: CloudProviderStatus, isHidden: Bool) -> String {
        switch status.state {
        case .notInstalled:
            return status.name + L10n.t(" chưa được cài.")
        case .installedNoAccount(let running):
            let runningPart = running ? L10n.t("đang chạy") : L10n.t("chưa chạy")
            return status.name + L10n.t(" đã cài, ") + runningPart + L10n.t(", chưa thấy thư mục đồng bộ.")
        case .connected(let running):
            let runningPart = running ? L10n.t("đang chạy") : L10n.t("chưa chạy")
            var line = status.name + L10n.t(" đã cài, ") + runningPart
            if let account = status.accountLabel { line += L10n.t(" — ") + account }
            if isHidden { line += L10n.t(" (đang ẩn trong XFinder)") }
            return line
        }
    }

    private func toggleHidden(_ bundleID: String) {
        if hiddenProviders.contains(bundleID) {
            hiddenProviders.remove(bundleID)
        } else {
            hiddenProviders.insert(bundleID)
        }
        CloudHiddenProviders.save(hiddenProviders)
    }

    private func openApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openDownloadPage(for status: CloudProviderStatus) {
        let urlString = status.bundleID == "com.google.drivefs"
            ? "https://www.google.com/drive/download/"
            : "https://www.dropbox.com/install"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// LaunchServices (`urlForApplication(withBundleIdentifier:)`) and the running-process list are both disk/IPC
    /// reads — off the main thread (CLAUDE.md rule 14), same pattern as `PrivacySettingsTab.recheckFullDiskAccess`.
    private func reloadAll() {
        Task.detached(priority: .utility) {
            let googleInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.drivefs") != nil
            let dropboxInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.getdropbox.dropbox") != nil
            let googleRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.drivefs").isEmpty
            let dropboxRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.getdropbox.dropbox").isEmpty

            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
            let folderNames = (try? FileManager.default.contentsOfDirectory(atPath: root.path).sorted()) ?? []
            let parsed = folderNames.compactMap { CloudProviders.parse(folderName: $0, root: root.path) }
            let googleAccounts = parsed.filter { $0.kind == .googleDrive }.map(\.displayName)
            let dropboxAccounts = parsed.filter { $0.kind == .dropbox }.map(\.displayName)
            let otherNames = parsed.filter { $0.kind != .googleDrive && $0.kind != .dropbox }.map(\.displayName).sorted()

            await MainActor.run {
                googleDrive.state = !googleInstalled ? .notInstalled
                    : (googleAccounts.isEmpty ? .installedNoAccount(running: googleRunning) : .connected(running: googleRunning))
                googleDrive.accountLabel = googleAccounts.first
                dropbox.state = !dropboxInstalled ? .notInstalled
                    : (dropboxAccounts.isEmpty ? .installedNoAccount(running: dropboxRunning) : .connected(running: dropboxRunning))
                dropbox.accountLabel = dropboxAccounts.first
                otherProviderFolders = otherNames
            }
        }
    }
}

/// Per-provider "Hide in XFinder" (spec §4: a provider stays installed/synced on disk, only its sidebar rows
/// disappear). A plain `Set<String>` of bundle ids in one key — not a `FeatureKeyDefaultsTests` row candidate, same
/// as `BrowserSettings.indexRoots` above it: not a feature toggle, a per-item preference with no single default
/// that a view's `@AppStorage` needs to match.
enum CloudHiddenProviders {
    private static let key = "fileBrowser.cloud.hiddenProviders"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @AppStorage("fileBrowser.showAllExtensions") private var showAllExtensions = false
    @AppStorage("fileBrowser.showHidden") private var showHidden = false
    @AppStorage("fileBrowser.foldersFirst") private var foldersFirst = false
    @AppStorage("fileBrowser.search.defaultScope") private var searchScope = "mac"
    @AppStorage("fileBrowser.defaultView") private var defaultView = "list"

    var body: some View {
        SettingsSection(title: L10n.t("Hiển thị tệp")) {
            HStack {
                Text(L10n.t("Kiểu xem của ngăn mới")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $defaultView) {
                    Text(L10n.t("Xem dạng biểu tượng")).tag("icons")
                    Text(L10n.t("Xem dạng danh sách")).tag("list")
                    Text(L10n.t("Xem dạng cột")).tag("columns")
                    Text(L10n.t("Xem dạng gallery")).tag("gallery")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Hiện mọi đuôi tệp"),
                      subtitle: L10n.t("Trừ tệp tự đặt cờ ẩn đuôi riêng (Lấy thông tin ▸ Tên & Đuôi)."),
                      isOn: $showAllExtensions)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Hiện tệp ẩn"), isOn: $showHidden).settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Thư mục lên đầu khi sắp theo tên"), isOn: $foldersFirst).settingsRow()
        }

        SettingsSection(title: L10n.t("Khi tìm kiếm")) {
            HStack {
                Text(L10n.t("Phạm vi tìm mặc định")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $searchScope) {
                    Text(L10n.t("Máy này")).tag("mac")
                    Text(L10n.t("Thư mục hiện tại")).tag("folder")
                    Text(L10n.t("Dùng phạm vi tìm trước")).tag("previous")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .settingsRow()
        }
    }
}

// MARK: - Keyboard

private struct KeyboardSettingsTab: View {
    @State private var bindings = BrowserSettings.keyBindings
    @State private var query = ""
    @State private var recording: BrowserCommand?
    @State private var recordingExtra = false
    @State private var conflict: (command: BrowserCommand, chord: KeyChord, extra: Bool)?
    @State private var importErrors: [KeyBindings.ImportError] = []
    @AppStorage("fileBrowser.tabSwitchesPanes") private var tabSwitchesPanes = false
    @AppStorage("fileBrowser.mouseBackForward") private var mouseBackForward = "on"

    private var filteredCommands: [BrowserCommand] {
        let all = BrowserCommand.allCases
        guard !query.isEmpty else { return all }
        let needle = query.lowercased()
        return all.filter { command in
            let title = L10n.t(BrowserCommands.titleKey(command)).lowercased()
            if title.contains(needle) { return true }
            if let chord = bindings.binding(for: command).primary { return BrowserCommands.display(chord).lowercased().contains(needle) }
            return false
        }
    }

    var body: some View {
        SettingsSection(title: L10n.t("Hồ sơ phím tắt")) {
            HStack {
                Picker("", selection: Binding(get: { bindings.profile }, set: applyProfile)) {
                    Text(L10n.t("Finder")).tag(KeyProfile.finder)
                    Text(L10n.t("Windows Explorer")).tag(KeyProfile.explorer)
                    Text(L10n.t("Total Commander")).tag(KeyProfile.commander)
                    if bindings.profile == .custom { Text(L10n.t("Tuỳ chỉnh")).tag(KeyProfile.custom) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Button(L10n.t("Khôi phục mặc định")) {
                    bindings.restoreAllDefaults()
                    persist()
                }
                .controlSize(.small)
            }
            .settingsRow()
        }

        SettingsSection(title: L10n.t("Bảng phím tắt"),
                        footer: L10n.t("Nhấp một ô rồi gõ phím mới. Esc huỷ, Delete xoá. Control-click một hàng để khôi phục riêng hàng đó.")) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(XFinderTokens.Font.caption)
                TextField(L10n.t("Tìm theo tên hoặc phím"), text: $query)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
            }
            .settingsRow()
            SettingsDivider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredCommands, id: \.self) { command in
                    commandRow(command)
                    if command != filteredCommands.last { SettingsDivider() }
                }
            }
        }

        SettingsSection(title: L10n.t("Chuột")) {
            ToggleRow(title: L10n.t("Tab chuyển ngăn"),
                      subtitle: L10n.t("Như Total Commander: Tab chuyển ngăn đang chọn thay vì focus trong ngăn."),
                      isOn: $tabSwitchesPanes)
                .settingsRow()
                .onChange(of: tabSwitchesPanes) { _, newValue in bindings.tabSwitchesPanes = newValue; persist() }
            SettingsDivider()
            HStack {
                Text(L10n.t("Nút chuột 4/5 (Lùi/Tiến)")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $mouseBackForward) {
                    Text(L10n.t("Bật")).tag("on")
                    Text(L10n.t("Tắt")).tag("off")
                    Text(L10n.t("Đảo")).tag("swapped")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .settingsRow()
            .onChange(of: mouseBackForward) { _, newValue in
                bindings.mouse = MouseBackForward(rawValue: newValue) ?? .on
                persist()
            }
        }

        SettingsSection(title: L10n.t("Xuất / nhập")) {
            HStack {
                Button(L10n.t("Xuất…")) { exportBindings() }.controlSize(.small)
                Button(L10n.t("Nhập…")) { importBindings() }.controlSize(.small)
                Spacer()
            }
            .settingsRow()
            if !importErrors.isEmpty {
                SettingsDivider()
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Không nhập được — mọi lỗi dưới đây cần sửa trước:"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    ForEach(Array(importErrors.enumerated()), id: \.offset) { _, error in
                        Text(importErrorText(error)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
                .settingsRow()
            }
        }
        .alert(L10n.t("Phím đang được dùng"), isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
            Button(L10n.t("Vẫn dùng"), role: .destructive) { if let c = conflict { commit(c.chord, to: c.command, extra: c.extra) }; conflict = nil }
            Button(L10n.t("Hủy"), role: .cancel) { conflict = nil }
        } message: {
            if let conflict { Text("\(L10n.t("Phím này đang dùng cho "))\(L10n.t(BrowserCommands.titleKey(conflict.command)))") }
        }
    }

    private func commandRow(_ command: BrowserCommand) -> some View {
        let binding = bindings.binding(for: command)
        return HStack {
            Text(L10n.t(BrowserCommands.titleKey(command))).font(XFinderTokens.Font.rowValue)
            if isSystemOverridden(command) {
                Text(L10n.t("(Cài đặt hệ thống)")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer()
            chordField(binding.primary, command: command, extra: false)
            chordField(binding.extra, command: command, extra: true)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1, perform: {})   // keep row from swallowing the chip buttons' own taps
        .background(ControlClickCatcher { restoreRowDefault(command) })
        .settingsRow()
    }

    private func chordField(_ chord: KeyChord?, command: BrowserCommand, extra: Bool) -> some View {
        let isRecording = recording == command && recordingExtra == extra
        return Button {
            recording = command
            recordingExtra = extra
        } label: {
            Group {
                if isRecording {
                    Text(L10n.t("Nhấn phím…")).font(XFinderTokens.Settings.keycap)
                } else if let chord {
                    Text(BrowserCommands.display(chord)).font(XFinderTokens.Settings.keycap)
                } else {
                    Text("—").font(XFinderTokens.Settings.keycap).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                .fill(isRecording ? XFinderTokens.Fill.focus : XFinderTokens.Fill.inset))
        }
        .buttonStyle(.plain)
        .background(KeyRecorderCatcher(isActive: isRecording) { event in handleRecordedKey(event, command: command, extra: extra) })
    }

    /// `event` is a real `NSEvent` from `KeyRecorderCatcher`; Esc cancels, Delete clears, anything else is validated
    /// then either assigned directly or routed through the conflict alert first ("Use Anyway").
    private func handleRecordedKey(_ event: NSEvent, command: BrowserCommand, extra: Bool) {
        defer { recording = nil }
        if event.keyCode == 53 { return }   // Esc: cancel, keep the existing binding
        if event.keyCode == 51 || event.keyCode == 117 {   // Delete / Forward Delete: clear this slot
            bindings.assign(nil, to: command, extra: extra)
            persist()
            return
        }
        guard let chord = KeyRecorderCatcher.chord(from: event) else { return }
        guard bindings.validate(chord) == nil else { return }
        if let holder = bindings.conflict(for: chord, excluding: command) {
            conflict = (holder, chord, extra)
            return
        }
        commit(chord, to: command, extra: extra)
    }

    private func commit(_ chord: KeyChord, to command: BrowserCommand, extra: Bool) {
        bindings.assign(chord, to: command, extra: extra)
        persist()
    }

    private func restoreRowDefault(_ command: BrowserCommand) {
        bindings.restoreDefault(command)
        persist()
    }

    /// Spec: a row a system-wide App Shortcuts override wins over reads "(Cài đặt hệ thống)". There is no public API
    /// to enumerate `NSApp.mainMenu`'s own App Shortcuts remaps from here, so this is always false until an
    /// integrator wires a real check — the label itself (not a fabricated true case) is the contract-compliant part.
    /// System Settings ▸ Keyboard ▸ App Shortcuts stores overrides in `NSUserKeyEquivalents` (this app's domain or the
    /// global one — `UserDefaults.standard` searches both), keyed by the menu item title, or by a menu path whose
    /// components are separated by ESC (U+001B) on recent macOS. Such a row wins over XFinder's own binding.
    private func isSystemOverridden(_ command: BrowserCommand) -> Bool {
        guard let overrides: [String: Any] = UserDefaults.standard.dictionary(forKey: "NSUserKeyEquivalents"),
              !overrides.isEmpty else { return false }
        let title: String = L10n.t(BrowserCommands.titleKey(command))
        return overrides.keys.contains { key in
            key == title || key.split(separator: "\u{1b}").last.map(String.init) == title
                || key.split(separator: ">").last.map(String.init) == title
        }
    }

    private func applyProfile(_ profile: KeyProfile) {
        bindings.apply(profile)
        tabSwitchesPanes = bindings.tabSwitchesPanes
        persist()
    }

    private func persist() { BrowserSettings.keyBindings = bindings }

    private func exportBindings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "XFinder-browser-shortcuts.json"
        panel.message = L10n.t("Chọn nơi lưu tệp phím tắt.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? bindings.export().write(to: url, options: .atomic)
    }

    private func importBindings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("Chọn tệp phím tắt đã xuất.")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        switch KeyBindings.importing(data) {
        case .success(let imported):
            bindings = imported
            importErrors = []
            persist()
        case .failure(let failure):
            importErrors = failure.errors
        }
    }

    private func importErrorText(_ error: KeyBindings.ImportError) -> String {
        switch error {
        case .unreadable: return L10n.t("Tệp không đọc được.")
        case .unknownCommand(let raw): return "\(L10n.t("Lệnh lạ: "))\(raw)"
        case .keyUsedTwice(let key): return "\(L10n.t("Phím dùng hai lần: "))\(key)"
        case .reservedKey(let key): return "\(L10n.t("Phím dành riêng: "))\(key)"
        }
    }
}

/// An invisible `NSView` placed behind a row so a Control-click (or right-click) anywhere on that row fires
/// `onReset()` — the spec's "Control-click a row ⇒ Restore Default", which SwiftUI alone has no gesture for
/// (`.onTapGesture` only sees the primary button, and `simultaneousGesture` cannot see the modifier-click AppKit
/// reports here without going through `NSEvent` directly).
private struct ControlClickCatcher: NSViewRepresentable {
    let onReset: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onReset = onReset
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) { view.onReset = onReset }

    final class CatcherView: NSView {
        var onReset: (() -> Void)?
        override func rightMouseDown(with event: NSEvent) { onReset?() }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { onReset?() } else { super.mouseDown(with: event) }
        }
    }
}

/// Captures the next physical key press while `isActive` and reports the raw `NSEvent` back — recording needs the
/// actual key code (to recognize Esc/Delete) and modifier flags, which SwiftUI's `.keyboardShortcut`/`onKeyPress`
/// cannot hand back as a *recorded* chord the way this view's local event monitor can.
private struct KeyRecorderCatcher: NSViewRepresentable {
    let isActive: Bool
    let onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onKey = onKey
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
        view.setActive(isActive)
    }

    static func chord(from event: NSEvent) -> KeyChord? {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else {
            return Self.namedKey(for: event.keyCode).map {
                KeyChord($0, command: event.modifierFlags.contains(.command), shift: event.modifierFlags.contains(.shift),
                         option: event.modifierFlags.contains(.option), control: event.modifierFlags.contains(.control))
            }
        }
        let flags = event.modifierFlags
        return KeyChord(characters, command: flags.contains(.command), shift: flags.contains(.shift),
                        option: flags.contains(.option), control: flags.contains(.control))
    }

    private static func namedKey(for keyCode: UInt16) -> String? {
        let table: [UInt16: String] = [36: "return", 51: "delete", 49: "space", 123: "left", 124: "right",
                                        125: "down", 126: "up", 53: "escape", 48: "tab"]
        return table[keyCode]
    }

    // No `deinit`: a nonisolated deinit may not touch MainActor state under Swift 6 (same reasoning as
    // `ClickOutsideDismisser`). `updateNSView` is SwiftUI's own teardown hook here — `isActive` always goes back to
    // `false` (the row stops being the `recording` one) before this view could be removed from the hierarchy, so
    // `setActive(false)` already runs on every path that matters.
    final class CatcherView: NSView {
        var onKey: ((NSEvent) -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.onKey?(event)
                    return nil   // swallow — the recorder, not the window, owns this keystroke while active
                }
            } else if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

// MARK: - Search

private struct SearchSettingsTab: View {
    @State private var roots = BrowserSettings.indexRoots
    @State private var statuses: [String: IndexRootStatus] = [:]

    var body: some View {
        SettingsSection(title: L10n.t("Thư mục được đánh chỉ mục"),
                        footer: L10n.t("Không tự quét toàn ổ đĩa — chỉ thư mục bạn thêm ở đây mới có chỉ mục tên/nội dung riêng; tìm theo Spotlight vẫn chạy ở mọi nơi khác.")) {
            if roots.isEmpty {
                Text(L10n.t("Chưa có thư mục nào được thêm."))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    .settingsRow()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(roots) { root in
                        rootRow(root)
                        if root.id != roots.last?.id { SettingsDivider() }
                    }
                }
            }
            SettingsDivider()
            HStack {
                Button { addRoot() } label: { Image(systemName: "plus") }.controlSize(.small)
                Spacer()
            }
            .settingsRow()
        }
        .onAppear(perform: reloadStatuses)
    }

    private func rootRow(_ root: IndexRoot) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(root.path).font(XFinderTokens.Font.rowValue).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    removeRoot(root.id)
                } label: { Image(systemName: "minus") }.controlSize(.small)
            }
            HStack(spacing: XFinderTokens.Space.inline) {
                Toggle(L10n.t("Nội dung"), isOn: contentBinding(root.id)).toggleStyle(.checkbox).controlSize(.small)
                Toggle(L10n.t("Chữ trong ảnh"), isOn: imagesBinding(root.id)).toggleStyle(.checkbox).controlSize(.small)
                Spacer()
                Text(L10n.t(SearchIndexRules.statusKey(statuses[root.id] ?? .ready)))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            HStack(spacing: XFinderTokens.Space.inline) {
                Button(root.paused ? L10n.t("Tiếp tục") : L10n.t("Tạm dừng")) { togglePause(root.id) }
                    .controlSize(.small)
                Button(L10n.t("Dựng lại")) { rebuild(root.id) }.controlSize(.small)
                Spacer()
                Button(L10n.t("Xoá chỉ mục…")) { eraseAll() }.controlSize(.small)
            }
        }
        .settingsRow()
    }

    private func contentBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { roots.first(where: { $0.id == id })?.contents ?? false },
            set: { newValue in
                guard let i = roots.firstIndex(where: { $0.id == id }) else { return }
                roots[i].contents = newValue
                persist()
            })
    }

    private func imagesBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { roots.first(where: { $0.id == id })?.textInImages ?? false },
            set: { newValue in
                guard let i = roots.firstIndex(where: { $0.id == id }) else { return }
                roots[i].textInImages = newValue
                persist()
            })
    }

    private func togglePause(_ id: String) {
        guard let i = roots.firstIndex(where: { $0.id == id }) else { return }
        roots[i].paused.toggle()
        let paused = roots[i].paused
        persist()
        Task { await FilenameIndex.shared.setPaused(id, paused); await ContentIndex.shared.setRoots(roots) }
    }

    private func rebuild(_ id: String) {
        Task { await FilenameIndex.shared.rebuild(id) }
    }

    private func eraseAll() {
        Task { await FilenameIndex.shared.eraseAll(); await ContentIndex.shared.eraseAll() }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("Chọn thư mục để đánh chỉ mục.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard case .ok = SearchIndexRules.validateNewRoot(url.path, isDirectory: true, existing: roots, home: home) else { return }
        let root = IndexRoot(id: UUID().uuidString, path: url.path, contents: false, textInImages: false, paused: false,
                             device: nil, inode: nil)
        roots.append(root)
        persist()
        Task { await FilenameIndex.shared.setRoots(roots); await ContentIndex.shared.setRoots(roots) }
    }

    private func removeRoot(_ id: String) {
        roots.removeAll { $0.id == id }
        persist()
        Task { await FilenameIndex.shared.setRoots(roots); await ContentIndex.shared.setRoots(roots) }
    }

    private func persist() { BrowserSettings.indexRoots = roots }

    private func reloadStatuses() {
        Task {
            let s = await FilenameIndex.shared.status()
            await MainActor.run { statuses = s }
        }
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    @State private var folderStatus: [String: FolderAccessStatus] = [:]
    @State private var fullDiskAccess: FullDiskAccessStatus = .couldNotCheck
    @State private var justGranted = false

    private let folders: [(key: String, name: String)] = [
        ("Desktop", "Màn hình nền"), ("Documents", "Tài liệu"), ("Downloads", "Thư mục Tải về"),
    ]

    var body: some View {
        SettingsSection(title: L10n.t("Quyền thư mục")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
                    HStack {
                        Text(L10n.t(folder.name)).font(XFinderTokens.Font.rowValue)
                        Spacer()
                        Text(L10n.t(FolderAccessStatus.titleKey(folderStatus[folder.key] ?? .unknown)))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        Button(L10n.t("Cho phép")) { requestAccess(folder.key) }
                            .controlSize(.small)
                    }
                    .settingsRow()
                    if index != folders.count - 1 { SettingsDivider() }
                }
            }
        }

        SettingsSection(title: L10n.t("Truy cập toàn bộ ổ đĩa")) {
            HStack {
                Text(L10n.t("Full Disk Access")).font(XFinderTokens.Font.row)
                Spacer()
                Text(L10n.t(FullDiskAccessStatus.titleKey(fullDiskAccess))).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                Button(L10n.t("Mở Cài đặt hệ thống…")) { openFullDiskAccessSettings() }.controlSize(.small)
                Button(L10n.t("Kiểm lại")) { recheckFullDiskAccess() }.controlSize(.small)
                Spacer()
            }
            .settingsRow()
            if justGranted {
                SettingsDivider()
                Text(L10n.t("Vừa cấp quyền? Thoát và mở lại XFinder để chắc chắn quyền có hiệu lực."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
            }
        }

        SettingsSection(title: L10n.t("Khởi động")) {
            Button(L10n.t("Hiện cửa sổ Chào…")) {
                OnboardingWindowController.shared.show { preset, folders in
                    OnboardingWindowController.openWindow(preset: preset, folders: folders)
                }
            }
            .controlSize(.small)
            .settingsRow()
        }
        .onAppear(perform: refreshAll)
    }

    private func requestAccess(_ folderName: String) {
        Task.detached(priority: .utility) {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderName)
            // Reading the folder's contents is what triggers the real TCC prompt the first time (never self-granted).
            let granted = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            await MainActor.run { folderStatus[folderName] = granted ? .granted : .denied }
        }
    }

    private func recheckFullDiskAccess() {
        let previous = fullDiskAccess
        Task.detached(priority: .utility) {
            let status = FullDiskAccessProbe.check()
            await MainActor.run {
                fullDiskAccess = status
                if previous != .on && status == .on { justGranted = true }
            }
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAll() {
        for folder in folders {
            let name = folder.key
            Task.detached(priority: .utility) {
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
                let granted = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
                await MainActor.run { folderStatus[name] = granted ? .granted : .denied }
            }
        }
        Task.detached(priority: .utility) {
            let status = FullDiskAccessProbe.check()
            await MainActor.run { fullDiskAccess = status }
        }
    }
}

/// Whether reading one of the three onboarding folders succeeded the last time it was tried. `.unknown` until the
/// first check (never claims "denied" before actually trying).
private enum FolderAccessStatus {
    case unknown, granted, denied
    static func titleKey(_ status: FolderAccessStatus) -> String {
        switch status {
        case .unknown: return "Chưa kiểm tra"
        case .granted: return "Đã cho phép"
        case .denied: return "Chưa cho phép"
        }
    }
}

enum FullDiskAccessStatus: Equatable { case on, off, couldNotCheck
    static func titleKey(_ status: FullDiskAccessStatus) -> String {
        switch status {
        case .on: return "Bật"
        case .off: return "Tắt"
        case .couldNotCheck: return "Không kiểm được"
        }
    }
}

/// Full Disk Access cannot be read from an entitlement or an API — the standard indirect probe (also how Finder's
/// own "step 2" works) is attempting to read a location only FDA unlocks: `~/Library/Safari` is TCC-protected even
/// though Safari's own data lives there regardless of this app, so a non-FDA process is refused `EPERM` reading its
/// directory listing while an FDA-granted one succeeds.
enum FullDiskAccessProbe {
    static func check() -> FullDiskAccessStatus {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari").path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .couldNotCheck }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil ? .on : .off
    }
}
