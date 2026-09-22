import SwiftUI
import AppKit

/// Tiện ích Finder — flat System-Settings layout matching the reference
/// screenshot: a status block for the Finder integration surfaces, then a
/// plain-language list of what XFinder adds to Finder.
///
/// Honesty Rule: the right-click row reads the extension's real plug-in state
/// from `FinderExtensionStatus.probe()` instead of asserting a value. XFinder
/// DOES ship `XFinderSync.appex`; whether Finder uses it is the user's switch in
/// System Settings, which no app can flip for them.
struct FinderUtilsDetailView: View {
    @AppStorage("finder.showExtensions") private var showExtensions = false
    @AppStorage("finder.showHidden") private var showHidden = false
    @AppStorage("finder.showFullPath") private var showFullPath = false

    @State private var status: String? = nil
    @State private var isApplying = false
    @State private var extensionStatus: FinderExtensionStatus = .unknown

    private let domain = "com.apple.finder"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "puzzlepiece.extension",
                           title: L10n.t("Tiện ích Finder"),
                           subtitle: L10n.t("Kết nối các lệnh XFinder với Finder."))

                integrationStatus

                Divider().padding(.horizontal, 20)

                finderPrefs

                Divider().padding(.horizontal, 20)

                explainer
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            readBack()
            Task { extensionStatus = await FinderExtensionStatus.probe() }
        }
    }

    // MARK: - Trạng thái tích hợp

    /// Row copy derived from the MEASURED plug-in state. Every branch names what
    /// the user has to do next, and the last one refuses to claim success.
    private var extensionRowState: (state: StatusChecklistRow.State, status: String) {
        switch extensionStatus {
        case .enabled:
            return (.ok, L10n.t("Đã bật"))
        case .disabled:
            return (.warning, L10n.t("Bạn đã tắt"))
        case .registeredNotEnabled:
            return (.warning, L10n.t("Chưa bật"))
        case .notRegistered:
            return (.warning, L10n.t("Chưa có"))
        case .unknown:
            return (.warning, L10n.t("Không xác định"))
        }
    }

    private var integrationStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "checkmark.seal",
                          title: L10n.t("Trạng thái tích hợp"),
                          subtitle: L10n.t("Những gì macOS cho phép XFinder gắn vào Finder."))

            VStack(spacing: 0) {
                StatusChecklistRow(
                    state: .ok,
                    title: L10n.t("Thao tác trên mục đang chọn"),
                    status: L10n.t("Đã bật"),
                    actionTitle: L10n.t("Mở trang"),
                    action: { AppState.shared.navigate(to: .finderActions) })

                Divider()

                // Measured, not asserted: this row used to hard-code "Chưa có",
                // which was true only while the appex failed to register.
                StatusChecklistRow(
                    state: extensionRowState.state,
                    title: L10n.t("Tác vụ nhanh trong menu chuột phải"),
                    status: extensionRowState.status,
                    actionTitle: L10n.t("Mở cài đặt"),
                    action: { openExtensionsPane() })
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(extensionExplanation)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The user reported the button "does not go straight to the
                // right-click menu settings like other apps". That is a real
                // macOS limit, not a bug here: `x-apple.systempreferences:`
                // can open a PANE but cannot select a row inside it. Say so,
                // and give the exact path to click instead of implying the
                // button lands on the switch.
                Text(L10n.md("Lưu ý: macOS chỉ cho mở tới trang cài đặt, không cho nhảy thẳng tới từng mục. Sau khi bấm nút trên, vào **Cài đặt hệ thống → Chung → Login Items & Extensions**, kéo xuống mục **Tiện ích mở rộng**, bấm ⓘ ở dòng **Finder** rồi bật ứng dụng bạn muốn hiện trong menu chuột phải."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
        }
    }

    /// One sentence per measured state, each saying what happens next.
    private var extensionExplanation: String {
        switch extensionStatus {
        case .enabled:
            return L10n.t("XFinder đã kèm phần mở rộng Finder và macOS đang bật nó: bấm chuột phải vào tập tin trong Finder sẽ thấy mục “Thêm vào Khay thả XFinder” và nút trên thanh công cụ.")
        case .disabled:
            return L10n.t("Phần mở rộng đã cài nhưng đang bị tắt trong Cài đặt hệ thống, nên Finder không hiện mục của XFinder. Bật lại theo hướng dẫn bên dưới.")
        case .registeredNotEnabled:
            return L10n.t("Phần mở rộng đã cài và macOS đã biết nó, nhưng chưa bật — mặc định của mọi tiện ích mới. Bật theo hướng dẫn bên dưới để Finder hiện mục của XFinder.")
        case .notRegistered:
            return L10n.t("macOS chưa thấy phần mở rộng Finder của XFinder. Hãy cài bản dựng mới nhất, rồi bật theo hướng dẫn bên dưới.")
        case .unknown:
            return L10n.t("Chưa đọc được trạng thái phần mở rộng từ macOS. Bấm “Kiểm tra lại” sau khi mở trang cài đặt bên dưới.")
        }
    }

    // MARK: - Tùy chọn Finder

    private var finderPrefs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "folder",
                          title: L10n.t("Tùy chọn Finder"),
                          subtitle: L10n.t("Các khóa cấu hình Finder mà Apple hỗ trợ công khai."))

            VStack(spacing: 10) {
                ToggleRow(title: L10n.t("Hiện phần mở rộng tập tin"), isOn: $showExtensions)
                ToggleRow(title: L10n.t("Hiện tập tin ẩn"), isOn: $showHidden)
                ToggleRow(title: L10n.t("Hiện đường dẫn đầy đủ ở tiêu đề"), isOn: $showFullPath)

                HStack(spacing: 8) {
                    Button(isApplying ? L10n.t("Đang áp dụng…") : L10n.t("Áp dụng & khởi động lại Finder")) {
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

                Text(L10n.t("Finder chỉ đọc các khóa này khi khởi động lại, nên XFinder sẽ khởi động lại Finder sau khi áp dụng. Cửa sổ Finder đang mở sẽ đóng lại."))
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
                          title: L10n.t("XFinder thêm gì vào Finder"),
                          subtitle: nil)

            VStack(alignment: .leading, spacing: 6) {
                bullet(L10n.t("Thao tác Finder: chạy lệnh của XFinder trên đúng các mục bạn đang chọn trong Finder."))
                bullet(L10n.t("Bàn phím Finder: viết lại phím tắt Cắt/Dán/Xóa/Mở trước khi Finder nhận được."))
                bullet(L10n.t("Đổi tên hàng loạt và Lịch sử thao tác: nhận trực tiếp mục đang chọn, và hoàn tác được."))
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
            status = L10n.t("Đã áp dụng.")
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
        WindowManager.openFinderExtensionsPane()
    }
}
