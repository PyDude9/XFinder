import SwiftUI

/// Lịch sử thao tác — reads ActionHistoryStore. Every mutating page logs here;
/// rename entries offer one-click undo, irreversible entries say so honestly.
struct ActionHistoryDetailView: View {
    @State private var store = ActionHistoryStore.shared
    @State private var undoMessage: String? = nil

    /// One formatter for the page, not one per row per render (audit 2026-10-18, P-5). Configured once, never mutated.
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Lịch sử thao tác"),
                    subtitle: "\(store.entries.count)\(L10n.t(" mục"))",
                    trailing: store.entries.isEmpty ? nil : AnyView(
                        Button(L10n.t("Xóa lịch sử")) { store.clear() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                    )
                )

                if let msg = undoMessage {
                    Text(msg).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, XFinderTokens.Space.page)
                }

                if store.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(XFinderTokens.Font.metric).foregroundColor(.secondary)
                        Text(L10n.t("Chưa có thao tác nào")).font(XFinderTokens.Font.sectionTitle)
                        Text(L10n.t("Đổi tên, nén/giải nén, xử lý PDF… sẽ được ghi lại ở đây."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, XFinderTokens.Space.section)
                } else {
                    SettingsSection {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { entry in
                            let item = entry.element
                            if entry.offset > 0 { SettingsDivider() }
                            HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                                Image(systemName: icon(for: item.kind))
                                    .foregroundColor(color(for: item.kind))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.summary)
                                        .font(XFinderTokens.Font.row)
                                        .fileNameRowSafe()
                                    if let d = item.detail, !d.isEmpty {
                                        Text(d).font(XFinderTokens.Font.mono)
                                            .foregroundColor(.secondary).lineLimit(4)
                                    }
                                    Text(Self.dateFmt.string(from: item.timestamp))
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                }
                                Spacer(minLength: XFinderTokens.Space.inline)
                                if item.reversible {
                                    Button(L10n.t("Hoàn tác")) {
                                        undoMessage = store.undo(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text(L10n.t("Không thể hoàn tác"))
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                }
                            }
                            .settingsRow()
                        }
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "rename": return "textformat.abc.dottedunderline"
        case "compress": return "archivebox.fill"
        case "extract": return "archivebox"
        case "pdf": return "doc.richtext.fill"
        case "image": return "photo.fill"
        case "trash": return "trash.fill"
        default: return "circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "rename": return .blue
        case "compress", "extract": return .orange
        case "pdf": return .red
        case "image": return .purple
        case "trash": return .gray
        default: return .secondary
        }
    }
}
