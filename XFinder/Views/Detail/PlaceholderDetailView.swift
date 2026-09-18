import SwiftUI

struct PlaceholderDetailView: View {
    let destination: SidebarDestination

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: destination.icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(destination.titleVI)
                .font(.title2).fontWeight(.semibold)
            if destination.isComingSoon {
                Text(L10n.t("Sắp có — sẽ làm ở mục riêng"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                Text(L10n.t("Đang xây dựng…"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}
