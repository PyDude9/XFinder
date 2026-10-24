import Foundation

/// Rules of the notch's clipboard page once the ⌘⇧V shelf is consolidated into it (D0) — pure, so every
/// decision that used to live in the shelf's event tap and view is testable without AppKit. The view and
/// `NotchSurfaceController` read these; nothing here touches UserDefaults or the pasteboard.
enum NotchClipboardRules {

    // MARK: - Which surface ⌘⇧V opens

    /// `clipboard.hotkeySurface`: where the global ⌘⇧V lands. The old floating shelf stays one picker
    /// away, so a notch page that misbehaves is never a dead end.
    enum HotkeySurface: String, CaseIterable { case notch, shelf }
    static let hotkeySurfaceKey = "clipboard.hotkeySurface"

    /// An unknown or missing value is the default, never "nothing opens".
    static func hotkeySurface(parsing raw: String?) -> HotkeySurface {
        HotkeySurface(rawValue: raw ?? "") ?? .notch
    }

    /// The notch surface has its own master switch (`dropTray.notchEnabled`). With it off, ⌘⇧V must still
    /// open something — the shelf — rather than a surface that cannot appear.
    static func surfaceToOpen(preferred: HotkeySurface, notchSurfaceEnabled: Bool) -> HotkeySurface {
        preferred == .notch && notchSurfaceEnabled ? .notch : .shelf
    }

    // MARK: - Scope (the board menu) and ⌘1–9

    enum Scope: Equatable {
        case history, pinned, saved, suggestions
        case board(UUID)
    }

    /// Key codes of the digit row → slot 0…8 — the same table the shelf has used since it shipped.
    static func slot(forKeyCode code: UInt16) -> Int? {
        let slots: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        return slots[code]
    }

    /// ⌘1 history · ⌘2 pinned · ⌘3 saved · ⌘4… custom boards in their order. A slot past the last board
    /// is nothing (not "the last board": the user pressed a number that has no meaning yet).
    static func scope(forSlot slot: Int, boardIDs: [UUID]) -> Scope? {
        switch slot {
        case 0: return .history
        case 1: return .pinned
        case 2: return .saved
        default:
            let i = slot - 3
            return boardIDs.indices.contains(i) ? .board(boardIDs[i]) : nil
        }
    }

    // MARK: - The grid's keyboard

    enum Direction { case left, right, up, down }

    /// Next selected index in a reading-order grid. No selection (or a stale one) ⇒ the first card.
    /// ←/→ step through reading order and STOP at the ends — wrapping hides "I am at the end" and
    /// makes a long deck feel endless. ↑/↓ move a whole row and stay put when there is no row there.
    static func move(_ d: Direction, from index: Int?, count: Int, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let i = index, i >= 0, i < count else { return 0 }
        let cols = max(1, columns)
        switch d {
        case .left:  return max(0, i - 1)
        case .right: return min(count - 1, i + 1)
        case .up:    return i - cols >= 0 ? i - cols : i
        case .down:  return i + cols < count ? i + cols : i
        }
    }

    /// Selection after the item at `index` was deleted: the item that slid into its place, or the new
    /// last one, or nothing when the deck is empty.
    static func selectionAfterDeleting(index: Int, newCount: Int) -> Int? {
        guard newCount > 0 else { return nil }
        return min(index, newCount - 1)
    }

    // MARK: - Filtering and counting

    /// Which records a scope shows. `boardItemIDs` is the chosen custom board's membership (nil for the
    /// built-in scopes). Suggestions are RANKED elsewhere; as a filter they are the whole history.
    static func apply(scope: Scope, boardItemIDs: Set<UUID>?, to records: [ClipboardRecord]) -> [ClipboardRecord] {
        switch scope {
        case .history, .suggestions: return records
        case .pinned: return records.filter(\.isPinned)
        case .saved:  return records.filter(\.isSavedSnippet)
        case .board:
            guard let ids = boardItemIDs else { return [] }
            return records.filter { ids.contains($0.id) }
        }
    }

    /// Count per content type over the LOADED history — the chip row. The total is the loaded count,
    /// never the database's: the page can only show what `ClipboardManager` holds (`clipboard.maxHistory`).
    static func typeCounts(_ types: [ContentType]) -> [ContentType: Int] {
        types.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Chip order, fixed so the row never reshuffles under the pointer. A type with no record is not
    /// offered: a chip that filters to nothing is a dead control.
    static let chipOrder: [ContentType] = [.image, .link, .text, .markdown, .code, .file, .color, .merged]

    static func chips(from counts: [ContentType: Int]) -> [(type: ContentType, count: Int)] {
        chipOrder.compactMap { t in
            guard let n = counts[t], n > 0 else { return nil }
            return (t, n)
        }
    }

    // MARK: - Footer line

    enum Footer: Equatable {
        case hints
        case pasteStack(remaining: Int, interceptsCommandV: Bool)
        case notice(String)
        case paused
        case accessibilityMissing
        /// XF-T29 — Free, scope `.history`, at least one item hidden past `ProLimit.clipboardItems`.
        case proLimit(hidden: Int)
    }

    /// The one-line footer, most urgent first: a running Paste Stack, then the last action's notice,
    /// then "recording is paused" (D1 #14 — the deck looks normal while nothing new arrives, so the
    /// page must say so), then the standing warning that Return can only COPY (auto-paste on, no
    /// Accessibility — the user must learn this before the first click, not after), then the Free-tier
    /// hidden-items notice (ambient, lowest priority — it never hides a warning that needs action), then
    /// the key hints.
    static func footer(pasteStackActive: Bool, remaining: Int, interceptsCommandV: Bool,
                       notice: String?, paused: Bool = false, autoPaste: Bool, accessibilityTrusted: Bool,
                       hiddenByProLimit: Int = 0) -> Footer {
        if pasteStackActive { return .pasteStack(remaining: remaining, interceptsCommandV: interceptsCommandV) }
        if let notice, !notice.isEmpty { return .notice(notice) }
        if paused { return .paused }
        if autoPaste && !accessibilityTrusted { return .accessibilityMissing }
        if hiddenByProLimit > 0 { return .proLimit(hidden: hiddenByProLimit) }
        return .hints
    }

    // MARK: - Image tiles

    enum ImageScaling: Equatable { case fill, fit }

    /// Fill the tile when the picture's shape is close to the tile's; otherwise fit it whole on a backdrop.
    /// A 1280×460 settings screenshot (2.8:1) filled into a 1.74:1 tile is a zoomed-in centre crop that looks
    /// nothing like the clip (reported 2026-10-12); a square or portrait image crops just as badly. The
    /// threshold is 1.5× either way — a 16:9 photo in a 1.74 tile still fills.
    static func imageScaling(imageAspect: Double, tileAspect: Double, tolerance: Double = 1.5) -> ImageScaling {
        guard imageAspect > 0, tileAspect > 0, tolerance >= 1 else { return .fit }
        let r = imageAspect / tileAspect
        return (r > tolerance || r < 1 / tolerance) ? .fit : .fill
    }

    // MARK: - Card footer facts

    /// Age of a clip in the footer's short form. `older` keeps the date so the view can format it.
    enum Age: Equatable { case justNow, minutes(Int), hours(Int), days(Int), older(Date) }

    static func age(of date: Date, now: Date) -> Age {
        let s = now.timeIntervalSince(date)
        if s < 60 { return .justNow }
        if s < 3600 { return .minutes(Int(s / 60)) }
        if s < 86_400 { return .hours(Int(s / 3600)) }
        if s < 7 * 86_400 { return .days(Int(s / 86_400)) }
        return .older(date)
    }

    /// The one fact worth the right side of a card footer. Images: their pixel size (written at capture
    /// as `metadata["dimensions"]`); files: the extension; code and markdown: lines; text: words. Links
    /// and colours show nothing — the body already IS the fact.
    enum Meta: Equatable { case dimensions(String), fileExtension(String), words(Int), lines(Int) }

    static func meta(type: ContentType, dimensions: String?, path: String?, text: String?) -> Meta? {
        switch type {
        case .image:
            guard let d = dimensions, !d.isEmpty else { return nil }
            return .dimensions(d)
        case .file:
            let ext = ((path ?? text) as NSString?)?.pathExtension ?? ""
            return ext.isEmpty ? nil : .fileExtension(ext.uppercased())
        case .code, .markdown:
            guard let t = text, !t.isEmpty else { return nil }
            return .lines(t.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
        case .text, .merged:
            guard let t = text else { return nil }
            let words = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            return words > 0 ? .words(words) : nil
        case .link, .color:
            return nil
        }
    }

    // MARK: Card-scroll haptic (2026-10-14)

    /// Whether the deck's leading card changing from `old` to `new` is a card passing under the user's finger: both
    /// known, different, and both in the list on screen. Not when the deck first appears (old nil) and not when a filter
    /// or a new clip replaced the list (the old card is gone) — those are not a swipe.
    static func cardChanged<ID: Equatable>(from old: ID?, to new: ID?, in ids: [ID]) -> Bool {
        guard let old, let new, old != new else { return false }
        return ids.contains(old) && ids.contains(new)
    }
}
