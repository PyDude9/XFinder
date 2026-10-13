import SwiftUI

/// P3 (2026-10-13): `SidebarTile` (a name, Foundation-only, in `SidebarDestination.swift`) resolved to a real
/// `Color` here — the only file that needs AppKit's `NSColor.system*` constants, so the model stays testable.
private extension SidebarTile {
    var color: Color {
        switch self {
        case .gray: return Color(nsColor: .systemGray)
        case .blue: return Color(nsColor: .systemBlue)
        case .indigo: return Color(nsColor: .systemIndigo)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .mint: return Color(nsColor: .systemMint)
        case .teal: return Color(nsColor: .systemTeal)
        case .cyan: return Color(nsColor: .systemCyan)
        case .brown: return Color(nsColor: .systemBrown)
        }
    }
}

/// One sidebar row: a coloured icon tile (OneNotch's convention) + title. Used for every destination, including
/// the footer "Giới thiệu" row — one row view for the whole list, not two parallel implementations.
private struct SidebarRow: View {
    let title: String
    let icon: String
    let tile: SidebarTile

    var body: some View {
        Label {
            Text(title)
                .font(XFinderTokens.Settings.sidebarRow)
                // Without these, a long row ("Đổi tên hàng loạt") grows the
                // sidebar's ideal width and the whole window jumps when that
                // page is selected.
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            RoundedRectangle(cornerRadius: XFinderTokens.Settings.tileRadius, style: .continuous)
                .fill(tile.color)
                .frame(width: XFinderTokens.Settings.tileSize, height: XFinderTokens.Settings.tileSize)
                .overlay {
                    Image(systemName: icon)
                        .font(XFinderTokens.Settings.tileGlyph)
                        .foregroundColor(.white)
                }
                // The tile is decorative — VoiceOver should read only the title,
                // exactly like the plain SF Symbol it replaces.
                .accessibilityHidden(true)
        }
    }
}

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
                Section(header: Text(L10n.t(group.header)).font(XFinderTokens.Settings.sidebarHeader).foregroundColor(.secondary)) {
                    ForEach(group.items, id: \.self) { dest in
                        SidebarRow(title: dest.titleVI, icon: dest.icon, tile: dest.tile)
                            .tag(dest)
                    }
                }
            }

            // Pinboards moved into the ⌘⇧V shelf, where the cards they hold
            // actually live — a board list here could only jump to a page that
            // no longer shows content.

            if showsAbout {
                Section {
                    SidebarRow(title: SidebarDestination.about.titleVI, icon: SidebarDestination.about.icon, tile: SidebarDestination.about.tile)
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
        // OneNotch's sidebar rows read taller than the system default list row —
        // this is the public SwiftUI knob for that, not a hand-rolled row height.
        .environment(\.sidebarRowSize, .large)
    }
}
