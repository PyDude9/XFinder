import SwiftUI

/// XF-T32 W2 (contract XF-T32-w23 §C) — the strip pinned to the foot of the sidebar (Tilde): ⊕ on the left (new sidebar
/// group, `onNewGroup`), one page dot per Space in the centre (active filled, click activates), + on the right (new Space).
struct SidebarSpacePager: View {
    let spaces: SpaceController
    let onNewGroup: () -> Void

    @State private var nameSheet: SidebarSpaceNameSheet.Mode?

    var body: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            iconButton(systemImage: "plus.circle", help: L10n.t("Nhóm mới…"), action: onNewGroup)
            Spacer(minLength: 0)
            pageIndicator
            Spacer(minLength: 0)
            iconButton(systemImage: "plus", help: L10n.t("Space mới…")) { nameSheet = .create }
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .frame(height: XFinderTokens.BrowserSidebar.pagerHeight)
        .sheet(item: $nameSheet) { (mode: SidebarSpaceNameSheet.Mode) in
            SidebarSpaceNameSheet(mode: mode, spaces: spaces) { nameSheet = nil }
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var pageIndicator: some View {
        let all: [Space] = spaces.store.spaces
        let activeID: UUID = spaces.active.id
        if all.count > XFinderTokens.BrowserSidebar.pagerMaxDots {
            compactIndicator(all: all, activeID: activeID)
        } else {
            HStack(spacing: XFinderTokens.BrowserSidebar.pagerDotGap) {
                ForEach(all) { (space: Space) in
                    dot(for: space, active: space.id == activeID)
                }
            }
        }
    }

    private func dot(for space: Space, active: Bool) -> some View {
        Button {
            spaces.activate(space.id)
        } label: {
            Circle()
                .fill(active ? XFinderTokens.BrowserSidebar.pagerDotActive : XFinderTokens.BrowserSidebar.pagerDotInactive)
                .frame(width: XFinderTokens.BrowserSidebar.pagerDot, height: XFinderTokens.BrowserSidebar.pagerDot)
                .padding(XFinderTokens.Space.hairline)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(SidebarSpaceNaming.displayName(space))
        .accessibilityLabel(SidebarSpaceNaming.displayName(space))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// Too many Spaces for dots: ‹ "3 / 12" › — the arrows step through Spaces (wrapping is SpaceController's rule).
    private func compactIndicator(all: [Space], activeID: UUID) -> some View {
        let position: Int = (all.firstIndex { $0.id == activeID } ?? 0) + 1
        return HStack(spacing: XFinderTokens.Space.hairline) {
            iconButton(systemImage: "chevron.left", help: L10n.t("Space trước")) { spaces.activatePrevious() }
            Text(verbatim: "\(position) / \(all.count)")
                .font(XFinderTokens.Font.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            iconButton(systemImage: "chevron.right", help: L10n.t("Space sau")) { spaces.activateNext() }
        }
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
