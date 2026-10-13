import SwiftUI

struct PlaceholderDetailView: View {
    let destination: SidebarDestination

    var body: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            PageHeader(icon: destination.icon, title: destination.titleVI)
            if destination.isComingSoon {
                Text(L10n.t("Sắp có — sẽ làm ở mục riêng"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(XFinderTokens.Fill.inset)
                    .cornerRadius(XFinderTokens.Radius.badge)
            } else {
                Text(L10n.t("Đang xây dựng…"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XFinderTokens.Settings.contentBackground)
    }
}
