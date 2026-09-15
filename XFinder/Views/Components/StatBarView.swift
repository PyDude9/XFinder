import SwiftUI

/// Horizontal progress bar with a label and trailing percent. Painted with
/// GeometryReader (no Gauge — deployment target is macOS 12).
struct StatBarView: View {
    let label: String
    /// 0...100. Pass nil to render the placeholder state (empty track, no number).
    var percent: Double? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if let p = percent {
                    Text(String(format: "%.0f%%", p))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            GeometryReader { geo in
                let fill = percent.map { CGFloat(max(0, min($0, 100)) / 100.0) * geo.size.width } ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tint).frame(width: fill)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Segmented bar for a memory breakdown (App / Wired / Compressed / Swap / Free).
struct SegmentedMemoryBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Int64
        let color: Color
        let label: String
    }
    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        let total = Double(segments.map(\.value).reduce(0, +))
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { seg in
                    let w = total > 0 ? CGFloat(Double(seg.value) / total) * geo.size.width : 0
                    Capsule().fill(seg.color).frame(width: max(w - 2, 0))
                }
            }
        }
        .frame(height: height)
    }
}
