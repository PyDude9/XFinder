import SwiftUI
import AppKit

/// Tiện ích Finder — flat System-Settings layout matching the reference
/// screenshot: a status block for the Finder integration surfaces, then a
/// plain-language list of what XFinder adds to Finder.
///
/// Honesty Rule: Finder context-menu items and Quick Actions require a
/// **Finder Sync / Action extension target**, which this app does not ship.
/// So those rows report their real state and link to the Extensions pane
/// instead of pretending to toggle something.
struct FinderUtilsDetailView: View {
    @AppStorage("finder.showExtensions") private var showExtensions = false
    @AppStorage("finder.showHidden") private var showHidden = false
    @AppStorage("finder.showFullPath") private var showFullPath = false

    @State private var status: String? = nil
    @State private var isApplying = false

    private let domain = "com.apple.finder"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "puzzlepiece.extension",
                           title: "Tiện ích Finder",
                           subtitle: "Kết nối các lệnh XFinder với Finder.")

                integrationStatus

                Divider().padding(.horizontal, 20)

                finderPrefs

                Divider().padding(.horizontal, 20)

                explainer
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear(perform: readBack)
    }

    // MARK: - Trạng thái tích hợp

    private var integrationStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "checkmark.seal",
                          title: "Trạng thái tích hợp",
                          subtitle: "Những gì macOS cho phép XFinder gắn vào Finder.")

            VStack(spacing: 0) {
                StatusChecklistRow(
                    state: .ok,
                    title: "Thao tác trên mục đang chọn",
                    status: "Đã bật",
                    actionTitle: "Mở trang",
                    action: { AppState.shared.navigate(to: .finderActions) })

                Divider()

                // Honest: this needs an extension target the app does not have.
                StatusChecklistRow(
                    state: .warning,
                    title: "Tác vụ nhanh trong menu chuột phải",
                    status: "Chưa có",
                    actionTitle: "Mở cài đặt",
                    action: { openExtensionsPane() })
            }
            .padding(.horizontal, 20)

            Text("Menu chuột phải và Tác vụ nhanh của Finder cần một Finder Extension riêng. XFinder chưa kèm phần mở rộng đó, nên mục này báo đúng trạng thái thay vì hiện một công tắc không có tác dụng.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Tùy chọn Finder

    private var finderPrefs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "folder",
                          title: "Tùy chọn Finder",
                          subtitle: "Các khóa cấu hình Finder mà Apple hỗ trợ công khai.")

            VStack(spacing: 10) {
                ToggleRow(title: "Hiện phần mở rộng tập tin", isOn: $showExtensions)
                ToggleRow(title: "Hiện tập tin ẩn", isOn: $showHidden)
                ToggleRow(title: "Hiện đường dẫn đầy đủ ở tiêu đề", isOn: $showFullPath)

                HStack(spacing: 8) {
                    Button(isApplying ? "Đang áp dụng…" : "Áp dụng & khởi động lại Finder") {
                        applyAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isApplying)

                    if let s = status {
                        Text(s).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("Finder chỉ đọc các khóa này khi khởi động lại, nên XFinder sẽ khởi động lại Finder sau khi áp dụng. Cửa sổ Finder đang mở sẽ đóng lại.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Giải thích

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "info.circle",
                          title: "XFinder thêm gì vào Finder",
                          subtitle: nil)

            VStack(alignment: .leading, spacing: 6) {
                bullet("Thao tác Finder: chạy lệnh của XFinder trên đúng các mục bạn đang chọn trong Finder.")
                bullet("Bàn phím Finder: viết lại phím tắt Cắt/Dán/Xóa/Mở trước khi Finder nhận được.")
                bullet("Đổi tên hàng loạt và Lịch sử thao tác: nhận trực tiếp mục đang chọn, và hoàn tác được.")
            }
            .padding(.horizontal, 20)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 12)).foregroundColor(.secondary)
            Text(text).font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - defaults read/write

    private func readBack() {
        let d = UserDefaults(suiteName: domain)
        showExtensions = d?.object(forKey: "AppleShowAllExtensions") as? Bool ?? false
        showHidden = d?.object(forKey: "AppleShowAllFiles") as? Bool ?? false
        showFullPath = d?.object(forKey: "_FXShowPosixPathInTitle") as? Bool ?? false
    }

    private func applyAll() {
        isApplying = true
        status = nil
        let d = UserDefaults(suiteName: domain)
        d?.set(showExtensions, forKey: "AppleShowAllExtensions")
        d?.set(showHidden, forKey: "AppleShowAllFiles")
        d?.set(showFullPath, forKey: "_FXShowPosixPathInTitle")
        d?.synchronize()

        Task {
            // cfprefsd caches the domain; flush it before restarting Finder or
            // Finder reads back the stale values.
            await run(["/usr/bin/killall", "-KILL", "cfprefsd"])
            await run(["/usr/bin/killall", "Finder"])
            isApplying = false
            status = "Đã áp dụng."
        }
    }

    private func run(_ cmd: [String]) async {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cmd[0])
            p.arguments = Array(cmd.dropFirst())
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }.value
    }

    private func openExtensionsPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")
        if let url, NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
