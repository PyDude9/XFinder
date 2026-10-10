import SwiftUI

/// System-Settings-style page header: a large symbol, the page title, and a
/// one-line description. Every detail page opens with this so the pages read
/// as one app rather than a stack of differently-shaped screens.
struct PageHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    /// Optional trailing control (a master on/off switch, a picker).
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundColor(.primary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(XFinderTokens.Font.pageTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(XFinderTokens.Font.pageSubtitle)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let trailing { trailing }
        }
        .padding(.horizontal, XFinderTokens.Space.page)
        .padding(.top, 18)
        .padding(.bottom, 4)
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
