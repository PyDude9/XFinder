import SwiftUI
import UniformTypeIdentifiers

/// XF-T30 W1 — a pane's tab strip (FileOctopus: every pane has one, with + and two split buttons at its right end).
/// Contract docs/specs/XF-T30-w1-contract.md §4. Always visible, even with a single tab (contract: "luôn hiện").
struct PaneTabStripView: View {
    /// Custom UT identifier for a dragged pane tab (contract §4). Not registered in Info.plist — a pane-tab drag
    /// never leaves this app's own process, so no exported/imported `UTType` declaration is needed, only a private
    /// NSItemProvider type identifier both the drag source and the drop target agree on.
    static let tabUTI = "com.xfinder.browser.tab"

    let paneID: PaneID
    let model: BrowserWindowModel
    let isActive: Bool

    static let height: CGFloat = 28
    private static let tabMaxWidth: CGFloat = 160
    private static let tabMinWidth: CGFloat = 90

    @State private var dropIndex: Int?
    @State private var tabFrames: [TabID: CGRect] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs, id: \.tabID) { tab in
                        tabView(tab)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: TabFramesKey.self, value: [tab.tabID: proxy.frame(in: .named(Self.coordinateSpaceName))])
                            })
                    }
                }
                .onPreferenceChange(TabFramesKey.self) { frames in
                    tabFrames = frames
                }
            }
            .coordinateSpace(name: Self.coordinateSpaceName)

            trailingButtons
        }
        .frame(height: Self.height)
        .background(XFinderTokens.Fill.surface)
        .onDrop(of: [UTType(Self.tabUTI) ?? .data], isTargeted: nil) { providers, location in
            handleStripDrop(providers: providers, location: location)
        }
    }

    private var tabs: [PaneState] {
        model.tabs(of: paneID)
    }

    // MARK: - One tab

    @ViewBuilder
    private func tabView(_ tab: PaneState) -> some View {
        let selected = tab.tabID == model.panes[paneID]?.tabID
        TabChip(tab: tab, isSelected: selected, isPaneActive: isActive) {
            model.selectTab(tab.tabID)
            model.focus(paneID)
        } onClose: {
            closeTab(tab.tabID)
        }
        .onDrag {
            NSItemProvider(item: tabDragPayload(tab), typeIdentifier: Self.tabUTI)
        }
        .contextMenu {
            tabContextMenu(tab)
        }
    }

    private func tabDragPayload(_ tab: PaneState) -> NSData {
        let payload = TabDragPayload(modelID: ObjectIdentifier(model).hashValue, tabID: tab.tabID.raw)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return data as NSData
    }

    @ViewBuilder
    private func tabContextMenu(_ tab: PaneState) -> some View {
        Button(L10n.t("Đóng tab")) { closeTab(tab.tabID) }
        Button(L10n.t("Đóng các tab khác")) { closeOtherTabs(keeping: tab.tabID) }
        Divider()
        Button(L10n.t("Chuyển tab sang ngăn mới bên phải")) {
            model.focus(paneID)
            model.selectTab(tab.tabID)
            _ = model.perform(.moveTabToNewPaneRight)
        }
        .disabled(!focusedCanPerform(.moveTabToNewPaneRight))
        Button(L10n.t("Chuyển tab sang ngăn mới bên dưới")) {
            model.focus(paneID)
            model.selectTab(tab.tabID)
            _ = model.perform(.moveTabToNewPaneBelow)
        }
        .disabled(!focusedCanPerform(.moveTabToNewPaneBelow))
        Button(L10n.t("Chuyển tab ra cửa sổ mới")) {
            model.focus(paneID)
            model.selectTab(tab.tabID)
            _ = model.perform(.moveTabToWindow)
        }
        .disabled(!focusedCanPerform(.moveTabToWindow))
    }

    private func closeTab(_ tab: TabID) {
        model.focus(paneID)
        model.selectTab(tab)
        _ = model.perform(.closePaneTab)
    }

    private func closeOtherTabs(keeping tab: TabID) {
        model.focus(paneID)
        for other in tabs where other.tabID != tab {
            model.selectTab(other.tabID)
            _ = model.perform(.closePaneTab)
        }
        model.selectTab(tab)
    }

    // MARK: - Trailing buttons: + / split right / split down

    private var trailingButtons: some View {
        HStack(spacing: 2) {
            Divider().frame(height: Self.height - 8)
            button(systemName: "plus", command: .newPaneTab, help: L10n.t("Tab mới"))
            button(systemName: "rectangle.righthalf.inset.filled", command: .moveTabToNewPaneRight, help: L10n.t("Chia phải"))
            button(systemName: "rectangle.bottomhalf.inset.filled", command: .moveTabToNewPaneBelow, help: L10n.t("Chia dưới"))
        }
        .padding(.horizontal, 4)
    }

    /// `help` arrives already translated (`L10n.t("literal")` at each call site above) — CLAUDE.md rule 8 requires
    /// the literal itself to sit directly in a `L10n.t(...)` call, not be passed through a variable first.
    private func button(systemName: String, command: BrowserCommand, help: String) -> some View {
        Button {
            model.focus(paneID)
            _ = model.perform(command)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .disabled(!focusedCanPerform(command))
        .help(help)
    }

    /// `canPerform` reads the model's CURRENT active pane, not `paneID` — a button on a non-active pane's strip
    /// still needs an answer before the click (which itself calls `model.focus(paneID)` first) actually runs.
    /// Bug found in review: this used to just forward to `model.canPerform(command)` unchanged, which means every
    /// inactive pane's buttons/menu items showed whatever the ACTIVE pane currently allows — e.g. a single-tab
    /// pane's split buttons would render enabled (not greyed out) whenever some OTHER pane with ≥ 2 tabs happened
    /// to be active, contradicting contract §3 ("moveTabToNewPane* cần ngăn nguồn ≥ 2 tab", "moveTabToWindow xám
    /// khi là tab duy nhất của ngăn duy nhất"). Both rules are checkable locally from this pane's own tab count and
    /// the tree's pane count, so they are applied here on top of the model's own answer, which still carries
    /// whatever other gating (license/Pro limits) `canPerform` enforces.
    private func focusedCanPerform(_ command: BrowserCommand) -> Bool {
        guard model.canPerform(command) else { return false }
        switch command {
        case .moveTabToNewPaneRight, .moveTabToNewPaneBelow:
            return model.tabs(of: paneID).count >= 2
        case .moveTabToWindow:
            return model.tabs(of: paneID).count > 1 || model.tree.count > 1
        default:
            return true
        }
    }

    // MARK: - Drop on strip background (append at end)

    private func handleStripDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: Self.tabUTI) { item, _ in
            guard let data = item as? Data,
                  let payload = try? JSONDecoder().decode(TabDragPayload.self, from: data) else { return }
            Task { @MainActor in
                guard payload.modelID == ObjectIdentifier(model).hashValue else { return }
                let tabID = TabID(raw: payload.tabID)
                let frames = Array(tabFrames.values)
                let target = PaneTabRules.dropTarget(
                    point: location,
                    paneRect: CGRect(x: 0, y: 0, width: 10_000, height: Self.height),
                    stripHeight: Self.height,
                    tabFrames: frames
                )
                switch target {
                case .strip(let index):
                    model.dropTab(tabID, onto: paneID, target: .strip(index: index))
                case .edge, .center:
                    model.dropTab(tabID, onto: paneID, target: .strip(index: tabs.count))
                }
            }
        }
        return true
    }

    fileprivate static let coordinateSpaceName = "XFinder.PaneTabStripView"
}

/// Cross-process-safe payload carried by a pane-tab drag: which `BrowserWindowModel` it came from (so a drop that
/// lands in a DIFFERENT window's pane tree is rejected — contract: "thả sang cửa sổ khác bị bỏ qua") and which tab.
private struct TabDragPayload: Codable {
    let modelID: Int
    let tabID: UUID
}

private struct TabFramesKey: PreferenceKey {
    static var defaultValue: [TabID: CGRect] { [:] }
    static func reduce(value: inout [TabID: CGRect], nextValue: () -> [TabID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// One tab chip: folder icon (via `FileIconCache`) + name, close button on hover/selected, selected look.
private struct TabChip: View {
    let tab: PaneState
    let isSelected: Bool
    let isPaneActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: FileIconCache.shared.icon(forPath: tab.path))
                .resizable()
                .frame(width: 14, height: 14)
            Text(tabTitle)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PaneTabStripView.height - 4)
        .frame(minWidth: 90, maxWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                .fill(isSelected ? XFinderTokens.Fill.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    private var tabTitle: String {
        if case .failed = tab.loadState {
            return (tab.path as NSString).lastPathComponent.isEmpty ? tab.path : (tab.path as NSString).lastPathComponent
        }
        let name = (tab.path as NSString).lastPathComponent
        return name.isEmpty ? tab.path : name
    }
}
