import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination
    @Environment(ClipboardManager.self) var clipboardManager
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding(get: { selection }, set: { if let v = $0 { selection = v } })
    }

    private var groups: [(header: String, items: [SidebarDestination])] {
        SidebarSearch.filter(SidebarDestination.groups, query: query) { header, dest in
            [dest.titleKey, L10n.english(dest.titleKey), header, L10n.english(header), dest.rawValue]
        }
    }

    private var showsAbout: Bool {
        SidebarSearch.matches(query: query, texts: [SidebarDestination.about.titleKey, L10n.english(SidebarDestination.about.titleKey), SidebarDestination.about.rawValue])
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            list
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.secondary)
            TextField(L10n.t("Tìm trang"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                // Return opens the first match; Esc clears (standard search-field behaviour).
                .onSubmit { if let first = groups.first?.items.first { selection = first } else if showsAbout { selection = .about } }
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }

    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(groups, id: \.header) { group in
                Section(header: Text(L10n.t(group.header)).font(.caption2).foregroundColor(.secondary)) {
                    ForEach(group.items, id: \.self) { dest in
                        Label(dest.titleVI, systemImage: dest.icon)
                            // Without these, a long row ("Đổi tên hàng loạt")
                            // grows the sidebar's ideal width and the whole
                            // window jumps when that page is selected.
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .tag(dest)
                    }
                }
            }

            // Pinboards moved into the ⌘⇧V shelf, where the cards they hold
            // actually live — a board list here could only jump to a page that
            // no longer shows content.

            if showsAbout {
                Section {
                    Label(SidebarDestination.about.titleVI, systemImage: SidebarDestination.about.icon)
                        .tag(SidebarDestination.about)
                }
            }

            if groups.isEmpty && !showsAbout {
                Text(L10n.t("Không có trang nào khớp."))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }
        }
        .listStyle(.sidebar)
    }
}
