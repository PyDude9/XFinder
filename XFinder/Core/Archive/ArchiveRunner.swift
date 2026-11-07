import Foundation
import os

/// Runs the commands `ArchiveEngine` plans. Foundation-only (Process + FileManager), so the test
/// package exercises it against the real `ditto`, `zip` and `tar` in temporary folders.
///
/// Three rules, each a bug that shipped before:
/// * stderr is read BEFORE `waitUntilExit()` — an unread full pipe blocks the child forever;
/// * exit 0 is not success when stderr says a source was skipped (`zip` does exactly that);
/// * extraction never writes into the destination directly — it lands in a staging folder on the
///   same volume and is placed item by item under the conflict policy, so nothing is overwritten
///   unless the user chose to merge.
///
/// Stage 03B adds ownership: a temporary folder is recorded when the job creates it (device + inode)
/// and cleanup refuses to remove anything that is no longer that very directory. A caller-supplied
/// output that already existed is never deleted merely because a tool failed on it.
enum ArchiveRunner {

    struct ProcessResult: Equatable {
        var status: Int32
        var stderr: String
    }

    enum Failure: Error, Equatable {
        case nothingToDo
        /// A source no longer exists. Checked up front because zip and tar both exit 0 and say
        /// nothing when a (staged) source is missing — measured, with and without `-q`.
        case missingSource([String])
        case staging(String)
        /// The tool exited non-zero; `stderr` is the tool's own text.
        case tool(status: Int32, stderr: String)
        /// The tool exited 0 but reported skipped input — the archive would be missing data.
        case missingData(stderr: String)
        case cancelled
        case placement(String)
        /// The archive holds symlinks that point outside it; nothing was placed.
        case unsafeLinks([String])
    }

    // MARK: Process

    /// Runs `command` off the main thread. Cancelling the calling task terminates the child.
    ///
    /// The cancellation race this closes (measured): `pid` used to be published only after
    /// `try p.run()` returned. A cancel landing in that window ran `onCancel`, read pid 0, skipped
    /// `kill`, and the child then ran to completion with nobody left to stop it — a "cancelled"
    /// extraction that still wrote its output. Now cancellation is recorded first and the launching
    /// thread re-reads it after publishing the pid, so the two orders both terminate the child.
    static func run(_ command: ArchiveEngine.Command) async -> ProcessResult {
        let pid = OSAllocatedUnfairLock<pid_t>(initialState: 0)
        let cancelledEarly = OSAllocatedUnfairLock<Bool>(initialState: false)
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) { () -> ProcessResult in
                if Task.isCancelled { return ProcessResult(status: -2, stderr: "cancelled") }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: command.executable)
                p.arguments = command.arguments
                if let dir = command.currentDirectory { p.currentDirectoryURL = dir }
                if !command.environment.isEmpty {
                    p.environment = ProcessInfo.processInfo.environment.merging(command.environment) { $1 }
                }
                p.standardInput = FileHandle.nullDevice
                if let file = command.stdoutFile, FileManager.default.createFile(atPath: file.path, contents: nil),
                   let handle = try? FileHandle(forWritingTo: file) {
                    p.standardOutput = handle            // a file, not a pipe: nothing to drain, cannot block
                } else {
                    p.standardOutput = FileHandle.nullDevice
                }
                let err = Pipe()
                p.standardError = err
                do { try p.run() } catch { return ProcessResult(status: -1, stderr: "\(error)") }
                // Publish, then re-check: `onCancel` may already have run with no pid to kill, and
                // that is exactly the window where the child would otherwise survive unattended.
                let identifier = p.processIdentifier
                pid.withLock { $0 = identifier }
                if cancelledEarly.withLock({ $0 }) || Task.isCancelled {
                    kill(identifier, SIGTERM)
                }
                let data = err.fileHandleForReading.readDataToEndOfFile()   // BEFORE wait
                p.waitUntilExit()
                return ProcessResult(status: p.terminationStatus, stderr: String(decoding: data, as: UTF8.self))
            }.value
        } onCancel: {
            cancelledEarly.withLock { $0 = true }
            let id = pid.withLock { $0 }
            if id > 0 { kill(id, SIGTERM) }
        }
    }

    // MARK: Ownership

    /// A directory this job created, pinned to the inode it had at creation.
    ///
    /// `URL` alone is not ownership: between creation and cleanup the path can be replaced (or the
    /// folder renamed and a new one created in its place), and `removeItem` would then delete
    /// something the job never made. The identity check is one `lstat`, taken only on the cleanup
    /// path, so it costs nothing on the happy path.
    struct OwnedDirectory: Equatable {
        let url: URL
        let device: UInt64
        let inode: UInt64

        /// Returns nil when the directory cannot be pinned — then the caller owns nothing and must
        /// not delete it later.
        static func adopt(_ url: URL) -> OwnedDirectory? {
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
            return OwnedDirectory(url: url, device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        }

        /// True only while this path is still the very directory creation produced.
        var isStillOwned: Bool {
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
            return UInt64(info.st_dev) == device && UInt64(info.st_ino) == inode
        }

        /// Removes the directory only if it is still the one we created. Returns whether it removed
        /// something, so a caller can distinguish "cleaned" from "left alone on purpose".
        @discardableResult
        func removeIfOwned() -> Bool {
            guard isStillOwned else { return false }
            do { try FileManager.default.removeItem(at: url); return true } catch { return false }
        }
    }

    // MARK: Compress

    /// `output` must already be resolved through `ArchiveEngine.destination` — the runner never
    /// picks names. A partial output is removed on failure **only when this job created it**: an
    /// output path that already existed when the call started is never deleted because a tool
    /// failed on it (measured before 03B: a failing compression into an existing directory removed
    /// the directory and its contents).
    static func compress(sources: [URL], format: ArchiveEngine.Format, level: Int = ArchiveEngine.defaultLevel,
                         password: String? = nil, output: URL) async -> Result<URL, Failure> {
        guard !sources.isEmpty else { return .failure(.nothingToDo) }
        let fm = FileManager.default
        let missing = sources.filter { !fm.fileExists(atPath: $0.path) }.map(\.lastPathComponent)
        guard missing.isEmpty else { return .failure(.missingSource(missing)) }
        // Snapshot before any tool runs: was there something at the output path already? If yes, the
        // job does not own it and must leave it exactly as it found it.
        let outputPreexisted = fm.fileExists(atPath: output.path)
        var staging: OwnedDirectory?
        defer { staging?.removeIfOwned() }
        // Only ever removes what the job produced: a path that was absent at entry and exists now.
        func removeOutputIfCreatedHere() {
            guard !outputPreexisted, fm.fileExists(atPath: output.path) else { return }
            try? fm.removeItem(at: output)
        }
        if ArchiveEngine.needsStaging(sourceCount: sources.count, format: format, level: level,
                                      hasPassword: !(password ?? "").isEmpty) {
            do {
                let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                     appropriateFor: output.deletingLastPathComponent(), create: true)
                staging = OwnedDirectory.adopt(dir)
                for (src, name) in zip(sources, ArchiveEngine.entryNames(for: sources)) {
                    try fm.createSymbolicLink(at: dir.appendingPathComponent(name), withDestinationURL: src)
                }
            } catch { return .failure(.staging("\(error)")) }
        }
        let command = ArchiveEngine.compressCommand(sources: sources, format: format, level: level,
                                                    password: password, output: output, stagingDir: staging?.url)
        let result = await run(command)
        if Task.isCancelled { removeOutputIfCreatedHere(); return .failure(.cancelled) }
        if result.status != 0 { removeOutputIfCreatedHere(); return .failure(.tool(status: result.status, stderr: result.stderr)) }
        if ArchiveEngine.stderrSignalsMissingData(result.stderr) {
            removeOutputIfCreatedHere(); return .failure(.missingData(stderr: result.stderr))
        }
        guard fm.fileExists(atPath: output.path) else { return .failure(.tool(status: 0, stderr: "no output written")) }
        // Read the ZIP's table of contents back (cheap: the central directory only) and require every
        // top-level entry — the tools' own exit codes have already lied once.
        if format == .zip {
            let expected = staging == nil ? [sources[0].lastPathComponent] : ArchiveEngine.entryNames(for: sources)
            let listFile = fm.temporaryDirectory.appendingPathComponent("xf-zip-list-\(UUID().uuidString).txt")
            defer { try? fm.removeItem(at: listFile) }
            var listCommand = ArchiveEngine.Command(executable: "/usr/bin/unzip", arguments: ["-Z1", output.path], currentDirectory: nil)
            listCommand.stdoutFile = listFile
            let listing = await run(listCommand)
            let text = (try? String(contentsOf: listFile, encoding: .utf8)) ?? ""
            let lost = ArchiveEngine.missingTopLevelEntries(expected: expected, listing: text)
            if listing.status != 0 || !lost.isEmpty {
                removeOutputIfCreatedHere()
                return .failure(.missingData(stderr: "not in the archive: \(lost.joined(separator: ", "))"))
            }
        }
        return .success(output)
    }

    // MARK: Extract

    /// An archive extracted into a private folder, not yet placed.
    ///
    /// `owned` is what makes cleanup safe: `staging` is only a path, and a path can be replaced
    /// between extraction and cleanup. Every removal goes through `owned`.
    struct ExtractedBatch: Equatable {
        let staging: URL
        let items: [String]
        let owned: OwnedDirectory

        static func == (lhs: ExtractedBatch, rhs: ExtractedBatch) -> Bool {
            lhs.staging == rhs.staging && lhs.items == rhs.items && lhs.owned == rhs.owned
        }
    }

    /// True only for a real directory whose permissions are exactly 0700.
    ///
    /// Extracted so it can be tested against a directory that is *not* private: the staging folder
    /// the system hands out is always 0700, so exercising the guard only through `extractToStaging`
    /// would never reach its refusal.
    static func isPrivateDirectory(_ url: URL) -> Bool {
        let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
        return permissions?.intValue == 0o700
    }

    /// Step 1: extract into a staging folder on `destination`'s volume (so placing is a rename).
    ///
    /// The staging root is created private (0700) and its identity is captured, so a later cleanup
    /// can prove it is removing the folder this job created and not something that took its place.
    static func extractToStaging(archive: URL, near destination: URL) async -> Result<ExtractedBatch, Failure> {
        let fm = FileManager.default
        let dir: URL
        do {
            dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        } catch { return .failure(.staging("\(error)")) }
        guard let owned = OwnedDirectory.adopt(dir) else { return .failure(.staging("staging is not a directory")) }
        // `itemReplacementDirectory` is documented to be private; assert it instead of trusting it,
        // because everything extracted below lands inside and a world-readable root would publish
        // the archive's contents to every user on the machine before the user placed it.
        guard Self.isPrivateDirectory(dir) else {
            owned.removeIfOwned()
            return .failure(.staging("staging directory is not private (0700)"))
        }
        let result = await run(ArchiveEngine.extractCommand(archive: archive, into: dir))
        if Task.isCancelled { owned.removeIfOwned(); return .failure(.cancelled) }
        guard result.status == 0 else {
            owned.removeIfOwned(); return .failure(.tool(status: result.status, stderr: result.stderr))
        }
        // ditto -x -k leaves a __MACOSX folder only for archives made elsewhere; it is resource-fork
        // debris, never user content.
        // Refuse the whole archive if any link inside it escapes — before a single item is placed.
        var links: [(path: String, target: String)] = []
        if let walker = fm.enumerator(atPath: dir.path) {
            while let rel = walker.nextObject() as? String {
                if let target = try? fm.destinationOfSymbolicLink(atPath: dir.appendingPathComponent(rel).path) {
                    links.append((rel, target))
                }
            }
        }
        let escaping = ArchiveEngine.escapingLinks(links)
        guard escaping.isEmpty else { owned.removeIfOwned(); return .failure(.unsafeLinks(escaping.sorted())) }
        let items = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "__MACOSX" && $0 != ".DS_Store" }.sorted()
        return .success(ExtractedBatch(staging: dir, items: items, owned: owned))
    }

    /// Names in the batch that already exist in `destination` — what an `.ask` prompt must list.
    static func conflicts(_ batch: ExtractedBatch, in destination: URL) -> [String] {
        batch.items.filter { FileManager.default.fileExists(atPath: destination.appendingPathComponent($0).path) }
    }

    /// The first path component **below `base`** that is a symbolic link, or nil.
    ///
    /// Measured (spec §2): with `dest/folder` a symlink to another directory, Merge reported success
    /// and wrote `outside/same.txt`. Existence checks alone cannot see this — `fileExists` follows the
    /// link and reports the target.
    ///
    /// Only components below `base` are checked, on purpose: `base` is the destination the user chose
    /// (NSOpenPanel, Downloads, "beside the archive"), and macOS itself spells `/var` and `/tmp` as
    /// symlinks, so walking from `/` would refuse every ordinary temporary folder. What must never be
    /// followed is a link the *archive* would write through.
    static func symlinkedComponent(of target: URL, under base: URL) -> URL? {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        guard targetComponents.count >= baseComponents.count,
              Array(targetComponents.prefix(baseComponents.count)) == baseComponents else { return nil }
        var current = base.standardizedFileURL
        for component in targetComponents.dropFirst(baseComponents.count) {
            current.appendPathComponent(component)
            var info = stat()
            guard lstat(current.path, &info) == 0 else { return nil }   // nothing here yet: safe
            if (info.st_mode & S_IFMT) == S_IFLNK { return current }
        }
        return nil
    }

    /// Step 2: move the items into `destination`. `.keepBoth` renames, `.merge` replaces files and
    /// merges folders. `.ask` must be resolved by the caller first — passing it places nothing that
    /// conflicts. The staging folder is removed afterwards, and only if it is still this job's.
    static func place(_ batch: ExtractedBatch, into destination: URL,
                      policy: ArchiveEngine.ConflictPolicy) async -> Result<[URL], Failure> {
        let fm = FileManager.default
        defer { batch.owned.removeIfOwned() }
        // A symlinked destination (or a symlinked component of it) is refused outright: writing
        // through it would put the user's data somewhere they never chose, and Merge would follow it
        // silently — that exact case was measured writing outside the chosen folder.
        if let link = symlinkedComponent(of: destination, under: destination.deletingLastPathComponent()) {
            return .failure(.placement("destination path component is a symbolic link: \(link.path)"))
        }
        do { try fm.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch { return .failure(.placement("\(error)")) }
        var placed: [URL] = []
        let plan = ArchiveEngine.placements(items: batch.items, into: destination, policy: policy,
                                            exists: { fm.fileExists(atPath: $0.path) })
        for (name, d) in plan {
            guard case .write(let target) = d else { continue }       // an unresolved .ask conflict
            let src = batch.staging.appendingPathComponent(name)
            // Re-checked per target: the plan was computed from snapshots, and a link appearing at a
            // target's own path between the plan and the write must not be followed either.
            if let link = symlinkedComponent(of: target, under: destination) {
                return .failure(.placement("destination path component is a symbolic link: \(link.path)"))
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: target.path, isDirectory: &isDir) {
                // Only reachable under .merge: folders merge (ditto copies into the existing tree,
                // replacing same-named files); a file replaces the file.
                if isDir.boolValue {
                    let r = await run(ArchiveEngine.Command(executable: "/usr/bin/ditto", arguments: [src.path, target.path], currentDirectory: nil))
                    guard r.status == 0 else { return .failure(.placement(r.stderr)) }
                } else {
                    do { _ = try fm.replaceItemAt(target, withItemAt: src) } catch { return .failure(.placement("\(error)")) }
                }
            } else {
                do { try fm.moveItem(at: src, to: target) } catch { return .failure(.placement("\(error)")) }
            }
            placed.append(target)
        }
        return .success(placed)
    }

    static func discard(_ batch: ExtractedBatch) {
        batch.owned.removeIfOwned()
    }
}

extension ArchiveRunner.Failure {
    /// Store key for the user-facing sentence; the view calls `L10n.t` on it (a model returns KEYS,
    /// never display text — CLAUDE.md, language leak #6). `detail` is the tool's own words or the
    /// names involved, shown verbatim on a second line.
    var messageKey: String {
        switch self {
        case .nothingToDo: return "Chưa chọn gì để xử lý."
        case .missingSource: return "Một số mục không còn tồn tại nên chưa nén gì."
        case .staging: return "Không chuẩn bị được thư mục tạm."
        case .tool: return "Công cụ nén của macOS báo lỗi."
        case .missingData: return "Tệp nén thiếu dữ liệu nên đã bị xoá."
        case .cancelled: return "Đã hủy."
        case .placement: return "Không đặt được tệp đã giải nén vào thư mục đích."
        case .unsafeLinks: return "Tệp nén chứa liên kết trỏ ra ngoài nên đã bị từ chối, không giải nén gì: "
        }
    }

    var detail: String? {
        switch self {
        case .missingSource(let names), .unsafeLinks(let names): return names.joined(separator: ", ")
        case .staging(let s), .placement(let s): return s
        case .tool(_, let stderr), .missingData(let stderr): return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        case .nothingToDo, .cancelled: return nil
        }
    }

    /// One value of every case — lets a test resolve every key against the shipped store.
    static let examples: [ArchiveRunner.Failure] = [
        .nothingToDo, .missingSource(["a"]), .staging("x"), .tool(status: 1, stderr: "x"),
        .missingData(stderr: "x"), .cancelled, .placement("x"), .unsafeLinks(["a"]),
    ]
}
