import Foundation

/// Pure rules for the Thư viện Clipboard sidebar page (D3): the job sentence is "I need to find an
/// old clip — beyond the 4 cards at the notch — filter by type / source app / board / time, inspect
/// it, then paste, pin to a board, or delete."
///
/// This differs from `NotchClipboardRules` in one load-bearing way: the notch page works over
/// `ClipboardManager`'s capped history (`clipboard.maxHistory`, default a few hundred), because it is
/// a glance surface a few taps from a copy. The library is the opposite job — searching the PAST, not
/// watching the present — so `ClipboardLibraryStore` loads every row in SQLite and every count here
/// (`Facets`) is computed over that full loaded set, not a cap. A type or app chip that is missing
/// here means the user genuinely has zero clips of that kind, not "zero in the last 200".
///
/// Foundation-only on purpose: `ClipboardLibraryStore` (AppKit, the pasteboard, `DatabaseService`) and
/// the SwiftUI view both sit on top of this file and are not symlinked into the test package.
enum ClipboardLibrary {

    // MARK: - Scope (the left filter rail)

    enum Scope: Hashable {
        case all
        case pinned
        case type(ContentType)
        case app(String)   // bundle id ("" for a record with no bundle id — see `facets`)
        case board(UUID)
    }

    enum Sort: String, CaseIterable {
        case newest, oldest, byApp, byType
    }

    enum Period: String, CaseIterable {
        case any, today, week, month
    }

    struct Query: Equatable {
        var scope: Scope = .all
        var text: String = ""
        var sort: Sort = .newest
        var period: Period = .any
    }

    struct AppFacet: Equatable, Hashable {
        let bundleID: String
        let name: String
        let count: Int
    }

    struct Facets: Equatable {
        var total: Int
        var pinned: Int
        var byType: [ContentType: Int]
        var apps: [AppFacet]
        var byBoard: [UUID: Int]
    }

    /// Page size for the "Hiện 1–N trong M · Tải thêm" footer: the display window grows by this many
    /// records per `loadMore()` call. Everything is already loaded — this only bounds how much of the
    /// filtered set is rendered at once.
    static let pageSize = 60

    // MARK: - Board membership

    /// A record belongs to a board either because it was captured straight into it (`pinboardID`) or
    /// because it was added to it later (`itemIDs`) — the same two paths `ClipboardManager` writes.
    static func isMember(_ record: ClipboardRecord, of board: Pinboard) -> Bool {
        record.pinboardID == board.id || board.itemIDs.contains(record.id)
    }

    // MARK: - Facets

    /// Counts over `records` as given — the caller passes the FULL loaded set (not `apply`'s filtered
    /// result), so the rail always shows what exists, not what the current filter narrowed to.
    static func facets(_ records: [ClipboardRecord], boards: [Pinboard]) -> Facets {
        var pinned = 0
        var byType: [ContentType: Int] = [:]
        var appCounts: [String: (name: String, count: Int)] = [:]

        for r in records {
            if r.isPinned { pinned += 1 }
            byType[r.type, default: 0] += 1

            let bundleID = r.sourceBundleID ?? ""
            let name = r.sourceAppName ?? "?"
            if var existing = appCounts[bundleID] {
                existing.count += 1
                appCounts[bundleID] = existing
            } else {
                appCounts[bundleID] = (name: name, count: 1)
            }
        }

        let apps = appCounts
            .map { AppFacet(bundleID: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        var byBoard: [UUID: Int] = [:]
        for board in boards {
            byBoard[board.id] = records.reduce(into: 0) { count, r in
                if isMember(r, of: board) { count += 1 }
            }
        }

        return Facets(
            total: records.count,
            pinned: pinned,
            byType: byType.filter { $0.value > 0 },
            apps: apps,
            byBoard: byBoard
        )
    }

    // MARK: - Query application

    /// Scope → tokens (`ClipboardFilterToken.parse`) → period → sort, in that order. Each stage narrows
    /// what the previous stage produced; none of them widen it back.
    static func apply(_ query: Query, to records: [ClipboardRecord], boards: [Pinboard], now: Date, calendar: Calendar) -> [ClipboardRecord] {
        var working = scoped(query.scope, records: records, boards: boards)

        let parsed = ClipboardFilterToken.parse(query.text)
        if let type = parsed.type {
            working = working.filter { $0.type == type }
        }
        if let app = parsed.app, !app.isEmpty {
            working = working.filter { ClipboardFilterToken.appMatches(token: app, appName: $0.sourceAppName, bundleID: $0.sourceBundleID) }
        }
        if !parsed.text.isEmpty {
            let needle = parsed.text.lowercased()
            working = working.filter { matchesFreeText(needle, in: $0) }
        }

        working = working.filter { inPeriod(query.period, date: $0.timestamp, now: now, calendar: calendar) }

        return sorted(working, by: query.sort)
    }

    private static func scoped(_ scope: Scope, records: [ClipboardRecord], boards: [Pinboard]) -> [ClipboardRecord] {
        switch scope {
        case .all:
            return records
        case .pinned:
            return records.filter(\.isPinned)
        case .type(let t):
            return records.filter { $0.type == t }
        case .app(let bundleID):
            return records.filter { ($0.sourceBundleID ?? "") == bundleID }
        case .board(let id):
            guard let board = boards.first(where: { $0.id == id }) else { return [] }
            return records.filter { isMember($0, of: board) }
        }
    }

    private static func matchesFreeText(_ needle: String, in r: ClipboardRecord) -> Bool {
        if let s = r.textSnippet, s.lowercased().contains(needle) { return true }
        if let s = r.ocrText, s.lowercased().contains(needle) { return true }
        if let s = r.customTitle, s.lowercased().contains(needle) { return true }
        if let s = r.sourceAppName, s.lowercased().contains(needle) { return true }
        if let s = r.metadata["url"], s.lowercased().contains(needle) { return true }
        return false
    }

    /// `.week` and `.month` are rolling windows measured in hours from `now` (7×24h / 30×24h), not
    /// calendar weeks/months — a clip from exactly 6 days 23 hours ago is "this week" on both sides of
    /// a calendar-week boundary, which a `Calendar`-based week definition would get wrong near a week
    /// rollover. `.today` is the one period that IS calendar-relative (same calendar day as `now`),
    /// because "today" has no other sensible meaning.
    private static func inPeriod(_ period: Period, date: Date, now: Date, calendar: Calendar) -> Bool {
        switch period {
        case .any:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return now.timeIntervalSince(date) <= 7 * 24 * 3600
        case .month:
            return now.timeIntervalSince(date) <= 30 * 24 * 3600
        }
    }

    private static func sorted(_ records: [ClipboardRecord], by sort: Sort) -> [ClipboardRecord] {
        switch sort {
        case .newest:
            return records.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return records.sorted { $0.timestamp < $1.timestamp }
        case .byApp:
            return records.sorted { lhs, rhs in
                let l = lhs.sourceAppName ?? ""
                let r = rhs.sourceAppName ?? ""
                let cmp = l.localizedCaseInsensitiveCompare(r)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.timestamp > rhs.timestamp
            }
        case .byType:
            return records.sorted { lhs, rhs in
                if lhs.type.rawValue != rhs.type.rawValue { return lhs.type.rawValue < rhs.type.rawValue }
                return lhs.timestamp > rhs.timestamp
            }
        }
    }

    // MARK: - Pagination

    static func visibleCount(total: Int, pagesShown: Int) -> Int {
        min(total, max(1, pagesShown) * pageSize)
    }

    // MARK: - Rail / header titles

    /// `.all`/`.pinned`/`.type` resolve to a store key (`L10n.t` must wrap the result); `.app`/`.board`
    /// resolve to a user-authored name (an app's display name, a board's name) that must NEVER be
    /// wrapped — `scopeTitleIsKey` is how the caller tells the two apart without guessing from content.
    static func scopeTitleKey(_ scope: Scope, boards: [Pinboard]) -> String {
        switch scope {
        case .all: return "Tất cả"
        case .pinned: return "Đã ghim"
        case .type(let t): return t.titleVI
        case .app(let bundleID):
            // The caller does not have the app name here (facets carry it); this default only fires if
            // a caller resolves the title without going through the facet list. Prefer the facet's name.
            return bundleID
        case .board(let id):
            return boards.first(where: { $0.id == id })?.name ?? ""
        }
    }

    static func scopeTitleIsKey(_ scope: Scope) -> Bool {
        switch scope {
        case .all, .pinned, .type: return true
        case .app, .board: return false
        }
    }

    // MARK: - Grid keyboard movement

    enum MoveDirection { case left, right, up, down }

    /// Same no-wrap semantics as the notch's grid (`NotchClipboardRules.move`): ←/→ stop at the ends,
    /// ↑/↓ stay put when there is no row there. `NotchClipboardRules.move` takes an `Int?` index and a
    /// different `Direction` enum scoped to that file, so the library gets its own small mirror rather
    /// than reaching across files for an enum that means the same thing under a different name.
    static func move(_ index: Int, direction: MoveDirection, count: Int, columns: Int) -> Int {
        guard count > 0 else { return 0 }
        let clampedIndex = min(max(index, 0), count - 1)
        let cols = max(1, columns)
        switch direction {
        case .left:  return max(0, clampedIndex - 1)
        case .right: return min(count - 1, clampedIndex + 1)
        case .up:    return clampedIndex - cols >= 0 ? clampedIndex - cols : clampedIndex
        case .down:  return clampedIndex + cols < count ? clampedIndex + cols : clampedIndex
        }
    }

    // MARK: - Inspector meta-row facts

    enum Facts {
        /// 1 + the number of newline characters; empty text has 0 lines (there is nothing to count).
        static func lines(in text: String) -> Int {
            guard !text.isEmpty else { return 0 }
            return 1 + text.filter { $0.isNewline }.count
        }

        static func characters(in text: String) -> Int {
            text.count
        }

        /// `ByteCountFormatter(.file)` style ("4,1 MB"); non-positive sizes have no meaningful label.
        static func sizeLabel(bytes: Int64) -> String {
            guard bytes > 0 else { return "" }
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }
    }
}
