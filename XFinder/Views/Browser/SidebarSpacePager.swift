import SwiftUI

/// XF-T32 W2 (contract XF-T32-w23 §C) — the strip pinned to the foot of the sidebar (Tilde): ⊕ on the left (new sidebar
/// group, `onNewGroup`), one page dot per Space in the centre (active filled, click activates), + on the right (new Space).
struct SidebarSpacePager: View {
    let spaces: SpaceController
    let onNewGroup: () -> Void
    let onNewLiveGroup: () -> Void

    @State private var nameSheet: SidebarSpaceNameSheet.Mode?

    var body: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Color.clear.frame(width: XFinderTokens.BrowserSidebar.pagerHeight, height: XFinderTokens.BrowserSidebar.pagerHeight)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            pageIndicator
            Spacer(minLength: 0)
            Menu {
                Button(L10n.t("Nhóm mới…"), systemImage: "folder.badge.plus", action: onNewGroup)
                Button(L10n.t("Live Group mới…"), systemImage: "folder.badge.gearshape", action: onNewLiveGroup)
                Button(L10n.t("Space mới…"), systemImage: "square.3.layers.3d") { nameSheet = .create }
            } label: {
                Image(systemName: "plus")
                    .frame(width: XFinderTokens.BrowserSidebar.pagerHeight, height: XFinderTokens.BrowserSidebar.pagerHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.t("Thêm nhóm hoặc Space"))
            .accessibilityLabel(L10n.t("Thêm nhóm hoặc Space"))
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .frame(height: XFinderTokens.BrowserSidebar.pagerHeight)
        .sheet(item: $nameSheet) { (mode: SidebarSpaceNameSheet.Mode) in
            SidebarSpaceNameSheet(mode: mode, spaces: spaces) { nameSheet = nil }
        }
    }

    // MARK: - Pieces

    private var pageIndicator: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XFinderTokens.BrowserSidebar.pagerDotGap) {
                    ForEach(spaces.store.spaces) { space in
                        dot(for: space, active: space.id == spaces.active.id).id(space.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo(spaces.active.id, anchor: .center) }
            .onChange(of: spaces.active.id) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
    }

    private func dot(for space: Space, active: Bool) -> some View {
        Button {
            spaces.activate(space.id)
        } label: {
            Circle()
                .fill(active ? XFinderTokens.BrowserSidebar.pagerDotActive : XFinderTokens.BrowserSidebar.pagerDotInactive)
                .frame(width: XFinderTokens.BrowserSidebar.pagerDot, height: XFinderTokens.BrowserSidebar.pagerDot)
                .frame(width: XFinderTokens.BrowserSidebar.pagerHeight, height: XFinderTokens.BrowserSidebar.pagerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(SidebarSpaceNaming.displayName(space))
        .accessibilityLabel(SidebarSpaceNaming.displayName(space))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func iconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(XFinderTokens.BrowserSidebar.headerButton)
                .foregroundColor(.secondary)
                .frame(width: XFinderTokens.BrowserSidebar.pagerHeight, height: XFinderTokens.BrowserSidebar.pagerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
