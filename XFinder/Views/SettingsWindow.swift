import SwiftUI

/// Settings now live in the sidebar (see `SettingsDetailView`). This file is
/// retained solely for `AboutView`, opened from the app menu.
struct AboutView: View {
    @State private var updater = UpdateChecker.shared
    @State private var appState = AppState.shared
    /// Bound here; the ONE reader is `DiagnosticsLog.isEnabled` (same default).
    @AppStorage("diagnostics.localLog") private var localLog = true
    /// The report on screen, built when the person asks for it. Nil ⇒ the preview is closed.
    @State private var report: String?
    @State private var supportNotice: String?
    /// Bound here; the ONE reader is `AnalyticsCenter.isOptedOut` (same default: sending is on until refused).
    @AppStorage("analytics.optOut") private var analyticsOptOut = false
    /// The exact JSON the next anonymous report would carry, shown on request. Nil ⇒ closed.
    @State private var analyticsPreview: String?

    /// Read from Info.plist, never hard-coded — a literal here drifted out of
    /// sync with the bundle (it claimed 2.0 while the bundle said 1.0.0) and
    /// would make the update check compare against the wrong number.
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            content
                .frame(width: 440)
                .frame(maxWidth: .infinity)
        }
        .onAppear(perform: takeReportRequest)
        .onChange(of: appState.aboutShowsReport) { takeReportRequest() }
        .onChange(of: appState.aboutShowsAnalytics) { takeReportRequest() }
    }

    private var content: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("XFinder")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(L10n.t("Phiên bản "))\(version) (build \(build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(L10n.t("Quản lý clipboard & giám sát hệ thống"))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(L10n.t("XFinder kết hợp quản lý clipboard và giám sát hệ thống theo thời gian thực trong một ứng dụng macOS gọn nhẹ. Clipboard, ghi chú và tệp của bạn nằm trên máy; chúng chỉ rời máy qua một tính năng bạn tự bật hoặc tự bấm (xem trước liên kết, giọng nói qua API, chia sẻ, kết nối từ xa)."))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            updateSection

            supportSection

            VStack(spacing: 6) {
                Link(L10n.t("Mã nguồn trên GitHub"),
                     destination: URL(string: "https://github.com/PyDude9/XFinder")!)
                Text("thang0todev@gmail.com")
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .font(.caption)

            Text(L10n.t("© 2026 XFinder · Giấy phép MIT"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    /// The menu's "Báo lỗi…" sets the flag and navigates here; build the report once and clear it.
    private func takeReportRequest() {
        if appState.aboutShowsReport {
            appState.aboutShowsReport = false
            report = DiagnosticsCenter.shared.buildReport()
        }
        if appState.aboutShowsAnalytics {
            appState.aboutShowsAnalytics = false
            analyticsPreview = AnalyticsCenter.shared.previewText()
        }
    }

    /// Job: "something broke — give the developer what they need, and nothing about me." A bug report is shown in full
    /// first, and only Copy / Save / GitHub (which copies it) take it anywhere. The anonymous daily report below it is
    /// the one thing sent by itself, and it is described, previewable and refusable on the same card.
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("Hỗ trợ & báo lỗi"))
                .font(.headline)
            Text(L10n.t("Báo cáo lỗi chỉ rời máy khi bạn tự sao chép, lưu hoặc dán nó — sau khi đã đọc toàn bộ."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L10n.t("Báo lỗi…")) {
                    supportNotice = nil
                    report = DiagnosticsCenter.shared.buildReport()
                }
                Button(L10n.t("Sao chép thông tin hệ thống")) {
                    DiagnosticsCenter.shared.copySystemInfo()
                    supportNotice = L10n.t("Đã sao chép thông tin hệ thống.")
                }
            }
            .controlSize(.small)

            if let report { reportPreview(report) }

            Toggle(L10n.t("Ghi lỗi kỹ thuật của XFinder trên máy này"), isOn: $localLog)
                .toggleStyle(.switch)
                .controlSize(.small)
            Text(L10n.t("Chỉ mã lỗi, phiên bản và crash của chính XFinder — không tên tệp, không nội dung clipboard, không tên cửa sổ hay tài khoản. Nhật ký nằm trên máy. Tắt công tắc này thì bản thống kê ẩn danh bên dưới cũng không mang số lần gặp lỗi hay tóm tắt crash."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L10n.t("Xoá nhật ký")) {
                    DiagnosticsCenter.shared.clearLog()
                    if report != nil { report = DiagnosticsCenter.shared.buildReport() }
                    supportNotice = L10n.t("Đã xoá nhật ký chẩn đoán.")
                }
                .controlSize(.small)
                if let supportNotice {
                    Text(supportNotice)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
            analyticsBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    /// Opt-out anonymous analytics: what it is for, what it carries, what it never carries, where it goes, the switch
    /// that refuses it (default off — the owner's choice), the honest state, and the exact JSON on request.
    private var analyticsBlock: some View {
        let center = AnalyticsCenter.shared
        let action = center.currentAction()
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Phân tích ẩn danh"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t("Để sửa lỗi và nâng cấp app cho đúng nhu cầu của người dùng, mỗi ngày XFinder gửi tối đa một bản thống kê ẩn danh về trải nghiệm: phiên bản app và macOS, loại máy, ngôn ngữ, tính năng đang bật, quyền đã cấp, số lần gặp từng mã lỗi và tóm tắt crash của chính XFinder."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("Không bao giờ có: mã định danh máy hay người dùng, tên tệp, nội dung clipboard, ghi chú, tên cửa sổ, tài khoản. Mỗi lần gửi là một bản rời, không nối được với lần trước. Nơi nhận: TelemetryDeck — theo chính sách của họ, dữ liệu lưu tại EU và địa chỉ IP không được lưu (như mọi kết nối mạng, máy nhận vẫn thấy IP lúc nhận)."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L10n.t("Từ chối gửi phân tích ẩn danh"), isOn: $analyticsOptOut)
                .toggleStyle(.switch)
                .controlSize(.small)
            Text(L10n.t(AnalyticsRules.statusKey(action)))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !analyticsOptOut, let sent = center.lastSentAt {
                Text("\(L10n.t("Lần gửi gần nhất: "))\(sent.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN"))))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(analyticsPreview == nil ? L10n.t("Xem dữ liệu sẽ gửi") : L10n.t("Ẩn dữ liệu")) {
                analyticsPreview = analyticsPreview == nil ? center.previewText() : nil
            }
            .controlSize(.small)
            if let analyticsPreview {
                ScrollView {
                    Text(analyticsPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 200)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
        }
    }

    /// Exactly the text that would leave the Mac, selectable, before any button takes it anywhere.
    private func reportPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Đây là toàn bộ nội dung sẽ được chia sẻ. Đọc trước, bớt dòng nào tuỳ bạn sau khi dán."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 8) {
                Button(L10n.t("Sao chép")) {
                    DiagnosticsCenter.shared.copy(text)
                    supportNotice = L10n.t("Đã sao chép báo cáo.")
                }
                Button(L10n.t("Lưu tệp…")) {
                    if DiagnosticsCenter.shared.save(text) { supportNotice = L10n.t("Đã lưu báo cáo.") }
                }
                Button(L10n.t("Mở GitHub Issues")) {
                    DiagnosticsCenter.shared.openIssue(with: text)
                    supportNotice = L10n.t("Đã sao chép báo cáo — dán vào ô mô tả trên GitHub.")
                }
                Spacer(minLength: 0)
                Button(L10n.t("Đóng")) { report = nil }
            }
            .controlSize(.small)
        }
    }

    /// The update control. Every state says something concrete — a spinner that
    /// never resolves, or a silent failure, would be worse than no button.
    @ViewBuilder
    private var updateSection: some View {
        VStack(spacing: 8) {
            switch updater.state {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang kiểm tra…")).font(.caption).foregroundColor(.secondary)
                }

            case .upToDate(let current):
                Label("\(L10n.t("Bạn đang dùng bản mới nhất ("))\(current))", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)

            case .updateAvailable(let latest, let current, let url):
                VStack(spacing: 6) {
                    Label("\(L10n.t("Có bản mới: "))\(latest)\(L10n.t(" (bạn đang dùng "))\(current))",
                          systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Button(L10n.t("Xem bản phát hành")) { updater.openReleasesPage(url) }
                        .controlSize(.small)
                }

            case .failed(let message):
                VStack(spacing: 4) {
                    Label(L10n.t("Không kiểm tra được"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

            case .idle:
                EmptyView()
            }

            Button(L10n.t("Kiểm tra cập nhật")) { updater.check() }
                .controlSize(.small)
                .disabled(updater.state == .checking)
        }
    }
}
