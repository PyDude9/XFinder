import SwiftUI

/// OneNotch-style page header (P3, measured on its settings screenshots): a fixed-height title bar with a
/// trailing control, a full-width hairline under it, then the subtitle below the hairline.
///
/// No icon: the sidebar's coloured tile carries the page's glyph (P3), and P4 removed the dead parameter from all
/// 45 call sites.
/// A page shown as a TAB inside another page (the four "Theo dõi hệ thống" tabs) hides its own header: the host page
/// draws one header for all of them.
private struct PageHeaderHiddenKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var pageHeaderHidden: Bool {
        get { self[PageHeaderHiddenKey.self] }
        set { self[PageHeaderHiddenKey.self] = newValue }
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    /// Optional trailing control (a master on/off switch, a picker).
    var trailing: AnyView? = nil
    @Environment(\.pageHeaderHidden) private var hidden

    var body: some View {
        if !hidden { header }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: XFinderTokens.Space.inline) {
                Text(title)
                    .font(XFinderTokens.Settings.headerTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: XFinderTokens.Space.inline)

                if let trailing { trailing }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
            .frame(height: XFinderTokens.Settings.headerHeight)

            Rectangle()
                .fill(XFinderTokens.Settings.hairline)
                .frame(height: 1)

            if let subtitle {
                Text(subtitle)
                    .font(XFinderTokens.Font.pageSubtitle)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .padding(.top, 10)
            }
        }
    }
}

/// Group heading inside a page — small symbol, bold label, muted description.
struct SectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(XFinderTokens.Font.sectionIcon)
                .foregroundColor(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(XFinderTokens.Font.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(XFinderTokens.Font.sectionSubtitle)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.page)
        .padding(.top, XFinderTokens.Space.tight)
    }
}

/// Status line used by the Tổng quan checklist: a state dot, a label, a
/// right-aligned status and an optional action button.
struct StatusChecklistRow: View {
    enum State {
        case ok          // green check
        case warning     // orange triangle
        case neutral     // hollow circle — not installed / not applicable

        var icon: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .neutral: return "circle"
            }
        }
        var color: Color {
            switch self {
            case .ok: return .green
            case .warning: return .orange
            case .neutral: return .secondary
            }
        }
    }

    let state: State
    let title: String
    let status: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.icon)
                .foregroundColor(state.color)
                .frame(width: 18)
            Text(title)
                .font(XFinderTokens.Font.row)
            Spacer(minLength: XFinderTokens.Space.inline)
            Text(status)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.secondary)
            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }
}
