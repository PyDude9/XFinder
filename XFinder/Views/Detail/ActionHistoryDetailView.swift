import SwiftUI

/// Lịch sử thao tác — reads ActionHistoryStore. Every mutating page logs here;
/// rename entries offer one-click undo, irreversible entries say so honestly.
struct ActionHistoryDetailView: View {
    @State private var store = ActionHistoryStore.shared
    @State private var undoMessage: String? = nil

    private var dateFmt: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "vi_VN")
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "clock.arrow.circlepath",
                title: L10n.t("Lịch sử thao tác"),
                subtitle: "\(store.entries.count)\(L10n.t(" mục"))",
                trailing: store.entries.isEmpty ? nil : AnyView(
                    Button(L10n.t("Xóa lịch sử")) { store.clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                )
            )
            Divider().padding(.horizontal, XFinderTokens.Space.page)

            if let msg = undoMessage {
                Text(msg).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, XFinderTokens.Space.page).padding(.vertical, XFinderTokens.Space.tight)
                Divider().padding(.horizontal, XFinderTokens.Space.page)
            }

            if store.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(XFinderTokens.Font.metric).foregroundColor(.secondary)
                    Text(L10n.t("Chưa có thao tác nào")).font(XFinderTokens.Font.sectionTitle)
                    Text(L10n.t("Đổi tên, nén/giải nén, xử lý PDF… sẽ được ghi lại ở đây."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.entries) { entry in
                            HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                                Image(systemName: icon(for: entry.kind))
                                    .foregroundColor(color(for: entry.kind))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.summary)
                                        .font(XFinderTokens.Font.row)
                                        .fileNameRowSafe()
                                    if let d = entry.detail, !d.isEmpty {
                                        Text(d).font(XFinderTokens.Font.mono)
                                            .foregroundColor(.secondary).lineLimit(4)
                                    }
                                    Text(dateFmt.string(from: entry.timestamp))
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                }
                                Spacer(minLength: XFinderTokens.Space.inline)
                                if entry.reversible {
                                    Button(L10n.t("Hoàn tác")) {
                                        undoMessage = store.undo(entry)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text(L10n.t("Không thể hoàn tác"))
                                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, XFinderTokens.Space.tight)
                            Divider()
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
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
