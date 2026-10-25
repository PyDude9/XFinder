import Foundation

/// XF-T30 — Finder/FileOctopus "Group By" (Icon, List, Column views; Gallery has none, only Sort By). W1 declares the
/// cases so the toolbar's Group menu and the pane state can name them; W2 implements the grouping itself (headers such
/// as Today / Yesterday / Previous 7 Days). Pure, symlinked into the test package.
enum GroupBy: String, Codable, CaseIterable, Sendable {
    case none, name, kind, application, dateLastOpened, dateAdded, dateModified, dateCreated, size, tags

    /// L10n store key (the Vietnamese text itself).
    var titleKey: String {
        switch self {
        case .none: return "Không nhóm"
        case .name: return "Tên"
        case .kind: return "Loại"
        case .application: return "Ứng dụng"
        case .dateLastOpened: return "Ngày mở gần nhất"
        case .dateAdded: return "Ngày thêm"
        case .dateModified: return "Ngày sửa"
        case .dateCreated: return "Ngày tạo"
        case .size: return "Cỡ"
        case .tags: return "Các thẻ"
        }
    }
}

/// XF-T30 W2 — one group of a grouped listing. `titleKey` is an L10n key; `titleArg` a value shown after it (a month
/// name, a year, a kind or tag name) that is not translated.
struct EntrySection: Equatable, Sendable {
    let titleKey: String
    let titleArg: String?
    let entries: [DirectoryEntry]

    /// The header text every view shows: the translated key, then the verbatim argument; a label-only section (a kind,
    /// application or tag name) has an empty key and shows just the argument.
    func displayTitle(translate: (String) -> String) -> String {
        let title: String = titleKey.isEmpty ? "" : translate(titleKey)
        guard let arg: String = titleArg, !arg.isEmpty else { return title }
        return title.isEmpty ? arg : "\(title) \(arg)"
    }
}

extension GroupBy {
    /// Groups `entries` (already filtered) into sections in display order, each section sorted by `sort` — rules in
    /// contract XF-T30-w2 §1 (relative dates Today / Yesterday / Previous 7 Days / Previous 30 Days / months / years,
    /// first letter, kind, application, size buckets, tags). `.none` ⇒ one section with every entry. W2 builder (pure).
    ///
    /// A section's displayed title is `L10n.t(titleKey)` with `titleArg` appended when present (a view concern — this
    /// file only decides the two parts). `titleArg` is already the text to show verbatim (a locale month name via
    /// `calendar.locale`, a 4-digit year, a kind/application/tag name) and is NEVER itself translated.
    static func sections(_ entries: [DirectoryEntry], by group: GroupBy, sort: SortOrder, foldersFirst: Bool, now: Date,
                         calendar: Calendar, kindName: (DirectoryEntry) -> String,
                         appName: (DirectoryEntry) -> String?) -> [EntrySection] {
        func finish(_ buckets: [(key: String, arg: String?, entries: [DirectoryEntry])]) -> [EntrySection] {
            buckets
                .filter { !$0.entries.isEmpty }
                .map { bucket in
                    EntrySection(titleKey: bucket.key, titleArg: bucket.arg,
                                 entries: EntryRules.sorted(bucket.entries, by: sort, foldersFirst: foldersFirst, kindName: kindName))
                }
        }

        switch group {
        case .none:
            // `.none` must still produce exactly one section (never zero) so a caller can always show
            // something, even when `entries` itself is empty.
            return [EntrySection(titleKey: "", titleArg: nil,
                                  entries: EntryRules.sorted(entries, by: sort, foldersFirst: foldersFirst, kindName: kindName))]

        case .dateLastOpened:
            return finish(dateSections(entries, dateOf: { $0.lastOpened }, now: now, calendar: calendar))
        case .dateAdded:
            return finish(dateSections(entries, dateOf: { $0.added }, now: now, calendar: calendar))
        case .dateCreated:
            return finish(dateSections(entries, dateOf: { $0.created }, now: now, calendar: calendar))
        case .dateModified:
            return finish(dateSections(entries, dateOf: { $0.modified }, now: now, calendar: calendar))

        case .name:
            return finish(nameSections(entries))

        case .kind:
            return finish(labelSections(entries) { kindName($0) })

        case .application:
            // Unresolvable application ⇒ the translated "Không rõ" group, placed last (review 2026-10-25: the raw
            // Vietnamese literal went out as an untranslated `titleArg`).
            let known: [DirectoryEntry] = entries.filter { appName($0) != nil }
            let unknown: [DirectoryEntry] = entries.filter { appName($0) == nil }
            return finish(labelSections(known) { appName($0) ?? "" } + [(key: "Không rõ", arg: nil, entries: unknown)])

        case .size:
            return finish(sizeSections(entries))

        case .tags:
            return finish(tagSections(entries))
        }
    }

    // MARK: - Date

    /// Today · Yesterday · Previous 7 Days · Previous 30 Days · one section per month so far this year (most recent
    /// first) · one section per earlier year (most recent first) · "no date" last. A date exactly 7 (or 30) days
    /// before `now`, by calendar day, is the OLDEST day still inside the "Previous 7/30 Days" bucket (a closed
    /// interval on whole days, matching Finder: "trong 7 ngày qua" includes the 7th day back).
    private static func dateSections(
        _ entries: [DirectoryEntry], dateOf: (DirectoryEntry) -> Date?, now: Date, calendar: Calendar
    ) -> [(key: String, arg: String?, entries: [DirectoryEntry])] {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: now)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: today),
              let sevenDaysAgoStart = calendar.date(byAdding: .day, value: -7, to: today),
              let thirtyDaysAgoStart = calendar.date(byAdding: .day, value: -30, to: today)
        else {
            return [(key: "Chưa có ngày", arg: nil, entries: entries)]
        }

        var todayBucket: [DirectoryEntry] = []
        var yesterdayBucket: [DirectoryEntry] = []
        var sevenDaysBucket: [DirectoryEntry] = []
        var thirtyDaysBucket: [DirectoryEntry] = []
        var monthBuckets: [Int: [DirectoryEntry]] = [:]          // month (1...12) -> entries, this year
        var yearBuckets: [Int: [DirectoryEntry]] = [:]           // year -> entries, earlier years
        var noDateBucket: [DirectoryEntry] = []

        for entry in entries {
            guard let date = dateOf(entry) else {
                noDateBucket.append(entry)
                continue
            }
            let day = calendar.startOfDay(for: date)
            if day >= today {
                todayBucket.append(entry)
            } else if day >= yesterdayStart {
                yesterdayBucket.append(entry)
            } else if day >= sevenDaysAgoStart {
                sevenDaysBucket.append(entry)
            } else if day >= thirtyDaysAgoStart {
                thirtyDaysBucket.append(entry)
            } else {
                let year = calendar.component(.year, from: date)
                if year == thisYear {
                    let month = calendar.component(.month, from: date)
                    monthBuckets[month, default: []].append(entry)
                } else {
                    yearBuckets[year, default: []].append(entry)
                }
            }
        }

        var result: [(key: String, arg: String?, entries: [DirectoryEntry])] = [
            (key: "Hôm nay", arg: nil, entries: todayBucket),
            (key: "Hôm qua", arg: nil, entries: yesterdayBucket),
            (key: "7 ngày trước", arg: nil, entries: sevenDaysBucket),
            (key: "30 ngày trước", arg: nil, entries: thirtyDaysBucket),
        ]
        for month in stride(from: 12, through: 1, by: -1) {
            guard let bucket = monthBuckets[month] else { continue }
            result.append((key: "", arg: monthName(month, calendar: calendar), entries: bucket))
        }
        for year in yearBuckets.keys.sorted(by: >) {
            result.append((key: "", arg: String(year), entries: yearBuckets[year] ?? []))
        }
        result.append((key: "Chưa có ngày", arg: nil, entries: noDateBucket))
        return result
    }

    /// Locale-correct standalone month name (e.g. "Tháng 10" with a Vietnamese locale, "October" with an English
    /// one) via `calendar.locale`, falling back to the device's current locale when the calendar carries none.
    private static func monthName(_ month: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        let months = formatter.standaloneMonthSymbols ?? []
        guard month >= 1, month <= months.count else { return String(month) }
        return months[month - 1]
    }

    // MARK: - Name (first letter)

    /// "#" for a name whose folded first byte is not a letter (digits, symbols, non-Latin scripts fold to their own
    /// lowercase form so e.g. Vietnamese "Đ" still groups under "D", not "#").
    private static func nameSections(_ entries: [DirectoryEntry]) -> [(key: String, arg: String?, entries: [DirectoryEntry])] {
        var buckets: [String: [DirectoryEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let letter = firstLetterBucket(entry.name)
            if buckets[letter] == nil { order.append(letter) }
            buckets[letter, default: []].append(entry)
        }
        return order.sorted().map { letter in (key: "", arg: letter, entries: buckets[letter] ?? []) }
    }

    private static func firstLetterBucket(_ name: String) -> String {
        let folded = EntryRules.foldBytes(name)
        guard let first = folded.first, first >= 0x61, first <= 0x7A else { return "#" }
        return String(UnicodeScalar(first - 32))
    }

    // MARK: - Kind / Application (arbitrary label)

    private static func labelSections(
        _ entries: [DirectoryEntry], label: (DirectoryEntry) -> String
    ) -> [(key: String, arg: String?, entries: [DirectoryEntry])] {
        var buckets: [String: [DirectoryEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let name = label(entry)
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(entry)
        }
        return order.sorted { EntryRules.naturalCompare(EntryRules.foldBytes($0), EntryRules.foldBytes($1)) < 0 }
            .map { name in (key: "", arg: name, entries: buckets[name] ?? []) }
    }

    // MARK: - Size

    private static func sizeSections(_ entries: [DirectoryEntry]) -> [(key: String, arg: String?, entries: [DirectoryEntry])] {
        var folders: [DirectoryEntry] = []
        var zero: [DirectoryEntry] = []
        var under100KB: [DirectoryEntry] = []
        var kb100ToMB1: [DirectoryEntry] = []
        var mb1To100: [DirectoryEntry] = []
        var mb100ToGB1: [DirectoryEntry] = []
        var overGB1: [DirectoryEntry] = []

        let kb: Int64 = 1024
        let mb = kb * 1024
        let gb = mb * 1024

        for entry in entries {
            if entry.size < 0 {
                folders.append(entry)
            } else if entry.size == 0 {
                zero.append(entry)
            } else if entry.size < 100 * kb {
                under100KB.append(entry)
            } else if entry.size < mb {
                kb100ToMB1.append(entry)
            } else if entry.size < 100 * mb {
                mb1To100.append(entry)
            } else if entry.size < gb {
                mb100ToGB1.append(entry)
            } else {
                overGB1.append(entry)
            }
        }

        return [
            (key: "Không byte", arg: nil, entries: zero),
            (key: "Dưới 100 KB", arg: nil, entries: under100KB),
            (key: "Từ 100 KB đến 1 MB", arg: nil, entries: kb100ToMB1),
            (key: "Từ 1 đến 100 MB", arg: nil, entries: mb1To100),
            (key: "Từ 100 MB đến 1 GB", arg: nil, entries: mb100ToGB1),
            (key: "Trên 1 GB", arg: nil, entries: overGB1),
            (key: "Thư mục", arg: nil, entries: folders),
        ]
    }

    // MARK: - Tags

    /// A multi-tag entry appears once, in the group of the FIRST tag in its own `tags` array (the order Finder already
    /// stores per file); groups themselves are ordered by first appearance across `entries`. "Không có thẻ" is last.
    private static func tagSections(_ entries: [DirectoryEntry]) -> [(key: String, arg: String?, entries: [DirectoryEntry])] {
        var buckets: [String: [DirectoryEntry]] = [:]
        var order: [String] = []
        var untagged: [DirectoryEntry] = []
        for entry in entries {
            guard let first = entry.tags?.first, !first.isEmpty else {
                untagged.append(entry)
                continue
            }
            if buckets[first] == nil { order.append(first) }
            buckets[first, default: []].append(entry)
        }
        var result: [(key: String, arg: String?, entries: [DirectoryEntry])] =
            order.map { name in (key: "", arg: name, entries: buckets[name] ?? []) }
        result.append((key: "Không có thẻ", arg: nil, entries: untagged))
        return result
    }
}
