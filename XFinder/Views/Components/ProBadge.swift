import SwiftUI

/// XF-T29 — the "PRO" tag beside a gated control, and the gate itself: a locked control is disabled, tagged and says why
/// (CLAUDE.md rule 7: a surface that is off must say it is off) instead of silently doing nothing.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(XFinderTokens.Font.caption.weight(.bold))
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, XFinderTokens.Space.hairline)
            .background(Capsule().fill(Color.primary))
            .foregroundColor(Color(nsColor: .windowBackgroundColor))
            .accessibilityLabel(L10n.t("Cần XFinder Pro"))
    }
}

private struct ProGate: ViewModifier {
    let feature: ProFeature
    @State private var license = LicenseManager.shared

    func body(content: Content) -> some View {
        let allowed = license.allows(feature)
        HStack(spacing: XFinderTokens.Space.tight) {
            content.disabled(!allowed)
            if !allowed {
                Button {
                    AppState.shared.navigate(to: .pro)
                } label: { ProBadge() }
                .buttonStyle(.plain)
                .help(L10n.t("Cần XFinder Pro — bấm để xem"))
            }
        }
    }
}

extension View {
    /// Disables the control and shows a PRO tag (linking to the Pro page) when the current tier does not allow `feature`.
    func proGated(_ feature: ProFeature) -> some View { modifier(ProGate(feature: feature)) }
}
