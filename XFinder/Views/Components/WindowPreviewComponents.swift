import SwiftUI
import AppKit

// MARK: - Content Preview View (Safari-Style 100% Flat)

public struct ContentPreviewView: View {
    public var image: NSImage?
    public var title: String
    public var subtitle: String
    public var icon: NSImage?
    public var width: CGFloat
    public var height: CGFloat

    public init(
        image: NSImage? = nil,
        title: String,
        subtitle: String,
        icon: NSImage? = nil,
        width: CGFloat = 304,
        height: CGFloat = 160
    ) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.width = width
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.55)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 6)

            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    ZStack {
                        Color.white.opacity(0.06)
                        VStack(spacing: 6) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 20))
                                .opacity(0.2)
                            Text(L10n.t("Ở Space khác"))
                                .font(.system(size: 11))
                                .opacity(0.4)
                        }
                    }
                    .frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(width: width + 16)
        .padding(8)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                Color.white.opacity(0.42)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 8)
    }
}

// MARK: - Web Snapshot Card View (Safari/Chrome 100% Flat Direct Preview)

public struct WebSnapshotCardView: View {
    public let tab: BrowserTabItem
    public var tabIndex: Int?
    public var totalTabs: Int?
    public var width: CGFloat
    public var height: CGFloat
    public var showFullDetails: Bool

    public init(
        tab: BrowserTabItem,
        tabIndex: Int? = nil,
        totalTabs: Int? = nil,
        width: CGFloat = 304,
        height: CGFloat = 160,
        showFullDetails: Bool = true
    ) {
        self.tab = tab
        self.tabIndex = tabIndex
        self.totalTabs = totalTabs
        self.width = width
        self.height = height
        self.showFullDetails = showFullDetails
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.18),
                            Color(red: 0.07, green: 0.08, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if showFullDetails {
                VStack(alignment: .leading, spacing: 0) {
                    // Top URL bar / security badge
                    HStack(spacing: 5) {
                        if tab.isSecure {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color.green.opacity(0.90))
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color.blue.opacity(0.85))
                        }
                        Text(tab.domain)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.90))
                            .lineLimit(1)

                        Spacer()

                        if tab.isActive {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 5, height: 5)
                                Text(L10n.t("Tab đang mở"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.30))
                            .clipShape(Capsule())
                        } else if let idx = tabIndex, let tot = totalTabs {
                            Text("\(idx)/\(tot)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.65))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text(L10n.t("Tab nền"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    Divider()
                        .background(Color.white.opacity(0.08))

                    // Content Area: Title + Full Link Box
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tab.title.isEmpty ? tab.domain : tab.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                            .multilineTextAlignment(.leading)

                        if !tab.url.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 8))
                                        .foregroundColor(.white.opacity(0.50))
                                    Text(L10n.t("Liên kết đầy đủ"))
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundColor(.white.opacity(0.50))
                                    Spacer()
                                    if !tab.fragmentOrQuery.isEmpty {
                                        Text(tab.fragmentOrQuery)
                                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                            .foregroundColor(Color.yellow.opacity(0.95))
                                            .lineLimit(1)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.yellow.opacity(0.18))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }

                                Text(tab.url)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.80))
                                    .lineLimit(3)
                                    .lineSpacing(1.5)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 5)

                    Spacer(minLength: 0)

                    // Bottom hint bar
                    HStack {
                        if tab.isSecure {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                                Text(L10n.t("Bảo mật"))
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.50))
                            }
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Text(L10n.t("Nhấn để chuyển"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.50))
                            Image(systemName: "return")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.50))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            } else {
                // Compact view (e.g. 196x110 switcher)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.isSecure ? "lock.fill" : "globe")
                            .font(.system(size: 8.5))
                            .foregroundColor(tab.isSecure ? .green.opacity(0.85) : .blue.opacity(0.85))
                        Text(tab.domain)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    Text(tab.title.isEmpty ? tab.domain : tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 8)

                    if !tab.url.isEmpty {
                        Text(tab.url)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.60))
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - App Hero Card View (100% Flat Direct Presentation for Stage Manager & Other Spaces)

public struct AppHeroCardView: View {
    public let appName: String
    public let title: String
    public let bundleID: String
    public let isStageMiniature: Bool
    public let isOnOtherSpace: Bool
    public var width: CGFloat
    public var height: CGFloat

    public init(
        appName: String,
        title: String,
        bundleID: String,
        isStageMiniature: Bool = false,
        isOnOtherSpace: Bool = false,
        width: CGFloat = 304,
        height: CGFloat = 160
    ) {
        self.appName = appName
        self.title = title
        self.bundleID = bundleID
        self.isStageMiniature = isStageMiniature
        self.isOnOtherSpace = isOnOtherSpace
        self.width = width
        self.height = height
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.15, blue: 0.18),
                            Color(red: 0.09, green: 0.10, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Spacer()
                if let icon = iconForBundle(bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.black.opacity(0.3), radius: 6, y: 2)
                }

                VStack(spacing: 2) {
                    Text(title.isEmpty ? appName : title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)

                    HStack(spacing: 4) {
                        Image(systemName: isStageMiniature ? "rectangle.split.2x1" : "macwindow.on.rectangle")
                            .font(.system(size: 10))
                        Text(isStageMiniature ? L10n.t("Trong Stage Manager") : L10n.t("Ở Space khác"))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.55))
                }

                Text(L10n.t("Nhấn để chuyển"))
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func iconForBundle(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Browser Tab Carousel View

public struct BrowserTabCarouselView: View {
    public let tabs: [BrowserTabItem]
    public let needsPermission: Bool
    public var selectedTabID: String?
    public var onHoverTab: ((BrowserTabItem) -> Void)?
    public var onSelectTab: ((BrowserTabItem) -> Void)?

    public init(
        tabs: [BrowserTabItem],
        needsPermission: Bool = false,
        selectedTabID: String? = nil,
        onHoverTab: ((BrowserTabItem) -> Void)? = nil,
        onSelectTab: ((BrowserTabItem) -> Void)? = nil
    ) {
        self.tabs = tabs
        self.needsPermission = needsPermission
        self.selectedTabID = selectedTabID
        self.onHoverTab = onHoverTab
        self.onSelectTab = onSelectTab
    }

    public var body: some View {
        if needsPermission || !tabs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
            if needsPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(L10n.t("Cần quyền Tự động hóa để đọc tab trình duyệt"))
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                    Spacer()
                    Button(L10n.t("Mở Cài đặt")) {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            } else if !tabs.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("OPEN TABS • \(tabs.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .opacity(0.45)
                    Spacer()
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            let isHighlighted = (tab.id == selectedTabID) || (selectedTabID == nil && tab.isActive)
                            Button(action: {
                                onSelectTab?(tab)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 13))
                                        .foregroundColor(isHighlighted ? .blue : .primary.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tab.title)
                                            .font(.system(size: 12, weight: isHighlighted ? .semibold : .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(tab.domain)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                        isHighlighted ? Color.white.opacity(0.95) : Color.white.opacity(0.70)
                                    }
                                )
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isHighlighted ? Color.blue.opacity(0.6) : Color.white.opacity(0.35), lineWidth: isHighlighted ? 1.5 : 0.5)
                                )
                                .shadow(color: Color.black.opacity(isHighlighted ? 0.12 : 0.05), radius: 4, x: 0, y: 1)
                                .frame(maxWidth: 180)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovered in
                                if isHovered {
                                    onHoverTab?(tab)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .padding(.horizontal, 4)
        }
    }
}

// MARK: - Calendar Preview View

public struct CalendarPreviewView: View {
    public let events: [CalendarEventItem]

    public init(events: [CalendarEventItem]) {
        self.events = events
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text(L10n.t("Sự kiện sắp tới"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(events.prefix(3)) { ev in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                        Text(ev.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(ev.timeString)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(4)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Weather Preview View

public struct WeatherPreviewView: View {
    public let weather: WeatherInfo

    public init(weather: WeatherInfo) {
        self.weather = weather
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 18))
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Thời tiết hiện tại"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(weather.temperature)
                        .font(.system(size: 12, weight: .bold))
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(weather.condition)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.4))
        .cornerRadius(6)
    }
}

// MARK: - Window Switcher Search Pill

public struct WindowSwitcherSearchPill: View {
    @Binding public var query: String
    @Binding public var isFocused: Bool
    public var onClear: () -> Void

    public init(query: Binding<String>, isFocused: Binding<Bool>, onClear: @escaping () -> Void = {}) {
        self._query = query
        self._isFocused = isFocused
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LiquidGlassTokens.SearchPill.iconSize, weight: .medium))
                .foregroundColor(.white.opacity(0.50))

            if isFocused {
                TextField(L10n.t("Nhấn , để tìm kiếm cửa sổ"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white)
                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        onClear()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(query.isEmpty ? L10n.t("Nhấn , để tìm kiếm cửa sổ") : query)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(query.isEmpty ? .white.opacity(0.50) : .white)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: LiquidGlassTokens.SearchPill.width, height: LiquidGlassTokens.SearchPill.height)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                Color.white.opacity(0.18)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
        .onTapGesture {
            isFocused = true
        }
    }
}

// MARK: - Window Preview Card

public struct WindowPreviewCard: View {
    public let item: PreviewItem
    public let isSelected: Bool
    public var size: CGSize
    public var thumbWidth: CGFloat?
    public var thumbHeight: CGFloat?
    public let onSelect: () -> Void

    @State private var isHovered: Bool = false

    public init(
        item: PreviewItem,
        isSelected: Bool = false,
        size: CGSize = LiquidGlassTokens.Card.size,
        thumbWidth: CGFloat? = nil,
        thumbHeight: CGFloat? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.size = size
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            LiquidGlassCard(isSelected: isSelected, cornerRadius: LiquidGlassTokens.Card.cornerRadius) {
                VStack(alignment: .leading, spacing: 4) {
                    // Card Header: Traffic lights + App Icon + 2-line title/subtitle
                    HStack(spacing: 8) {
                        // Traffic lights (3 dots, 10px each, spacing 4px)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.372, blue: 0.337)) // #FF5F56
                                .frame(width: LiquidGlassTokens.Card.trafficDotSize, height: LiquidGlassTokens.Card.trafficDotSize)
                            Circle()
                                .fill(Color(red: 1.0, green: 0.741, blue: 0.180)) // #FFBD2E
                                .frame(width: LiquidGlassTokens.Card.trafficDotSize, height: LiquidGlassTokens.Card.trafficDotSize)
                            Circle()
                                .fill(Color(red: 0.153, green: 0.788, blue: 0.247)) // #27C93F
                                .frame(width: LiquidGlassTokens.Card.trafficDotSize, height: LiquidGlassTokens.Card.trafficDotSize)
                        }

                        // App Icon (18px, corner 4)
                        if let icon = iconForBundle(item.bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: LiquidGlassTokens.Card.appIconSize, height: LiquidGlassTokens.Card.appIconSize)
                                .cornerRadius(4)
                        }

                        // App name 13 semibold + Window title 11 regular opacity 0.55
                        VStack(alignment: .leading, spacing: 1) {
                            let headerTitle = item.isGroup
                                ? "\(appNameForBundle(item.bundleID)) • \(item.windowCount) \(L10n.t("cửa sổ"))"
                                : appNameForBundle(item.bundleID)
                            Text(headerTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            let subTitle = item.isOnOtherSpace ? L10n.t("Ở Space khác") : (item.title.isEmpty ? appNameForBundle(item.bundleID) : item.title)
                            Text(subTitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                    // Thumbnail: 220x110 fill, crisp border, mini badge
                    let calculatedThumbWidth = thumbWidth ?? (size.width - LiquidGlassTokens.Card.padding * 2)
                    let calculatedThumbHeight = thumbHeight ?? LiquidGlassTokens.Card.switcherThumbSize.height

                    if let thumb = item.thumbnail {
                        WindowThumbnailView(image: thumb, width: calculatedThumbWidth, height: calculatedThumbHeight)
                            .overlay(alignment: .topTrailing) {
                                badgeView
                            }
                    } else if BrowserTabProvider.isSupportedBrowser(bundleID: item.bundleID) {
                        let repTab = item.tabs.first ?? BrowserTabItem(title: item.title, url: item.appName)
                        WebSnapshotCardView(
                            tab: repTab,
                            width: calculatedThumbWidth,
                            height: calculatedThumbHeight,
                            showFullDetails: false
                        )
                        .overlay(alignment: .topTrailing) {
                            badgeView
                        }
                    } else {
                        // Other space / fallback: subtle glass gradient + 32px icon opacity 0.15 + label
                        ZStack {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.03)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: LiquidGlassTokens.thumbRadius, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )

                            VStack(spacing: 6) {
                                if let icon = iconForBundle(item.bundleID) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .opacity(0.15)
                                }
                                Text(item.isOnOtherSpace ? L10n.t("Ở Space khác") : (item.title.isEmpty ? appNameForBundle(item.bundleID) : item.title))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.60))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .frame(width: calculatedThumbWidth, height: calculatedThumbHeight)
                        .overlay(alignment: .topTrailing) {
                            badgeView
                        }
                    }
                }
                .padding(LiquidGlassTokens.Card.padding)
                .frame(width: size.width, height: size.height)
            }
            .scaleEffect(isSelected ? LiquidGlassTokens.switcherSelectionScale : (isHovered ? 1.02 : 1.0))
            .offset(y: isSelected ? LiquidGlassTokens.switcherSelectionYOffset : (isHovered ? -2 : 0))
            .brightness(isSelected ? LiquidGlassTokens.switcherSelectionBrightness : 0)
            .opacity(isSelected ? 1.0 : (isHovered ? 0.92 : LiquidGlassTokens.unselectedOpacity))
            .saturation(isSelected ? 1.0 : (isHovered ? 1.0 : LiquidGlassTokens.unselectedSaturation))
            .animation(LiquidGlassTokens.spring, value: isSelected)
            .animation(.easeOut(duration: 0.18), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badgeView: some View {
        if item.windowCount > 1 {
            Text("\(item.windowCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        Color.black.opacity(0.55)
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .padding(6)
        }
    }

    private func iconForBundle(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func appNameForBundle(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
               bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
               url.deletingPathExtension().lastPathComponent
    }
}

