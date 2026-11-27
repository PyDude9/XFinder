import SwiftUI
import AppKit

/// XF-ISLAND-NOTES — Lightweight presenter for XFinder's existing `NoteEditorSheet`
/// when Edge Notes is disabled, so creating or editing a note from the Dynamic Island
/// never mutates `notes.edgeEnabled` or overwrites `NoteStore.shared.onChange`.
@MainActor
final class NotchNoteEditorPresenter {
    static let shared = NotchNoteEditorPresenter()
    private var panel: SurfacePanel?

    private init() {}

    func present(note: QuickNote?) {
        let size = CGSize(width: 480, height: 420)
        if panel == nil {
            panel = SurfacePanel(kind: .interactive, size: size)
        }
        let binding = Binding<Bool>(
            get: { true },
            set: { [weak self] presented in
                if !presented {
                    self?.close()
                }
            }
        )
        panel?.host(
            NoteEditorSheet(isPresented: binding, note: note)
                .frame(width: size.width, height: size.height)
                .background(XFinderTokens.Fill.window)
                .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous))
        )
        panel?.show(anchor: .spotlight)
        panel?.installClickOutside { [weak self] in
            self?.close()
        }
    }

    func close() {
        panel?.hide()
    }
}

/// XF-ISLAND-NOTES — Dynamic Island Notes page.
/// Reads live active notes from `NoteStore.shared` (`@Observable`) without replacing `NoteStore.shared.onChange`.
/// Adapts between Ref29 wide (`612 pt`) and narrow (`382 pt`) Island bodies using XFinder tokens.
struct NotchNotesPage: View {
    /// Optional hook for `NotchSurfaceController` to give the Island panel key focus while typing in search.
    var onSearchFocusChanged: ((Bool) -> Void)? = nil
    /// Optional hook for `NotchSurfaceController` to collapse/dismiss the Island before presenting an editor window.
    var onWillOpenEditor: (() -> Void)? = nil

    @State private var store = NoteStore.shared
    @State private var searchQuery = ""
    @State private var selectedNoteID: UUID?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    private var snapshots: [NotchNoteSnapshot] {
        store.notes.map {
            NotchNoteSnapshot(
                id: $0.id,
                title: $0.title,
                content: $0.content,
                updatedAt: $0.updatedAt,
                isPinned: $0.isPinned,
                isArchived: $0.isArchived
            )
        }
    }

    private var visibleSnapshots: [NotchNoteSnapshot] {
        NotchNotesRules.visibleNotes(from: snapshots, query: searchQuery)
    }

    private var activeCount: Int {
        snapshots.filter { !$0.isArchived }.count
    }

    private var emptyState: NotchNotesEmptyState {
        NotchNotesRules.emptyState(
            allNotes: snapshots,
            visibleNotes: visibleSnapshots,
            query: searchQuery
        )
    }

    var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            VStack(alignment: .leading, spacing: isNarrow ? 5 : 6) {
                headerBar(isNarrow: isNarrow)
                Divider().overlay(Color.white.opacity(0.10))
                contentBody(isNarrow: isNarrow)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            reconcileSelection()
        }
        .onDisappear {
            if isSearchFocused {
                isSearchFocused = false
                onSearchFocusChanged?(false)
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            onSearchFocusChanged?(focused)
        }
        .onChange(of: visibleSnapshots) { _, newVisible in
            selectedNoteID = NotchNotesRules.reconciledSelection(
                currentSelection: selectedNoteID,
                visibleNotes: newVisible
            )
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if openSelectedNote() {
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if !searchQuery.isEmpty {
                searchQuery = ""
                return .handled
            }
            if isSearchFocused {
                isSearchFocused = false
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Header

    private func headerBar(isNarrow: Bool) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)

            Text(L10n.t("Ghi chú"))
                .font(.system(size: isNarrow ? 11.5 : 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(activeCount)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(N.capsule))

            if !isNarrow {
                searchField
                    .frame(maxWidth: 210)
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            Button {
                openNotesSettingsPage()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Mở trang Ghi chú"))
            .accessibilityLabel(L10n.t("Mở trang Ghi chú"))

            Button {
                createNewNote()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Ghi chú mới"))
            .accessibilityLabel(L10n.t("Ghi chú mới"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))

            TextField(L10n.t("Tìm ghi chú…"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .focused($isSearchFocused)
                .onSubmit {
                    _ = openSelectedNote()
                }
                .accessibilityLabel(L10n.t("Tìm ghi chú…"))

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Xoá tìm kiếm"))
                .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(N.capsule))
        .overlay(Capsule().strokeBorder(isSearchFocused ? accent.opacity(0.75) : N.cardStroke, lineWidth: 1))
    }

    // MARK: - Body

    @ViewBuilder
    private func contentBody(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isNarrow {
                searchField
            }

            switch emptyState {
            case .noActiveNotes:
                emptyStateView(
                    symbol: "note.text",
                    title: L10n.t("Chưa có ghi chú"),
                    subtitle: L10n.t("Tạo ghi chú mới để xem nhanh tại đây."),
                    actionTitle: L10n.t("Ghi chú mới"),
                    action: createNewNote
                )

            case .noSearchMatches:
                emptyStateView(
                    symbol: "magnifyingglass",
                    title: L10n.t("Không tìm thấy ghi chú phù hợp"),
                    subtitle: L10n.t("Thử từ khóa khác hoặc xóa tìm kiếm."),
                    actionTitle: L10n.t("Xoá tìm kiếm"),
                    action: { searchQuery = "" }
                )

            case .hasResults:
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(visibleSnapshots) { snapshot in
                                if let liveNote = store.notes.first(where: { $0.id == snapshot.id && !$0.isArchived }) {
                                    noteRow(snapshot: snapshot, liveNote: liveNote, isNarrow: isNarrow)
                                        .id(snapshot.id)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .onChange(of: selectedNoteID) { _, id in
                        if let id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyStateView(
        symbol: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: symbol)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(subtitle)
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .tint(accent)
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteRow(snapshot: NotchNoteSnapshot, liveNote: QuickNote, isNarrow: Bool) -> some View {
        let isSelected = selectedNoteID == snapshot.id
        let title = NotchNotesRules.displayTitle(for: snapshot) ?? L10n.t("Ghi chú không tiêu đề")
        let excerpt = NotchNotesRules.previewExcerpt(for: snapshot)

        return HStack(spacing: 8) {
            Circle()
                .fill(liveNote.color.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if snapshot.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityLabel(L10n.t("Đã ghim"))
                    }
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isNarrow {
                Text(liveNote.timeString)
                    .font(.system(size: 9.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Button {
                store.togglePin(liveNote)
            } label: {
                Image(systemName: snapshot.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(snapshot.isPinned ? .orange : .white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help(snapshot.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))
            .accessibilityLabel(snapshot.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))

            Button {
                openEditor(for: liveNote)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Mở trong trình chỉnh sửa"))
            .accessibilityLabel(L10n.t("Mở trong trình chỉnh sửa"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.7) : N.cardStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous))
        .onTapGesture {
            selectedNoteID = snapshot.id
            openEditor(for: liveNote)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(L10n.t("Dùng ↑↓ để chọn, Enter để mở"))
    }

    // MARK: - Actions & Navigation

    private func reconcileSelection() {
        selectedNoteID = NotchNotesRules.reconciledSelection(
            currentSelection: selectedNoteID,
            visibleNotes: visibleSnapshots
        )
    }

    private func moveSelection(by delta: Int) {
        selectedNoteID = NotchNotesRules.moveSelection(
            currentSelection: selectedNoteID,
            delta: delta,
            visibleNotes: visibleSnapshots
        )
    }

    @discardableResult
    private func openSelectedNote() -> Bool {
        let targetID = NotchNotesRules.reconciledSelection(
            currentSelection: selectedNoteID,
            visibleNotes: visibleSnapshots
        )
        guard let targetID,
              let liveNote = store.notes.first(where: { $0.id == targetID && !$0.isArchived }) else {
            return false
        }
        selectedNoteID = targetID
        openEditor(for: liveNote)
        return true
    }

    private func openEditor(for note: QuickNote) {
        guard let fresh = store.notes.first(where: { $0.id == note.id && !$0.isArchived }) else {
            reconcileSelection()
            return
        }
        isSearchFocused = false
        onSearchFocusChanged?(false)
        onWillOpenEditor?()
        if EdgeNotesController.shared.isEnabled {
            EdgeNotesController.shared.open(fresh.id)
        } else {
            NotchNoteEditorPresenter.shared.present(note: fresh)
        }
    }

    private func createNewNote() {
        isSearchFocused = false
        onSearchFocusChanged?(false)
        onWillOpenEditor?()
        NotchNoteEditorPresenter.shared.present(note: nil)
    }

    private func openNotesSettingsPage() {
        isSearchFocused = false
        onSearchFocusChanged?(false)
        onWillOpenEditor?()
        MainWindowController.shared.showWindow(destination: .notes)
    }
}
