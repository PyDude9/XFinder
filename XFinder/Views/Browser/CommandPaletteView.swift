import SwiftUI

/// XF-T28 cluster E — the floating command palette (⌃⌘P Quick Open / ⌃⇧⌘P or `>` prefix Commands), drawn as a card
/// OVER the window content (contract: "not a separate panel") rather than its own `NSPanel`.
struct CommandPaletteView: View {
    // Computed, not `static let`: a `static let` would call `L10n.t` exactly once for the lifetime of the process
    // (the first time the palette opens) and cache the result at the TYPE level, so switching `AppLanguage` later —
    // which resets the view tree via `RootView`'s `.id(language)` but does not touch process-wide statics — would
    // leave these four labels frozen in whatever language was active the first time Quick Open was used.
    private static var favoritePaths: [(String, String)] {
        [
            (L10n.t("Home"), NSHomeDirectory()),
            (L10n.t("Màn hình nền"), NSHomeDirectory() + "/Desktop"),
            (L10n.t("Tài liệu"), NSHomeDirectory() + "/Documents"),
            (L10n.t("Tải về"), NSHomeDirectory() + "/Downloads"),
        ]
    }

    let model: BrowserWindowModel
    let mode: BrowserWindowModel.PaletteMode

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)
            card
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.001) // catches a click outside the card without drawing a visible scrim.
                .onTapGesture { model.palette = nil }
        )
        .onAppear {
            query = BrowserCommands.commandMode(query).isCommand ? query : (mode == .commands ? ">" : "")
            fieldFocused = true
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(L10n.t("Gõ để tìm hoặc \">\" để gõ lệnh"), text: $query)
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.sectionTitle)
                .padding(XFinderTokens.Space.row)
                .focused($fieldFocused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.return) { commitSelection(); return .handled }
                .onKeyPress(.escape) { model.palette = nil; return .handled }

            SettingsDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let (isCommand, _) = BrowserCommands.commandMode(query)
                    if isCommand {
                        commandResults
                    } else {
                        quickOpenResults
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.surface, style: .continuous).fill(XFinderTokens.Fill.surface))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.surface, style: .continuous).stroke(XFinderTokens.Fill.hairline))
        .shadow(radius: 20)
    }

    // MARK: - Commands mode

    private var commandCandidates: [BrowserCommands.Candidate] {
        BrowserCommand.allCases
            .filter { model.canPerform($0) }
            .map { command in
                BrowserCommands.Candidate(
                    id: command.rawValue,
                    title: L10n.t(BrowserCommands.titleKey(command)),
                    subtitle: BrowserCommands.chord(for: command).map(BrowserCommands.display)
                )
            }
    }

    private var rankedCommands: [BrowserCommands.Candidate] {
        let (_, rest) = BrowserCommands.commandMode(query)
        return BrowserCommands.rank(rest, commandCandidates, limit: 50)
    }

    private var commandResults: some View {
        ForEach(Array(rankedCommands.enumerated()), id: \.element.id) { index, candidate in
            resultRow(title: candidate.title, subtitle: candidate.subtitle, isSelected: index == selectedIndex) {
                performCommand(candidate.id)
            }
        }
    }

    private func performCommand(_ id: String) {
        guard let command = BrowserCommand(rawValue: id) else { return }
        model.perform(command)
        model.palette = nil
    }

    // MARK: - Quick Open mode

    private struct QuickOpenItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let path: String
    }

    private var quickOpenCandidates: [QuickOpenItem] {
        var seen = Set<String>()
        var items: [QuickOpenItem] = []

        func add(_ title: String, _ path: String, subtitle: String? = nil) {
            let key = (path as NSString).standardizingPath
            guard !seen.contains(key) else { return }
            seen.insert(key)
            items.append(QuickOpenItem(id: key, title: title, subtitle: subtitle ?? path, path: path))
        }

        for pane in model.panes.values {
            add((pane.path as NSString).lastPathComponent, pane.path, subtitle: L10n.t("Ngăn đang mở"))
        }
        for (name, path) in Self.favoritePaths {
            add(name, path, subtitle: L10n.t("Mục ưa thích"))
        }
        for pane in model.panes.values {
            for recent in (pane.history.back + pane.history.forward).reversed() {
                add((recent as NSString).lastPathComponent, recent, subtitle: L10n.t("Gần đây"))
            }
        }
        return items
    }

    private var rankedQuickOpen: [QuickOpenItem] {
        let candidates = quickOpenCandidates.map { BrowserCommands.Candidate(id: $0.id, title: $0.title, subtitle: $0.subtitle) }
        let ranked = BrowserCommands.rank(query, candidates, limit: 50)
        let byID = Dictionary(uniqueKeysWithValues: quickOpenCandidates.map { ($0.id, $0) })
        return ranked.compactMap { byID[$0.id] }
    }

    private var quickOpenResults: some View {
        ForEach(Array(rankedQuickOpen.enumerated()), id: \.element.id) { index, item in
            resultRow(title: item.title, subtitle: item.subtitle, isSelected: index == selectedIndex) {
                model.active.navigate(to: item.path)
                model.palette = nil
            }
        }
    }

    // MARK: - Shared row + keyboard

    private func resultRow(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(XFinderTokens.Font.row)
            Spacer()
            if let subtitle {
                Text(subtitle).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, XFinderTokens.Space.tight)
        .background(isSelected ? XFinderTokens.Fill.hover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func move(_ delta: Int) {
        let (isCommand, _) = BrowserCommands.commandMode(query)
        let count = isCommand ? rankedCommands.count : rankedQuickOpen.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func commitSelection() {
        let (isCommand, _) = BrowserCommands.commandMode(query)
        if isCommand {
            guard rankedCommands.indices.contains(selectedIndex) else { return }
            performCommand(rankedCommands[selectedIndex].id)
        } else {
            guard rankedQuickOpen.indices.contains(selectedIndex) else { return }
            model.active.navigate(to: rankedQuickOpen[selectedIndex].path)
            model.palette = nil
        }
    }
}
