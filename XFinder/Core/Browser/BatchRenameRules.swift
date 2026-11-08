import Foundation

/// XF-T37 L2 — the browser's batch rename, with the three modes Finder's own Rename window has (`BulkRenameWindow.nib`:
/// Replace Text / Add Text / Format) plus FileOctopus 1.0.10's "Include extension", and FileOctopus's rule that ONE
/// error blocks the whole batch (a partial rename leaves a folder half in the old scheme, half in the new).
///
/// Pure planning (`plan`) takes disk facts as values — they are read once by the caller, never inside a SwiftUI `body`.
/// `execute` is the only part that touches the disk: two phases through temporary names (FileOctopus uses
/// `.betterfinder-rename-`), so chains (a→b, b→c) and swaps (a↔b) work, and a failure puts every item back.
enum BatchRenameRules {

    enum Mode: String, CaseIterable, Sendable { case replaceText, addText, format }
    enum Position: String, CaseIterable, Sendable { case before, after }
    enum FormatStyle: String, CaseIterable, Sendable { case nameAndIndex, nameAndCounter, nameAndDate }

    struct Options: Equatable, Sendable {
        var mode: Mode = .replaceText
        var find: String = ""
        var replaceWith: String = ""
        var addText: String = ""
        var addPosition: Position = .after
        var formatStyle: FormatStyle = .nameAndIndex
        var formatPosition: Position = .after
        /// Finder's default is "File " — the trailing space is the user's separator, Finder adds none of its own.
        var customName: String = "File "
        var startNumber: Int = 1
        /// Replace Text / Add Text only: off ⇒ the extension is left alone; a folder always uses its whole name.
        var includeExtension: Bool = false
    }

    /// Disk facts for one selected item, read once by the caller.
    struct Item: Equatable, Sendable {
        var path: String
        var isFolder: Bool
        var modified: Date
        var exists: Bool = true
        var isLocked: Bool = false
        var parentWritable: Bool = true
    }

    enum Issue: Equatable, Sendable {
        case name(RenameRules.Problem)
        case duplicateInBatch, existsInFolder, insideRenamedItem, missing, locked, noPermission

        var key: String {
            switch self {
            case .name(let problem): return problem.key
            case .duplicateInBatch: return "Một mục khác trong lô cũng ra tên này."
            case .existsInFolder: return "Đã có mục khác cùng tên trong thư mục này."
            case .insideRenamedItem: return "Nằm trong một mục khác cũng đang đổi tên."
            case .missing: return "Mục không còn ở chỗ cũ."
            case .locked: return "Mục đang bị khoá."
            case .noPermission: return "Không có quyền đổi tên trong thư mục này."
            }
        }
    }

    struct Row: Equatable, Sendable, Identifiable {
        var source: String
        var oldName: String
        var newName: String
        var issues: [Issue]
        var notes: [RenameRules.Note]
        var id: String { source }
        var isUnchanged: Bool { oldName == newName }
        var target: String { ((source as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName) }
    }

    struct Plan: Equatable, Sendable {
        var rows: [Row]
        var renameCount: Int { rows.filter { !$0.isUnchanged && $0.issues.isEmpty }.count }
        var errorCount: Int { rows.filter { !$0.issues.isEmpty }.count }
        /// FileOctopus: any error disables Rename for the whole batch; nothing to rename disables it too.
        var canRename: Bool { errorCount == 0 && renameCount > 0 }
        var pairs: [(from: String, to: String)] {
            rows.filter { !$0.isUnchanged }.map { (from: $0.source, to: $0.target) }
        }
    }

    // MARK: - Names

    /// "2026-11-08 at 10.15.02" — FileOctopus's `yyyy-MM-dd 'at' HH.mm.ss`, built from calendar components so no
    /// (non-Sendable) DateFormatter is needed; `connector` is the localized " at " / " lúc ".
    static func dateStamp(_ date: Date, calendar: Calendar, connector: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let time = String(format: "%02d.%02d.%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return day + connector + time
    }

    /// The proposed name of the `index`-th item (0-based, in the order shown). Never validated here — see `plan`.
    static func newName(for item: Item, index: Int, options: Options, calendar: Calendar, dateConnector: String) -> String {
        let name = (item.path as NSString).lastPathComponent
        let (stem, ext) = RenameRules.splitExtension(name, isFolder: item.isFolder)
        func withExt(_ s: String) -> String { ext.isEmpty ? s : "\(s).\(ext)" }
        let wholeName = options.includeExtension || item.isFolder

        switch options.mode {
        case .replaceText:
            guard !options.find.isEmpty else { return name }
            if wholeName { return name.replacingOccurrences(of: options.find, with: options.replaceWith) }
            return withExt(stem.replacingOccurrences(of: options.find, with: options.replaceWith))

        case .addText:
            let base = wholeName ? name : stem
            let added = options.addPosition == .before ? options.addText + base : base + options.addText
            return wholeName ? added : withExt(added)

        case .format:
            let number = max(0, options.startNumber) + index
            let token: String
            switch options.formatStyle {
            case .nameAndIndex: token = String(number)
            case .nameAndCounter: token = String(format: "%05d", number)
            case .nameAndDate: token = dateStamp(item.modified, calendar: calendar, connector: dateConnector)
            }
            let stemOut = options.formatPosition == .after ? options.customName + token : token + options.customName
            return withExt(stemOut)
        }
    }

    // MARK: - Plan

    /// `siblings(folder)` = names currently in `folder` (read once by the caller); nil = unreadable, treated as empty.
    static func plan(items: [Item], options: Options, siblings: (String) -> Set<String>?, calendar: Calendar,
                     dateConnector: String) -> Plan {
        var names: [String] = items.enumerated().map { index, item in
            newName(for: item, index: index, options: options, calendar: calendar, dateConnector: dateConnector)
        }
        let isFormat = options.mode == .format
        if isFormat, options.formatStyle == .nameAndDate {
            names = numberDateTies(items: items, names: names, siblings: siblings)
        }
        var plan = validate(items: items, newNames: names, siblings: siblings)
        if isFormat {
            // Format keeps the original extension; a name without one gets none, even though the time "07.33.20" has
            // dots a naive split would read as an extension ".20".
            for i in plan.rows.indices where RenameRules.splitExtension(plan.rows[i].oldName, isFolder: items[i].isFolder).ext.isEmpty {
                plan.rows[i].notes.removeAll { if case .extensionAdded = $0 { return true }; return false }
            }
        }
        return plan
    }

    /// XF-T37 Q-T37-3 (owner: "the simplest experience, with probability/statistics, easy to sort"). Measured on this
    /// Mac's real folders (2026-11-08): items sharing a modification second — 1.5 % (Downloads) to 16.7 % (Documents);
    /// by creation date it is worse (6–22 %), and even milliseconds leave 14.4 % of Documents tied. So Name and Date uses
    /// the modification date to the second (a clean, sortable "yyyy-MM-dd at HH.mm.ss"), and every name that would
    /// still clash — inside the batch or with an item already in the folder — gets "-1", "-2"… zero-padded to the
    /// group's size, in true time order (full-precision date, then the old name). The batch is never blocked by a tie,
    /// and sorting by name stays chronological.
    static func numberDateTies(items: [Item], names: [String], siblings: (String) -> Set<String>?) -> [String] {
        var result = names
        func folder(_ i: Int) -> String { (items[i].path as NSString).deletingLastPathComponent }
        func oldName(_ i: Int) -> String { (items[i].path as NSString).lastPathComponent }
        let changing = items.indices.filter { names[$0] != oldName($0) }

        // Names that stay taken: what is in the folder now, minus the batch's own items that are renamed away.
        var taken: [String: Set<String>] = [:]
        for i in changing where taken[folder(i)] == nil {
            taken[folder(i)] = Set((siblings(folder(i)) ?? []).map { RenameRules.nameKey($0) })
        }
        for i in changing { taken[folder(i)]?.remove(RenameRules.nameKey(oldName(i))) }

        var groups: [String: [Int]] = [:]
        var order: [String] = []
        for i in changing {
            let key = folder(i) + "\u{0}" + RenameRules.nameKey(names[i])
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(i)
        }
        var used: [String: Set<String>] = [:]
        for key in order {
            guard let members = groups[key], let first = members.first else { continue }
            let dir = folder(first)
            if members.count == 1, taken[dir]?.contains(RenameRules.nameKey(names[first])) != true { continue }
            let ordered = members.sorted {
                items[$0].modified != items[$1].modified ? items[$0].modified < items[$1].modified : oldName($0) < oldName($1)
            }
            let width = String(ordered.count).count
            var number = 1
            for i in ordered {
                let ext = RenameRules.splitExtension(oldName(i), isFolder: items[i].isFolder).ext
                var candidate = tieName(names[i], number: number, width: width, originalExtension: ext)
                while taken[dir]?.contains(RenameRules.nameKey(candidate)) == true
                        || used[dir]?.contains(RenameRules.nameKey(candidate)) == true {
                    number += 1
                    candidate = tieName(names[i], number: number, width: width, originalExtension: ext)
                }
                used[dir, default: []].insert(RenameRules.nameKey(candidate))
                result[i] = candidate
                number += 1
            }
        }
        return result
    }

    /// "Trip 2026-10-26 at 07.33.20.jpg" → "Trip 2026-10-26 at 07.33.20-2.jpg": the number goes before the item's own
    /// extension (never re-split the new name — its time has dots).
    static func tieName(_ name: String, number: Int, width: Int, originalExtension ext: String) -> String {
        let digits = String(number)
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        guard !ext.isEmpty, name.hasSuffix("." + ext) else { return "\(name)-\(padded)" }
        return "\(name.dropLast(ext.count + 1))-\(padded).\(ext)"
    }

    /// Validation of proposed names — shared by the browser sheet and the old Batch Rename page (Q-T37-5): every name
    /// rule, duplicates inside the batch, names already taken in the folder (the batch's own renamed-away names do not
    /// count), items inside another renamed item, and the disk facts.
    static func validate(items: [Item], newNames: [String], siblings: (String) -> Set<String>?) -> Plan {
        var rows: [Row] = items.indices.map { i in
            let oldName = (items[i].path as NSString).lastPathComponent
            return Row(source: items[i].path, oldName: oldName, newName: newNames[i], issues: [],
                       notes: RenameRules.notes(old: oldName, new: newNames[i], isFolder: items[i].isFolder))
        }

        // Paths of the items that will actually move — an item inside one of them would be renamed under a parent
        // that is itself being renamed (FileOctopus: "It’s inside another item being renamed.").
        let changingPaths: Set<String> = Set(rows.filter { !$0.isUnchanged }.map { ($0.source as NSString).standardizingPath })

        // Per folder: the names that stay taken once the batch has run = everything there now, minus the batch's own
        // items that are renamed away (an unchanged batch item keeps its name). Built up front, one read per folder.
        var occupiedByFolder: [String: Set<String>] = [:]
        // Duplicate new names among the changing rows, per folder.
        var newNameCount: [String: Int] = [:]
        for row in rows where !row.isUnchanged {
            let folder = (row.source as NSString).deletingLastPathComponent
            if occupiedByFolder[folder] == nil {
                occupiedByFolder[folder] = Set((siblings(folder) ?? []).map { RenameRules.nameKey($0) })
            }
            newNameCount[folder + "\u{0}" + RenameRules.nameKey(row.newName), default: 0] += 1
        }
        for row in rows where !row.isUnchanged {
            let folder = (row.source as NSString).deletingLastPathComponent
            occupiedByFolder[folder]?.remove(RenameRules.nameKey(row.oldName))
        }

        for i in rows.indices where !rows[i].isUnchanged {
            let item = items[i]
            let folder = (item.path as NSString).deletingLastPathComponent
            var issues: [Issue] = []
            if !item.exists { issues.append(.missing) }
            if item.isLocked { issues.append(.locked) }
            if !item.parentWritable { issues.append(.noPermission) }
            if let problem = RenameRules.problem(for: rows[i].newName) { issues.append(.name(problem)) }
            if isInsideChanging(item.path, changing: changingPaths) { issues.append(.insideRenamedItem) }
            let key = RenameRules.nameKey(rows[i].newName)
            if (newNameCount[folder + "\u{0}" + key] ?? 0) > 1 {
                issues.append(.duplicateInBatch)
            } else if occupiedByFolder[folder]?.contains(key) == true {
                issues.append(.existsInFolder)
            }
            rows[i].issues = issues
        }
        return Plan(rows: rows)
    }

    /// Walks `path`'s ancestors (not `path` itself) looking for one that is renamed in the same batch — O(depth) per
    /// item, so a 10 000-item selection is not 10 000² path compares.
    static func isInsideChanging(_ path: String, changing: Set<String>) -> Bool {
        var current = (path as NSString).standardizingPath
        while true {
            let parent = (current as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != current else { return false }
            if changing.contains(parent) { return true }
            current = parent
        }
    }

    // MARK: - Execute (two phases)

    struct Outcome: Equatable, Sendable {
        /// Pairs that ended at their new name (empty when the batch was rolled back).
        var renamed: [Pair]
        /// The item and errno that stopped the batch; nil on success.
        var failedPath: String?
        var failedErrno: Int32?
        /// Items that could not be put back after a failure — still at their temporary name (must be reported).
        var stranded: [String]

        struct Pair: Equatable, Sendable { var from: String; var to: String }
        var succeeded: Bool { failedPath == nil }
    }

    /// Renames every `from` to a temporary sibling, then every temporary to its `to`; any failure undoes what was done
    /// in reverse order. `rename` returns 0 or an errno (injected so tests can fail a chosen step).
    static func execute(_ pairs: [(from: String, to: String)], token: String = UUID().uuidString,
                        rename: (String, String) -> Int32 = BatchRenameRules.renameExclusive) -> Outcome {
        let temps: [String] = pairs.enumerated().map { index, pair in
            ((pair.from as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("\(RenameRules.reservedPrefix)rename-\(token)-\(index)")
        }
        var stranded: [String] = []

        // Phase 1: sources → temporary names.
        for i in pairs.indices {
            let err = rename(pairs[i].from, temps[i])
            if err != 0 {
                for j in (0..<i).reversed() where rename(temps[j], pairs[j].from) != 0 { stranded.append(temps[j]) }
                return Outcome(renamed: [], failedPath: pairs[i].from, failedErrno: err, stranded: stranded)
            }
        }
        // Phase 2: temporary names → new names.
        for i in pairs.indices {
            let err = rename(temps[i], pairs[i].to)
            if err != 0 {
                // Back to temporaries first, so every original name is free again, then back to the originals.
                for j in (0..<i).reversed() where rename(pairs[j].to, temps[j]) != 0 { stranded.append(pairs[j].to) }
                for j in pairs.indices.reversed() where !stranded.contains(pairs[j].to) {
                    if rename(temps[j], pairs[j].from) != 0 { stranded.append(temps[j]) }
                }
                return Outcome(renamed: [], failedPath: pairs[i].from, failedErrno: err, stranded: stranded)
            }
        }
        return Outcome(renamed: pairs.map { Outcome.Pair(from: $0.from, to: $0.to) }, failedPath: nil, failedErrno: nil,
                       stranded: [])
    }

    // MARK: - The old Batch Rename page (Q-T37-5: "fix the bugs, update the features")

    /// The page keeps its own modes (prefix, suffix, replace, numbering with separator and digits, case changes) and
    /// gains Format; names are then validated, executed and undone exactly like the browser sheet's.
    enum PageMode: String, CaseIterable, Sendable { case prefix, suffix, replace, sequence, lowercase, uppercase, format }

    struct PageOptions: Equatable, Sendable {
        var mode: PageMode = .prefix
        var affix: String = ""
        var find: String = ""
        var replaceWith: String = ""
        var sequenceStart: Int = 1
        var sequenceDigits: Int = 2
        var sequenceSeparator: String = "_"
        var keepExtension: Bool = true
        /// Format mode's fields (style, position, custom name, start number).
        var format: Options = Options(mode: .format)
    }

    static func pageName(for item: Item, index: Int, options: PageOptions, calendar: Calendar, dateConnector: String) -> String {
        if options.mode == .format {
            return newName(for: item, index: index, options: options.format, calendar: calendar, dateConnector: dateConnector)
        }
        let name = (item.path as NSString).lastPathComponent
        let (stemPart, ext) = RenameRules.splitExtension(name, isFolder: item.isFolder)
        var stem = stemPart
        switch options.mode {
        case .prefix: stem = options.affix + stem
        case .suffix: stem += options.affix
        case .replace:
            if !options.find.isEmpty { stem = stem.replacingOccurrences(of: options.find, with: options.replaceWith) }
        case .sequence:
            let number = String(max(0, options.sequenceStart) + index)
            let width = min(max(1, options.sequenceDigits), 9)
            stem += options.sequenceSeparator + String(repeating: "0", count: max(0, width - number.count)) + number
        case .lowercase: stem = stem.lowercased()
        case .uppercase: stem = stem.uppercased()
        case .format: break
        }
        // "Giữ phần mở rộng" off drops the extension, as the page always did.
        return (options.keepExtension && !ext.isEmpty) ? "\(stem).\(ext)" : stem
    }

    static func pagePlan(items: [Item], options: PageOptions, siblings: (String) -> Set<String>?, calendar: Calendar,
                         dateConnector: String) -> Plan {
        if options.mode == .format {
            return plan(items: items, options: options.format, siblings: siblings, calendar: calendar, dateConnector: dateConnector)
        }
        let names = items.indices.map { pageName(for: items[$0], index: $0, options: options, calendar: calendar, dateConnector: dateConnector) }
        return validate(items: items, newNames: names, siblings: siblings)
    }

    // MARK: - Disk facts (read once, off the main thread)

    /// Existence, folder-vs-file (a package counts as a file — "MyApp.app" has an extension), modification date, the
    /// user-immutable flag, whether the parent is writable, and each parent's names straight from `readdir`.
    static func readFacts(_ paths: [String]) -> (items: [Item], siblings: [String: Set<String>]) {
        var loaded: [Item] = []
        var names: [String: Set<String>] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey,
                                                           .isUserImmutableKey])
            var info = stat()
            let exists = lstat(path, &info) == 0
            let parent = (path as NSString).deletingLastPathComponent
            if names[parent] == nil { names[parent] = directoryNames(parent) ?? [] }
            let seconds = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
            loaded.append(Item(
                path: path,
                isFolder: (values?.isDirectory ?? false) && !(values?.isPackage ?? false),
                modified: values?.contentModificationDate ?? Date(timeIntervalSince1970: seconds),
                exists: exists,
                isLocked: values?.isUserImmutable ?? false,
                parentWritable: access(parent, W_OK) == 0
            ))
        }
        return (loaded, names)
    }

    // MARK: - One item (inline rename, Get Info, New Folder)

    enum SingleResult: Equatable, Sendable {
        case renamed(String)
        case unchanged
        case rejected(key: String)
    }

    /// The rename every one-item path uses. Leading/trailing whitespace is trimmed (a typed name, not a format).
    /// A case-only change is allowed; another item with the same name is never replaced (`RENAME_EXCL`), so there is
    /// no `fileExists` pre-check to race with or to misread as a conflict.
    static func renameOne(_ path: String, to typedName: String,
                          rename: (String, String) -> Int32 = BatchRenameRules.renameExclusive) -> SingleResult {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = RenameRules.problem(for: name) { return .rejected(key: problem.key) }
        guard name != (path as NSString).lastPathComponent else { return .unchanged }
        let destination = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
        switch rename(path, destination) {
        case 0: return .renamed(destination)
        case EEXIST, ENOTEMPTY: return .rejected(key: Issue.existsInFolder.key)
        case EACCES: return .rejected(key: Issue.noPermission.key)
        case EPERM: return .rejected(key: Issue.locked.key)
        case ENOENT: return .rejected(key: Issue.missing.key)
        case ENAMETOOLONG: return .rejected(key: RenameRules.Problem.tooLong.key)
        default: return .rejected(key: "Không đổi được tên")
        }
    }

    /// Names in `folder` straight from `readdir` — FileManager's listing hides regular files named `._*` on macOS 27
    /// (CLAUDE.md §6), and a hidden name is still a name a rename can collide with. nil = unreadable.
    static func directoryNames(_ folder: String) -> Set<String>? {
        guard let dir = opendir(folder) else { return nil }
        defer { closedir(dir) }
        var names = Set<String>()
        while let entry = readdir(dir) {
            let name: String = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                let bytes = raw.bindMemory(to: UInt8.self).prefix(Int(entry.pointee.d_namlen))
                return String(decoding: bytes, as: UTF8.self)
            }
            if name != ".", name != ".." { names.insert(name) }
        }
        return names
    }

    /// `renamex_np(RENAME_EXCL)`: atomic, never replaces another item, and allows a case-only change of the same item
    /// (measured 2026-11-08: "report.txt" → "rEport.txt" succeeds, "rEport.txt" → "OTHER.txt" over "other.txt" fails
    /// with EEXIST).
    static func renameExclusive(_ from: String, _ to: String) -> Int32 {
        renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
    }
}
