import SwiftUI

/// P3 (2026-10-13) — OneNotch's settings grammar, measured on its settings screenshots: a plain section title, then a
/// flat card (#F7F7F7-equivalent, corner 10, no stroke, no shadow) holding rows separated by inset hairlines. The new
/// pages use this; the older flat pages keep their `Divider` rows until P4 converts them through the same parts.
///
/// macOS 14 has no public way to walk a `ViewBuilder`'s children, so a card does not insert its own dividers: write
/// `SettingsDivider()` between rows and give each row `.settingsRow()`.
struct SettingsSection<Content: View>: View {
    var title: String? = nil
    /// Plain text under the card (OneNotch puts explanations outside the box, not inside it).
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            if let title {
                Text(title)
                    .font(XFinderTokens.Settings.sectionTitle)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, XFinderTokens.Settings.cardInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: XFinderTokens.Settings.cardRadius, style: .continuous)
                        .fill(XFinderTokens.Settings.cardFill)
                )
            if let footer {
                Text(footer)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.page)
        // The page-width rule (PageWidth.swift): minWidth 0 alone never stopped a wide row pushing the window.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between two rows inside a card. The card's own inset makes it start where the row text starts and
/// stop short of the right edge — never full-bleed (measured).
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(XFinderTokens.Settings.hairline)
            .frame(height: 1)
    }
}

extension View {
    /// Frames one row inside a `SettingsSection` card: the measured 31-pt one-line height, growing for a subtitle.
    func settingsRow() -> some View {
        padding(.vertical, XFinderTokens.Settings.rowVerticalPadding)
            .frame(minWidth: 0, maxWidth: .infinity,
                   minHeight: XFinderTokens.Settings.rowMinHeight, alignment: .leading)
    }
}

/// A row that sends the user to the page that OWNS a setting (Part 0 §4: one key, one control). Use it wherever a
/// second page wants to mention a setting — never a second toggle bound to the same key.
struct SettingsLinkRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let destination: SidebarDestination
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button {
            AppState.shared.navigate(to: destination)
        } label: {
            HStack(spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(XFinderTokens.Font.row)
                        .foregroundColor(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: XFinderTokens.Space.inline)
                trailing
                Image(systemName: "chevron.right")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(destination.titleVI)
        .settingsRow()
    }
}

extension SettingsLinkRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, destination: SidebarDestination) {
        self.init(title: title, subtitle: subtitle, destination: destination) { EmptyView() }
    }
}

/// A keyboard shortcut drawn as a keycap ("⌘⇧V"). Glyph labels are language-neutral, so callers pass them unwrapped.
struct ShortcutChip: View {
    let label: String
    /// Drawn quieter when the shortcut is currently switched off.
    var isActive = true

    var body: some View {
        Text(label)
            .font(XFinderTokens.Settings.keycap)
            .foregroundColor(isActive ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(XFinderTokens.Fill.inset)
            )
            .accessibilityLabel(label)
    }
}
