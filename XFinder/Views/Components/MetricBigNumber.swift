import SwiftUI

/// A large numeric readout with a small unit suffix and a caption label.
/// The value is supplied pre-formatted so callers can pass placeholders
/// ("Đang thu thập…") without a number.
struct MetricBigNumber: View {
    let value: String
    var unit: String = ""
    let label: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(XFinderTokens.Font.metric)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .font(XFinderTokens.Font.metricUnit)
                        .foregroundColor(.secondary)
                }
            }
            Text(label)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
