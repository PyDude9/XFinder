import SwiftUI

/// A tiny history line chart. No dependency on Charts (macOS 13+). Rendered with
/// Path + linear interpolation + translucent fill — smooth enough for sparklines.
struct SparklineView: View {
    let values: [Double]
    /// The full-scale upper bound the sparkline maps against (if nil, uses max(values)).
    var yMax: Double? = nil
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 1.5
    var height: CGFloat = 36

    /// Drawn with a single `Canvas`, NOT `GeometryReader` + stacked `Path`s.
    /// Measured: the old form allocated a fresh GPU layer per `Path` on every
    /// 2 s metrics tick and the surfaces were never reclaimed — idle footprint
    /// climbed 54 MB → 178 MB (105 MB of it graphics) within 20 seconds.
    /// `Canvas` renders into one reused drawing surface, so the cost is flat.
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let w = size.width
            let h = size.height
            let denom = Swift.max(yMax ?? (values.max() ?? 1), 1)

            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                with: .color(.primary.opacity(0.04)))

            guard values.count > 1 else {
                if let v = values.first {
                    let y = h - CGFloat(v / denom) * h
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: w, y: y))
                    context.stroke(line, with: .color(tint.opacity(0.7)), lineWidth: lineWidth)
                }
                return
            }

            let stepX = w / CGFloat(values.count - 1)
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(v / denom) * h)
            }

            var line = Path()
            line.move(to: points[0])
            for pt in points.dropFirst() { line.addLine(to: pt) }

            var area = line
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: h))
            area.addLine(to: CGPoint(x: points[0].x, y: h))
            area.closeSubpath()

            context.fill(area, with: .color(tint.opacity(0.14)))
            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
