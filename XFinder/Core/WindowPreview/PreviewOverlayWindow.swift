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
        let containerWidth = min(screen.frame.width - 32, 1400)
        let containerHeight: CGFloat = 220
        let searchPillHeight: CGFloat = LiquidGlassTokens.SearchPill.height
        let spacingAboveContainer: CGFloat = 16

        // Search pill (36) + spacing (16) = 52px above container top
        let topOffsetFromContainer = searchPillHeight + spacingAboveContainer
        let containerTopY = screen.frame.maxY - 140
        let windowTopY = containerTopY + topOffsetFromContainer

        let fittingH = host.fittingSize.height
        let totalH = max(fittingH, topOffsetFromContainer + containerHeight)
        let windowY = windowTopY - totalH
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
    @Namespace private var switcherNamespace

    var body: some View {
        VStack(spacing: 16) {
            // Search pill + Position Counter pill (same liquid glass system, 16px above container)
            HStack(spacing: 10) {
                WindowSwitcherSearchPill(
                    query: $store.searchQuery,
                    isFocused: $store.isSearchActive,
                    onClear: {
                        store.searchQuery = ""
                    }
                )

                let totalCount = store.filteredPreviewItems.count
                if totalCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.70))
                        Text("\(store.selectedIndex + 1) / \(totalCount)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.90))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: LiquidGlassTokens.SearchPill.height)
                    .background(
                        ZStack {
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            Color.white.opacity(0.14)
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
            }

            // Horizontal pill container for cards (height 220)
            let items = store.filteredPreviewItems
            ZStack {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "macwindow.badge.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.60))
                        Text(L10n.t("Không có cửa sổ"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.60))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LiquidGlassTokens.Container.gap) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = (index == store.selectedIndex)
                                    VStack(spacing: 6) {
                                        ZStack {
                                            if isSelected {
                                                RoundedRectangle(cornerRadius: LiquidGlassTokens.Card.cornerRadius)
                                                    .stroke(LiquidGlassTokens.cardSelectedBorder, lineWidth: 1.5)
                                                    .shadow(color: LiquidGlassTokens.selectionGlow, radius: 20)
                                                    .matchedGeometryEffect(id: "selectionGlow", in: switcherNamespace)
                                            }
                                            WindowPreviewCard(
                                                item: item,
                                                isSelected: isSelected,
                                                size: LiquidGlassTokens.Card.size,
                                                thumbWidth: LiquidGlassTokens.Card.switcherThumbSize.width,
                                                thumbHeight: LiquidGlassTokens.Card.switcherThumbSize.height,
                                                onSelect: { onSelect(index) }
                                            )
                                        }

                                        if isSelected {
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 6, height: 6)
                                                .shadow(color: Color.white.opacity(0.6), radius: 3)
                                                .matchedGeometryEffect(id: "selectionDot", in: switcherNamespace)
                                        } else {
                                            Circle()
                                                .fill(Color.clear)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, LiquidGlassTokens.Container.padding)
                            .padding(.vertical, 12)
                            .frame(minHeight: 220)
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
            .frame(height: 220)
            .liquidGlassContainer(cornerRadius: LiquidGlassTokens.Container.cornerRadius)

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
        .onAppear {
            let animEnabled = UserDefaults.standard.object(forKey: "windowPreview.animationEnabled") as? Bool ?? true
            if animEnabled {
                withAnimation(LiquidGlassTokens.Motion.spring) {
                    scale = LiquidGlassTokens.Motion.scaleFinal
                    opacity = 1.0
                }
            } else {
                scale = LiquidGlassTokens.Motion.scaleFinal
                opacity = 1.0
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
