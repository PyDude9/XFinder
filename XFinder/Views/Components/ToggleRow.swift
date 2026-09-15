import SwiftUI

/// A labeled Toggle with description, matching the card aesthetic of SettingsCard.
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
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
