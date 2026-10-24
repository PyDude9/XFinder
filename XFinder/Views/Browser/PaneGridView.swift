import SwiftUI
import AppKit

/// XF-T28 cluster E — lays every pane out from `tree.frames(in:divider:)`, draws the dividers from
/// `tree.dividers(in:divider:)`, and turns a divider drag into `tree.setFraction(at:_:)`. Pure SwiftUI positioning:
/// the tree (`Core/Browser/PaneTree.swift`) already decides geometry, this view only paints it and reports gestures
/// back.
struct PaneGridView: View {
    /// 1 pt visible line; spec also asks for a 6 pt invisible drag area around it, so the hit target is easier to
    /// grab than the hairline itself (named layout constants, not ad hoc literals — ui-contract Cụm E header).
    private static let dividerThickness: CGFloat = 1
    private static let dividerHitSlop: CGFloat = 6

    let model: BrowserWindowModel

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let frames = model.tree.frames(in: rect, divider: Self.dividerThickness)
            let dividers = model.tree.dividers(in: rect, divider: Self.dividerThickness)

            ZStack(alignment: .topLeading) {
                ForEach(model.tree.panes, id: \.self) { paneID in
                    if let frame = frames[paneID], let pane = model.panes[paneID] {
                        PaneView(pane: pane, model: model, isActive: paneID == model.activePane)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .overlay(alignment: .topLeading) {
                                if paneID == model.activePane {
                                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 1)
                                        .frame(width: frame.width, height: frame.height)
                                        .position(x: frame.midX, y: frame.midY)
                                        .allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.focus(paneID)
                            }
                    }
                }

                ForEach(Array(dividers.enumerated()), id: \.offset) { _, divider in
                    DividerHandle(
                        divider: divider,
                        hitSlop: Self.dividerHitSlop,
                        model: model
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(name: Self.coordinateSpaceName)
        }
    }

    fileprivate static let coordinateSpaceName = "XFinder.PaneGridView"
}

/// One draggable divider line. Keeps its own drag-start fraction so a drag computes the new fraction from the
/// divider's PARENT rect (the split node's own rect before it was carved in two — `PaneDivider.parent`), not from
/// cumulative deltas, so a fast drag never drifts from where the pointer actually is.
private struct DividerHandle: View {
    let divider: PaneDivider
    let hitSlop: CGFloat
    let model: BrowserWindowModel

    @State private var isHovering = false

    var body: some View {
        let hitRect = divider.rect.insetBy(
            dx: divider.axis == .horizontal ? -hitSlop : 0,
            dy: divider.axis == .vertical ? -hitSlop : 0
        )
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: hitRect.width, height: hitRect.height)
            Rectangle()
                .fill(XFinderTokens.Fill.hairline)
                .frame(width: divider.rect.width, height: divider.rect.height)
        }
        .contentShape(Rectangle())
        .position(x: hitRect.midX, y: hitRect.midY)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                (divider.axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(PaneGridView.coordinateSpaceName))
                .onChanged { value in
                    let parent = divider.parent
                    let fraction: Double
                    switch divider.axis {
                    case .horizontal:
                        guard parent.width > 0 else { return }
                        fraction = Double((value.location.x - parent.minX) / parent.width)
                    case .vertical:
                        guard parent.height > 0 else { return }
                        fraction = Double((value.location.y - parent.minY) / parent.height)
                    }
                    model.tree.setFraction(at: divider.path, fraction)
                }
        )
    }
}
