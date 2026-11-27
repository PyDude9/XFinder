import Foundation
import Observation

// MARK: - Models

/// Filter tab for the Dynamic Island personal to-do list.
/// Completely independent from EventKit Reminders (`CalendarGlanceMonitor` / `GlanceEvent`).
enum NotchTodoFilter: String, Equatable, Codable, CaseIterable, Sendable {
    case active
    case done
}

/// A single personal to-do item persisted locally by XFinder.
struct NotchTodoItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = isCompleted ? (completedAt ?? updatedAt ?? createdAt) : nil
    }
}

/// Versioned on-disk envelope for atomic JSON persistence.
struct NotchTodoEnvelope: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var items: [NotchTodoItem]

    init(schemaVersion: Int = Self.currentSchemaVersion, items: [NotchTodoItem]) {
        self.schemaVersion = schemaVersion
        self.items = items
    }
}

// MARK: - Validation & Normalization Rules

enum NotchTodoRules {
    /// Hard cap for a single to-do title (grapheme clusters) so pastes never blow up notch rows or disk files.
    static let maxTitleLength = 160

    struct NormalizedTitle: Equatable, Sendable {
        let value: String
        let wasTruncated: Bool
    }

    /// Trims surrounding whitespace/newlines, collapses internal whitespace runs (including newlines/tabs)
    /// into single spaces, and clamps to `maxTitleLength`. Returns `nil` for empty or whitespace-only input.
    static func normalizeTitle(_ raw: String) -> NormalizedTitle? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count > maxTitleLength {
            let trimmed = String(collapsed.prefix(maxTitleLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NormalizedTitle(value: trimmed, wasTruncated: true)
        }
        return NormalizedTitle(value: collapsed, wasTruncated: false)
    }

    /// Filters items for the active tab. Order is preserved (newest-first on insert, stable across edits).
    static func visibleItems(_ items: [NotchTodoItem], filter: NotchTodoFilter) -> [NotchTodoItem] {
        switch filter {
        case .active: return items.filter { !$0.isCompleted }
        case .done: return items.filter { $0.isCompleted }
        }
    }

    /// Picks the next valid selection after a removal or filter-exiting mutation so `selectedID`
    /// never points at a hidden or deleted row.
    static func nextSelectionAfterRemoving(
        id: UUID,
        from visibleBefore: [NotchTodoItem]
    ) -> UUID? {
        guard let index = visibleBefore.firstIndex(where: { $0.id == id }) else {
            return visibleBefore.first?.id
        }
        var remaining = visibleBefore
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        let nextIndex = min(index, remaining.count - 1)
        return remaining[nextIndex].id
    }

    /// Moves selection up (`-1`) or down (`+1`) within `visible`, clamped at both ends.
    static func movedSelection(
        current: UUID?,
        delta: Int,
        in visible: [NotchTodoItem]
    ) -> UUID? {
        guard !visible.isEmpty else { return nil }
        guard let current, let idx = visible.firstIndex(where: { $0.id == current }) else {
            return delta >= 0 ? visible.first?.id : visible.last?.id
        }
        let target = max(0, min(visible.count - 1, idx + delta))
        return visible[target].id
    }
}

// MARK: - Storage Errors & Codec (including Legacy Items)

enum NotchTodoStorageError: Error, Equatable, Sendable {
    case unreadableFile(detail: String)
    case corruptedData(detail: String)
    case unsupportedSchemaVersion(Int)
    case writeBlockedByUnreadableDisk
    case writeFailed(detail: String)

    var detail: String {
        switch self {
        case .unreadableFile(let d): return d
        case .corruptedData(let d): return d
        case .unsupportedSchemaVersion(let v): return "schemaVersion=\(v)"
        case .writeBlockedByUnreadableDisk: return "disk-preserved"
        case .writeFailed(let d): return d
        }
    }
}

/// Encodes/decodes the current `NotchTodoEnvelope` and gracefully migrates legacy on-disk formats:
/// - v1 envelope with ISO-8601 or numeric timestamps
/// - legacy bare JSON array (`[{ "id": ..., "title": ..., "done" | "isCompleted": ... }]`)
/// - legacy items missing `createdAt`, `updatedAt`, `completedAt`, or `id`
enum NotchTodoCodec {
    private struct LegacyItem: Decodable {
        let id: UUID?
        let title: String?
        let text: String?
        let isCompleted: Bool?
        let done: Bool?
        let completed: Bool?
        let createdAt: FlexibleDate?
        let updatedAt: FlexibleDate?
        let completedAt: FlexibleDate?
    }

    private struct LegacyEnvelope: Decodable {
        let schemaVersion: Int?
        let items: [LegacyItem]?
        let todos: [LegacyItem]?
    }

    private struct FlexibleDate: Decodable {
        let date: Date

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                // Distinguish Unix epoch seconds (> 1980-01-01) from Swift ReferenceDate if needed;
                // standard JSONEncoder `.secondsSince1970` is used here.
                self.date = Date(timeIntervalSince1970: seconds)
                return
            }
            if let iso = try? container.decode(String.self) {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = fractional.date(from: iso) {
                    self.date = parsed
                    return
                }
                let basic = ISO8601DateFormatter()
                if let parsed = basic.date(from: iso) {
                    self.date = parsed
                    return
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format"
            )
        }
    }

    static func encode(_ items: [NotchTodoItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let envelope = NotchTodoEnvelope(items: items)
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data, fallbackDate: Date = Date()) throws -> [NotchTodoItem] {
        guard !data.isEmpty else {
            throw NotchTodoStorageError.corruptedData(detail: "empty file")
        }

        // 1. Try decoding as versioned envelope (or legacy envelope with `todos` key).
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(LegacyEnvelope.self, from: data),
           (env.items != nil || env.todos != nil || env.schemaVersion != nil)
        {
            if let version = env.schemaVersion, version > NotchTodoEnvelope.currentSchemaVersion {
                throw NotchTodoStorageError.unsupportedSchemaVersion(version)
            }
            if let rawItems = env.items ?? env.todos {
                return normalizeDecoded(rawItems, fallbackDate: fallbackDate)
            }
            throw NotchTodoStorageError.corruptedData(detail: "missing items array")
        }

        // 2. Fallback: legacy bare JSON array `[ { ... } ]`.
        if let rawArray = try? decoder.decode([LegacyItem].self, from: data) {
            return normalizeDecoded(rawArray, fallbackDate: fallbackDate)
        }

        throw NotchTodoStorageError.corruptedData(detail: "invalid JSON structure")
    }

    private static func normalizeDecoded(_ rawItems: [LegacyItem], fallbackDate: Date) -> [NotchTodoItem] {
        var seenIDs = Set<UUID>()
        var result: [NotchTodoItem] = []
        result.reserveCapacity(rawItems.count)

        for raw in rawItems {
            let rawTitle = raw.title ?? raw.text ?? ""
            guard let normalized = NotchTodoRules.normalizeTitle(rawTitle) else {
                continue
            }
            let id: UUID
            if let candidate = raw.id, !seenIDs.contains(candidate) {
                id = candidate
            } else {
                id = UUID()
            }
            seenIDs.insert(id)

            let completed = raw.isCompleted ?? raw.done ?? raw.completed ?? false
            let created = raw.createdAt?.date ?? fallbackDate
            let updated = raw.updatedAt?.date ?? created
            let completedAt = completed ? (raw.completedAt?.date ?? updated) : nil

            result.append(NotchTodoItem(
                id: id,
                title: normalized.value,
                isCompleted: completed,
                createdAt: created,
                updatedAt: updated,
                completedAt: completedAt
            ))
        }
        return result
    }
}

// MARK: - Atomic Local File Store

/// Local JSON persistence in `~/Library/Application Support/XFinder/notch-todos.json`.
/// Uses `.atomic` writes (temp file in same directory + atomic rename) and never overwrites
/// an unreadable/corrupted file on disk.
struct NotchTodoFileStore: Sendable {
    typealias ReadHandler = @Sendable (URL) throws -> Data?
    typealias WriteHandler = @Sendable (Data, URL) throws -> Void

    let fileURL: URL
    private let readHandler: ReadHandler
    private let writeHandler: WriteHandler

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder", isDirectory: true)
            .appendingPathComponent("notch-todos.json", isDirectory: false)
    }

    init(
        fileURL: URL = Self.defaultFileURL,
        readHandler: ReadHandler? = nil,
        writeHandler: WriteHandler? = nil
    ) {
        self.fileURL = fileURL
        self.readHandler = readHandler ?? { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }
        self.writeHandler = writeHandler ?? { data, url in
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    enum LoadResult: Equatable, Sendable {
        case emptyNoFile
        case loaded([NotchTodoItem])
        case failed(NotchTodoStorageError)
    }

    func load(fallbackDate: Date = Date()) -> LoadResult {
        do {
            guard let data = try readHandler(fileURL) else {
                return .emptyNoFile
            }
            let items = try NotchTodoCodec.decode(data, fallbackDate: fallbackDate)
            return .loaded(items)
        } catch let storageError as NotchTodoStorageError {
            return .failed(storageError)
        } catch {
            return .failed(.unreadableFile(detail: error.localizedDescription))
        }
    }

    func save(_ items: [NotchTodoItem]) -> Result<Void, NotchTodoStorageError> {
        do {
            let data = try NotchTodoCodec.encode(items)
            try writeHandler(data, fileURL)
            return .success(())
        } catch let storageError as NotchTodoStorageError {
            return .failure(storageError)
        } catch {
            return .failure(.writeFailed(detail: error.localizedDescription))
        }
    }
}

// MARK: - Keyboard Navigation Contract (Pure)

/// Keyboard event abstraction so `NotchSurfaceController`'s local `NSEvent` monitor
/// and unit tests drive the exact same key-handling logic without AppKit.
struct NotchTodoKeyEvent: Equatable, Sendable {
    let keyCode: UInt16
    let command: Bool
    let shift: Bool

    init(keyCode: UInt16, command: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
    }

    // Standard macOS virtual key codes (matches NotchClipboardRules / NotchSurfaceController).
    static let keyEscape: UInt16 = 53
    static let keyReturn: UInt16 = 36
    static let keyKeypadEnter: UInt16 = 76
    static let keySpace: UInt16 = 49
    static let keyDelete: UInt16 = 51
    static let keyUpArrow: UInt16 = 126
    static let keyDownArrow: UInt16 = 125
    static let keyTab: UInt16 = 48
    static let key1: UInt16 = 18
    static let key2: UInt16 = 19
    static let keyE: UInt16 = 14
    static let keyN: UInt16 = 45
}

enum NotchTodoKeyOutcome: Equatable, Sendable {
    /// Event was consumed by the to-do page.
    case handled
    /// Event was not handled; pass through to the focused control (e.g. typing in TextField).
    case ignored
    /// Esc on a clean page: coordinator should dismiss the notch hub.
    case dismissSurface
}

// MARK: - Focus & Observable View Model

/// Focus contract shared between `NotchTodosPage` and `NotchSurfaceController`.
///
/// Coordinator wiring summary:
/// 1. Own one `let todos = NotchTodosModel()` on `NotchSurfaceModel`.
/// 2. In `NotchSurfaceController.currentSettings()`: include `model.todos.isComposing` in `composing`.
/// 3. When entering `.expanded(.todos)`: call `panel?.makeKeyAndOrderFront(nil)` (WITHOUT `NSApp.activate`)
///    and install a local `.keyDown` monitor forwarding events to `model.todos.handleKeyEvent(_:)`.
///    On `.dismissSurface`, call `dismiss()`.
/// 4. When leaving `.expanded(.todos)` or collapsing: call `model.todos.endTransientState()` and remove the monitor.
/// 5. Tab visibility switch (`notch.pages`) only hides/shows the page in UI; never clears `NotchTodosModel` or disk data.
@MainActor
@Observable
final class NotchTodosModel {
    private let store: NotchTodoFileStore
    private let nowProvider: @Sendable () -> Date

    private(set) var items: [NotchTodoItem] = []
    var filter: NotchTodoFilter = .active
    var selectedID: UUID?

    /// Draft text in the "Add new task" field.
    var draftTitle: String = ""
    /// True while the add-task field currently holds keyboard focus.
    var isAddFieldFocused: Bool = false

    /// Inline editing state for an existing row.
    private(set) var editingItemID: UUID?
    var editingText: String = ""

    /// Two-step delete confirmation state; never deletes immediately without confirm.
    private(set) var pendingDeleteID: UUID?

    /// Non-nil when the file on disk exists but could not be read/decoded.
    /// While set, all disk writes are blocked so the existing file on disk is strictly preserved.
    private(set) var loadError: NotchTodoStorageError?
    /// Non-nil when the most recent save attempt failed.
    private(set) var lastWriteError: NotchTodoStorageError?
    /// True when the last accepted title was trimmed to `NotchTodoRules.maxTitleLength`.
    private(set) var lastTitleWasTruncated: Bool = false

    /// Focus-bump counters observed by `NotchTodosPage` (same pattern as `agentReplyFocus` / `focusSearchRequest`).
    private(set) var focusAddFieldRequest: Int = 0
    private(set) var focusEditFieldRequest: Int = 0

    /// Optional hook for `NotchSurfaceController` to ensure the panel is key without `NSApp.activate`.
    var onRequestPanelKey: (() -> Void)?

    init(
        store: NotchTodoFileStore = NotchTodoFileStore(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.nowProvider = nowProvider
        reloadFromDisk()
    }

    // MARK: - Derived State

    var isReadBlocked: Bool { loadError != nil }

    var activeCount: Int { items.reduce(0) { $0 + ($1.isCompleted ? 0 : 1) } }
    var doneCount: Int { items.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) } }

    var visibleItems: [NotchTodoItem] {
        NotchTodoRules.visibleItems(items, filter: filter)
    }

    var selectedItem: NotchTodoItem? {
        guard let id = selectedID else { return nil }
        return visibleItems.first { $0.id == id }
    }

    /// True while typing in any field or confirming a delete — keeps the notch hub from auto-collapsing on pointer drift.
    var isComposing: Bool {
        isAddFieldFocused || editingItemID != nil || pendingDeleteID != nil
    }

    /// True while a text input owns character keys (Space, Delete, Arrows should not hijack typing).
    var isTextInputFocused: Bool {
        isAddFieldFocused || editingItemID != nil
    }

    var canSubmitDraft: Bool {
        !isReadBlocked && NotchTodoRules.normalizeTitle(draftTitle) != nil
    }

    // MARK: - Lifecycle & Persistence

    func reloadFromDisk() {
        switch store.load(fallbackDate: nowProvider()) {
        case .emptyNoFile:
            items = []
            loadError = nil
            lastWriteError = nil
        case .loaded(let loaded):
            items = loaded
            loadError = nil
            lastWriteError = nil
        case .failed(let error):
            items = []
            loadError = error
            lastWriteError = nil
        }
        reconcileSelection()
    }

    @discardableResult
    func retrySave() -> Bool {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return false
        }
        return persist()
    }

    /// Called when leaving the Todos page or collapsing the notch surface.
    /// Clears transient focus/edit/delete-confirm state without touching persisted items.
    func endTransientState() {
        editingItemID = nil
        editingText = ""
        pendingDeleteID = nil
        isAddFieldFocused = false
    }

    // MARK: - Filter & Selection

    func setFilter(_ newFilter: NotchTodoFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        pendingDeleteID = nil
        if let editID = editingItemID, !visibleItems.contains(where: { $0.id == editID }) {
            cancelEdit()
        }
        reconcileSelection()
    }

    func select(_ id: UUID?) {
        if pendingDeleteID != nil && pendingDeleteID != id {
            pendingDeleteID = nil
        }
        if let editID = editingItemID, editID != id {
            cancelEdit()
        }
        if let id, visibleItems.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = nil
        }
    }

    func requestAddFieldFocus() {
        cancelEdit()
        pendingDeleteID = nil
        onRequestPanelKey?()
        isAddFieldFocused = true
        focusAddFieldRequest += 1
    }

    // MARK: - CRUD Mutations

    /// Adds a new active to-do item from `draftTitle`.
    /// Returns the created item on acceptance, or `nil` when empty/whitespace or read-blocked.
    @discardableResult
    func submitDraft() -> NotchTodoItem? {
        addItem(title: draftTitle, clearDraft: true)
    }

    @discardableResult
    func addItem(title rawTitle: String, clearDraft: Bool = false) -> NotchTodoItem? {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return nil
        }
        guard let normalized = NotchTodoRules.normalizeTitle(rawTitle) else {
            return nil
        }
        let now = nowProvider()
        let item = NotchTodoItem(
            title: normalized.value,
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        items.insert(item, at: 0)
        lastTitleWasTruncated = normalized.wasTruncated
        if clearDraft { draftTitle = "" }
        pendingDeleteID = nil
        editingItemID = nil
        editingText = ""

        // If user adds a task while viewing "Đã xong", switch to "Đang làm" so the new task is immediately visible.
        if filter != .active {
            filter = .active
        }
        selectedID = item.id
        _ = persist()
        return item
    }

    /// Marks an item complete or unmarks it back to active.
    @discardableResult
    func toggleCompletion(id: UUID) -> Bool {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return false
        }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }

        let visibleBefore = visibleItems
        let now = nowProvider()
        items[idx].isCompleted.toggle()
        items[idx].updatedAt = now
        items[idx].completedAt = items[idx].isCompleted ? now : nil

        if pendingDeleteID == id { pendingDeleteID = nil }
        if editingItemID == id {
            editingItemID = nil
            editingText = ""
        }

        // Because the item moved out of the current filter, advance selection cleanly.
        if selectedID == id {
            selectedID = NotchTodoRules.nextSelectionAfterRemoving(id: id, from: visibleBefore)
        } else {
            reconcileSelection()
        }
        return persist()
    }

    // MARK: - Inline Editing

    func beginEdit(id: UUID) {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return
        }
        guard let item = visibleItems.first(where: { $0.id == id }) else { return }
        pendingDeleteID = nil
        isAddFieldFocused = false
        selectedID = id
        editingItemID = id
        editingText = item.title
        onRequestPanelKey?()
        focusEditFieldRequest += 1
    }

    func cancelEdit() {
        editingItemID = nil
        editingText = ""
    }

    /// Commits the inline edit. Empty/whitespace titles are rejected (keeps original title, exits edit).
    @discardableResult
    func commitEdit() -> Bool {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            cancelEdit()
            return false
        }
        guard let id = editingItemID, let idx = items.firstIndex(where: { $0.id == id }) else {
            cancelEdit()
            return false
        }
        guard let normalized = NotchTodoRules.normalizeTitle(editingText) else {
            cancelEdit()
            return false
        }
        items[idx].title = normalized.value
        items[idx].updatedAt = nowProvider()
        lastTitleWasTruncated = normalized.wasTruncated
        editingItemID = nil
        editingText = ""
        selectedID = id
        return persist()
    }

    // MARK: - Delete with Confirmation & Cancel

    func requestDelete(id: UUID) {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return
        }
        guard visibleItems.contains(where: { $0.id == id }) else { return }
        cancelEdit()
        isAddFieldFocused = false
        selectedID = id
        pendingDeleteID = id
    }

    func requestDeleteSelected() {
        guard let id = selectedID else { return }
        requestDelete(id: id)
    }

    func cancelDelete() {
        pendingDeleteID = nil
    }

    @discardableResult
    func confirmDelete() -> Bool {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            pendingDeleteID = nil
            return false
        }
        guard let id = pendingDeleteID else { return false }
        let visibleBefore = visibleItems
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            pendingDeleteID = nil
            reconcileSelection()
            return false
        }
        items.remove(at: idx)
        pendingDeleteID = nil
        selectedID = NotchTodoRules.nextSelectionAfterRemoving(id: id, from: visibleBefore)
        return persist()
    }

    // MARK: - Keyboard Navigation

    func handleKeyEvent(_ event: NotchTodoKeyEvent) -> NotchTodoKeyOutcome {
        // 1. Escape follows strict priority: cancel delete -> cancel edit -> blur/clear add draft -> dismiss hub.
        if event.keyCode == NotchTodoKeyEvent.keyEscape {
            if pendingDeleteID != nil {
                cancelDelete()
                return .handled
            }
            if editingItemID != nil {
                cancelEdit()
                return .handled
            }
            if isAddFieldFocused || !draftTitle.isEmpty {
                draftTitle = ""
                isAddFieldFocused = false
                return .handled
            }
            return .dismissSurface
        }

        // 2. Command shortcuts that work regardless of text focus.
        if event.command {
            switch event.keyCode {
            case NotchTodoKeyEvent.key1:
                setFilter(.active)
                return .handled
            case NotchTodoKeyEvent.key2:
                setFilter(.done)
                return .handled
            case NotchTodoKeyEvent.keyN:
                requestAddFieldFocus()
                return .handled
            case NotchTodoKeyEvent.keyDelete where !isTextInputFocused:
                guard let id = selectedID else { return .ignored }
                requestDelete(id: id)
                return .handled
            case NotchTodoKeyEvent.keyE where !isTextInputFocused:
                guard let id = selectedID else { return .ignored }
                beginEdit(id: id)
                return .handled
            default:
                break
            }
        }

        // 3. When a text field owns focus, let AppKit/SwiftUI handle typing & caret movement.
        if isTextInputFocused {
            return .ignored
        }

        // 4. Pending delete confirmation active: Return confirms, anything else ignored.
        if pendingDeleteID != nil {
            if event.keyCode == NotchTodoKeyEvent.keyReturn || event.keyCode == NotchTodoKeyEvent.keyKeypadEnter {
                _ = confirmDelete()
                return .handled
            }
            return .ignored
        }

        // 5. List navigation & row actions (no text field focused).
        let visible = visibleItems
        switch event.keyCode {
        case NotchTodoKeyEvent.keyDownArrow:
            selectedID = NotchTodoRules.movedSelection(current: selectedID, delta: 1, in: visible)
            return .handled
        case NotchTodoKeyEvent.keyUpArrow:
            selectedID = NotchTodoRules.movedSelection(current: selectedID, delta: -1, in: visible)
            return .handled
        case NotchTodoKeyEvent.keySpace:
            guard let id = selectedID else { return .ignored }
            _ = toggleCompletion(id: id)
            return .handled
        case NotchTodoKeyEvent.keyReturn, NotchTodoKeyEvent.keyKeypadEnter:
            guard let id = selectedID else { return .ignored }
            beginEdit(id: id)
            return .handled
        case NotchTodoKeyEvent.keyDelete:
            guard let id = selectedID else { return .ignored }
            requestDelete(id: id)
            return .handled
        case NotchTodoKeyEvent.keyTab:
            setFilter(filter == .active ? .done : .active)
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Helpers

    private func reconcileSelection() {
        let visible = visibleItems
        if let id = selectedID, visible.contains(where: { $0.id == id }) {
            return
        }
        selectedID = visible.first?.id
    }

    @discardableResult
    private func persist() -> Bool {
        guard !isReadBlocked else {
            lastWriteError = .writeBlockedByUnreadableDisk
            return false
        }
        switch store.save(items) {
        case .success:
            lastWriteError = nil
            return true
        case .failure(let error):
            lastWriteError = error
            return false
        }
    }
}
