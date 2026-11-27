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
    let subtitle: String?
    let icon: String
    let tile: SidebarTile

    init(title: String, subtitle: String? = nil, icon: String, tile: SidebarTile) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tile = tile
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(XFinderTokens.Settings.sidebarRow)
                    // Without these, a long row ("Đổi tên hàng loạt") grows the
                    // sidebar's ideal width and the whole window jumps when that
                    // page is selected.
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
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
    @State private var query = ""
    @AppStorage("sidebar.collapsedGroups") private var collapsedRaw = ""
    @State private var cachedGroups: [(header: String, items: [SidebarDestination])] = SidebarDestination.groups
    @State private var cachedShowsPro = true
    @State private var cachedShowsAbout = true
    @FocusState private var searchFocused: Bool

    private var collapsedHeaders: Set<String> {
        MenubarPanelRules.parseCollapsedHeaders(collapsedRaw)
    }

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding(get: { selection }, set: { if let v = $0 { selection = v } })
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Recomputes sidebar filtering only when `query` changes (not on every selection click),
    /// matching Vorssaint's `SettingsDirectoryCache` pattern for snappy navigation.
    private func rebuildFilterCache() {
        cachedGroups = SidebarSearch.filter(SidebarDestination.groups, query: query) { header, dest in
            [dest.titleKey, L10n.english(dest.titleKey), header, L10n.english(header), dest.rawValue]
                + dest.searchAlsoKeys.flatMap { [$0, L10n.english($0)] }
                + SettingsSearchIndex.keywords(for: dest)
        }
        cachedShowsPro = SidebarSearch.matches(
            query: query,
            texts: [SidebarDestination.pro.titleKey, L10n.english(SidebarDestination.pro.titleKey), SidebarDestination.pro.rawValue]
                + SettingsSearchIndex.keywords(for: .pro)
        )
        cachedShowsAbout = SidebarSearch.matches(
            query: query,
            texts: [SidebarDestination.about.titleKey, L10n.english(SidebarDestination.about.titleKey), SidebarDestination.about.rawValue]
                + SettingsSearchIndex.keywords(for: .about)
        )
    }

    private func toggleSection(_ header: String) {
        var next = collapsedHeaders
        if next.contains(header) {
            next.remove(header)
        } else {
            next.insert(header)
        }
        collapsedRaw = MenubarPanelRules.encodeCollapsedHeaders(next)
    }

    private func matchHint(for dest: SidebarDestination) -> String? {
        guard isSearching else { return nil }
        return SettingsSearchIndex.firstMatchedKeyword(for: dest, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            list
        }
        .onAppear { rebuildFilterCache() }
        .onChange(of: query) { rebuildFilterCache() }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.secondary)
            TextField(L10n.t("Tìm trang"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                // Return opens the first match; Esc clears (standard search-field behaviour).
                .onSubmit { if let first = cachedGroups.first?.items.first { selection = first } else if cachedShowsAbout { selection = .about } }
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                    .help(L10n.t("Xoá tìm kiếm"))
                    .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
            } else {
                Button { QuickSearchPanelController.shared.toggle() } label: {
                    Text("⌘K")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Mở bảng lệnh (⌘K)"))
                .accessibilityLabel(L10n.t("Mở bảng lệnh (⌘K)"))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(XFinderTokens.Fill.inset, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }

    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(cachedGroups, id: \.header) { group in
                let isCollapsed = !isSearching && collapsedHeaders.contains(group.header)
                Section {
                    if !isCollapsed {
                        ForEach(group.items, id: \.self) { dest in
                            SidebarRow(title: dest.titleVI, subtitle: matchHint(for: dest), icon: dest.icon, tile: dest.tile)
                                .tag(dest)
                        }
                    }
                } header: {
                    Button { toggleSection(group.header) } label: {
                        HStack(spacing: 4) {
                            Text(L10n.t(group.header))
                                .font(XFinderTokens.Settings.sidebarHeader)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                            if !isSearching {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Pinboards moved into the ⌘⇧V shelf, where the cards they hold
            // actually live — a board list here could only jump to a page that
            // no longer shows content.

            if cachedShowsAbout || cachedShowsPro {
                Section {
                    if cachedShowsPro {
                        SidebarRow(title: SidebarDestination.pro.titleVI, subtitle: matchHint(for: .pro), icon: SidebarDestination.pro.icon, tile: SidebarDestination.pro.tile)
                            .tag(SidebarDestination.pro)
                    }
                    if cachedShowsAbout {
                        SidebarRow(title: SidebarDestination.about.titleVI, subtitle: matchHint(for: .about), icon: SidebarDestination.about.icon, tile: SidebarDestination.about.tile)
                            .tag(SidebarDestination.about)
                    }
                }
            }

            if cachedGroups.isEmpty && !cachedShowsAbout && !cachedShowsPro {
                Text(L10n.t("Không có trang nào khớp."))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .medium)
    }
}
