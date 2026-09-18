import SwiftUI

/// Settings now live in the sidebar (see `SettingsDetailView`). This file is
/// retained solely for `AboutView`, opened from the app menu.
struct AboutView: View {
    @State private var updater = UpdateChecker.shared

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

            Text(L10n.t("XFinder kết hợp quản lý clipboard và giám sát hệ thống theo thời gian thực trong một ứng dụng macOS gọn nhẹ. 100% cục bộ, không thu thập dữ liệu."))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            updateSection

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Link(L10n.t("Mã nguồn trên GitHub"),
                     destination: URL(string: "https://github.com/PyDude9/XFinder")!)
                Link(L10n.t("Báo lỗi / góp ý"),
                     destination: URL(string: "https://github.com/PyDude9/XFinder/issues")!)
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
        .frame(width: 400, height: 470)
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
