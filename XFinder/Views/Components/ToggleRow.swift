import SwiftUI

/// A labeled Toggle with description — the standard boolean settings row.
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(XFinderTokens.Font.row)
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: $isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(tint)
        }
        .padding(.vertical, 2)
    }
}
