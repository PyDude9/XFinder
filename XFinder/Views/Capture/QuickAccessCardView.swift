import SwiftUI
import AppKit

/// OneNotch's Quick Access card: a thumbnail with a thin countdown bar, corner actions that only
/// appear on hover, a centre "Chú thích" pill, drag-out, and a context menu with the rest. The panel
/// that hosts this view is never key (CONTRACT) — nothing here calls `NSApp.activate` or expects
/// keyboard focus; every action is a click or the already-armed swipe monitor in `QuickAccessController`.
struct QuickAccessCardView: View {
    let item: CaptureItem
    @State private var controller = CaptureController.shared
    @State private var quickAccess = QuickAccessController.shared
    @State private var hovering = false
    @State private var now = Date()

    private let tickTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var countdown: CardCountdown? { quickAccess.countdown(for: item) }
    private var thumbnail: CGImage? { controller.thumbnail(for: item, maxPixel: 440) }
    private var size: CGSize { CaptureRules.cardSize(pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight) }

    var body: some View {
        ZStack {
            thumbnailLayer
            if hovering { overlay }
            countdownBar
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous))
        .shadow(radius: 10, y: 4)
        .onHover { inside in
            hovering = inside
            if inside { quickAccess.pointerEntered(item) } else { quickAccess.pointerExited(item) }
        }
        .onTapGesture(count: 2) { controller.annotate(item) }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button(L10n.t("Chép chữ")) { controller.copyText(item) }
            Button(L10n.t("Hiện trong Finder")) { controller.reveal(item) }
            Divider()
            Button(L10n.t("Xoá"), role: .destructive) { controller.delete(item) }
        }
        .onReceive(tickTimer) { now = $0 }
    }

    private var thumbnailLayer: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(XFinderTokens.Fill.surface)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var overlay: some View {
        ZStack {
            Color.black.opacity(0.28)
            VStack {
                HStack {
                    cornerButton(systemName: "xmark.circle.fill", help: L10n.t("Đóng")) {
                        quickAccess.dismiss(item)
                    }
                    Spacer()
                    cornerButton(systemName: "pin.fill", help: L10n.t("Ghim lên màn hình")) {
                        controller.pin(item)
                    }
                }
                Spacer()
                Button(L10n.t("Chú thích")) { controller.annotate(item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                HStack {
                    cornerButton(systemName: "square.and.arrow.down", help: L10n.t("Lưu")) {
                        controller.save(item)
                    }
                    Spacer()
                    cornerButton(systemName: "doc.on.doc", help: L10n.t("Sao chép")) {
                        controller.copy(item)
                    }
                }
            }
            .padding(8)
        }
    }

    private func cornerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(6)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var countdownBar: some View {
        if let countdown, countdown.total > 0 {
            VStack {
                Spacer()
                GeometryReader { geo in
                    let fraction = max(0, min(1, countdown.remaining(at: now) / countdown.total))
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: geo.size.width * fraction, height: 3, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
            }
        }
    }
}
