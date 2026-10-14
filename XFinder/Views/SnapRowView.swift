import SwiftUI

/// Which tile of the notch layout row is under the pointer. Set by `SnapZoneController`.
@MainActor
@Observable
final class SnapRowModel {
    var highlighted: Int?
    /// The layout the highlighted tile gives right now (inside the four-corner tile: the corner under the pointer).
    var target: SnapLayout.Target?
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
            ForEach(Array(SnapLayout.rowItems.enumerated()), id: \.offset) { i, item in
                SnapTile(item: item, highlighted: model.highlighted == i, target: model.target)
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

/// A tiny screen with the tile's layout filled. The four-corner tile draws all four corners; while highlighted, the one
/// under the pointer is filled with the accent (the controller decides which — this view only draws it).
private struct SnapTile: View {
    let item: SnapLayout.RowItem
    let highlighted: Bool
    let target: SnapLayout.Target?

    var body: some View {
        GeometryReader { geo in
            let screen = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(Color.white.opacity(highlighted ? 0.22 : 0.10))
                ForEach(item.targets, id: \.self) { t in
                    // top-left space = SwiftUI's own space; a 1-pt inset keeps the four corners apart
                    let r = t.rect(in: screen).insetBy(dx: item.targets.count > 1 ? 1 : 0, dy: item.targets.count > 1 ? 1 : 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fill(for: t))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
        .scaleEffect(highlighted ? 1.06 : 1)
        .animation(.easeOut(duration: XFinderTokens.Motion.overlayIn), value: highlighted)
        .animation(.easeOut(duration: XFinderTokens.Motion.overlayIn), value: target)
        .accessibilityLabel(Text(L10n.t(item.titleKey)))
    }

    private func fill(for t: SnapLayout.Target) -> Color {
        guard highlighted else { return Color.white.opacity(0.55) }
        if item.targets.count == 1 || t == target { return Color.accentColor }
        return Color.white.opacity(0.35)
    }
}
