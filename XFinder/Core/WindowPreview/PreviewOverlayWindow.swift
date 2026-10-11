import AppKit
import SwiftUI

/// Floating window hosting the liquid glass Cmd+Tab switcher overlay.
public final class PreviewOverlayWindow: NSPanel {
    public static let shared = PreviewOverlayWindow()

    private var onCommitSelection: ((Int) -> Void)?
    private var onDismissOverlay: (() -> Void)?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
    }

    public func present(
        selection: Int,
        onCommit: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onCommitSelection = onCommit
        self.onDismissOverlay = onDismiss

        WindowPreviewStore.shared.selectedIndex = selection

        let view = PreviewOverlayContentView(
            onSelect: { [weak self] index in
                self?.commit(index: index)
            }
        )
        let host = NSHostingView(rootView: view)
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = host

        // Position: centered top y = screen.maxY - 140
        reposition(for: host)

        self.orderFrontRegardless()
    }

    public func updateSelection(_ index: Int) {
        WindowPreviewStore.shared.selectedIndex = index
        if let host = self.contentView as? NSHostingView<PreviewOverlayContentView> {
            reposition(for: host)
        }
    }

    public func focusSearch() {
        WindowPreviewStore.shared.isSearchActive = true
    }

    public static func maxVisibleCards(for screen: NSScreen?) -> Int {
        let screenWidth = screen?.visibleFrame.width ?? 1440
        return WindowPreviewStore.maxVisibleCards(screenWidth: screenWidth)
    }

    private func reposition(for host: NSView) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let count = max(1, WindowPreviewStore.shared.filteredPreviewItems.count)
        let cardWidth: CGFloat = LiquidGlassTokens.Card.size.width
        let cardGap: CGFloat = LiquidGlassTokens.Container.gap
        let padding: CGFloat = LiquidGlassTokens.Container.padding
        let contentWidth = padding * 2 + CGFloat(count) * cardWidth + CGFloat(max(0, count - 1)) * cardGap
        let containerWidth = min(screen.frame.width - 32, max(300, contentWidth))
        let containerHeight: CGFloat = LiquidGlassTokens.Card.size.height + 24
        let searchPillHeight: CGFloat = LiquidGlassTokens.SearchPill.height
        let spacingAboveContainer: CGFloat = 10

        // Phase C: room for the mode line, the key legend, and the zoomed capture when on.
        let extrasH: CGFloat = 18 + 18 + (WindowPreviewStore.shared.isZoomed ? min(screen.frame.height * 0.45, 460) + 10 : 0)
        let totalH = searchPillHeight + spacingAboveContainer + containerHeight + extrasH
        let windowY = screen.frame.midY - totalH / 2
        let windowX = screen.frame.midX - containerWidth / 2

        self.setFrame(NSRect(x: windowX, y: windowY, width: containerWidth, height: totalH), display: true)
    }

    public func commit(index: Int) {
        let callback = onCommitSelection
        dismiss()
        callback?(index)
    }

    public func dismiss() {
        self.orderOut(nil)
        self.contentView = nil
        onCommitSelection = nil
        onDismissOverlay = nil
    }
}

/// SwiftUI content for the Cmd+Tab overlay with liquid glass, screen-aware auto-scrolling carousel, and spring animation.
struct PreviewOverlayContentView: View {
    let onSelect: (Int) -> Void

    @State private var store = WindowPreviewStore.shared
    @State private var scale: CGFloat = LiquidGlassTokens.Motion.scaleInitial
    @State private var opacity: Double = 0.0
    @State private var blur: CGFloat = 4.0

    var body: some View {
        VStack(spacing: 10) {
            // Single merged Search + Position Counter pill (300x28, 10px above container)
            let totalCount = store.filteredPreviewItems.count
            let counterText = totalCount > 0 ? "\(store.selectedIndex + 1)/\(totalCount)" : nil
            WindowSwitcherSearchPill(
                query: $store.searchQuery,
                isFocused: $store.isSearchActive,
                counterText: counterText,
                onClear: {
                    store.searchQuery = ""
                }
            )

            // Phase C: which deck this is — all apps, or the windows of one app.
            if case .windows(let bundleID) = store.mode {
                let name = store.filteredPreviewItems.first?.appName ?? bundleID
                Text("\(L10n.t("Cửa sổ của "))\(name)")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
            } else {
                Text(L10n.t("Ứng dụng")).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.55))
            }

            // Horizontal container for cards
            let items = store.filteredPreviewItems
            let containerHeight: CGFloat = LiquidGlassTokens.Card.size.height + 24
            ZStack {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow.badge.magnifyingglass")
                            .font(.system(size: 26))
                            .foregroundColor(.white.opacity(0.50))
                        Text(L10n.t("Không có cửa sổ"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.50))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LiquidGlassTokens.Container.gap) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = (index == store.selectedIndex)
                                    WindowPreviewCard(
                                        item: item,
                                        isSelected: isSelected,
                                        size: LiquidGlassTokens.Card.size,
                                        thumbWidth: LiquidGlassTokens.Card.switcherThumbSize.width,
                                        thumbHeight: LiquidGlassTokens.Card.switcherThumbSize.height,
                                        onSelect: { onSelect(index) }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, LiquidGlassTokens.Container.padding)
                            .padding(.vertical, 12)
                            .frame(minHeight: containerHeight)
                        }
                        .onChange(of: store.selectedIndex) { newIndex in
                            withAnimation(LiquidGlassTokens.spring) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                        .onAppear {
                            proxy.scrollTo(store.selectedIndex, anchor: .center)
                        }
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.02),
                                .init(color: .black, location: 0.98),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: containerHeight)
            .liquidGlassContainer(cornerRadius: LiquidGlassTokens.Container.cornerRadius)

            // Phase C: Space — the selected window, large.
            if store.isZoomed, store.filteredPreviewItems.indices.contains(store.selectedIndex) {
                let current = store.filteredPreviewItems[store.selectedIndex]
                let maxH = min((NSScreen.main?.frame.height ?? 1000) * 0.45, 460)
                Group {
                    if let img = store.zoomImage ?? current.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "macwindow").font(.system(size: 40)).foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: 900, maxHeight: maxH)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .liquidGlassContainer(cornerRadius: 14)
            }

            // Phase C: the keys, where the user is looking.
            Text(L10n.t("Q đóng cửa sổ · H ẩn ứng dụng · Space phóng to · ` cửa sổ của ứng dụng · , tìm"))
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.45)).lineLimit(1)

            // Special previews for active highlighted window (Calendar / Weather only)
            if store.filteredPreviewItems.indices.contains(store.selectedIndex) {
                let current = store.filteredPreviewItems[store.selectedIndex]
                VStack(spacing: 8) {
                    if current.bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty {
                        CalendarPreviewView(events: store.calendarEvents)
                    }
                    if current.bundleID == "com.apple.weather", let weather = store.weatherInfo {
                        WeatherPreviewView(weather: weather)
                    }
                }
                .frame(maxWidth: 720)
            }

            // Screen Recording permission note if needed
            if store.isScreenRecordingDenied {
                Text(L10n.t("Thiếu quyền Ghi màn hình — chưa có ảnh xem trước. Mở Tổng quan → “Cấp mọi quyền…”."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .blur(radius: blur)
        .onAppear {
            let animEnabled = UserDefaults.standard.object(forKey: "windowPreview.animationEnabled") as? Bool ?? true
            if animEnabled {
                withAnimation(.easeOut(duration: XFinderTokens.Motion.overlayIn)) {
                    scale = LiquidGlassTokens.Motion.scaleFinal
                    opacity = 1.0
                    blur = 0.0
                }
            } else {
                scale = LiquidGlassTokens.Motion.scaleFinal
                opacity = 1.0
                blur = 0.0
            }
            if store.filteredPreviewItems.indices.contains(store.selectedIndex) {
                store.loadSpecialPreviews(for: store.filteredPreviewItems[store.selectedIndex])
            }
        }
        .onChange(of: store.selectedIndex) {
            if store.filteredPreviewItems.indices.contains(store.selectedIndex) {
                store.loadSpecialPreviews(for: store.filteredPreviewItems[store.selectedIndex])
            }
        }
    }
}
