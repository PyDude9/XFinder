import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// One connected display, as the Settings page shows it. Identity is the numeric CGDirectDisplayID —
/// never the name, which the user can change and macOS localizes.
private struct NotchDisplayChoice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isMain: Bool
    let hasPhysicalNotch: Bool
    let frame: CGRect
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
                                  hasPhysicalNotch: screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil,
                                  frame: screen.frame)
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
    enum ToolPage { case stocks, revenue }

    var embeddedInNotch = false
    private let toolPage: ToolPage?
    @State private var inlineSection: InlineSection = .tabs
    @State private var draggedTab: NotchDestinationID?
    @State private var scaleRevision = 0
    private static let tabDragType = UTType(importedAs: "com.xfinder.app.island-tab")

    private enum InlineSection: String, CaseIterable {
        case general, display, tabs, appearance, stocks, revenue, websiteAnalytics, about

        var title: String {
            switch self {
            case .general: L10n.t("Chung")
            case .display: L10n.t("Màn hình đích")
            case .tabs: L10n.t("Các tab")
            case .appearance: L10n.t("Giao diện")
            case .stocks: L10n.t("Chứng khoán")
            case .revenue: L10n.t("Doanh thu")
            case .websiteAnalytics: L10n.t("Phân tích web")
            case .about: L10n.t("Giới thiệu")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .display: "display"
            case .tabs: "rectangle.bottomthird.inset.filled"
            case .appearance: "paintbrush"
            case .stocks: "chart.line.uptrend.xyaxis"
            case .revenue: "banknote.fill"
            case .websiteAnalytics: "chart.bar.xaxis"
            case .about: "info.circle"
            }
        }
    }

    init(embeddedInNotch: Bool = false, showStocks: Bool = false, toolPage: ToolPage? = nil) {
        self.embeddedInNotch = embeddedInNotch
        self.toolPage = toolPage
        _inlineSection = State(initialValue: showStocks ? .stocks : .tabs)
    }
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

    /// D1 #44 — legacy page order + visibility; kept for migration compatibility (`NotchPagesTests`, `FeatureKeyDefaultsTests`).
    @AppStorage("notch.pages") private var pagesRaw = "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"
    /// XF-ISLAND-C — unified ordered visibility catalog for legacy pages + extra modules (`NotchDestinationCatalog`).
    @AppStorage("notch.tabCatalog.v1") private var catalogRaw = ""
    /// D1 #47 — accent of the notch surfaces; one reader: `NotchSurfaceController.accentName`.
    @AppStorage("notch.accent") private var accent = "system"

    /// Bumped by macOS' screen-parameter notification. The list itself is read from `NSScreen.screens`
    /// during body evaluation, so it can never be the stale copy of a screen that has since left; the
    /// counter only tells SwiftUI to redraw (event-driven — no timer polls the display list).
    @State private var screenRevision = 0

    // Explicit Stocks/Crypto watchlist management (persisted independently of quote provider configuration).
    @State private var stocksWatchlist: [StockAssetDescriptor] = []
    @State private var stocksKeyDraft = ""
    @AppStorage(StocksAPIKey.Source.preferenceKey) private var selectedStockSource: StocksAPIKey.Source = .massive
    @State private var hasStocksKey = false
    @State private var stocksKeySaveFailed = false
    @State private var stocksKeySaveSucceeded = false
    @State private var stocksSearchQuery = ""

    // Explicit read-only Revenue connector form state (starts disconnected; tokens live only in Keychain).
    @State private var stripeAccountId = ""
    @State private var stripeLabel = ""
    @State private var stripeTimeZone = "America/New_York"
    @State private var stripeTokenInput = ""
    @State private var stripeStoredMask: String?
    @State private var stripeFeedback: String?

    @State private var shopifyShopDomain = ""
    @State private var shopifyLabel = ""
    @State private var shopifyTimeZone = "America/New_York"
    @State private var shopifyHasPayoutScope = false
    @State private var shopifyTokenInput = ""
    @State private var shopifyStoredMask: String?
    @State private var shopifyFeedback: String?

    private static let revenueTimeZoneChoices = [
        "America/New_York",
        "America/Los_Angeles",
        "UTC",
        "Europe/London",
        "Asia/Ho_Chi_Minh",
        "Asia/Tokyo",
    ]

    var body: some View {
        Group {
            if embeddedInNotch { inlineBody }
            else if let toolPage { toolPageBody(toolPage) }
            else { windowBody }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenRevision &+= 1
        }
    }

    private func toolPageBody(_ page: ToolPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                switch page {
                case .stocks:
                    PageHeader(title: L10n.t("Chứng khoán"), subtitle: L10n.t("Cài nguồn giá và danh sách theo dõi trên Dynamic Island."))
                    stocksWatchlistSection
                case .revenue:
                    PageHeader(title: L10n.t("Doanh thu"), subtitle: L10n.t("Quản lý kết nối Stripe và Shopify trên Dynamic Island."))
                    revenueConnectionsSection
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            switch page {
            case .stocks: reloadStocksWatchlistForm()
            case .revenue: reloadRevenueConnectionForms()
            }
        }
    }

    private var windowBody: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                    PageHeader(title: L10n.t("Giao diện notch"),
                        subtitle: L10n.t("Bật tắt notch, chọn cách nó mở, màn hình đích, hình dạng và quyền riêng tư, cùng các trang nó hiện."))

                    HStack {
                        Button(L10n.t("Các tab")) { scroll.scrollTo(InlineSection.tabs, anchor: .top) }
                        Button(L10n.t("Chứng khoán")) { AppState.shared.navigate(to: .stocks) }
                    }
                    .buttonStyle(.bordered)

                    enabledSection
                    openingSection
                        .disabled(!notchEnabled)
                    displayTargetSection
                        .disabled(!notchEnabled)
                    inlineScaleSection
                        .disabled(!notchEnabled)
                    appearanceSection
                        .disabled(!notchEnabled)
                    pagesSection
                        .disabled(!notchEnabled)
                        .id(InlineSection.tabs)
                }
                .padding(.bottom, XFinderTokens.Space.section)
                .pageWidthSafe()
            }
        }
        .background(XFinderTokens.Settings.contentBackground)
        // macOS reports a plug/unplug/rearrange here; redrawing re-reads the list so a new screen is
        // selectable and a departed one shows as disconnected instead of vanishing from the rows.
    }

    private var inlineBody: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(InlineSection.allCases, id: \.self) { section in
                    Button {
                        inlineSection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .font(XFinderTokens.Font.caption)
                            .fontWeight(inlineSection == section ? .semibold : .regular)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(.white.opacity(inlineSection == section ? 0.13 : 0), in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(section.title)
                    .accessibilityAddTraits(inlineSection == section ? .isSelected : [])
                }
            }
            .frame(width: 139)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch inlineSection {
                    case .general:
                        enabledSection
                        openingSection
                        Button(L10n.t("Phím tắt")) {
                            NotchSurfaceController.shared.dismiss()
                            AppState.shared.navigate(to: .shortcuts)
                        }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                    case .display:
                        inlineScaleSection
                        displayTargetSection
                    case .tabs: inlineTabs
                    case .appearance: appearanceSection
                    case .stocks: stocksWatchlistSection
                        .onAppear { reloadStocksWatchlistForm() }
                    case .revenue: revenueConnectionsSection
                        .onAppear { reloadRevenueConnectionForms() }
                    case .websiteAnalytics: WebsiteAnalyticsSettingsPage(inline: true)
                    case .about:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("XFinder").font(.headline)
                            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                                Text(version).font(.caption).foregroundStyle(.secondary)
                            }
                            Button(L10n.t("Cài đặt đầy đủ")) {
                                NotchSurfaceController.shared.openNotchSettings()
                            }
                            .buttonStyle(NotchPillButtonStyle(primary: false))
                        }
                        .padding(.leading, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(inlineSection)
        }
        .environment(\.colorScheme, .dark)
        .onDisappear { draggedTab = nil }
    }

    private var inlineScaleSection: some View {
        let _ = scaleRevision
        let controller = NotchSurfaceController.shared
        let displays = connectedDisplays
        return SettingsSection(title: L10n.t("Cỡ notch theo màn hình")) {
            if !displays.isEmpty { inlineDisplayMap(displays).padding(.vertical, 8) }
            ForEach(displays) { display in
                HStack {
                    Label(display.name, systemImage: display.hasPhysicalNotch ? "laptopcomputer" : "display")
                        .lineLimit(1)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { controller.displayScale(for: display.id) },
                        set: { scale in
                            controller.setDisplayScale(scale, for: display.id)
                            scaleRevision &+= 1
                        })) {
                        Text(L10n.t("Nhỏ")).tag(NotchDisplayScale.small)
                        Text(L10n.t("Chuẩn")).tag(NotchDisplayScale.regular)
                        Text(L10n.t("Lớn")).tag(NotchDisplayScale.large)
                    }
                    .labelsHidden()
                    .accessibilityLabel(display.name)
                }
                .settingsRow()
            }
        }
    }

    private func inlineDisplayMap(_ displays: [NotchDisplayChoice]) -> some View {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        return GeometryReader { geometry in
            let scale = min(geometry.size.width / max(1, bounds.width), geometry.size.height / max(1, bounds.height))
            ForEach(displays) { display in
                let frame = display.frame
                let width = max(2, frame.width * scale - 3)
                let height = max(2, frame.height * scale - 3)
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(Color.primary.opacity(display.isMain ? 0.22 : 0.10))
                    .overlay {
                        if width > 30 && height > 16 {
                            Image(systemName: display.hasPhysicalNotch ? "laptopcomputer" : "display")
                                .font(.caption)
                        }
                    }
                    .frame(width: width, height: height)
                    .position(x: geometry.size.width / 2 + (frame.midX - bounds.midX) * scale,
                              y: geometry.size.height / 2 - (frame.midY - bounds.midY) * scale)
                    .help(display.name)
            }
        }
        .frame(height: 54)
        .accessibilityHidden(true)
    }

    private var inlineTabs: some View {
        let catalog = currentCatalog
        return VStack(alignment: .leading, spacing: 8) {
            inlineTabGroup(catalog.entries.filter(\.enabled), title: L10n.t("Tab đang bật"))
            inlineTabGroup(catalog.entries.filter { !$0.enabled }, title: L10n.t("Công cụ đang tắt"))
            Button(L10n.t("Khôi phục mặc định"), action: resetCatalogToDefaults)
                .buttonStyle(NotchPillButtonStyle(primary: false))
        }
    }

    private func inlineTabGroup(_ entries: [NotchTabEntry], title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(XFinderTokens.Font.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                inlineTabRow(entry, previous: index > 0 ? entries[index - 1].id : nil,
                             next: index + 1 < entries.count ? entries[index + 1].id : nil)
            }
        }
    }

    private func inlineTabRow(_ entry: NotchTabEntry, previous: NotchDestinationID?, next: NotchDestinationID?) -> some View {
        let id = entry.id
        let readiness = NotchSurfaceController.shared.destinationAvailability.readiness(for: id)
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
                .onDrag {
                    draggedTab = id
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: Self.tabDragType.identifier, visibility: .ownProcess) { completion in
                        completion(Data(), nil)
                        return nil
                    }
                    return provider
                }
                .accessibilityHidden(true)
            Image(systemName: id.symbol).frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(id.titleKey)).lineLimit(1)
                if let subtitle = readinessSubtitle(for: readiness) {
                    Text(subtitle).font(XFinderTokens.Font.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if let target = configureDestination(for: id, readiness: readiness) {
                Button(L10n.t("Cấu hình…")) {
                    if embeddedInNotch, let section = inlineConfigurationSection(for: id) {
                        inlineSection = section
                    } else {
                        NotchSurfaceController.shared.dismiss()
                        AppState.shared.navigate(to: target)
                    }
                }
                .buttonStyle(.link)
            }
            inlineMoveButton(id, to: previous, symbol: "chevron.up", title: L10n.t("Lên"))
            inlineMoveButton(id, to: next, symbol: "chevron.down", title: L10n.t("Xuống"))
            Toggle(L10n.t(id.titleKey), isOn: Binding(
                get: { entry.enabled },
                set: { commitCatalog(currentCatalog.setting(id, enabled: $0)) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .font(XFinderTokens.Font.caption)
        .padding(.horizontal, 6)
        .frame(minHeight: XFinderTokens.Settings.rowMinHeight)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
        .onDrop(of: [Self.tabDragType], isTargeted: nil) { _ in
            guard let source = draggedTab else { return false }
            draggedTab = nil
            return moveInlineTab(source, to: id)
        }
    }

    private func inlineMoveButton(_ id: NotchDestinationID, to target: NotchDestinationID?, symbol: String, title: String) -> some View {
        Button {
            if let target { _ = moveInlineTab(id, to: target) }
        } label: {
            Image(systemName: symbol).frame(width: 16, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .help(title)
        .accessibilityLabel(title)
    }

    private func moveInlineTab(_ id: NotchDestinationID, to target: NotchDestinationID) -> Bool {
        let current = currentCatalog
        let moved = current.movedWithinVisibilityGroup(id, to: target)
        guard current != moved else { return false }
        commitCatalog(moved)
        return true
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
    }

    // MARK: - 5. Dynamic Island tabs

    private var currentCatalog: NotchTabCatalogState {
        let legacy = UserDefaults.standard.string(forKey: NotchPages.key)
        return NotchDestinationCatalog.parse(
            catalogRaw: catalogRaw.isEmpty ? nil : catalogRaw,
            legacyPagesRaw: legacy
        )
    }

    private func commitCatalog(_ next: NotchTabCatalogState) {
        NotchSurfaceController.shared.commitNotchCatalog(next)
    }

    private func resetCatalogToDefaults() {
        commitCatalog(NotchDestinationCatalog.defaultState)
    }

    /// XF-ISLAND-C / D1 #44 / #47: unified ordered visibility for every Dynamic Island destination
    /// (legacy pages + extra modules), preserving hidden-tab order, separating enablement from readiness,
    /// and allowing intentional all-hidden with always-accessible recovery.
    private var pagesSection: some View {
        SettingsSection(title: L10n.t("Các tab Dynamic Island")) {
            inlineTabs.settingsRow()
        }
        .onChange(of: catalogRaw) { NotchSurfaceController.shared.applySettings() }
        .onChange(of: pagesRaw) { NotchSurfaceController.shared.applySettings() }
    }

    private var stocksWatchlistSection: some View {
        let searchHits = StocksWatchlistCatalog.search(stocksSearchQuery)
        let savedIds = Set(stocksWatchlist.map(\.id))

        return SettingsSection(title: L10n.t("Danh sách theo dõi Chứng khoán & BTC/USD")) {
            stocksSourceControls.settingsRow()
            SettingsDivider()
            InlineNote(
                text: L10n.t("Quản lý mã theo dõi ngay cả khi chưa cấu hình nguồn giá. Danh sách bạn lưu (kể cả danh sách trống) được giữ nguyên; Bitcoin (BTC/USD) dùng phiên 24/7 và mốc so sánh riêng.")
            )
            .settingsRow()

            SettingsDivider()
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                TextField(L10n.t("Tìm mã để thêm (S&P 500, AAPL, NVDA, CROX, BTC/USD...)"), text: $stocksSearchQuery)
                    .textFieldStyle(.roundedBorder)

                let trimmedQuery = stocksSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedQuery.isEmpty {
                    if searchHits.isEmpty {
                        Text(L10n.t("Không tìm thấy mã phù hợp"))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(searchHits.prefix(6)) { hit in
                            HStack(spacing: XFinderTokens.Space.tight) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.displayName)
                                        .font(XFinderTokens.Font.row)
                                        .lineLimit(1)
                                    Text("\(hit.shortTicker) · \(hit.exchange) · \(L10n.t(hit.kind.badgeKey))")
                                        .font(XFinderTokens.Font.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: XFinderTokens.Space.tight)
                                if savedIds.contains(hit.id) {
                                    Text(L10n.t("Đã có"))
                                        .font(XFinderTokens.Font.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Button(L10n.t("Thêm")) { addStocksAsset(hit) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .settingsRow()

            SettingsDivider()
            if stocksWatchlist.isEmpty {
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Danh sách theo dõi đang trống — lựa chọn trống này được giữ lại."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                .settingsRow()
            } else {
                ForEach(Array(stocksWatchlist.enumerated()), id: \.element.id) { idx, asset in
                    if idx > 0 { SettingsDivider() }
                    HStack(spacing: XFinderTokens.Space.tight) {
                        Image(systemName: asset.kind.sfSymbol)
                            .font(XFinderTokens.Font.sectionIcon)
                            .foregroundColor(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(asset.displayName)
                                .font(XFinderTokens.Font.row)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(asset.shortTicker) · \(asset.exchange) · \(L10n.t(asset.kind.badgeKey))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: XFinderTokens.Space.tight)
                        Button { moveStocksAsset(from: idx, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(idx == 0)
                            .help(L10n.t("Lên"))
                            .accessibilityLabel(L10n.t("Lên"))
                        Button { moveStocksAsset(from: idx, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(idx == stocksWatchlist.count - 1)
                            .help(L10n.t("Xuống"))
                            .accessibilityLabel(L10n.t("Xuống"))
                        Button { removeStocksAsset(id: asset.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help(L10n.t("Xóa mã"))
                            .accessibilityLabel(L10n.t("Xóa mã"))
                    }
                    .settingsRow()
                }
            }

            SettingsDivider()
            HStack {
                Spacer()
                Button(L10n.t("Khôi phục danh sách mặc định")) { resetStocksWatchlistToDefaults() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .settingsRow()
        }
    }

    private func reloadStocksWatchlistForm() {
        selectedStockSource = .massive
        stocksWatchlist = UserDefaultsStocksWatchlistStore().loadWatchlist()
        hasStocksKey = StocksAPIKey.read(for: .massive) != nil
    }

    private var stocksSourceControls: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(L10n.t("Nguồn giá chứng khoán"))
                Spacer()
                Label(L10n.t("Massive · Basic miễn phí"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
            }
            if hasStocksKey {
                Label(L10n.t("Đã lưu khóa API trong Keychain"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                InlineNote(text: L10n.t("Massive Basic miễn phí: dữ liệu cuối ngày, tối đa 5 yêu cầu mỗi phút và tối đa 2 năm lịch sử. Quyền từng mã phụ thuộc loại tài sản."))
                Link(L10n.t("Lấy khóa Massive Basic"), destination: URL(string: "https://massive.com/pricing?product=stocks")!)
            }
            HStack {
                SecureField(L10n.t("Khóa API Massive"), text: $stocksKeyDraft)
                    .onChange(of: stocksKeyDraft) {
                        stocksKeySaveSucceeded = false
                        stocksKeySaveFailed = false
                    }
                Button(L10n.t("Lưu khóa")) { saveStocksKey(stocksKeyDraft) }
                    .disabled(stocksKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasStocksKey {
                    Button(L10n.t("Xóa khóa"), role: .destructive) { saveStocksKey("") }
                }
            }
            if stocksKeySaveFailed {
                Text(L10n.t("Không lưu được khóa API")).foregroundStyle(.orange)
            } else if stocksKeySaveSucceeded {
                Label(L10n.t("Đã lưu khóa Massive vào Keychain. Mở Stocks hoặc làm mới để thử quyền truy cập."),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func saveStocksKey(_ value: String) {
        guard StocksAPIKey.save(value, for: selectedStockSource) else {
            stocksKeySaveFailed = true
            stocksKeySaveSucceeded = false
            return
        }
        stocksKeyDraft = ""
        stocksKeySaveFailed = false
        stocksKeySaveSucceeded = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        hasStocksKey = StocksAPIKey.read(for: selectedStockSource) != nil
        NotchSurfaceController.shared.reloadStocksProvider()
    }

    private func commitStocksWatchlist(_ next: [StockAssetDescriptor]) {
        stocksWatchlist = next
        UserDefaultsStocksWatchlistStore().saveWatchlist(next)
        NotchSurfaceController.shared.reloadStocksWatchlist()
    }

    private func addStocksAsset(_ asset: StockAssetDescriptor) {
        guard !stocksWatchlist.contains(where: { $0.id == asset.id }) else { return }
        commitStocksWatchlist(stocksWatchlist + [asset])
    }

    private func removeStocksAsset(id: String) {
        commitStocksWatchlist(stocksWatchlist.filter { $0.id != id })
    }

    private func moveStocksAsset(from index: Int, by delta: Int) {
        let target = index + delta
        guard stocksWatchlist.indices.contains(index), stocksWatchlist.indices.contains(target) else { return }
        var copy = stocksWatchlist
        let item = copy.remove(at: index)
        copy.insert(item, at: target)
        commitStocksWatchlist(copy)
    }

    private func resetStocksWatchlistToDefaults() {
        let store = UserDefaultsStocksWatchlistStore()
        store.resetToDefaults()
        stocksWatchlist = store.loadWatchlist()
        NotchSurfaceController.shared.reloadStocksWatchlist()
    }

    private var revenueConnectionsSection: some View {
        SettingsSection(title: L10n.t("Kết nối Doanh thu bán app (chỉ đọc)")) {
            InlineNote(
                text: L10n.t("Khóa chỉ đọc được lưu riêng theo tài khoản trong Keychain và chỉ gửi tới máy chủ chính thức api.stripe.com hoặc *.myshopify.com. Ứng dụng mặc định ở trạng thái ngắt kết nối.")
            )
            .settingsRow()

            SettingsDivider()
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack {
                    Text(L10n.t("Stripe (Balance Transactions — chỉ đọc)"))
                        .font(XFinderTokens.Font.row)
                    Spacer()
                    Text(stripeStoredMask != nil ? L10n.t("Đã kết nối") : L10n.t("Chưa kết nối"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(stripeStoredMask != nil ? .green : .secondary)
                }
                HStack(spacing: XFinderTokens.Space.tight) {
                    TextField(L10n.t("Mã tài khoản Stripe (vd: acct_main)"), text: $stripeAccountId)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t("Nhãn hiển thị"), text: $stripeLabel)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: XFinderTokens.Space.tight) {
                    SecureField(stripeStoredMask ?? L10n.t("Khóa chỉ đọc Stripe (rk_...)"), text: $stripeTokenInput)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $stripeTimeZone) {
                        ForEach(Self.revenueTimeZoneChoices, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                HStack(spacing: XFinderTokens.Space.tight) {
                    Button(L10n.t("Lưu kết nối Stripe")) { saveStripeConnection() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    if stripeStoredMask != nil {
                        Button(L10n.t("Ngắt kết nối Stripe")) { disconnectStripeConnection() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    if let fb = stripeFeedback {
                        Text(fb)
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .settingsRow()

            SettingsDivider()
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack {
                    Text(L10n.t("Shopify (Admin GraphQL — chỉ đọc)"))
                        .font(XFinderTokens.Font.row)
                    Spacer()
                    Text(shopifyStoredMask != nil ? L10n.t("Đã kết nối") : L10n.t("Chưa kết nối"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(shopifyStoredMask != nil ? .green : .secondary)
                }
                HStack(spacing: XFinderTokens.Space.tight) {
                    TextField(L10n.t("Tên miền cửa hàng (*.myshopify.com)"), text: $shopifyShopDomain)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t("Nhãn hiển thị"), text: $shopifyLabel)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: XFinderTokens.Space.tight) {
                    SecureField(shopifyStoredMask ?? L10n.t("Token Admin API chỉ đọc"), text: $shopifyTokenInput)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $shopifyTimeZone) {
                        ForEach(Self.revenueTimeZoneChoices, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Toggle(L10n.t("Bật quyền payout Shopify Payments (read_shopify_payments_payouts)"), isOn: $shopifyHasPayoutScope)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                HStack(spacing: XFinderTokens.Space.tight) {
                    Button(L10n.t("Lưu kết nối Shopify")) { saveShopifyConnection() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    if shopifyStoredMask != nil {
                        Button(L10n.t("Ngắt kết nối Shopify")) { disconnectShopifyConnection() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    if let fb = shopifyFeedback {
                        Text(fb)
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .settingsRow()
        }
    }

    private func reloadRevenueConnectionForms() {
        let saved = UserDefaultsRevenueAccountStore().loadConfigs()
        if let s = saved[.stripe] {
            stripeAccountId = s.accountId
            stripeLabel = s.accountLabel
            stripeTimeZone = s.timeZoneIdentifier
            stripeStoredMask = RevenueKeychainStore.shared.maskedToken(for: .stripe, accountId: s.accountId)
        } else {
            stripeStoredMask = nil
        }
        if let sh = saved[.shopify] {
            shopifyShopDomain = sh.accountId
            shopifyLabel = sh.accountLabel
            shopifyTimeZone = sh.timeZoneIdentifier
            shopifyHasPayoutScope = sh.hasPayoutScope
            shopifyStoredMask = RevenueKeychainStore.shared.maskedToken(for: .shopify, accountId: sh.accountId)
        } else {
            shopifyStoredMask = nil
        }
    }

    private func saveStripeConnection() {
        let acct = stripeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !acct.isEmpty, !acct.contains(where: \.isWhitespace) else {
            stripeFeedback = L10n.t("Nhập mã tài khoản Stripe hợp lệ.")
            return
        }
        let label = stripeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceAccountConfig(
            source: .stripe,
            accountId: acct,
            accountLabel: label.isEmpty ? acct : label,
            timeZoneIdentifier: stripeTimeZone,
            hasPayoutScope: true,
            historyLimitedDays: nil,
            reconciliationProvenDisjoint: false
        )
        if NotchSurfaceController.shared.connectRevenueAccount(config, token: stripeTokenInput) {
            stripeTokenInput = ""
            stripeFeedback = nil
            reloadRevenueConnectionForms()
        } else {
            stripeFeedback = L10n.t("Cần nhập khóa chỉ đọc Stripe để lưu kết nối.")
        }
    }

    private func disconnectStripeConnection() {
        NotchSurfaceController.shared.disconnectRevenueAccount(.stripe)
        stripeTokenInput = ""
        stripeStoredMask = nil
        stripeFeedback = nil
    }

    private func saveShopifyConnection() {
        guard let host = RevenueHostPolicy.normalizedShopifyHost(from: shopifyShopDomain) else {
            shopifyFeedback = L10n.t("Tên miền Shopify phải có dạng ten-cua-hang.myshopify.com.")
            return
        }
        let label = shopifyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceAccountConfig(
            source: .shopify,
            accountId: host,
            accountLabel: label.isEmpty ? host : label,
            timeZoneIdentifier: shopifyTimeZone,
            hasPayoutScope: shopifyHasPayoutScope,
            historyLimitedDays: 60,
            reconciliationProvenDisjoint: false
        )
        if NotchSurfaceController.shared.connectRevenueAccount(config, token: shopifyTokenInput) {
            shopifyShopDomain = host
            shopifyTokenInput = ""
            shopifyFeedback = nil
            reloadRevenueConnectionForms()
        } else {
            shopifyFeedback = L10n.t("Cần nhập token Admin API chỉ đọc để lưu kết nối.")
        }
    }

    private func disconnectShopifyConnection() {
        NotchSurfaceController.shared.disconnectRevenueAccount(.shopify)
        shopifyTokenInput = ""
        shopifyStoredMask = nil
        shopifyFeedback = nil
    }

    private func readinessSubtitle(for readiness: NotchDestinationReadiness) -> String? {
        switch readiness {
        case .ready:
            return nil
        case .featureDisabled:
            return L10n.t("Đang tắt ở trang tính năng")
        case .unconfigured:
            return L10n.t("Chưa cấu hình nguồn")
        }
    }

    private func configureDestination(for id: NotchDestinationID, readiness: NotchDestinationReadiness) -> SidebarDestination? {
        guard let target = id.settingsTarget(for: readiness) else { return nil }
        return SidebarDestination(rawValue: target)
    }

    private func inlineConfigurationSection(for id: NotchDestinationID) -> InlineSection? {
        switch id {
        case .stocks: return .stocks
        case .revenue: return .revenue
        case .websiteAnalytics: return .websiteAnalytics
        default: return nil
        }
    }
}
