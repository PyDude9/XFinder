import SwiftUI

/// The three row shapes the flat pages were missing. Together with `LabeledLine`, `ToggleRow` and
/// `StatusChecklistRow` they cover every settings row in the app, so a page never has to invent one.

/// A label with a menu picker on the right. `.menu` on purpose: a `.segmented` picker sums every
/// label into its ideal width and has resized the window three times in this project; segmented is
/// allowed only for ≤ 4 short labels, and the UI-token audit enforces that.
struct PickerRow<SelectionValue: Hashable, Options: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: SelectionValue
    var width: CGFloat = 150
    @ViewBuilder var options: Options

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(XFinderTokens.Font.row)
                if let subtitle {
                    Text(subtitle).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: XFinderTokens.Space.inline)
            Picker("", selection: $selection) { options }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: width)
        }
        .padding(.vertical, 2)
    }
}

/// A label (optionally with a status) and a bordered button on the right.
struct ActionRow: View {
    let title: String
    var subtitle: String? = nil
    var status: String? = nil
    let buttonTitle: String
    var destructive = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(XFinderTokens.Font.row)
                if let subtitle {
                    Text(subtitle).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: XFinderTokens.Space.inline)
            if let status {
                Text(status).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(destructive ? .red : nil)
                .disabled(disabled)
        }
        .padding(.vertical, 2)
    }
}

/// An explanatory note under a row: plain, a warning, or a permission that is missing (with the
/// button that fixes it). Replaces the three hand-rolled `permissionNote`-style helpers.
struct InlineNote: View {
    enum Kind { case plain, warning, success }
    var kind: Kind = .plain
    let text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    private var color: Color {
        switch kind {
        case .plain: return .secondary
        case .warning: return .orange
        case .success: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Text(text)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, value on the right. The most common settings/readout row.
/// (Moved here from NetworkDetailView.swift — it was a shared component living inside a page.)
struct LabeledLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(XFinderTokens.Font.row)
            Spacer()
            Text(value).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }
}

/// A label, a percentage, and a thin bar. `percent == nil` renders "Không khả dụng" with an empty
/// track — never a fabricated 0 %. (Moved here from SystemDetailView.swift.)
struct MeterRow: View {
    let label: String
    let percent: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(label).font(XFinderTokens.Font.row)
                Spacer()
                Text(percent.map { String(format: "%.0f%%", $0) } ?? L10n.t("Không khả dụng"))
                    .font(percent == nil ? XFinderTokens.Font.rowValue : XFinderTokens.Font.row)
                    .foregroundColor(percent == nil ? .secondary : .primary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(XFinderTokens.Fill.inset)
                    if let percent {
                        Capsule().fill(tint).frame(width: geo.size.width * min(max(percent / 100, 0), 1))
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }
}
