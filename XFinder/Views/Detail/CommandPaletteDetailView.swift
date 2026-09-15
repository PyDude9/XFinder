import SwiftUI

/// Command Palette settings page — cấu hình quicklinks, hotkey, v.v.
struct CommandPaletteDetailView: View {
    @State private var quicklinks = Quicklinks.shared
    @State private var showAddSheet = false
    @State private var editingLink: Quicklinks.Quicklink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "command",
                    title: "Command Palette",
                    subtitle: "Tìm ứng dụng, file, tính toán — nhấn ⌘Space để mở."
                )

                summaryCard
                Divider().padding(.horizontal, 20)
                quicklinksCard
            }
            .padding(.vertical, 16)
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showAddSheet) {
            QuicklinkEditorSheet(isPresented: $showAddSheet, link: editingLink)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "command").foregroundColor(.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nhấn ⌘Space để mở Command Palette")
                    .font(.system(size: 13))
                Text("Tìm nhanh app, file, tính toán, và quicklink")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var quicklinksCard: some View {
        SettingsCard(
            title: "Quicklinks",
            subtitle: "\(quicklinks.links.count) liên kết nhanh"
        ) {
            VStack(spacing: 8) {
                ForEach(quicklinks.links) { link in
                    QuicklinkRow(link: link, onEdit: {
                        editingLink = link
                        showAddSheet = true
                    }, onDelete: {
                        quicklinks.delete(link)
                    })
                }

                Button("Thêm quicklink") {
                    editingLink = nil
                    showAddSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct QuicklinkRow: View {
    let link: Quicklinks.Quicklink
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundColor(.purple).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    Text(link.keyword)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                    Text(link.url)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil").font(.caption)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

private struct QuicklinkEditorSheet: View {
    @Binding var isPresented: Bool
    let link: Quicklinks.Quicklink?
    @State private var title = ""
    @State private var url = ""
    @State private var keyword = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(link == nil ? "Thêm quicklink" : "Sửa quicklink")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Tiêu đề").font(.system(size: 12, weight: .medium))
                TextField("Google", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL").font(.system(size: 12, weight: .medium))
                TextField("https://google.com", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Từ khóa").font(.system(size: 12, weight: .medium))
                TextField("g", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Hủy") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(link == nil ? "Thêm" : "Lưu") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || url.isEmpty || keyword.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let link = link {
                title = link.title
                url = link.url
                keyword = link.keyword
            }
        }
    }

    private func save() {
        if let link = link {
            Quicklinks.shared.update(link, title: title, url: url, keyword: keyword)
        } else {
            Quicklinks.shared.add(title: title, url: url, keyword: keyword)
        }
        isPresented = false
    }
}
