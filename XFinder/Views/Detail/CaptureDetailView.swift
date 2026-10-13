import SwiftUI
import AppKit

/// F4 — Chụp & chú thích. The user comes here to decide WHEN a capture turns into a clip (and how), choose
/// shortcuts if they want any (OneNotch's default preset is one button away), where saved files land, and look
/// back at recent captures. Everything a capture actually DOES — the card, the editor, OCR, pinning — lives in
/// `CaptureController` / `QuickAccessController` / `AnnotateWindowController`; this page only sets the keys they
/// read and offers the same actions the card's context menu offers, on the history grid.
struct CaptureDetailView: View {
    @State private var controller = CaptureController.shared

    @AppStorage("capture.enabled") private var enabled = true
    @AppStorage("capture.after") private var afterRaw = "copyAndCard"
    @AppStorage("capture.cardSeconds") private var cardSeconds = 10
    @AppStorage("capture.cardEdge") private var cardEdgeRaw = "left"
    @AppStorage("capture.pauseOnHover") private var pauseOnHover = true
    @AppStorage("capture.swipeDismiss") private var swipeDismiss = true
    @AppStorage("capture.sound") private var sound = true
    @AppStorage("capture.format") private var formatRaw = "png"
    @AppStorage("capture.keepHistory") private var keepHistory = true
    @AppStorage("capture.annotate.color") private var annotateColorRaw = "red"
    @AppStorage("capture.annotate.width") private var annotateWidthRaw = "medium"

    private var format: CaptureFormat { CaptureFormat(rawValue: formatRaw) ?? .png }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Chụp & chú thích"),
                           subtitle: L10n.t("Chụp một vùng, cửa sổ hoặc cả màn hình; ảnh vào clipboard ngay, rồi chú thích, lưu hoặc ghim lên màn hình."))
                if !controller.isScreenRecordingGranted {
                    SettingsSection {
                        InlineNote(kind: .warning,
                                   text: L10n.t("Chưa có quyền Ghi màn hình — ảnh chụp sẽ chỉ có hình nền."),
                                   buttonTitle: L10n.t("Mở Cài đặt")) {
                            if let url = URL(string: AppPermission.screenRecording.settingsURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .settingsRow()
                    }
                }
                captureSection
                afterSection
                saveSection
                annotateSection
                recentSection
            }
            .padding(.bottom, 24)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    // MARK: Chụp

    private var captureSection: some View {
        SettingsSection(title: L10n.t("Chụp"),
                        footer: L10n.t("Không có phím tắt mặc định — ⇧⌘3, ⇧⌘4, ⇧⌘5 vẫn là của macOS.")) {
            ToggleRow(title: L10n.t("Bật phím tắt chụp"), isOn: $enabled)
                .onChange(of: enabled) { controller.applySettings() }
                .settingsRow()
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                SettingsDivider()
                captureModeRow(mode)
            }
            SettingsDivider()
            SettingsLinkRow(title: L10n.t("Đổi phím tắt trong Phím tắt"), destination: .shortcuts)
        }
    }

    @ViewBuilder
    private func captureModeRow(_ mode: CaptureMode) -> some View {
        let shortcut = controller.shortcut(for: mode)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Image(systemName: mode.symbol)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(mode.titleKey)).font(XFinderTokens.Font.row)
                    Text(L10n.t(mode.descriptionKey)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    ShortcutChip(label: shortcut.label)
                } else {
                    Text(L10n.t("Chưa gán"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                // P3 review: the split dropped this — without it, the three modes the flyout lacks (annotate, text,
                // colour) could only be reached by assigning a shortcut first.
                Button(L10n.t("Chụp")) { controller.capture(mode) }
                    .controlSize(.small)
            }
            if let conflict = controller.lastConflict, conflict.mode == mode {
                conflictCaption(conflict.conflict, mode: mode)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
                    .padding(.leading, 30)
            }
        }
        .settingsRow()
    }

    @ViewBuilder
    private func conflictCaption(_ conflict: CaptureRules.Conflict, mode: CaptureMode) -> some View {
        switch conflict {
        case .system(let nameKey):
            Text("\(L10n.t("Trùng với "))\(L10n.t(nameKey))\(L10n.t(" — macOS có thể giành trước."))")
        case .mode(let other):
            Text("\(L10n.t(other.titleKey))\(L10n.t(" đã giữ tổ hợp này rồi."))")
        }
    }

    // MARK: Sau khi chụp

    private var afterSection: some View {
        SettingsSection(title: L10n.t("Sau khi chụp")) {
            HStack {
                Text(L10n.t("Sau khi chụp")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $afterRaw) {
                    ForEach(CaptureAfter.allCases, id: \.self) { a in
                        Text(L10n.t(a.titleKey)).tag(a.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260)
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                Text(L10n.t("Thẻ xem trước tự đóng sau")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $cardSeconds) {
                    ForEach(CaptureRules.cardSecondsChoices, id: \.self) { seconds in
                        cardSecondsLabel(seconds).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                Text(L10n.t("Cạnh màn hình")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $cardEdgeRaw) {
                    ForEach(CaptureCardEdge.allCases, id: \.self) { edge in
                        Text(L10n.t(edge.titleKey)).tag(edge.rawValue)
                    }
                }
                .pickerStyle(.segmented) // segmented-ok: CaptureCardEdge has 2 cases
                .labelsHidden()
                .frame(width: 140)
            }
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Dừng đếm khi trỏ vào thẻ"), isOn: $pauseOnHover)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Vuốt hai ngón để đóng thẻ"), isOn: $swipeDismiss)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Âm thanh khi chụp"), isOn: $sound)
                .settingsRow()
        }
    }

    @ViewBuilder
    private func cardSecondsLabel(_ seconds: Int) -> some View {
        if seconds == 0 {
            Text(L10n.t("Không tự đóng"))
        } else {
            Text("\(seconds)\(L10n.t(" giây"))")
        }
    }

    // MARK: Lưu

    private var saveSection: some View {
        SettingsSection(title: L10n.t("Lưu")) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Text(L10n.t("Thư mục lưu"))
                    .font(XFinderTokens.Font.row)
                Text(controller.saveFolder.lastPathComponent)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, XFinderTokens.Space.tight)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(XFinderTokens.Fill.inset))
                Button("\(L10n.t("Chọn"))…") { controller.chooseSaveFolder() }
                    .controlSize(.small)
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                Text(L10n.t("Định dạng")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $formatRaw) {
                    Text("PNG").tag(CaptureFormat.png.rawValue)
                    Text("JPEG").tag(CaptureFormat.jpg.rawValue)
                    Text("HEIC").tag(CaptureFormat.heic.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            .settingsRow()
            SettingsDivider()
            Text(exampleFileName())
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .settingsRow()
        }
    }

    private func exampleFileName() -> String {
        CaptureRules.fileName(prefix: L10n.t("Ảnh chụp"), at: L10n.t(" lúc "), date: Date(), ext: format.fileExtension)
    }

    // MARK: Chú thích

    private var annotateSection: some View {
        SettingsSection(title: L10n.t("Chú thích")) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Text(L10n.t("Màu mặc định cho lần sau")).font(XFinderTokens.Font.row)
                Spacer()
                ForEach(MarkColor.allCases, id: \.self) { color in
                    colorSwatch(color)
                }
            }
            .settingsRow()
            SettingsDivider()
            HStack {
                Text(L10n.t("Độ dày nét cho lần sau")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $annotateWidthRaw) {
                    ForEach(StrokeWidth.allCases, id: \.self) { w in
                        Text(L10n.t(w.titleKey)).tag(w.rawValue)
                    }
                }
                .pickerStyle(.segmented) // segmented-ok: StrokeWidth has 3 cases
                .labelsHidden()
                .frame(width: 180)
            }
            .settingsRow()
        }
    }

    private func colorSwatch(_ color: MarkColor) -> some View {
        let rgb = color.rgb
        let swiftColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let selected = annotateColorRaw == color.rawValue
        return Circle()
            .fill(swiftColor)
            .frame(width: 20, height: 20)
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0.15), lineWidth: selected ? 2 : 1)
            )
            .onTapGesture { annotateColorRaw = color.rawValue }
    }

    // MARK: Gần đây

    private var recentSection: some View {
        SettingsSection(title: L10n.t("Gần đây")) {
            ToggleRow(title: L10n.t("Giữ lịch sử ảnh chụp"),
                      subtitle: L10n.t("Tối đa 50 ảnh, trong thư mục của XFinder trên máy này."),
                      isOn: $keepHistory)
                .settingsRow()
            SettingsDivider()
            if controller.history.isEmpty {
                Text(L10n.t("Chưa có ảnh chụp nào."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .settingsRow()
            } else {
                recentGrid
                    .settingsRow()
            }
            SettingsDivider()
            Button(L10n.t("Xoá lịch sử")) { controller.clearHistory() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controller.history.isEmpty)
                .settingsRow()
        }
    }

    private var recentGrid: some View {
        let items = Array(controller.history.prefix(12))
        let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: XFinderTokens.Space.row)]
        return LazyVGrid(columns: columns, spacing: XFinderTokens.Space.row) {
            ForEach(items) { item in
                recentTile(item)
            }
        }
    }

    private func recentTile(_ item: CaptureItem) -> some View {
        let image = controller.thumbnail(for: item, maxPixel: 320)
        return VStack(alignment: .leading, spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                    .fill(XFinderTokens.Fill.surface)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous))
                }
            }
            .frame(height: 90)
            .onTapGesture { controller.annotate(item) }
            .contextMenu {
                Button(L10n.t("Sao chép")) { controller.copy(item) }
                Button(L10n.t("Lưu")) { controller.save(item) }
                Button(L10n.t("Ghim lên màn hình")) { controller.pin(item) }
                Button(L10n.t("Chép chữ")) { controller.copyText(item) }
                Button(L10n.t("Hiện trong Finder")) { controller.reveal(item) }
                Divider()
                Button(L10n.t("Xoá"), role: .destructive) { controller.delete(item) }
            }
        }
    }
}
