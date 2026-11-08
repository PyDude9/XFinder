import SwiftUI
import AppKit

/// One connected display, as the Settings page shows it. Identity is the numeric CGDirectDisplayID —
/// never the name, which the user can change and macOS localizes.
private struct NotchDisplayChoice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isMain: Bool
    let hasPhysicalNotch: Bool
}

/// Read at render time so a screen plugged in after the page opened is never the stale list.
private func notchConnectedDisplays() -> [NotchDisplayChoice] {
    var seen = Set<UInt32>()
    return NSScreen.screens.compactMap { screen -> NotchDisplayChoice? in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = number.uint32Value
        guard seen.insert(id).inserted else { return nil }   // mirrored screens report the same display twice
        return NotchDisplayChoice(id: id,
                                  name: screen.localizedName,
                                  isMain: screen == NSScreen.screens.first,
                                  hasPhysicalNotch: screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil)
    }
}

/// Giao diện notch — the user comes here to decide whether the notch is on, what a hover does, which
/// display owns it, how it looks there, and which pages it shows. Split off "Notch & Khay thả" (P3):
/// this page owns the notch SURFACE; Khay thả (`DropTrayDetailView`) owns the files held in it.
///
/// Layout is the five groups from docs/specs/XF-NOTCH-02-interface-settings-layout.md. Every control keeps
/// its existing key, default and live effect. The display target is only WRITTEN here; which screen wins is
/// decided by `NotchDisplayTargetRules` (XF-NOTCH-01) and applied by `NotchSurfaceController`.
struct NotchInterfaceDetailView: View {
    // Master switch of the whole notch surface (NotchSurfaceController.swift:63-64) — turning it off
    // disables the tray, clipboard, now playing, agents and calendar surfaces all at once.
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true

    // Every hover on the notch is gated by this one switch (NotchSurfaceMachine.swift:151) — off, a
    // file drag and a shake still open the tray, but resting the pointer on the notch never does.
    @AppStorage("dropTray.hoverEnabled") private var hoverEnabled = true
    @AppStorage("notch.hoverOpens") private var hoverOpens = "peek"   // N2 (replaces notch.clipboardOnHover)
    @AppStorage("notch.hoverSpeed") private var hoverSpeed = "medium"
    @AppStorage("notch.clickOpens") private var clickOpens = "files"

    /// XF-NOTCH-01: which display owns the single surface. Reader: `NotchSurfaceController.displayTargetRaw`
    /// (`automatic` by default — the current behavior). The selected screen's CGDirectDisplayID lives in
    /// its own integer key so a screen name is never identity, and it is NOT cleared when the screen leaves.
    @AppStorage("notch.displayTarget") private var displayTarget = "automatic"
    @AppStorage("notch.displayTargetID") private var displayTargetID = 0

    // B7 notch behaviour. Readers: NotchSurfaceController (defaults must match — FeatureKeyDefaultsTests).
    @AppStorage("notch.pillOnPlainScreens") private var pillOnPlainScreens = true
    @AppStorage("notch.hideFromCapture") private var hideFromCapture = false
    @AppStorage("notch.fullscreenVisibility") private var fullscreenVisibility = "show"

    /// D1 #44 — page order + visibility; one reader: `NotchSurfaceController.pageOrderRaw`.
    @AppStorage("notch.pages") private var pagesRaw = "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"
    /// D1 #47 — accent of the notch surfaces; one reader: `NotchSurfaceController.accentName`.
    @AppStorage("notch.accent") private var accent = "system"

    /// Bumped by macOS' screen-parameter notification. The list itself is read from `NSScreen.screens`
    /// during body evaluation, so it can never be the stale copy of a screen that has since left; the
    /// counter only tells SwiftUI to redraw (event-driven — no timer polls the display list).
    @State private var screenRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Giao diện notch"),
                    subtitle: L10n.t("Bật tắt notch, chọn cách nó mở, màn hình đích, hình dạng và quyền riêng tư, cùng các trang nó hiện."))

                enabledSection
                openingSection
                    .disabled(!notchEnabled)
                displayTargetSection
                    .disabled(!notchEnabled)
                appearanceSection
                    .disabled(!notchEnabled)
                pagesSection
                    .disabled(!notchEnabled)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        // macOS reports a plug/unplug/rearrange here; redrawing re-reads the list so a new screen is
        // selectable and a departed one shows as disconnected instead of vanishing from the rows.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenRevision &+= 1
        }
    }

    // MARK: - 1. Bật/tắt

    private var enabledSection: some View {
        SettingsSection(
            title: L10n.t("Bật/tắt"),
            footer: L10n.t("Đây là công tắc chính của toàn bộ bề mặt notch; các nhóm bên dưới chỉ chỉnh cách nó hiện và cách nó mở.")
        ) {
            ToggleRow(title: L10n.t("Bật notch"),
                      subtitle: L10n.t("Tắt thì notch và các trang của nó biến mất khỏi màn hình. Những tính năng khác của XFinder — clipboard, chụp màn hình, sắp xếp cửa sổ, chuột và cử chỉ — vẫn chạy bình thường."),
                      isOn: $notchEnabled)
                .onChange(of: notchEnabled) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            if !notchEnabled {
                SettingsDivider()
                InlineNote(kind: .warning,
                           text: L10n.t("Notch đang tắt. Các nhóm còn lại bị khoá để thấy rõ chúng không có tác dụng; bật lại notch để chỉnh tiếp — không giá trị nào bị đặt lại."))
                    .settingsRow()
            }
        }
    }

    // MARK: - 2. Cách mở

    /// The user comes here to decide what resting the pointer on the notch does, and what a deliberate
    /// click opens. Kept in one group because the two are independent routes into the same hub.
    private var openingSection: some View {
        SettingsSection(
            title: L10n.t("Cách mở"),
            footer: L10n.t("Rê chuột và bấm là hai đường độc lập. Lối mở trang cụ thể — liên kết sâu, phím tắt, URL xfinder:// — luôn giữ đúng trang được yêu cầu. Trang đích đang bị tắt ở nhóm Trang và màu sẽ được thay bằng trang đang hiện.")
        ) {
            ToggleRow(title: L10n.t("Rê chuột vào notch"),
                      subtitle: L10n.t("Nút chính của mọi hiệu ứng rê chuột trên notch. Tắt thì kéo file vào notch hoặc lắc khi đang kéo file vẫn mở được khay — chỉ riêng việc dừng con trỏ ở notch là không còn phản ứng."),
                      isOn: $hoverEnabled)
                .settingsRow()
            SettingsDivider()
            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Rê chuột vào notch mở")).font(XFinderTokens.Font.row)
                    Text(L10n.t("Chỉ xem nhanh: dừng con trỏ hiện tệp đang giữ hoặc bài đang phát; khay trống không mở gì. Các lựa chọn khác mở thẳng trang đó. Theo hoạt động chọn trang theo việc đang diễn ra: agent chờ bạn → Agent AI, nhạc đang phát → Đang phát, có tệp → Khay, còn lại → Clipboard."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: XFinderTokens.Space.inline)
                Picker("", selection: $hoverOpens) {
                    ForEach(NotchHoverOpen.allCases, id: \.rawValue) { h in
                        Text(L10n.t(h.labelKey)).tag(h.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 170)
                .onChange(of: hoverOpens) { NotchSurfaceController.shared.applySettings() }
            }
            .disabled(!hoverEnabled)
            .settingsRow()
            SettingsDivider()
            HStack(alignment: .firstTextBaseline) {
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
                // segmented-ok: 3 cases
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                .onChange(of: hoverSpeed) { NotchSurfaceController.shared.applySettings() }
            }
            .disabled(!hoverEnabled)
            .settingsRow()
            SettingsDivider()
            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Bấm mở notch vào trang")).font(XFinderTokens.Font.row)
                    Text(L10n.t("Chọn một trang cố định, trang dùng lần cuối hoặc trang phù hợp hoạt động hiện tại. Áp dụng khi bấm huy hiệu hoặc dải xem nhanh."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: XFinderTokens.Space.inline)
                Picker("", selection: $clickOpens) {
                    ForEach(NotchClickOpen.allCases, id: \.rawValue) { rule in
                        Text(L10n.t(rule.labelKey)).tag(rule.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 170)
            }
            .settingsRow()
        }
    }

    // MARK: - 3. Màn hình đích

    private var displayTargetSection: some View {
        SettingsSection(
            title: L10n.t("Màn hình đích"),
            footer: L10n.t("Tự động giữ cách chạy hiện tại: theo con trỏ khi bạn đang thao tác, khi rảnh thì ở màn hình có notch cứng, không có thì ở màn hình chính. Màn hình tích hợp: không có notch cứng thì dùng màn hình chính và vẽ notch ảo. Màn hình chính: theo màn hình macOS đang đặt là chính, không xác định được thì dùng màn hình đầu tiên.")
        ) {
            PickerRow(title: L10n.t("Notch hiện trên"),
                      subtitle: L10n.t("Tự động, màn hình có notch cứng, màn hình chính, hay một màn hình cụ thể."),
                      selection: $displayTarget, width: 200) {
                Text(L10n.t("Tự động")).tag(NotchDisplayTargetRules.Target.automatic.rawValue)
                Text(L10n.t("Màn hình tích hợp")).tag(NotchDisplayTargetRules.Target.builtIn.rawValue)
                Text(L10n.t("Màn hình chính")).tag(NotchDisplayTargetRules.Target.main.rawValue)
                Text(L10n.t("Chọn màn hình…")).tag(NotchDisplayTargetRules.Target.specific.rawValue)
                // A stored value this build does not know stays visible and selected — opening Settings
                // must never silently rewrite it (the reader still parses it as automatic, so it keeps
                // behaving that way until the user picks something else on purpose).
                if !Self.knownTargets.contains(displayTarget) {
                    Text("\(L10n.t("Giá trị đã lưu không nhận ra: "))\(displayTarget)").tag(displayTarget)
                }
            }
            .onChange(of: displayTarget) { NotchSurfaceController.shared.applySettings() }
            .settingsRow()

            if NotchDisplayTargetRules.Target.parse(displayTarget) == .specific {
                SettingsDivider()
                HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Màn hình đã chọn")).font(XFinderTokens.Font.row)
                        Text(L10n.t("Danh sách chỉ có màn hình đang kết nối. ID màn hình được giữ nguyên khi rút ra rồi cắm lại, và notch tự quay lại màn hình đó."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: XFinderTokens.Space.inline)
                    Picker("", selection: chosenDisplayBinding) {
                        if savedDisplayID == nil {
                            Text(L10n.t("Chưa chọn màn hình")).tag(UInt32(0))
                        }
                        ForEach(connectedDisplays) { display in
                            Text("\(display.name) — ID \(display.id)").tag(display.id)
                        }
                        if let saved = savedDisplayID, !connectedDisplays.contains(where: { $0.id == saved }) {
                            Text("\(L10n.t("Đã lưu")) — ID \(saved) — \(L10n.t("không kết nối"))").tag(saved)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 230)
                    .accessibilityLabel(L10n.t("Màn hình đã chọn"))
                }
                .settingsRow()
            }

            SettingsDivider()
            if let resolved = resolvedDisplay {
                LabeledLine(label: L10n.t("Màn hình notch dùng khi rảnh"),
                            value: "\(resolved.name) — ID \(resolved.id)")
                    .settingsRow()
            } else {
                InlineNote(kind: .warning,
                           text: L10n.t("macOS chưa báo màn hình nào. Notch tạm ẩn và tự hiện lại khi có màn hình; lựa chọn đã lưu không bị xoá."))
                    .settingsRow()
            }
            if let fallbackNote {
                SettingsDivider()
                InlineNote(kind: .warning, text: fallbackNote)
                    .settingsRow()
            }
        }
    }

    private static let knownTargets: [String] = [NotchDisplayTargetRules.Target.automatic.rawValue,
                                                 NotchDisplayTargetRules.Target.builtIn.rawValue,
                                                 NotchDisplayTargetRules.Target.main.rawValue,
                                                 NotchDisplayTargetRules.Target.specific.rawValue]

    /// The display list the page shows: only what macOS currently reports, re-read on every body pass
    /// after a screen-parameter change.
    private var connectedDisplays: [NotchDisplayChoice] {
        _ = screenRevision
        return notchConnectedDisplays()
    }

    /// A CGDirectDisplayID persisted as an integer; zero (or a value that cannot be one) means none.
    private var savedDisplayID: UInt32? {
        let value = displayTargetID
        guard value > 0, let id = UInt32(exactly: value) else { return nil }
        return id
    }

    private var chosenDisplayBinding: Binding<UInt32> {
        Binding(
            get: { savedDisplayID ?? 0 },
            set: { newID in
                // Choosing a screen IS choosing the specific mode; the ID is never cleared afterwards.
                displayTargetID = Int(newID)
                if displayTarget != NotchDisplayTargetRules.Target.specific.rawValue {
                    displayTarget = NotchDisplayTargetRules.Target.specific.rawValue
                }
                NotchSurfaceController.shared.applySettings()
            })
    }

    /// XF-NOTCH-01's resolver, called with no pointer/active surface: it answers "where does the notch sit
    /// while idle". The view only reads it to show the truth — it never decides the display itself.
    private var displayResolution: NotchDisplayTargetRules.Resolution? {
        NotchDisplayTargetRules.resolve(
            target: NotchDisplayTargetRules.Target.parse(displayTarget),
            selectedDisplayID: savedDisplayID,
            displays: connectedDisplays.map {
                NotchDisplayTargetRules.Display(id: $0.id, isMain: $0.isMain, hasPhysicalNotch: $0.hasPhysicalNotch)
            })
    }

    private var resolvedDisplay: NotchDisplayChoice? {
        guard let id = displayResolution?.displayID else { return nil }
        return connectedDisplays.first { $0.id == id }
    }

    /// The resolver's own fallback reason, in words. Never resets the saved choice.
    private var fallbackNote: String? {
        guard let fallback = displayResolution?.fallback else { return nil }
        switch fallback {
        case .builtInUnavailable:
            return L10n.t("Máy này không có màn hình với notch cứng. Notch dùng màn hình chính (hoặc màn hình dùng được đầu tiên) và vẽ notch ảo.")
        case .mainUnavailable:
            return L10n.t("macOS chưa xác định được màn hình chính. Notch dùng màn hình dùng được đầu tiên.")
        case .selectedDisplayUnavailable:
            return savedDisplayID == nil
                ? L10n.t("Chưa chọn màn hình nào. Notch dùng màn hình chính (hoặc màn hình dùng được đầu tiên) cho tới khi bạn chọn một màn hình.")
                : L10n.t("Màn hình đã chọn hiện không kết nối. Notch tạm dùng màn hình chính (hoặc màn hình dùng được đầu tiên); ID vẫn được giữ và notch tự quay lại khi màn hình kết nối lại.")
        }
    }

    // MARK: - 4. Hiển thị và quyền riêng tư

    /// The user comes here to decide how the notch looks on this Mac — a notch-less screen, fullscreen
    /// apps — and what it does about screen recordings and screen sharing.
    private var appearanceSection: some View {
        SettingsSection(
            title: L10n.t("Hiển thị và quyền riêng tư"),
            footer: L10n.t("Trên màn hình không có notch, XFinder vẽ một notch ảo: các bề mặt dính mép trên, ở giữa thanh menu, y như ở notch thật; rê chuột vào giữa mép trên để xem các tệp đang giữ.")
        ) {
            ToggleRow(title: L10n.t("Pill trên màn hình không có notch"),
                      subtitle: L10n.t("Màn hình ngoài / iMac: tệp đang giữ, hẹn giờ và bài đang phát hiện trong một viên thuốc nhỏ dính mép trên, giữa thanh menu. Chưa đo trên màn hình thật — chỉ hình học."),
                      isOn: $pillOnPlainScreens)
                .onChange(of: pillOnPlainScreens) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Hiển thị notch trong ứng dụng toàn màn hình")).font(XFinderTokens.Font.row)
                    Text(L10n.t("XFinder chỉ ẩn notch khi nhận diện được cửa sổ phủ khớp màn hình. Nếu không xác định chắc chắn, notch vẫn hiện. Thao tác đang chạy, yêu cầu duyệt và khung nhập luôn được giữ trên màn hình."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("Chế độ chỉ ẩn theo media cần ứng dụng phát nhạc/video cung cấp trạng thái Now Playing đang chạy."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: XFinderTokens.Space.inline)
                Picker("", selection: $fullscreenVisibility) {
                    ForEach(NotchFullscreenVisibility.allCases, id: \.rawValue) { policy in
                        Text(L10n.t(policy.labelKey)).tag(policy.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 220)
                .onChange(of: fullscreenVisibility) { NotchSurfaceController.shared.applySettings() }
            }
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Không hiện trong ảnh chụp, quay và chia sẻ màn hình"),
                      subtitle: L10n.t("Bật thì cửa sổ notch đặt sharingType = none, nên macOS không đưa cửa sổ đó vào luồng chia sẻ (đo được kCGWindowSharingState = 0)."),
                      isOn: $hideFromCapture)
                .onChange(of: hideFromCapture) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            InlineNote(kind: .warning,
                       text: L10n.t("Đây là trạng thái chia sẻ của riêng cửa sổ notch, không phải bảo đảm cho mọi cách chụp: công cụ chụp khác, bản macOS khác hoặc cách chia sẻ khác có thể vẫn thấy notch."))
                .padding(.bottom, 2)
        }
    }

    // MARK: - 5. Trang và màu

    /// D1 #44 / #47: which tabs the hub shows and in what order, and the surfaces' accent.
    private var pagesSection: some View {
        let shown = NotchPages.parse(pagesRaw)
        return SettingsSection(
            title: L10n.t("Trang và màu"),
            footer: L10n.t("Bật, tắt và sắp xếp thứ tự các tab trong hub. Tắt Clipboard thì ⌘⇧V mở khay nổi cũ. Vuốt hai ngón ngang trên dải tab để đổi trang.")
        ) {
            ForEach(Array(NotchPages.allInOrder(shown: shown).enumerated()), id: \.element) { entry in
                let page = entry.element
                let isShown = shown.contains(page)
                let index = shown.firstIndex(of: page)
                if entry.offset > 0 { SettingsDivider() }
                HStack(spacing: XFinderTokens.Space.inline) {
                    Image(systemName: pageIcon(page)).font(XFinderTokens.Font.sectionIcon).foregroundColor(.secondary).frame(width: 18)
                    Text(pageTitle(page)).font(XFinderTokens.Font.row)
                    Spacer()
                    Button { pagesRaw = NotchPages.serialize(NotchPages.moved(page, by: -1, in: shown)) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!isShown || index == 0)
                        .help(L10n.t("Lên"))
                        .accessibilityLabel(L10n.t("Lên"))
                    Button { pagesRaw = NotchPages.serialize(NotchPages.moved(page, by: 1, in: shown)) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!isShown || index == shown.count - 1)
                        .help(L10n.t("Xuống"))
                        .accessibilityLabel(L10n.t("Xuống"))
                    Toggle("", isOn: Binding(get: { isShown },
                                             set: { _ in pagesRaw = NotchPages.serialize(NotchPages.toggled(page, in: shown)) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .disabled(isShown && shown.count == 1)
                }
                .settingsRow()
            }
            SettingsDivider()
            HStack {
                Spacer()
                Button(L10n.t("Khôi phục mặc định")) { pagesRaw = NotchPages.defaultRaw }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .settingsRow()
            SettingsDivider()
            PickerRow(title: L10n.t("Màu nhấn"),
                      subtitle: L10n.t("Màu của viền chọn, thẻ đang chọn và các điểm nhấn trên notch."),
                      selection: $accent, width: 150) {
                Text(L10n.t("Theo hệ thống")).tag("system")
                Text(L10n.t("Xanh dương")).tag("blue")
                Text(L10n.t("Tím")).tag("purple")
                Text(L10n.t("Hồng")).tag("pink")
                Text(L10n.t("Cam")).tag("orange")
                Text(L10n.t("Xanh lá")).tag("green")
                Text(L10n.t("Xanh ngọc")).tag("teal")
            }
            .onChange(of: accent) { NotchSurfaceController.shared.applySettings() }
            .settingsRow()
        }
        .onChange(of: pagesRaw) { NotchSurfaceController.shared.applySettings() }
    }

    /// One title and one symbol per page, shared with the hub (`NotchPages`).
    private func pageTitle(_ p: NotchSurfaceMachine.Page) -> String { L10n.t(NotchPages.titleKey(p)) }
    private func pageIcon(_ p: NotchSurfaceMachine.Page) -> String { NotchPages.symbol(p) }
}
