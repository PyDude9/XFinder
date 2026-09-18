import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination
    @Environment(ClipboardManager.self) var clipboardManager

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding(get: { selection }, set: { if let v = $0 { selection = v } })
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(SidebarDestination.groups, id: \.header) { group in
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

            Section {
                Label(SidebarDestination.about.titleVI, systemImage: SidebarDestination.about.icon)
                    .tag(SidebarDestination.about)
            }
        }
        .listStyle(.sidebar)
    }
}
