import SwiftUI

/// Đang phát — the user comes here to decide whether the notch shows what is playing, and to read, in
/// plain words, what that costs and what it rests on. Split off "Notch & Khay thả" (P3); this page owns
/// the Now Playing surface only — opening/hover behaviour lives on Giao diện notch.
struct MediaDetailView: View {
    // B6 Now Playing. Reader: NowPlayingMonitor (default must match — FeatureKeyDefaultsTests). Off by
    // default: it runs a helper process and rides a private framework, so the user opts in.
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("notch.nowPlaying") private var nowPlaying = false
    @AppStorage("notch.nowPlaying.waveform") private var waveform = false   // §3b #21
    @State private var nowPlayingMonitor = NowPlayingMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Đang phát"),
                    subtitle: L10n.t("Bài đang phát hiện dưới notch; rê chuột để xem và điều khiển, bấm để mở trang Đang phát trong khay.")
                )

                // P3 review: the notch master switches this surface off with the rest of the notch — say so, here.
                if !notchEnabled {
                    SettingsSection {
                        SettingsLinkRow(
                            title: L10n.t("Notch đang tắt"),
                            subtitle: L10n.t("Mục này không hiện ở notch cho tới khi bạn bật lại notch ở Giao diện notch."),
                            destination: .notchInterface
                        )
                    }
                }

                toggleSection
                statusSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private var toggleSection: some View {
        SettingsSection {
            ToggleRow(title: L10n.t("Hiện bài đang phát ở notch"),
                      subtitle: L10n.t("Tên bài, nghệ sĩ, ảnh bìa và nút điều khiển cho app đang phát — kể cả trình duyệt. Mặc định tắt."),
                      isOn: $nowPlaying)
                .onChange(of: nowPlaying) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Sóng nhạc thời gian thực"),
                      subtitle: L10n.t("Cột sóng theo đúng âm thanh của app đang phát (không lẫn tiếng thông báo). Lần đầu macOS hỏi quyền Ghi âm thanh hệ thống. Chỉ chạy khi sóng đang hiện và nhạc đang phát; không ghi lại gì. Cần macOS 14.2."),
                      isOn: $waveform)
                .onChange(of: waveform) { NotchSurfaceController.shared.syncWaveform() }
                .disabled(!nowPlaying || !AudioTapMonitor.isSupported)
                .settingsRow()
        }
    }

    /// The user comes here to see, in one glance, whether the mechanism is actually working right now.
    private var statusSection: some View {
        SettingsSection(
            footer: L10n.t("Đọc qua MediaRemote, API riêng của Apple. Từ macOS 15.4 chỉ tiến trình do Apple ký mới đọc được, nên khi bật, XFinder nhờ /usr/bin/perl của hệ thống nạp một thư viện nhỏ và nhận dữ liệu qua pipe: thêm một tiến trình khoảng 18 MB, không polling. Apple có thể đóng đường này ở bất kỳ bản cập nhật nào — khi đó dòng trạng thái sẽ báo không khả dụng thay vì bịa. Nút điều khiển gửi lệnh trực tiếp từ XFinder.")
        ) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Trạng thái: ")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                Text(L10n.t(nowPlayingMonitor.availability.messageKey)).font(XFinderTokens.Font.caption)
                if let np = nowPlayingMonitor.liveSnapshot, np.hasTrack {
                    Text("· \(L10n.t("Đang phát: "))\(np.headline)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
            }
            .settingsRow()
        }
    }
}
