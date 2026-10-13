import SwiftUI
import AppKit

/// F3 — Thoát ứng dụng. The user comes here to control WHEN an app quits: never by a stray ⌘Q, and on its own once its
/// last window is closed (only for the apps listed here). Both switches are the same keys the Features hub toggles.
struct AppQuitDetailView: View {
    @AppStorage("quitProtection.enabled") private var holdEnabled = false
    @AppStorage("quitOnClose.enabled") private var closeEnabled = false
    @AppStorage("quitOnClose.apps") private var appsRaw = ""
    @State private var trusted = WindowManager.isTrusted

    private var chosen: [String] { QuitOnCloseRules.parseApps(appsRaw).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Thoát ứng dụng"),
                           subtitle: L10n.t("Không thoát nhầm vì ⌘Q, và tự thoát một app khi bạn đã đóng hết cửa sổ của nó."))
                holdSection
                closeSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .onAppear { trusted = WindowManager.isTrusted }
    }

    private var holdSection: some View {
        SettingsSection(title: L10n.t("Giữ ⌘Q để thoát ứng dụng"),
                        footer: L10n.t("Nhấn nhanh ⌘Q không thoát nhầm; phải giữ khoảng 1 giây.")) {
            ToggleRow(title: L10n.t("Bật giữ ⌘Q"),
                      subtitle: L10n.t("Một vòng tiến trình hiện khi bạn giữ; nhả sớm hoặc bấm Esc là huỷ."),
                      isOn: $holdEnabled)
                .onChange(of: holdEnabled) { QuitProtectionController.shared.applySettings() }
                .settingsRow()
        }
    }

    private var closeSection: some View {
        SettingsSection(title: L10n.t("Thoát khi đóng cửa sổ cuối"),
                        footer: L10n.t("Đóng hết cửa sổ của một app trong danh sách thì app thoát, không nằm lại trên Dock.")) {
            ToggleRow(title: L10n.t("Thoát app khi đóng cửa sổ cuối"),
                      subtitle: L10n.t("Chỉ với những app bạn chọn dưới đây. App vẫn hỏi lưu tài liệu như khi bạn chọn Thoát."),
                      isOn: $closeEnabled)
                .onChange(of: closeEnabled) { QuitOnCloseController.shared.applySettings() }
                .settingsRow()
            if closeEnabled && !trusted {
                SettingsDivider()
                InlineNote(kind: .warning, text: L10n.t("Cần quyền Trợ năng để biết cửa sổ của app khác đã đóng."),
                           buttonTitle: L10n.t("Cấp quyền Trợ năng")) { WindowManager.requestAccessibilityTrust() }
                    .settingsRow()
            }
            SettingsDivider()
            if chosen.isEmpty {
                Text(L10n.t("Chưa chọn app nào — chưa có app nào tự thoát."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .settingsRow()
            }
            // P4 review: one hairline before the list (above), then one BETWEEN rows — not a second one before the first.
            ForEach(Array(chosen.enumerated()), id: \.element) { index, bid in
                if index > 0 { SettingsDivider() }
                HStack {
                    Text(appName(bid)).font(XFinderTokens.Font.row)
                        .lineLimit(1).truncationMode(.middle).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Button(L10n.t("Bỏ")) { setApps { $0.remove(bid) } }.controlSize(.small)
                }
                .settingsRow()
            }
            SettingsDivider()
            HStack {
                Menu(L10n.t("Thêm app đang chạy")) {
                    ForEach(runningApps(), id: \.0) { bid, name in
                        Button(name) { setApps { $0.insert(bid) } }
                    }
                }
                .frame(width: 200)
                Spacer()
            }
            .settingsRow()
            SettingsDivider()
            InlineNote(text: L10n.t("Mọi cửa sổ đều tính, kể cả bảng phụ và hộp thoại; app đang ẩn vẫn còn cửa sổ nên không bị thoát. XFinder đợi 1 giây sau khi cửa sổ đóng rồi mới đếm lại, để ⌘W rồi ⌘N không làm app thoát giữa chừng. Finder không bao giờ bị thoát."))
                .settingsRow()
        }
    }

    private func setApps(_ change: (inout Set<String>) -> Void) {
        var s = QuitOnCloseRules.parseApps(appsRaw)
        change(&s)
        appsRaw = QuitOnCloseRules.encodeApps(s)
        QuitOnCloseController.shared.applySettings()
    }

    private func appName(_ bid: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return bid }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func runningApps() -> [(String, String)] {
        let own = Bundle.main.bundleIdentifier ?? "com.xfinder.app"
        var seen = QuitOnCloseRules.parseApps(appsRaw).union(QuitOnCloseRules.neverQuit)
        seen.insert(own)
        return NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let bid = app.bundleIdentifier, !seen.contains(bid) else { return nil }
            seen.insert(bid)
            return (bid, app.localizedName ?? bid)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}
