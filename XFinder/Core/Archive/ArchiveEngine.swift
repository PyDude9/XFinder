import Foundation

/// Pure planning for every archive operation in the app — the Nén & Giải nén page, the Khay thả
/// "Nén ZIP" button, Thao tác Finder's ZIP, and the Notch hub. No `Process` runs here; this file
/// decides names, destinations and exact command lines, so all of it is unit-tested.
///
/// It exists because three call sites hand-rolled `ditto -c -k --keepParent src… dst`, and measured
/// on macOS 27 **ditto refuses more than one source** ("Can't archive multiple sources", exit 1) —
/// so zipping two or more items failed everywhere. The `zip` fallback was worse: it ran from the
/// FIRST source's folder with bare names, so a file from another folder was skipped with only a
/// "name not matched" warning and **exit 0** — a "successful" archive missing data.
enum ArchiveEngine {

    enum Format: String, CaseIterable {
        case zip, tarGz
        var fileExtension: String { self == .zip ? "zip" : "tar.gz" }
    }

    /// What to do when the output already exists.
    enum ConflictPolicy: String, CaseIterable {
        /// "Report.zip" → "Report 2.zip", "Report 3.zip"…
        case keepBoth
        /// Stop and let the user choose; the engine never decides for them.
        case ask
        /// Extraction only: put the contents into the existing folder, replacing same-named files.
        case merge
    }

    enum Destination: Equatable {
        case write(URL)
        /// `.ask` hit an existing item; the caller must ask before anything touches the disk.
        case needsDecision(existing: URL)
    }

    static let defaultLevel = 6

    // MARK: Names

    /// A file-system-safe archive name: trimmed, "/" and ":" removed, never empty.
    static func archiveName(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Archive" : cleaned
    }

    /// "Report.pdf" → "Report 2.pdf"; "Folder" → "Folder 2"; "a.tar.gz" → "a 2.tar.gz".
    static func numbered(_ name: String, _ n: Int) -> String {
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where name.lowercased().hasSuffix(compound) && name.count > compound.count {
            return "\(name.dropLast(compound.count)) \(n)\(name.suffix(compound.count))"
        }
        let ns = name as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty, ns.deletingPathExtension.isEmpty == false else { return "\(name) \(n)" }
        return "\(ns.deletingPathExtension) \(n).\(ext)"
    }

    /// Top-level names inside the archive, one per source, in order. Each keeps its own name; a
    /// collision (two "Report.pdf" from different folders) gets " 2", " 3" — so nothing overwrites.
    static func entryNames(for sources: [URL]) -> [String] {
        var used = Set<String>()
        return sources.map { url in
            let base = url.lastPathComponent
            var candidate = base, n = 2
            while used.contains(candidate.lowercased()) { candidate = numbered(base, n); n += 1 }
            used.insert(candidate.lowercased())    // APFS is case-insensitive by default
            return candidate
        }
    }

    /// Output path under a conflict policy. Never loops on itself (the old `.ask` branch recursed
    /// with the same arguments forever — a stack overflow the moment the name already existed).
    static func destination(base: URL, policy: ConflictPolicy, exists: (URL) -> Bool) -> Destination {
        guard exists(base) else { return .write(base) }
        switch policy {
        case .merge: return .write(base)
        case .ask: return .needsDecision(existing: base)
        case .keepBoth:
            let dir = base.deletingLastPathComponent(), name = base.lastPathComponent
            var n = 2
            while true {
                let candidate = dir.appendingPathComponent(numbered(name, n))
                if !exists(candidate) { return .write(candidate) }
                n += 1
            }
        }
    }

    // MARK: Commands

    struct Command: Equatable {
        var executable: String
        var arguments: [String]
        var currentDirectory: URL?
        var environment: [String: String] = [:]
        /// Where stdout goes when the caller needs it (a file, so it can never fill and block); nil discards it.
        var stdoutFile: URL? = nil
    }

    /// Expected top-level names that a `unzip -Z1` listing does not contain ("folder/x" counts for "folder").
    static func missingTopLevelEntries(expected: [String], listing: String) -> [String] {
        let present = Set(listing.split(separator: "\n").compactMap { line -> String? in
            let first = line.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first
            return first.map { String($0).lowercased() }
        })
        return expected.filter { !present.contains($0.lowercased()) }
    }

    /// What the one source of a single-source ZIP is. It decides how `ditto` is called, because `ditto` treats the
    /// three differently (measured 2026-11-08): `--keepParent` stores a FOLDER as `folder/…` (wanted) but a FILE
    /// under its parent folder's name (`parent/one.txt` — the read-back then missed `one.txt` and every one-file ZIP
    /// "failed" since `0a184ba`), and a symlinked source is followed and stored under the TARGET's name.
    enum SingleSource: Equatable { case file, directory, link }

    /// One source (not a link), ZIP, default level, no password ⇒ `ditto`, which keeps macOS metadata (resource
    /// forks, extended attributes). Everything else is presented through a staging folder of symlinks named by
    /// `entryNames` and archived from there — zip and tar follow the links, so a linked source keeps its own name.
    static func needsStaging(sourceCount: Int, format: Format, level: Int, hasPassword: Bool,
                             single: SingleSource) -> Bool {
        !(format == .zip && sourceCount == 1 && level == defaultLevel && !hasPassword && single != .link)
    }

    /// The ZIP password goes in `ZIPOPT`, not argv: on macOS every user can read any process's
    /// arguments with `ps`, while the environment is readable only by the same user or root.
    /// Measured: passwords with spaces, `"` and `'` round-trip through this quoting.
    static func zipOptPassword(_ password: String) -> String {
        let escaped = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "-P \"\(escaped)\""
    }

    static func compressCommand(sources: [URL], format: Format, level: Int, password: String?,
                                output: URL, stagingDir: URL?, single: SingleSource) -> Command {
        let hasPassword = !(password ?? "").isEmpty
        if !needsStaging(sourceCount: sources.count, format: format, level: level, hasPassword: hasPassword,
                         single: single),
           let only = sources.first {
            // A folder keeps its own name as the top level only with `--keepParent`; a file keeps it only without.
            let keepParent = single == .directory ? ["--keepParent"] : []
            return Command(executable: "/usr/bin/ditto",
                           arguments: ["-c", "-k", "--sequesterRsrc"] + keepParent + [only.path, output.path],
                           currentDirectory: nil)
        }
        let names = entryNames(for: sources)
        switch format {
        case .zip:
            var env: [String: String] = [:]
            if hasPassword, let password { env["ZIPOPT"] = zipOptPassword(password) }
            let lvl = min(max(level, 0), 9)
            return Command(executable: "/usr/bin/zip",
                           arguments: ["-r", "-\(lvl)", "-q", output.path] + names,
                           currentDirectory: stagingDir, environment: env)
        case .tarGz:
            // -h: follow the staging symlinks, store the real files.
            return Command(executable: "/usr/bin/tar", arguments: ["-czhf", output.path] + names,
                           currentDirectory: stagingDir)
        }
    }

    /// `.zip` ⇒ `ditto -x -k`; anything else ⇒ `tar -xf`. bsdtar detects gzip / bzip2 / xz / plain
    /// tar by content on extraction (measured: plain .tar and .tar.bz2 both extract), so the
    /// extension only has to tell ZIP apart.
    static func extractCommand(archive: URL, into dir: URL) -> Command {
        if archive.pathExtension.lowercased() == "zip" {
            return Command(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, dir.path], currentDirectory: nil)
        }
        return Command(executable: "/usr/bin/tar", arguments: ["-xf", archive.path, "-C", dir.path], currentDirectory: nil)
    }

    /// The folder an archive is extracted into when "new folder beside the archive" is chosen:
    /// "Photos.zip" → "Photos", "a.tar.gz" → "a".
    static func folderName(forArchive archive: URL) -> String {
        let name = archive.lastPathComponent
        for ext in [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".zip", ".tar", ".gz", ".bz2"]
        where name.lowercased().hasSuffix(ext) && name.count > ext.count {
            return String(name.dropLast(ext.count))
        }
        return (name as NSString).deletingPathExtension
    }

    /// Where each extracted top-level item goes under **Keep Both**: names chosen earlier in the same
    /// batch count as taken (so "a" and "a 2" from one archive cannot both be renamed onto "a 2").
    ///
    /// Kept as the Keep Both shape of the same plan `mergePlan` produces, so there is exactly one
    /// collision decision in the app rather than two that can drift.
    static func placements(items: [String], into dir: URL, policy: ConflictPolicy,
                           exists: (URL) -> Bool) -> [(name: String, destination: Destination)] {
        mergePlan(items: items.map { StagedItem(path: $0, isDirectory: false) }, into: dir) { url in
            exists(url) ? .file : nil
        }.map { step in
            (name: step.source, destination: .write(step.target))
        }
    }

    /// Symlinks inside an extracted archive that point OUT of it: an absolute target, or a relative one
    /// that climbs above the archive root. `ditto -x` and `tar -x` keep them verbatim, and a merge then
    /// copies them into the user's folder — replacing a real file and aliasing an outside path for
    /// every later write (B2a review, reproduced end to end). `links` are (path relative to the
    /// extraction root, raw link target). Returns the offending relative paths.
    static func escapingLinks(_ links: [(path: String, target: String)]) -> [String] {
        links.compactMap { link in
            if link.target.hasPrefix("/") || link.target.hasPrefix("~") { return link.path }
            var depth = link.path.split(separator: "/").count - 1      // directories the link sits in
            for part in link.target.split(separator: "/") {
                if part == ".." { depth -= 1; if depth < 0 { return link.path } }
                else if part != "." { depth += 1 }
            }
            return nil
        }
    }

    // MARK: Recursive merge (stage 03C)

    /// What is already at a candidate destination path.
    enum ExistingItem: Equatable {
        case file
        /// A symbolic link is never merged into and never replaced: it is treated as an ordinary
        /// occupied name, so the incoming item gets a numbered name instead (spec §5).
        case link
        case directory
    }

    /// One object inside the staging folder, as the plan needs to see it.
    struct StagedItem: Equatable {
        var path: String
        var isDirectory: Bool
    }

    /// Where one staged object goes.
    ///
    /// `renamed` is true when this object — or any folder above it in the same batch — received a
    /// numbered name, i.e. its *path* is not the one the archive declared. `renamedHere` is true only
    /// when this object's **own** name changed. The result line uses `renamedHere` (a child that
    /// inherited a renamed folder did not itself get renamed, and saying so would describe something
    /// the user never sees); `renamed` describes the path and is kept for callers that need it.
    struct MergeStep: Equatable {
        var source: String
        var target: URL
        var isDirectory: Bool
        var renamed: Bool
        var renamedHere: Bool
    }

    /// Plan a **combining** merge: folders join, colliding leaves are numbered instead of replaced.
    ///
    /// This is the approved semantic change (Boss decision 1). The old Merge replaced every
    /// same-named leaf — measured in the spec (§2: `folder/same.txt` `OLD` → `NEW`), which is data
    /// loss the user never confirmed. Numbering keeps both, and "Report 2.pdf" preserves the
    /// extension because `numbered` already handles compound ones.
    ///
    /// Pure on purpose: `existing` answers "what is at this path" and nothing here touches the disk,
    /// so every collision shape (file/file, file/folder, folder/file, link) is unit-testable.
    /// `items` must be the staged tree; parents are planned before their children.
    static func mergePlan(items: [StagedItem], into destination: URL,
                          existing: (URL) -> ExistingItem?) -> [MergeStep] {
        let ordered = items.sorted { lhs, rhs in
            let ld = lhs.path.split(separator: "/").count, rd = rhs.path.split(separator: "/").count
            return ld == rd ? lhs.path < rhs.path : ld < rd
        }
        var mappedFolder: [String: String] = [:]          // incoming folder → folder actually used
        var claimed = Set<String>()                       // lowercased absolute paths this batch took
        var steps: [MergeStep] = []

        for item in ordered {
            let components = item.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            let parentPath = components.dropLast().joined(separator: "/")
            let parent = parentPath.isEmpty ? nil : (mappedFolder[parentPath] ?? parentPath)
            let name = components.last!
            let baseName = parent.map { "\($0)/\(name)" } ?? name
            var relative = baseName
            var inheritedRename = parent != nil && mappedFolder[parentPath] != parentPath
            var renamedHere = false
            var target = destination.appendingPathComponent(relative)

            // Decide what happens at this name. A folder over a folder combines; anything else that is
            // already taken — including a link, and including a name this batch already claimed —
            // moves the incoming object to a numbered name.
            var n = 2
            while true {
                let taken = existing(target) != nil || claimed.contains(target.path.lowercased())
                let combines = item.isDirectory && existing(target) == .directory
                if !taken || combines { break }
                let numberedName = numbered(name, n)
                relative = parent.map { "\($0)/\(numberedName)" } ?? numberedName
                target = destination.appendingPathComponent(relative)
                renamedHere = true
                n += 1
                // A hostile/exhausted volume must not make planning spin forever, and after this many
                // collisions the numbered names are not a promise worth keeping — a unique suffix is,
                // and exclusive publication still refuses to replace anything.
                if n > 10_000 {
                    let unique = "\(name) \(UUID().uuidString.prefix(8))"
                    relative = parent.map { "\($0)/\(unique)" } ?? unique
                    target = destination.appendingPathComponent(relative)
                    renamedHere = true
                    break
                }
            }
            claimed.insert(target.path.lowercased())
            if item.isDirectory { mappedFolder[item.path] = relative }
            steps.append(MergeStep(source: item.path, target: target, isDirectory: item.isDirectory,
                                   renamed: inheritedRename || renamedHere, renamedHere: renamedHere))
        }
        return steps
    }

    /// The result line names what was actually renamed, so "merge" never reads as "replaced".
    ///
    /// Reports an object only when its **own** name changed. A child of a renamed folder inherits that
    /// folder's name and did not itself get renamed, so listing it would describe something the user
    /// never sees (`Photos 2/a.txt` is not "a.txt was renamed"). An object that was numbered inside a
    /// renamed folder *was* renamed and is listed — both names are true there.
    static func renamedLeafNames(_ steps: [MergeStep]) -> [String] {
        steps.filter(\.renamedHere).map { $0.target.lastPathComponent }
    }

    /// The Ask dialog's choices and its default. Default **Cancel** is a Boss decision (approval
    /// point 1): a collision prompt that defaults to a write is a write the user did not choose.
    enum AskChoice: String, CaseIterable {
        case keepBoth, merge, cancel

        static let all: [AskChoice] = [.keepBoth, .merge, .cancel]
        static let defaultChoice: AskChoice = .cancel

        /// The order the alert shows its buttons: the approved default first, then the rest in their
        /// usual order. The page builds its buttons from this, so the default is defined once here
        /// instead of being restated by whoever writes the alert code.
        static var buttonOrder: [AskChoice] {
            [defaultChoice] + all.filter { $0 != defaultChoice }
        }
    }

    /// A stderr line that means data was left out even though the tool exited 0.
    static func stderrSignalsMissingData(_ stderr: String) -> Bool {
        stderr.contains("name not matched") || stderr.contains("Cannot stat") || stderr.contains("No such file")
    }
}
