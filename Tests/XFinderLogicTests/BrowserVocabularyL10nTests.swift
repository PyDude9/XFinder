import XCTest

/// XF-T28: the file browser shows model vocabulary through `L10n.t(variable)` — command titles, recovery messages,
/// search warnings. No literal sweep sees those keys, so every model case is walked and resolved in the shipped store.
final class BrowserVocabularyL10nTests: XCTestCase {

    private func entries() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (root["entries"] as? [String: Any]) ?? root
    }

    func testEveryBrowserVocabularyKeyIsTranslated() throws {
        let store = try entries()
        var keys = BrowserCommand.allCases.map { BrowserCommands.titleKey($0) }
        // One recovery message per unfinished phase.
        let job = UUID()
        let at = Date(timeIntervalSince1970: 0)
        for (i, phase) in [JournalPhase.started, .copied, .verified, .trashing].enumerated() {
            let entry = JournalEntry(job: job, kind: .move, source: "/src/\(i)", destination: "/dst/\(i)", phase: phase, at: at)
            keys += FileOperationRules.recoveryReport([entry]).map(\.messageKey)
        }
        keys += SearchQuery.parse("bogus:thing", now: at, calendar: Calendar(identifier: .gregorian)).warnings
        keys += Access.allCases.map(\.titleKey)                                       // Get Info permissions
        keys += ["", "a/b", "a:b"].compactMap { FileInfoRules.renameRejectionKey(for: $0) }
        keys += GroupBy.allCases.map(\.titleKey)                                      // XF-T30 W1: toolbar Group menu
        keys += TagColor.allCases.map(\.titleKey)                                     // XF-T30 W2: tag swatch names
        keys += groupBySectionTitleKeys()                                             // XF-T30 W2: section headers
        XCTAssertGreaterThanOrEqual(
            keys.count,
            BrowserCommand.allCases.count + GroupBy.allCases.count + TagColor.allCases.count + 5,
            "a collapsed list would pass as a clean one"
        )
        for k in keys {
            let en = (store[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(k)")
        }
    }

    /// XF-T30 W2 — `GroupBy.sections`' fixed (non-empty, L10n-key-bearing) section titles: Today / Yesterday /
    /// Previous 7 Days / Previous 30 Days / no date / zero bytes / the four size buckets / folders / no tags. Month
    /// and year headers, and name/kind/application/tag names, are `titleArg` (never an L10n key — see the doc comment
    /// on `GroupBy.sections`), so they are deliberately excluded here.
    private func groupBySectionTitleKeys() -> [String] {
        let now = Date(timeIntervalSince1970: 0)
        let calendar = Calendar(identifier: .gregorian)
        func entry(size: Int64 = 0, kind: DirectoryEntry.Kind = .file, modified: Date? = nil, tags: [String]? = nil) -> DirectoryEntry {
            var e = DirectoryEntry(
                name: "x", path: "/x", kind: kind, isPackage: false, isHidden: false, size: size,
                modified: modified ?? now, created: now, volumeID: 1
            )
            e.tags = tags
            return e
        }
        func sectionKeys(_ entries: [DirectoryEntry], _ group: GroupBy) -> [String] {
            GroupBy.sections(
                entries, by: group, sort: .finderDefault, foldersFirst: false, now: now, calendar: calendar,
                kindName: { _ in "" }, appName: { _ in nil }
            ).map(\.titleKey).filter { !$0.isEmpty }
        }
        let dateEntries = [
            entry(modified: now),                                                     // Today
            entry(modified: calendar.date(byAdding: .day, value: -1, to: now)!),       // Yesterday
            entry(modified: calendar.date(byAdding: .day, value: -7, to: now)!),       // Previous 7 Days
            entry(modified: calendar.date(byAdding: .day, value: -30, to: now)!),      // Previous 30 Days
            entry(modified: nil, tags: nil),                                          // falls through to "no date" via .added below
        ]
        var keys = sectionKeys(dateEntries, .dateModified)
        var noDate = entry(modified: now)
        noDate.added = nil
        keys += sectionKeys([noDate], .dateAdded)                                     // "Chưa có ngày"
        keys += sectionKeys([entry(size: -1, kind: .directory), entry(size: 0), entry(size: 50), entry(size: 200_000),
                              entry(size: 50_000_000), entry(size: 500_000_000), entry(size: 2_000_000_000)], .size)
        keys += sectionKeys([entry(tags: nil)], .tags)                                // "Không có thẻ"
        return keys
    }
}
