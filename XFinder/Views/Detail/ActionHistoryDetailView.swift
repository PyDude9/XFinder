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
            HStack {
                Text("Lịch sử thao tác")
                    .font(.system(size: 22, weight: .bold))
                Text("\(store.entries.count)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color(.controlBackgroundColor)).cornerRadius(8)
                Spacer()
                if !store.entries.isEmpty {
                    Button("Xóa lịch sử") { store.clear() }
                        .font(.system(size: 12)).foregroundColor(.red)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()

            if let msg = undoMessage {
                Text(msg).font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                Divider()
            }

            if store.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36)).foregroundColor(.secondary)
                    Text("Chưa có thao tác nào").font(.headline)
                    Text("Đổi tên, nén/giải nén, xử lý PDF… sẽ được ghi lại ở đây.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: entry.kind))
                                    .foregroundColor(color(for: entry.kind))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.summary)
                                        .font(.system(size: 13, weight: .medium))
                                    if let d = entry.detail, !d.isEmpty {
                                        Text(d).font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary).lineLimit(4)
                                    }
                                    Text(dateFmt.string(from: entry.timestamp))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if entry.reversible {
                                    Button("Hoàn tác") {
                                        undoMessage = store.undo(entry)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text("Không thể hoàn tác")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "rename": return "textformat.abc.dottedunderline"
        case "compress": return "archivebox.fill"
        case "extract": return "archivebox"
        case "pdf": return "doc.richtext.fill"
        case "trash": return "trash.fill"
        default: return "circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "rename": return .blue
        case "compress", "extract": return .orange
        case "pdf": return .red
        case "trash": return .gray
        default: return .secondary
        }
    }
}
