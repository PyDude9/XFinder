import Foundation
import CoreGraphics

/// Pure geometry of window snapping — every target rectangle, which zone a window drag is over, and
/// the layout row that appears under the notch (B3). It used to live inside `WindowManager` and
/// `SnapZoneController` (AppKit), so the tests checked a hand-copied duplicate that could drift;
/// now the real functions are tested.
///
/// Spaces: target rects are in TOP-LEFT origin (they feed AXPosition) — "bottom" has the larger y.
/// Pointer zones, the row and its tiles are in AppKit space (origin bottom-left, like NSEvent).
enum SnapLayout {

    enum Target: String, CaseIterable, Identifiable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center
        case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds, focus
        var id: String { rawValue }

        /// Store key for the user-facing name (the view calls L10n.t).
        var titleKey: String {
            switch self {
            case .leftHalf: return "Trái nửa màn hình"
            case .rightHalf: return "Phải nửa màn hình"
            case .topHalf: return "Trên nửa màn hình"
            case .bottomHalf: return "Dưới nửa màn hình"
            case .topLeft: return "Góc trên-trái"
            case .topRight: return "Góc trên-phải"
            case .bottomLeft: return "Góc dưới-trái"
            case .bottomRight: return "Góc dưới-phải"
            case .maximize: return "Toàn màn hình"
            case .center: return "Giữa màn hình"
            case .leftThird: return "Một phần ba bên trái"
            case .centerThird: return "Một phần ba ở giữa"
            case .rightThird: return "Một phần ba bên phải"
            case .leftTwoThirds: return "Hai phần ba bên trái"
            case .rightTwoThirds: return "Hai phần ba bên phải"
            case .focus: return "Tập trung (giữa, 60% bề ngang)"
            }
        }

        /// Target rectangle inside `screen` (top-left origin). Thirds are rounded so neighbours share
        /// an edge exactly and the three thirds always cover the full width.
        func rect(in screen: CGRect) -> CGRect {
            let w = screen.width, h = screen.height, x = screen.minX, y = screen.minY
            let t1 = (w / 3).rounded(.down), t2 = (2 * w / 3).rounded(.down)
            switch self {
            case .leftHalf:       return CGRect(x: x, y: y, width: w / 2, height: h)
            case .rightHalf:      return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
            case .topHalf:        return CGRect(x: x, y: y, width: w, height: h / 2)
            case .bottomHalf:     return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
            case .topLeft:        return CGRect(x: x, y: y, width: w / 2, height: h / 2)
            case .topRight:       return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
            case .bottomLeft:     return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
            case .bottomRight:    return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
            case .maximize:       return screen
            case .center:
                let cw = min(w * 0.7, 1100), ch = min(h * 0.75, 750)
                return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
            case .leftThird:      return CGRect(x: x, y: y, width: t1, height: h)
            case .centerThird:    return CGRect(x: x + t1, y: y, width: t2 - t1, height: h)
            case .rightThird:     return CGRect(x: x + t2, y: y, width: w - t2, height: h)
            case .leftTwoThirds:  return CGRect(x: x, y: y, width: t2, height: h)
            case .rightTwoThirds: return CGRect(x: x + t1, y: y, width: w - t1, height: h)
            case .focus:
                let fw = (w * 0.6).rounded()
                return CGRect(x: x + ((w - fw) / 2).rounded(), y: y, width: fw, height: h)
            }
        }
    }

    // MARK: Stage Manager

    /// Left clearance for the Stage Manager strip (macOS does not shrink visibleFrame for it —
    /// measured). Off ⇒ 0; the user can switch it off or tune it; clamped to the slider's 48…140.
    static func stageInset(stageManagerOn: Bool, reserve: Bool, custom: Double?) -> CGFloat {
        guard stageManagerOn, reserve else { return 0 }
        return min(max(CGFloat(custom ?? 68), 48), 140)
    }

    // MARK: Edge zones (AppKit space)

    /// Which edge target a window drag at `point` is over. Corners (the top/bottom 25 % of a side)
    /// win over edges. The top edge maximises — except where the notch row takes over (see `decide`).
    static func edgeTarget(at point: CGPoint, screen f: CGRect, margin m: CGFloat) -> Target? {
        let nearLeft = point.x <= f.minX + m, nearRight = point.x >= f.maxX - m
        let nearTop = point.y >= f.maxY - m, nearBottom = point.y <= f.minY + m
        let cornerY = f.height * 0.25
        if nearLeft && point.y >= f.maxY - cornerY { return .topLeft }
        if nearLeft && point.y <= f.minY + cornerY { return .bottomLeft }
        if nearRight && point.y >= f.maxY - cornerY { return .topRight }
        if nearRight && point.y <= f.minY + cornerY { return .bottomRight }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearTop { return .maximize }
        if nearBottom { return .bottomHalf }
        return nil
    }

    // MARK: Notch layout row (AppKit space)

    /// The layouts the row offers, left to right.
    static let rowTargets: [Target] = [.leftHalf, .rightHalf, .leftThird, .centerThird, .rightThird, .focus, .maximize]

    struct RowMetrics: Equatable {
        var tileSize = CGSize(width: 64, height: 44)
        var spacing: CGFloat = 8
        var padding: CGFloat = 10
        /// How far the drag zone reaches beyond each side of the notch and below the top edge.
        var zoneMargin: CGFloat = 80
        var zoneDepth: CGFloat = 40
        static let standard = RowMetrics()
    }

    /// Where a window drag summons the row: the notch widened by `zoneMargin` and reaching
    /// `zoneDepth` below the top edge. `notch` may be a zero-height stand-in on a notch-less screen.
    static func rowActivationZone(notch: CGRect, screen: CGRect, metrics m: RowMetrics = .standard) -> CGRect {
        let depth = max(notch.height, m.zoneDepth)
        return CGRect(x: notch.midX - notch.width / 2 - m.zoneMargin, y: screen.maxY - depth,
                      width: notch.width + 2 * m.zoneMargin, height: depth)
    }

    /// The row panel: centred on the notch, hanging just below it (or below the top edge), clamped
    /// to the screen.
    static func rowFrame(count: Int, notch: CGRect, screen: CGRect, metrics m: RowMetrics = .standard) -> CGRect {
        let width = CGFloat(count) * m.tileSize.width + CGFloat(max(count - 1, 0)) * m.spacing + 2 * m.padding
        let height = m.tileSize.height + 2 * m.padding
        let top = screen.maxY - max(notch.height, 0) - 6
        var r = CGRect(x: notch.midX - width / 2, y: top - height, width: width, height: height)
        r.origin.x = max(min(r.minX, screen.maxX - r.width), screen.minX)   // too wide ⇒ keep the left edge on screen
        return r
    }

    static func tileFrames(row: CGRect, count: Int, metrics m: RowMetrics = .standard) -> [CGRect] {
        (0..<count).map { i in
            CGRect(x: row.minX + m.padding + CGFloat(i) * (m.tileSize.width + m.spacing),
                   y: row.minY + m.padding, width: m.tileSize.width, height: m.tileSize.height)
        }
    }

    /// The tile under the pointer. The gaps between tiles count for the nearer tile, so sliding
    /// along the row never flickers to "nothing".
    static func tileIndex(at point: CGPoint, row: CGRect, count: Int, metrics m: RowMetrics = .standard) -> Int? {
        guard count > 0, row.contains(point) else { return nil }
        let x = point.x - row.minX - m.padding + m.spacing / 2
        let i = Int((x / (m.tileSize.width + m.spacing)).rounded(.down))
        return min(max(i, 0), count - 1)
    }

    enum Decision: Equatable {
        /// Show the row; `tile` is the highlighted one (nil while the pointer is in the zone but not yet on a tile).
        case row(tile: Int?)
        case edge(Target?)
    }

    /// One answer per pointer position during a window drag. The row appears when the pointer
    /// enters the activation zone and stays while the pointer is over the activation zone or the
    /// row itself (so the user can move down onto the tiles); anywhere else, the edge zones apply.
    static func decide(point: CGPoint, screen: CGRect, notch: CGRect, edgeMargin: CGFloat,
                       rowEnabled: Bool, rowVisible: Bool, metrics m: RowMetrics = .standard) -> Decision {
        if rowEnabled {
            let zone = rowActivationZone(notch: notch, screen: screen, metrics: m)
            let row = rowFrame(count: rowTargets.count, notch: notch, screen: screen, metrics: m)
            if zone.contains(point) || (rowVisible && row.insetBy(dx: -8, dy: -8).contains(point)) {
                return .row(tile: tileIndex(at: point, row: row, count: rowTargets.count, metrics: m))
            }
        }
        return .edge(edgeTarget(at: point, screen: screen, margin: edgeMargin))
    }

    // MARK: - Is this press a WINDOW drag? (2026-10-14)

    /// The owner reported drag-to-edge dead while the keyboard snaps still worked. Measured cause: the press was
    /// qualified by walking at most 4 Accessibility parents from the element under the pointer to an AXWindow/AXToolbar,
    /// and on this Mac the window is 5–7 parents up in 6 of 8 real apps — so no drag ever qualified. Widening the walk is
    /// wrong too: every element of a window has the window as an ancestor, so a deep walk would also qualify a text
    /// selection (the old "snap fired on every drag" bug). The honest signal is the one WindowServer reports: the
    /// window under the pointer at press MOVED. `windowOrigin` comes from CGWindowList (top-left space), `pointer` from
    /// NSEvent (bottom-left) — each is compared only with itself.
    struct DragQualifier: Equatable, Sendable {
        enum Verdict: Equatable, Sendable { case pending, windowMove, notWindowMove }
        private(set) var verdict: Verdict
        let pressPoint: CGPoint
        let windowOrigin: CGPoint?
        /// The window moved at least this far ⇒ it is being dragged.
        static let moveThreshold: CGFloat = 1
        /// The pointer travelled this far and the window stayed put ⇒ a text selection, a file drag, a drawing.
        static let travelLimit: CGFloat = 40

        init(pressPoint: CGPoint, windowOrigin: CGPoint?) {
            self.pressPoint = pressPoint
            self.windowOrigin = windowOrigin
            verdict = windowOrigin == nil ? .notWindowMove : .pending
        }

        /// One drag event. `windowOriginNow` nil = the window could not be read this time (it stays pending until the
        /// pointer has travelled `travelLimit`). Once decided, the verdict never changes for this press.
        @discardableResult
        mutating func observe(pointer: CGPoint, windowOriginNow: CGPoint?) -> Verdict {
            guard verdict == .pending, let start = windowOrigin else { return verdict }
            if let now = windowOriginNow, hypot(now.x - start.x, now.y - start.y) >= Self.moveThreshold {
                verdict = .windowMove
            } else if hypot(pointer.x - pressPoint.x, pointer.y - pressPoint.y) >= Self.travelLimit {
                verdict = .notWindowMove
            }
            return verdict
        }
    }
}
