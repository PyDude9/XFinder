import SwiftUI

/// XF-T32 W2 (contract XF-T32-w23 §C) — one sidebar section per Live Group of the active Space (Tilde: "In Progress •"
/// small secondary title with the option's colour dot after the name; rows = every item set to that option, icon 16 pt +
/// nickname or last path component, 28 pt, selected = gray rounded 8). A group whose property or option was deleted is
/// dropped by `BrowserMetadata.liveGroups`; an empty group still shows its section with a secondary "Trống" row.
/// No refs ⇒ nothing is rendered.
struct SidebarLiveGroupsSection: View {
    let spaces: SpaceController
    let metadata: BrowserMetadata
    let onOpen: (String) -> Void
    let isSelected: (String) -> Bool

    var body: some View {
        let refs: [LiveGroupRef] = spaces.active.liveGroups
        if !refs.isEmpty {
            let groups: [PropertyRules.LiveGroup] = metadata.liveGroups(refs)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.option.id) { (group: PropertyRules.LiveGroup) in
                    LiveGroupBlock(group: group, metadata: metadata, onOpen: onOpen, isSelected: isSelected) {
                        spaces.toggleLiveGroup(LiveGroupRef(propertyID: group.property.id, optionID: group.option.id))
                    }
                }
            }
        }
    }
}

// MARK: - One group

private struct LiveGroupBlock: View {
    let group: PropertyRules.LiveGroup
    let metadata: BrowserMetadata
    let onOpen: (String) -> Void
    let isSelected: (String) -> Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            if group.paths.isEmpty {
                Text(L10n.t("Trống"))
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.row)
                    .frame(maxWidth: .infinity, minHeight: XFinderTokens.BrowserSidebar.rowHeight,
                           maxHeight: XFinderTokens.BrowserSidebar.rowHeight, alignment: .leading)
            } else {
                ForEach(group.paths, id: \.self) { (path: String) in
                    LiveGroupRow(path: path, name: displayName(path), selected: isSelected(path)) { onOpen(path) }
                }
            }
        }
    }

    private var title: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(group.option.title)
                .font(XFinderTokens.BrowserSidebar.sectionTitle)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Circle()
                .fill(XFinderTokens.PropertyTint.color(group.option.color))
                .frame(width: XFinderTokens.BrowserSidebar.groupDot, height: XFinderTokens.BrowserSidebar.groupDot)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.top, XFinderTokens.BrowserSidebar.sectionTopGap)
        .padding(.bottom, XFinderTokens.Space.hairline)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.t("Bỏ khỏi thanh bên"), action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Nickname when set, else the last path component (a root "/" keeps "/" rather than an empty label).
    private func displayName(_ path: String) -> String {
        if let nickname: String = metadata.nickname(for: path), !nickname.isEmpty { return nickname }
        let last: String = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }
}

// MARK: - One row

private struct LiveGroupRow: View {
    let path: String
    let name: String
    let selected: Bool
    let onOpen: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(nsImage: FileIconCache.shared.icon(forPath: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: XFinderTokens.BrowserSidebar.iconSize, height: XFinderTokens.BrowserSidebar.iconSize)
                    .accessibilityHidden(true)
                Text(name)
                    .font(XFinderTokens.BrowserSidebar.row)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, XFinderTokens.Space.row)
            .frame(height: XFinderTokens.BrowserSidebar.rowHeight)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { (inside: Bool) in hovering = inside }
        .help(path)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        if selected {
            RoundedRectangle(cornerRadius: XFinderTokens.BrowserSidebar.rowRadius, style: .continuous)
                .fill(XFinderTokens.BrowserSidebar.selectedFill)
        } else if hovering {
            RoundedRectangle(cornerRadius: XFinderTokens.BrowserSidebar.rowRadius, style: .continuous)
                .fill(XFinderTokens.Fill.hover)
        }
    }
}
