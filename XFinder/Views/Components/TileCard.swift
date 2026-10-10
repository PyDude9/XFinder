import SwiftUI

/// A bordered tile for GRIDS of equal things — feature bundles, battery devices, clipboard cards.
/// It is NOT a page section: settings pages are flat (`PageHeader` → `SectionHeader` → rows), and
/// `scripts/audit-ui-tokens.py` fails on any `SettingsCard(`/`TileCard(` used as a section box in
/// `Views/Detail/`. The old name was `SettingsCard`, which is exactly how 12 pages ended up boxed.
struct TileCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.inline) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(XFinderTokens.Font.row).foregroundColor(.primary)
                    if let subtitle {
                        Text(subtitle).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous).fill(XFinderTokens.Fill.surface))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous).strokeBorder(XFinderTokens.Fill.hairline, lineWidth: 1))
    }
}
