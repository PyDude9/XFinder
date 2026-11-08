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
        /// The archive itself was refused before anything was written (hostile entry path, duplicate
        /// or aliased name, unsupported entry, link graph problem, safety limit, unreadable format).
        /// `reasons` are the rules' verdicts; `diagnostic` is the reader's technical text, shown on
        /// the detail line and never as the sentence.
        case unsafeArchive(reasons: [ArchiveSafetyRules.Reason], diagnostic: String?)
        /// Not enough free space for the reviewed plan; nothing was written.
        case outOfSpace(required: Int64, available: Int64)
        /// The archive changed between inspection and extraction, so the plan no longer describes the
        /// bytes on disk. Nothing was placed.
        case archiveChanged(String)
        /// The system reader is not usable here (missing libarchive symbols or an unregistered format),
        /// so the archive cannot be checked and is refused rather than extracted unverified.
        case readerUnavailable
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
    /// The archive is **inspected and validated before anything is written**: the system reader walks
    /// the raw entry table (no extraction), the pure rules accept or refuse the whole manifest, and
    /// only then does a decoder run. Measured before 03B: `ditto` silently normalised `../escaped.txt`
    /// and a leading `/`, and two entries named `same.txt` overwrote one another inside staging, so
    /// validating after materialisation could not refuse what had already happened.
    static func extractToStaging(archive: URL, near destination: URL) async -> Result<ExtractedBatch, Failure> {
        guard SystemArchiveReader.isAvailable else { return .failure(.readerUnavailable) }
        let inspection: SystemArchiveReader.Inspection
        do {
            inspection = try SystemArchiveReader().inspect(at: archive)
        } catch let failure as SystemArchiveReader.Failure {
            return .failure(Self.map(failure))
        } catch {
            return .failure(.staging("\(error)"))
        }
        return await extractVerified(archive: archive, inspection: inspection, near: destination)
    }

    /// The half of `extractToStaging` that runs after inspection, split out so the identity guards can
    /// be exercised deterministically: a test can inspect, replace the file, and hand the now-stale
    /// inspection to this function. Without the split the swap window would be microseconds wide and
    /// the guard could not be proven to be wired at all.
    static func extractVerified(archive: URL,
                                inspection: SystemArchiveReader.Inspection,
                                near destination: URL) async -> Result<ExtractedBatch, Failure> {
        let fm = FileManager.default

        let verdict = ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                  compressedSize: inspection.archiveBytes,
                                                  availableBytes: Self.availableBytes(for: destination))
        switch verdict {
        case .rejected(let reasons):
            // Space problems get their own sentence: "the archive is unsafe" would mis-describe a
            // perfectly ordinary archive on a full disk, and the remedy is different.
            if let space = Self.spaceFailure(from: reasons) { return .failure(space) }
            return .failure(.unsafeArchive(reasons: reasons, diagnostic: nil))
        case .accepted:
            break
        }

        // Only now create the staging root and let a decoder write into it.
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
        // (3) The bytes must still be the ones the manifest describes. The reader bound identity from
        // the descriptor it read; a swap between inspection and extraction would make the validated
        // manifest describe a different archive, so extraction refuses instead of proceeding.
        guard Self.identityStillMatches(inspection.identity, at: archive) else {
            owned.removeIfOwned()
            return .failure(.archiveChanged("the archive changed after it was inspected"))
        }
        let result = await run(ArchiveEngine.extractCommand(archive: archive, into: dir))
        return Self.finishExtraction(archive: archive, inspection: inspection, dir: dir, owned: owned, result: result)
    }

    /// Everything after the decoder ran, split out for the same reason as `extractVerified`: the window
    /// "the tool ran, then the archive changed" is microseconds wide in a real run, so a test that wants
    /// to prove the second identity check is wired has to be able to stand exactly there.
    static func finishExtraction(archive: URL,
                                 inspection: SystemArchiveReader.Inspection,
                                 dir: URL,
                                 owned: OwnedDirectory,
                                 result: ProcessResult) -> Result<ExtractedBatch, Failure> {
        let fm = FileManager.default
        if Task.isCancelled { owned.removeIfOwned(); return .failure(.cancelled) }
        guard result.status == 0 else {
            owned.removeIfOwned(); return .failure(.tool(status: result.status, stderr: result.stderr))
        }
        // (4) Revalidate once more: a tool that ran for a while is exactly when a swap would pay off.
        guard Self.identityStillMatches(inspection.identity, at: archive) else {
            owned.removeIfOwned()
            return .failure(.archiveChanged("the archive changed while it was being extracted"))
        }
        // ditto -x -k leaves a __MACOSX folder only for archives made elsewhere; it is resource-fork
        // debris, never user content.
        // Second layer, kept from 03A: whatever the decoder actually produced must not contain a link
        // that escapes. The manifest check above already refuses these before writing; this catches a
        // decoder that materialises a link the manifest did not describe.
        let escaping = Self.escapingLinks(in: dir)
        guard escaping.isEmpty else { owned.removeIfOwned(); return .failure(.unsafeLinks(escaping)) }
        let items = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "__MACOSX" && $0 != ".DS_Store" }.sorted()
        return .success(ExtractedBatch(staging: dir, items: items, owned: owned))
    }

    /// Every link inside `dir` whose target leaves it, sorted — the stage 03A second layer, split out
    /// so it can be tested against a staging folder built by hand.
    ///
    /// The walk must see names starting with `._`: `FileManager` hides ordinary AppleDouble *files* from
    /// listings and `bsdtar` writes `._x` as a **symlink** when unpacking a foreign tar, so a walk that
    /// skipped that prefix would be blind to exactly the entries a hostile archive plants (F1).
    static func escapingLinks(in dir: URL) -> [String] {
        let fm = FileManager.default
        var links: [(path: String, target: String)] = []
        if let walker = fm.enumerator(atPath: dir.path) {
            while let rel = walker.nextObject() as? String {
                if let target = try? fm.destinationOfSymbolicLink(atPath: dir.appendingPathComponent(rel).path) {
                    links.append((rel, target))
                }
            }
        }
        return ArchiveEngine.escapingLinks(links).sorted()
    }

    /// Free capacity of the volume `destination` will live on, or nil when it cannot be queried.
    ///
    /// Queried once per operation, never per entry (the Boss fix `8092dd0` rule: one volume query, not
    /// one per item). nil is passed through honestly: `ArchiveSafetyRules` refuses unknown capacity
    /// rather than treating it as infinite.
    static func availableBytes(for destination: URL) -> Int64? {
        // A destination that does not exist yet still has a volume: ask its nearest existing parent.
        var probe = destination
        let fm = FileManager.default
        while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int64(capacity)
    }

    /// Split the space reasons out of a rejection, so they get their own sentence.
    static func spaceFailure(from reasons: [ArchiveSafetyRules.Reason]) -> Failure? {
        for reason in reasons {
            switch reason {
            case .insufficientSpace(let required, let available): return .outOfSpace(required: required, available: available)
            case .spaceUnknown: return .outOfSpace(required: 0, available: 0)
            default: continue
            }
        }
        return nil
    }

    /// Is the file at `url` still the very inode the reader inspected?
    ///
    /// `lstat`, not `stat`: a path swapped for a symlink must compare as "changed", not silently
    /// resolve to whatever it points at.
    static func identityStillMatches(_ identity: SystemArchiveReader.Identity, at url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
        return UInt64(info.st_dev) == identity.device
            && UInt64(info.st_ino) == identity.inode
            && Int64(info.st_size) == identity.size
            && Int64(info.st_mtimespec.tv_sec) == identity.modifiedSeconds
            && Int64(info.st_mtimespec.tv_nsec) == identity.modifiedNanos
            && Int64(info.st_ctimespec.tv_sec) == identity.changedSeconds
            && Int64(info.st_ctimespec.tv_nsec) == identity.changedNanos
    }

    /// Map the reader's technical refusal to a user-facing one.
    ///
    /// The reader's associated strings are English diagnostics from libarchive and are kept for the
    /// log only; they are never shown as UI copy. "Unsupported on this system" stays distinguishable
    /// from "this archive is bad", because the remedy is different.
    static func map(_ failure: SystemArchiveReader.Failure) -> Failure {
        switch failure {
        case .libraryUnavailable, .formatRegistrationFailed:
            return .readerUnavailable
        case .unsupportedFormat, .encrypted, .invalidEncoding, .sparse, .unsupportedEntry:
            // Refused by policy or by the approved format set — the archive is not something this app
            // will extract, and saying "unavailable" would suggest retrying.
            return .unsafeArchive(reasons: [], diagnostic: "\(failure)")
        case .notRegularFile, .notMaterialised, .changedWhileOpening:
            return .archiveChanged("\(failure)")
        case .openFailed(let code):
            return .archiveChanged("open failed (errno \(code))")
        case .damaged(let detail):
            return .unsafeArchive(reasons: [], diagnostic: detail)
        case .tooManyEntries, .byteBudgetExceeded, .cumulativeBudgetExceeded, .sizeMismatch,
             .sizeOverflow, .timedOut:
            return .unsafeArchive(reasons: [], diagnostic: "\(failure)")
        }
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
        case .unsafeArchive: return "Tệp nén không an toàn nên đã bị từ chối, chưa ghi gì: "
        case .outOfSpace: return "Không đủ dung lượng để giải nén tệp này."
        case .archiveChanged: return "Tệp nén đã thay đổi trong lúc kiểm tra nên đã dừng, chưa đặt gì."
        case .readerUnavailable: return "Không kiểm tra được tệp nén trên máy này nên đã từ chối, chưa giải nén gì."
        }
    }

    var detail: String? {
        switch self {
        case .missingSource(let names), .unsafeLinks(let names): return names.joined(separator: ", ")
        case .staging(let s), .placement(let s), .archiveChanged(let s): return s
        case .tool(_, let stderr), .missingData(let stderr): return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        case .unsafeArchive(let reasons, let diagnostic):
            let parts = reasons.map(Self.describe).filter { !$0.isEmpty }
            let text = parts.joined(separator: "; ")
            guard let diagnostic, !diagnostic.isEmpty else { return text.isEmpty ? nil : text }
            return text.isEmpty ? diagnostic : "\(text) — \(diagnostic)"
        case .outOfSpace(let required, let available):
            return "\(Self.bytes(required)) / \(Self.bytes(available))"
        case .nothingToDo, .cancelled, .readerUnavailable: return nil
        }
    }

    /// One value of every case — lets a test resolve every key against the shipped store.
    static let examples: [ArchiveRunner.Failure] = [
        .nothingToDo, .missingSource(["a"]), .staging("x"), .tool(status: 1, stderr: "x"),
        .missingData(stderr: "x"), .cancelled, .placement("x"), .unsafeLinks(["a"]),
        .unsafeArchive(reasons: [.escapesRoot("../x")], diagnostic: nil), .outOfSpace(required: 1, available: 0),
        .archiveChanged("x"), .readerUnavailable,
    ]

    /// Human-readable name of one refused path, for the detail line under the sentence.
    ///
    /// These are file names and path fragments only — the *reason* itself is already carried by
    /// `messageKey`, so no reason needs a translated sentence of its own here.
    static func describe(_ reason: ArchiveSafetyRules.Reason) -> String {
        switch reason {
        case .absolutePath(let p): return p
        case .driveOrUNCPath(let p): return p
        case .escapesRoot(let p): return p
        case .emptyPath: return "."
        case .controlCharacter(let p): return p
        case .ambiguousSeparator(let p): return p
        case .pathTooLong(let p, let bytes): return "\(p) (\(bytes) bytes)"
        case .tooManyComponents(let p, let count): return "\(p) (\(count))"
        case .duplicatePath(let p): return p
        case .aliasedPath(let a, let b): return "\(a) / \(b)"
        case .fileUsedAsParent(let p): return p
        case .duplicateAfterNormalisation(let a, let b): return "\(a) / \(b)"
        case .unsupportedEntry(let p): return p
        case .rootEntryIsNotADirectory(let p): return p
        case .tooManyEntries(let count, let limit): return "\(count)/\(limit)"
        case .fileTooLarge(let p, let declared, let limit): return "\(p) \(bytes(declared))/\(bytes(limit))"
        case .payloadTooLarge(let declared, let limit): return "\(bytes(declared))/\(bytes(limit))"
        case .sizeOverflow: return ""
        case .undeclaredSize(let p): return p
        case .expansionRatioTooHigh(let ratio, let limit): return String(format: "%.0f×/%.0f×", ratio, limit)
        case .absoluteLink(let p, let target): return "\(p) → \(target)"
        case .escapingLink(let p, let target): return "\(p) → \(target)"
        case .linkCycle(let paths): return paths.joined(separator: " → ")
        case .linkTargetMissing(let p, let target): return "\(p) → \(target)"
        case .hardLinkOutside(let p, let target): return "\(p) → \(target)"
        case .insufficientSpace(let required, let available): return "\(bytes(required))/\(bytes(available))"
        case .spaceUnknown: return ""
        }
    }

    /// Byte counts for the detail line: binary units, matching Finder's own wording.
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
