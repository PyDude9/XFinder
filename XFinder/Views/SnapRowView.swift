import SwiftUI

/// Which tile of the notch layout row is under the pointer. Set by `SnapZoneController`.
@MainActor
@Observable
final class SnapRowModel {
    var highlighted: Int?
}

/// The layout row shown under the notch while a window is dragged there (B3). The panel is
/// mouse-transparent — the drag keeps going underneath — so the highlight follows the pointer
/// position the controller computes, never clicks. Each tile draws a tiny screen with its target
/// filled, so the row reads without words; the name is in the tooltip-free caption under it.
struct SnapRowView: View {
    var model: SnapRowModel

    var body: some View {
        let m = SnapLayout.RowMetrics.standard
        HStack(spacing: m.spacing) {
            ForEach(Array(SnapLayout.rowTargets.enumerated()), id: \.offset) { i, target in
                SnapTile(target: target, highlighted: model.highlighted == i)
                    .frame(width: m.tileSize.width, height: m.tileSize.height)
            }
        }
        .padding(m.padding)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous).fill(Color.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SnapTile: View {
    let target: SnapLayout.Target
    let highlighted: Bool

    var body: some View {
        GeometryReader { geo in
            let screen = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            let r = target.rect(in: screen)          // top-left space = SwiftUI's own space
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(Color.white.opacity(highlighted ? 0.22 : 0.10))
                RoundedRectangle(cornerRadius: 3)
                    .fill(highlighted ? Color.accentColor : Color.white.opacity(0.55))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .scaleEffect(highlighted ? 1.06 : 1)
        .animation(.easeOut(duration: XFinderTokens.Motion.overlayIn), value: highlighted)
        .accessibilityLabel(Text(L10n.t(target.titleKey)))
    }
}
