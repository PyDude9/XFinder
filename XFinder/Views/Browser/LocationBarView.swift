import SwiftUI
import AppKit

/// XF-T28 cluster E — the breadcrumb bar above a pane: `BrowserPath.segments(of:rootName:)` collapsed to fit the
/// available width, a chevron per segment that lists its subfolders (filled asynchronously from `DirectoryReader`),
/// a right-click menu, and an edit mode (`model.editingLocation == pane.id`) with Tab completion.
struct LocationBarView: View {
    private static let rootName = "Macintosh HD"
    /// Width budget for one visible segment label before `BrowserPath.collapse` is asked to drop it into the
    /// ellipsis — measured against this bar's own font (XFinderTokens.Font.rowValue, ~12 pt).
    private static let minVisibleSegments = 3

    let pane: PaneState
    let model: BrowserWindowModel

    @State private var typedPath: String = ""
    @State private var completionBase: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if model.editingLocation == pane.id {
                editField
            } else {
                breadcrumb
            }
        }
        .frame(height: 24)
        .onChange(of: model.editingLocation) { _, newValue in
            if newValue == pane.id {
                typedPath = pane.path
                completionBase = nil
                fieldFocused = true
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        GeometryReader { proxy in
            let segments = BrowserPath.segments(of: pane.path, rootName: Self.rootName)
            let maxVisible = max(Self.minVisibleSegments, Int(proxy.size.width / 90))
            let display = BrowserPath.collapse(count: segments.count, maxVisible: maxVisible)

            HStack(spacing: 2) {
                ForEach(Array(display.enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case .segment(let index):
                        segmentView(segments[index])
                    case .ellipsis(let hidden):
                        ellipsisView(hidden: hidden, segments: segments)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Empty space ⇒ edit mode (spec: "bấm chỗ trống = gõ đường dẫn").
                model.editingLocation = pane.id
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: BrowserPath.Segment) -> some View {
        HStack(spacing: 2) {
            Button {
                pane.navigate(to: segment.path)
            } label: {
                Text(segment.name)
                    .font(XFinderTokens.Font.rowValue)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .browserPathContextMenu(for: segment.path, pane: pane, model: model)

            ChevronMenuButton(path: segment.path, pane: pane, model: model)
        }
    }

    @ViewBuilder
    private func ellipsisView(hidden: [Int], segments: [BrowserPath.Segment]) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { index in
                Button(segments[index].name) {
                    pane.navigate(to: segments[index].path)
                }
            }
        } label: {
            Text("…")
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Edit mode

    private var editField: some View {
        TextField(L10n.t("Gõ đường dẫn…"), text: $typedPath)
            .textFieldStyle(.roundedBorder)
            .font(XFinderTokens.Font.rowValue)
            .focused($fieldFocused)
            .onKeyPress(.tab) {
                applyTabCompletion()
                return .handled
            }
            .onSubmit {
                commitTypedPath()
            }
            .onExitCommand {
                model.editingLocation = nil
            }
    }

    private func applyTabCompletion() {
        let base = completionBase ?? typedPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resolved = BrowserPath.resolve(typed: base, current: pane.path, home: home)
        let parent = (resolved as NSString).deletingLastPathComponent
        Task { @MainActor in
            let children = await DirectoryReader.subfolders(of: parent.isEmpty ? "/" : parent, showHidden: pane.showHidden, timeout: 2)
            guard case .success(let names) = children else { return }
            let matches = BrowserPath.completions(typed: base, children: names)
            guard !matches.isEmpty else { return }
            completionBase = base
            let lastSlash = base.lastIndex(of: "/")
            let prefixPath = lastSlash.map { String(base[...$0]) } ?? ""
            if matches.count == 1 {
                typedPath = prefixPath + matches[0]
            } else {
                typedPath = prefixPath + BrowserPath.commonPrefix(matches)
            }
        }
    }

    private func commitTypedPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resolved = BrowserPath.resolve(typed: typedPath, current: pane.path, home: home)
        pane.navigate(to: resolved)
        model.editingLocation = nil
    }
}

// MARK: - Chevron menu (NSMenu, filled asynchronously from DirectoryReader)

/// A tiny chevron button that pops an `NSMenu` of `path`'s subfolders. An `NSMenu` (not a SwiftUI `Menu`) is used
/// here because the contract asks for a placeholder item ("Đang tải…") that is replaced once the async listing
/// comes back — SwiftUI's `Menu` has no API to mutate an already-open menu's items.
private struct ChevronMenuButton: NSViewRepresentable {
    let path: String
    let pane: PaneState
    let model: BrowserWindowModel

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        context.coordinator.update(path: path, pane: pane, model: model)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.update(path: path, pane: pane, model: model)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        private var path = ""
        private var pane: PaneState?
        private var model: BrowserWindowModel?

        func update(path: String, pane: PaneState, model: BrowserWindowModel) {
            self.path = path
            self.pane = pane
            self.model = model
        }

        @objc func showMenu(_ sender: NSButton) {
            guard let pane else { return }
            let menu = NSMenu()
            let loading = NSMenuItem(title: L10n.t("Đang tải…"), action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)

            // `NSMenu.popUp` runs its own modal tracking loop and does not return until the menu is dismissed, so
            // the async listing must be kicked off BEFORE popUp is called — code placed after popUp here would only
            // ever run once the user has already closed the menu, leaving it permanently stuck on "Đang tải…".
            let path = self.path
            let showHidden = pane.showHidden
            Task { @MainActor [weak self] in
                let result = await DirectoryReader.subfolders(of: path, showHidden: showHidden, timeout: 2)
                guard let self else { return }
                menu.removeAllItems()
                switch result {
                case .success(let names) where !names.isEmpty:
                    for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                        let item = NSMenuItem(title: name, action: #selector(Coordinator.select(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = (path as NSString).appendingPathComponent(name)
                        menu.addItem(item)
                    }
                case .success:
                    let empty = NSMenuItem(title: L10n.t("Không có thư mục"), action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                case .failure:
                    let failed = NSMenuItem(title: L10n.t("Không xem được"), action: nil, keyEquivalent: "")
                    failed.isEnabled = false
                    menu.addItem(failed)
                }
            }

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        }

        @objc private func select(_ sender: NSMenuItem) {
            guard let target = sender.representedObject as? String else { return }
            pane?.navigate(to: target)
        }
    }
}

// MARK: - Right-click menu shared by breadcrumb segments

private struct BrowserPathContextMenu: ViewModifier {
    let path: String
    let pane: PaneState
    let model: BrowserWindowModel

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(L10n.t("Mở")) { pane.navigate(to: path) }
            Button(L10n.t("Mở ở ngăn kia")) {
                if let other = model.tree.other(than: pane.id), let otherPane = model.panes[other] {
                    otherPane.navigate(to: path)
                }
            }
            Button(L10n.t("Sao chép đường dẫn")) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(path, forType: .string)
            }
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            }
        }
    }
}

private extension View {
    func browserPathContextMenu(for path: String, pane: PaneState, model: BrowserWindowModel) -> some View {
        modifier(BrowserPathContextMenu(path: path, pane: pane, model: model))
    }
}
