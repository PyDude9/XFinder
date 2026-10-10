import AppKit
import UniformTypeIdentifiers

/// The live half of settings export/import: the panels, the alert and the write. Every decision
/// about WHAT travels lives in `SettingsTransfer` (pure, tested).
@MainActor
@Observable
final class SettingsTransferController {
    static let shared = SettingsTransferController()

    private(set) var status: String?
    private(set) var statusIsError = false
    private init() {}

    private var domain: String { Bundle.main.bundleIdentifier ?? "com.xfinder.app" }

    // MARK: Export

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "XFinder-settings.json"
        panel.message = L10n.t("Chọn nơi lưu tệp cài đặt.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        do {
            let result = try SettingsTransfer.export(defaults: UserDefaults.standard.persistentDomain(forName: domain) ?? [:],
                                                     appVersion: version, date: Date())
            try result.data.write(to: url, options: .atomic)
            var text = "\(L10n.t("Đã xuất "))\(result.exported)\(L10n.t(" cài đặt"))"
            if result.skippedMachineSpecific > 0 {
                text += "\(L10n.t("; đã bỏ "))\(result.skippedMachineSpecific)\(L10n.t(" giá trị là đường dẫn riêng của máy này."))"
            } else { text += "." }
            report(text, error: false)
        } catch {
            report("\(L10n.t("Không ghi được tệp: "))\(error.localizedDescription)", error: true)
        }
    }

    // MARK: Import

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("Chọn tệp cài đặt XFinder đã xuất.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSettings(from: url, confirm: true)
    }

    /// `confirm: false` is for tests that drive the flow without a modal alert.
    func importSettings(from url: URL, confirm: Bool) {
        // Check the size BEFORE reading: a wrong file (a disk image, a video) must not be loaded.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= SettingsTransfer.maxFileBytes else { return report(message(for: .tooLarge), error: true) }
        guard let data = try? Data(contentsOf: url) else {
            return report(L10n.t("Không đọc được tệp."), error: true)
        }
        switch SettingsTransfer.parse(data) {
        case .failure(let e): report(message(for: e), error: true)
        case .success(let plan):
            if confirm && !confirmImport(plan) { return }
            let n = SettingsTransfer.apply(plan, to: .standard)
            // The feature switches take effect now; everything else is read at point of use or at launch.
            for f in FeatureCatalog.all { FeatureHub.apply(f.id) }
            FeatureHub.shared.refresh()
            report("\(L10n.t("Đã nhập "))\(n)\(L10n.t(" cài đặt. Công tắc tính năng đã áp dụng ngay; phần còn lại có hiệu lực khi mở lại XFinder."))",
                   error: false)
        }
    }

    private func confirmImport(_ plan: SettingsTransfer.ImportPlan) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.t("Nhập cài đặt?")
        var info = "\(L10n.t("Tệp có "))\(plan.settings.count)\(L10n.t(" cài đặt. Cài đặt hiện tại cùng tên sẽ bị ghi đè."))"
        if !plan.rejected.isEmpty {
            info += "\(L10n.t(" Bỏ qua "))\(plan.rejected.count)\(L10n.t(" mục không phải cài đặt hoặc không hợp lệ."))"
        }
        alert.informativeText = info
        alert.addButton(withTitle: L10n.t("Nhập"))
        alert.addButton(withTitle: L10n.t("Hủy"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func message(for e: SettingsTransfer.ImportError) -> String {
        switch e {
        case .tooLarge: return L10n.t("Tệp quá lớn để là tệp cài đặt.")
        case .notASettingsFile: return L10n.t("Đây không phải tệp cài đặt của XFinder.")
        case .empty: return L10n.t("Tệp không có cài đặt nào dùng được.")
        case .newerThanThisApp(let v):
            return "\(L10n.t("Tệp này do bản XFinder mới hơn tạo ra (định dạng "))\(v)\(L10n.t("); hãy cập nhật XFinder."))"
        }
    }

    private func report(_ text: String, error: Bool) { status = text; statusIsError = error }
}
