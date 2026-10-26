import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// XF-T28 cluster E — lays every pane out from `tree.frames(in:divider:)`, draws the dividers from
/// `tree.dividers(in:divider:)`, and turns a divider drag into `tree.setFraction(at:_:)`. Pure SwiftUI positioning:
/// the tree (`Core/Browser/PaneTree.swift`) already decides geometry, this view only paints it and reports gestures
/// back. XF-T30 W1 also adds the pane-tab drop zones here (contract §4): a dragged tab's drop target is computed via
/// `PaneTabRules.dropTarget` against this pane's own rect, with a highlight that differs for `.edge` (half the pane)
/// vs `.center` (the whole pane's border) — `.strip` drops are handled by `PaneTabStripView` itself.
struct PaneGridView: View {
    /// 1 pt visible line; spec also asks for a 6 pt invisible drag area around it, so the hit target is easier to
    /// grab than the hairline itself (named layout constants, not ad hoc literals — ui-contract Cụm E header).
    private static let dividerThickness: CGFloat = 1
    private static let dividerHitSlop: CGFloat = 6

    let model: BrowserWindowModel

    /// Live pane-tab drop target per pane (highlight only) — set by `PaneTabDropDelegate`, drawn by
    /// `PaneTabDropHighlight`, never hit-testable.
    @State private var dropTargets: [PaneID: PaneTabRules.DropTarget] = [:]

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let frames = model.tree.frames(in: rect, divider: Self.dividerThickness)
            let dividers = model.tree.dividers(in: rect, divider: Self.dividerThickness)

            ZStack(alignment: .topLeading) {
                ForEach(model.tree.panes, id: \.self) { paneID in
                    if let frame = frames[paneID], let pane = model.panes[paneID] {
                        // `.onDrop` sits on the pane itself, not on an overlay: a hit-testable overlay over the
                        // content area swallowed every click meant for the List/Icons/Columns view (measured
                        // 2026-10-26: synthetic click ⇒ first responder stayed the window, AX-set selection worked).
                        // A drop modifier claims no mouse events; the outline keeps its clicks and its file drops.
                        PaneView(pane: pane, model: model, isActive: paneID == model.activePane)
                            .onDrop(of: [PaneTabStripView.tabType],
                                    delegate: PaneTabDropDelegate(paneID: paneID, paneSize: frame.size,
                                                                  stripHeight: PaneTabStripView.height, model: model,
                                                                  target: Binding(get: { dropTargets[paneID] },
                                                                                  set: { dropTargets[paneID] = $0 })))
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
                            .overlay(alignment: .topLeading) {
                                // Highlight below the tab strip only (the strip draws its own insertion marker).
                                let strip = PaneTabStripView.height
                                PaneTabDropHighlight(target: dropTargets[paneID])
                                    .frame(width: frame.width, height: max(0, frame.height - strip))
                                    .position(x: frame.midX, y: frame.midY + strip / 2)
                                    .allowsHitTesting(false)
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

/// The `.edge` / `.center` highlight while a pane tab hovers — drawing only, never hit-testable (the drop target is
/// the pane itself, see `PaneGridView.body`). `.strip` targets draw nothing here: the strip view owns those.
private struct PaneTabDropHighlight: View {
    let target: PaneTabRules.DropTarget?

    var body: some View {
        ZStack {
            if let target {
                highlight(for: target)
            }
        }
    }

    @ViewBuilder
    private func highlight(for target: PaneTabRules.DropTarget) -> some View {
        switch target {
        case .edge(let direction):
            GeometryReader { proxy in
                XFinderTokens.Fill.focus
                    .frame(width: edgeWidth(proxy.size, direction), height: edgeHeight(proxy.size, direction))
                    .position(edgePosition(proxy.size, direction))
            }
        case .center:
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        case .strip:
            EmptyView()
        }
    }

    private func edgeWidth(_ size: CGSize, _ direction: SplitDirection) -> CGFloat {
        direction == .left || direction == .right ? size.width / 2 : size.width
    }

    private func edgeHeight(_ size: CGSize, _ direction: SplitDirection) -> CGFloat {
        direction == .up || direction == .down ? size.height / 2 : size.height
    }

    private func edgePosition(_ size: CGSize, _ direction: SplitDirection) -> CGPoint {
        switch direction {
        case .left: return CGPoint(x: size.width / 4, y: size.height / 2)
        case .right: return CGPoint(x: size.width * 3 / 4, y: size.height / 2)
        case .up: return CGPoint(x: size.width / 2, y: size.height / 4)
        case .down: return CGPoint(x: size.width / 2, y: size.height * 3 / 4)
        }
    }
}

/// Same shape as `PaneTabStripView`'s own private payload type — kept as a second private declaration (rather than
/// shared) since each file owns its drag/drop wire format independently and both must only agree on JSON shape.
private struct TabDropPayload: Codable {
    let modelID: Int
    let tabID: UUID
}

/// `DropDelegate` (macOS 10.15+, unlike `onDropSessionUpdated` which needs macOS 26) — `dropUpdated` fires on every
/// pointer move during the drag and is where the live highlight target gets computed; `performDrop` does the actual
/// `model.dropTab`. The drop zone has no visibility into individual tab frames (those are `PaneTabStripView`'s own
/// `@State`), so `tabFrames` is always empty here — `PaneTabRules.dropTarget` with an empty array still separates
/// the strip band from edge/center correctly (contract: "sau tab cuối ⇒ count"), it only cannot place a mid-strip
/// insertion index, which this zone never needs since `.strip` targets are ignored (the strip view owns those).
private struct PaneTabDropDelegate: DropDelegate {
    let paneID: PaneID
    /// The whole pane (strip included): `info.location` is in the pane's own coordinates.
    let paneSize: CGSize
    let stripHeight: CGFloat
    let model: BrowserWindowModel
    @Binding var target: PaneTabRules.DropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [PaneTabStripView.tabType])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let computed = computeTarget(at: info.location)
        target = isEdgeOrCenter(computed) ? computed : nil
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        target = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { target = nil }
        guard let provider = info.itemProviders(for: [PaneTabStripView.tabType]).first else {
            return false
        }
        let computed = computeTarget(at: info.location)
        provider.loadItem(forTypeIdentifier: PaneTabStripView.tabUTI) { item, _ in
            guard let data = item as? Data,
                  let payload = try? JSONDecoder().decode(TabDropPayload.self, from: data) else { return }
            Task { @MainActor in
                guard payload.modelID == ObjectIdentifier(model).hashValue else { return }
                let tabID = TabID(raw: payload.tabID)
                switch computed {
                case .strip:
                    model.dropTab(tabID, onto: paneID, target: .strip(index: model.tabs(of: paneID).count))
                case .edge, .center:
                    model.dropTab(tabID, onto: paneID, target: computed)
                }
            }
        }
        return true
    }

    private func computeTarget(at location: CGPoint) -> PaneTabRules.DropTarget {
        // The strip band maps to `.strip` (the strip view handles mid-strip insertion itself; a drop landing there
        // through this delegate appends — see `performDrop`); the edge bands start right below it.
        PaneTabRules.dropTarget(point: location, paneRect: CGRect(origin: .zero, size: paneSize),
                                stripHeight: stripHeight, tabFrames: [])
    }

    private func isEdgeOrCenter(_ target: PaneTabRules.DropTarget) -> Bool {
        if case .strip = target { return false }
        return true
    }
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
