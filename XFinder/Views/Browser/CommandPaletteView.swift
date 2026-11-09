import SwiftUI
import AppKit

/// One in-window palette: locations, aliases and commands, with a captured-selection Move to mode.
struct CommandPaletteView: View {
    let model: BrowserWindowModel
    let mode: BrowserWindowModel.PaletteMode
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var resolvedKinds: [String: Bool] = [:]
    @State private var candidates: [BrowserPaletteRules.Item] = []
    @State private var results: [BrowserPaletteRules.Item] = []
    @State private var moveSources: [String] = []
    @State private var activation = UUID()
    @State private var appliedQuery: String?
    @AppStorage(BrowserPaletteRules.usageKey) private var usage = Data()
    @FocusState private var focused: Bool

    private struct Preparation: Equatable {
        let items: [BrowserPaletteRules.Item]
        let moving: Bool
        let typedPath: String?
    }
    private struct Ranking: Equatable {
        let items: [BrowserPaletteRules.Item]
        let query: String
        let usage: Data
        let moving: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer().frame(height: min(80, geometry.size.height / 8))
                card.frame(width: max(0, min(800, geometry.size.width - 32)))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.001).onTapGesture { model.palette = nil })
        .onAppear { query = mode == .commands ? ">" : "" }
        .onDisappear { activation = UUID() }
        .onChange(of: mode) { _, value in
            moveSources = []
            query = value == .commands ? ">" : ""
            focused = true
        }
        .onChange(of: query) { _, _ in selectedIndex = 0; appliedQuery = nil; results = [] }
        .onChange(of: model.active.tabID) { _, _ in model.palette = nil }
        .onChange(of: model.active.path) { _, _ in model.palette = nil }
        .onChange(of: model.active.selection) { _, _ in model.palette = nil }
        .task(id: Preparation(items: rawCandidates, moving: !moveSources.isEmpty, typedPath: typedPath)) {
            let snapshot = rawCandidates
            let moving = !moveSources.isEmpty
            let knownKinds = resolvedKinds
            let typedPath = typedPath
            let prepared = await Task.detached(priority: .userInitiated) {
                BrowserPaletteRules.preparing(snapshot, destinationsOnly: moving,
                                              typedPath: typedPath, knownKinds: knownKinds) { path in
                    var directory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
                }
            }.value
            guard !Task.isCancelled else { return }
            for item in prepared where item.kind == .location {
                if let directory = item.isDirectory { resolvedKinds[item.target] = directory }
            }
            candidates = prepared
        }
        .task(id: Ranking(items: candidates, query: query, usage: usage, moving: !moveSources.isEmpty)) {
            let request = Ranking(items: candidates, query: query, usage: usage, moving: !moveSources.isEmpty)
            let ranked = await Task.detached(priority: .userInitiated) {
                BrowserPaletteRules.rank(query: request.query, items: request.items,
                                         usage: BrowserPaletteRules.usage(request.usage), destinationsOnly: request.moving)
            }.value
            guard !Task.isCancelled else { return }
            results = ranked
            appliedQuery = request.query
            selectedIndex = 0
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            if !moveSources.isEmpty {
                Text(L10n.t("Chọn thư mục đích để di chuyển"))
                    .font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(XFinderTokens.Space.row)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.t("Thư mục, tab và workspace — gõ > để xem lệnh"), text: $query)
                    .textFieldStyle(.plain).font(XFinderTokens.Font.sectionTitle)
                    .focused($focused)
                    .task {
                        // Wait until AppKit has attached the field before requesting its editor.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        focused = true
                    }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(keys: [.return], phases: .down) { press in commit(modifiers: press.modifiers); return .handled }
                    .onKeyPress(.escape) {
                        if moveSources.isEmpty { model.palette = nil }
                        else { moveSources = []; query = "" }
                        return .handled
                    }
            }.padding(XFinderTokens.Space.row)
            SettingsDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if results.isEmpty {
                            if appliedQuery != query { ProgressView().padding(XFinderTokens.Space.row) }
                            else { Text(L10n.t("Không có kết quả phù hợp."))
                                .font(XFinderTokens.Font.row).foregroundStyle(.secondary)
                                .padding(XFinderTokens.Space.section) }
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            Button { selectedIndex = index; commit(modifiers: []) } label: {
                                HStack(spacing: XFinderTokens.Space.row) {
                                    Image(systemName: Self.symbol(for: item))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(XFinderTokens.Font.row).lineLimit(1)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle).font(XFinderTokens.Font.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if item.kind == .command, let command = BrowserCommand(rawValue: item.target) {
                                        let binding = BrowserSettings.keyBindings.binding(for: command)
                                        if let chord = binding.primary ?? binding.extra {
                                            Text(BrowserCommands.display(chord)).font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(XFinderTokens.Space.row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(index == selectedIndex ? XFinderTokens.Fill.hover : Color.clear)
                            }
                            .buttonStyle(.plain).id(item.id)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .onChange(of: selectedIndex) { _, index in
                    if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                }
            }
            SettingsDivider()
            HStack(spacing: XFinderTokens.Space.row) {
                Text(moveSources.isEmpty ? L10n.t("↵ Mở · ⌘↵ Tab mới · ⌥↵ Chia ngăn") : L10n.t("↵ Di chuyển vào thư mục đã chọn"))
                Spacer(minLength: 0)
                let binding = BrowserSettings.keyBindings.binding(for: .quickOpen)
                let chord = binding.primary ?? binding.extra
                Text((chord.map(BrowserCommands.display) ?? "") + " " + L10n.t("Các lệnh") + " · esc " + (moveSources.isEmpty ? L10n.t("Đóng") : L10n.t("Quay lại")))
            }.font(XFinderTokens.Font.caption).foregroundStyle(.secondary).padding(XFinderTokens.Space.row)
        }
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.surface).fill(XFinderTokens.Fill.surface))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.surface).stroke(XFinderTokens.Fill.hairline))
        .shadow(radius: 20)
    }

    private var typedPath: String? {
        query.hasPrefix("/") || query.hasPrefix("~/") ? (query as NSString).expandingTildeInPath : nil
    }

    private var rawCandidates: [BrowserPaletteRules.Item] {
        var items: [BrowserPaletteRules.Item] = []
        var seen = Set<String>()
        let metadata = BrowserMetadata.shared
        func add(_ path: String, title: String? = nil, directory: Bool? = nil) {
            guard items.count < 3000 else { return }
            let key = path.precomposedStringWithCanonicalMapping
            guard seen.insert(key).inserted else { return }
            let name = title ?? ((path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent)
            let nickname = metadata.nickname(for: path)
            items.append(.init(id: "path:" + key, title: nickname ?? name, subtitle: path, target: path,
                               kind: .location, aliases: [name, path], isDirectory: VirtualLocation.parse(path) == nil ? directory : false))
        }
        for pane in model.tree.panes {
            for tab in model.tabs(of: pane) { add(tab.path, directory: true) }
        }
        let sidebar = SpaceController.shared.active.sidebar
        for favorite in sidebar.favorites + sidebar.groups.flatMap(\.items) { add(favorite.path, title: favorite.displayName, directory: true) }
        for recent in BrowserSettings.recentFolders.paths { add(recent, directory: true) }
        for item in metadata.paletteNicknames { add(item.path, title: item.nickname) }
        for entry in model.active.entries.prefix(1500) { add(entry.path, title: entry.name, directory: entry.isFolderLike) }
        if let typedPath { add(typedPath) }
        // XF-T39 (Q-T39-1): saved workspaces by name — "2 cửa sổ · 08/11/2026"; "workspace" lists them all.
        for workspace in model.workspaces {
            let subtitle = "\(workspace.windows.count)\(L10n.t(" cửa sổ · "))\(workspace.savedAt.formatted(date: .numeric, time: .omitted))"
            items.append(.init(id: "workspace:" + workspace.id.uuidString, title: workspace.name, subtitle: subtitle,
                               target: workspace.id.uuidString, kind: .workspace, aliases: ["workspace", workspace.name]))
        }
        if !model.active.selectedEntries.isEmpty, VirtualLocation.parse(model.active.path) == nil {
            items.append(.init(id: "action:move", title: L10n.t("Di chuyển đến…"), subtitle: L10n.t("Chọn thư mục đích"), target: "", kind: .move, aliases: ["move"]))
        }
        for command in BrowserCommand.allCases where command != .quickOpen && command != .commandPalette && model.canPerform(command) {
            let titleKey = BrowserCommands.titleKey(command)
            items.append(.init(id: "command:" + command.rawValue, title: L10n.t(titleKey), subtitle: Self.menuName(of: command), target: command.rawValue, kind: .command, aliases: [command.rawValue, L10n.english(titleKey)]))
        }
        return items
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }
    private func record(_ id: String) {
        let latest = UserDefaults.standard.data(forKey: BrowserPaletteRules.usageKey) ?? Data()
        usage = BrowserPaletteRules.recording(id, in: latest)
    }
    private func commit(modifiers: EventModifiers) {
        guard appliedQuery == query, results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]
        if item.kind == .move {
            moveSources = model.active.selectedEntries.map(\.path)
            query = ""
            appliedQuery = nil
            return
        }
        if item.kind == .command {
            guard let command = BrowserCommand(rawValue: item.target), model.canPerform(command) else { return }
            if model.perform(command) { record(item.id); model.palette = nil }
            return
        }
        if item.kind == .workspace {
            guard let id = UUID(uuidString: item.target) else { return }
            model.openWorkspace(id)   // adds its windows (XF-T39); a missing one says so in the banner
            record(item.id)
            model.palette = nil
            return
        }
        let source = model.active
        let selection = source.selection
        let sourcePath = source.path
        let token = activation
        let typedQuery = query
        let moving = moveSources
        Task { @MainActor in
            let kind = await Task.detached(priority: .userInitiated) {
                if VirtualLocation.parse(item.target) != nil { return 2 }
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.target, isDirectory: &directory) else { return -1 }
                return directory.boolValue ? 1 : 0
            }.value
            guard activation == token, model.palette != nil, query == typedQuery,
                  model.active.tabID == source.tabID, source.path == sourcePath, source.selection == selection else { return }
            guard kind >= 0 else { model.banner = "Không mở được mục này. Tệp có thể đã bị xoá hoặc thiếu quyền truy cập."; return }
            if !moving.isEmpty {
                guard kind == 1 else { model.banner = "Hãy chọn một thư mục thật làm đích di chuyển."; return }
                model.drop(moving, into: item.target, copy: false)
            } else {
                let path = kind == 0 ? (item.target as NSString).deletingLastPathComponent : item.target
                if modifiers.contains(.command) {
                    guard let tab = model.newTab(in: model.activePane, path: path),
                          let state = model.tabs(of: model.activePane).first(where: { $0.tabID == tab }) else { return }
                    if kind == 0 { state.selectAfterLoad = (item.target as NSString).lastPathComponent }
                } else if modifiers.contains(.option) {
                    guard model.canPerform(.splitRight), model.perform(.splitRight) else {
                        model.banner = "Không thể tạo thêm ngăn trong bố cục hoặc gói hiện tại."
                        return
                    }
                    model.active.navigate(to: path)
                    if kind == 0 { model.active.selectAfterLoad = (item.target as NSString).lastPathComponent }
                } else if kind == 0 {
                    guard NSWorkspace.shared.open(URL(fileURLWithPath: item.target)) else { model.banner = "Không mở được mục này. Tệp có thể đã bị xoá hoặc thiếu quyền truy cập."; return }
                } else { source.navigate(to: item.target) }
            }
            record(item.id)
            model.palette = nil
        }
    }
}

extension CommandPaletteView {
    static func symbol(for item: BrowserPaletteRules.Item) -> String {
        switch item.kind {
        case .command: return "command"
        case .move: return "folder.badge.arrowshape.right"
        case .workspace: return "macwindow.on.rectangle"
        case .location: return "doc"
        }
    }

    /// XF-T38: the menu a command lives in, under its title — "Tệp", "Xem", … — as FileOctopus's palette shows it.
    static func menuName(of command: BrowserCommand) -> String {
        guard let menu = BrowserMenuLayout.menu(containing: command) else { return L10n.t("Trình duyệt") }
        return L10n.t(BrowserMenuLayout.titleKey(menu))
    }
}
