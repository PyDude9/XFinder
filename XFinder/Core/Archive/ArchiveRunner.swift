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
        /// The destination volume's free space could not be read. Its own case because it is not a
        /// shortage: telling the user "not enough space: 0 / 0" was a lie the page printed.
        case spaceUnknown
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
    /// What the first source is, read with `lstat` — `fileExists(isDirectory:)` would follow a link, and a linked
    /// source must not reach `ditto` (it archives the link's TARGET under the target's name).
    static func singleSourceKind(_ url: URL) -> ArchiveEngine.SingleSource {
        switch existingItem(at: url) {
        case .link: return .link
        case .directory: return .directory
        case .file, nil: return .file
        }
    }

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
        let single = Self.singleSourceKind(sources[0])
        if ArchiveEngine.needsStaging(sourceCount: sources.count, format: format, level: level,
                                      hasPassword: !(password ?? "").isEmpty, single: single) {
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
                                                    password: password, output: output, stagingDir: staging?.url,
                                                    single: single)
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
            case .spaceUnknown: return .spaceUnknown
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

    /// What `place` actually did. Reported instead of a bare `[URL]` so a partly-placed batch can say
    /// exactly which outputs exist: "nothing was changed" is a claim this app must never make loosely
    /// (spec §7 — measured: first file placed, second failed, failure reported as if nothing happened).
    struct PlacementOutcome: Equatable {
        var placed: [URL] = []
        /// Staged objects that could not be placed. Their staging copies are still inside the
        /// recovered folder when `recoveryRoot` is set.
        var failed: [String] = []
        /// Names that were numbered because the name was taken (the "kept both" part of a merge).
        var renamed: [String] = []
        /// Where unplaced staged data was kept, when anything failed.
        var recoveryRoot: URL?
        var failure: Failure?

        var isComplete: Bool { failure == nil && failed.isEmpty }
    }

    /// The review step (spec §4.4–4.5): inspect the archive, validate it and count what it really
    /// holds, without writing anything.
    ///
    /// A refusal is still a review — it comes back as `success` with `refusals` filled in, so the page
    /// can show *why* this archive is blocked instead of a bare error line. Only a reader failure that
    /// leaves nothing to describe (unavailable library, unreadable file) is a `failure`.
    static func inspect(archive: URL, near destination: URL,
                        topLevelName: String? = nil) async -> Result<ArchiveJob.ArchiveReview, Failure> {
        guard SystemArchiveReader.isAvailable else { return .failure(.readerUnavailable) }
        let inspection: SystemArchiveReader.Inspection
        do {
            inspection = try SystemArchiveReader().inspect(at: archive)
        } catch let failure as SystemArchiveReader.Failure {
            return .failure(Self.map(failure))
        } catch {
            return .failure(.staging("\(error)"))
        }
        let available = availableBytes(for: destination)
        let verdict = ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                  compressedSize: inspection.archiveBytes,
                                                  availableBytes: available)
        let payload = inspection.manifest.reduce(into: Int64(0)) { total, entry in
            if entry.kind == .regular, entry.declaredSize > 0 { total &+= entry.declaredSize }
        }
        let peak: Int64
        switch verdict {
        case .accepted(let plan): peak = plan.peakBytes
        case .rejected: peak = payload
        }
        let fm = FileManager.default
        let conflicts: [String]
        if let topLevelName {
            // "new folder beside the archive": the conflict is that one folder name.
            conflicts = fm.fileExists(atPath: destination.appendingPathComponent(topLevelName).path)
                ? [topLevelName] : []
        } else {
            let top = Set(inspection.manifest.compactMap { entry -> String? in
                let parts = entry.rawPath.split(separator: "/", omittingEmptySubsequences: true)
                return parts.count > 1 ? String(parts[0]) : nil
            } + inspection.manifest.filter { !$0.rawPath.contains("/") }.map(\.rawPath))
            conflicts = top.sorted().filter { fm.fileExists(atPath: destination.appendingPathComponent($0).path) }
        }
        let renames = Self.conflictPolicyPreview(conflicts: conflicts)
        return .success(ArchiveJob.review(archive: archive, destination: destination,
                                          manifest: inspection.manifest, declaredBytes: payload,
                                          availableBytes: available, requiredBytes: peak,
                                          conflicts: conflicts, keepsBothRenames: renames,
                                          refusals: verdict.reasons))
    }

    /// Names a Keep Both merge would produce, so the review can print them before anything runs.
    static func conflictPolicyPreview(conflicts: [String]) -> [String] {
        conflicts.map { ArchiveEngine.numbered($0, 2) }
    }

    /// Step 2: move the staged items into `destination`.
    ///
    /// `.keepBoth` numbers the incoming top-level item. `.merge` **combines** folders and numbers
    /// colliding leaves instead of replacing them (Boss decision 1; the old behaviour replaced the
    /// user's file with the archive's — measured in spec §2). `.ask` must be resolved by the caller;
    /// it places nothing that conflicts.
    ///
    /// Publication is exclusive: a move that would land on an existing path fails rather than
    /// replacing it (`renamex_np` + `RENAME_EXCL`, measured to return `EEXIST` and leave the target
    /// byte-identical). That makes the plan race-safe against a file appearing after it was computed.
    ///
    /// A failure no longer discards the batch silently: placed outputs and the still-staged remainder
    /// are both reported, and the remainder is kept in the app-owned recovery root.
    static func place(_ batch: ExtractedBatch, into destination: URL,
                      policy: ArchiveEngine.ConflictPolicy,
                      protected: Set<URL> = [],
                      recoveryRoot: URL? = ArchiveRecoveryStore.root) async -> Result<PlacementOutcome, Failure> {
        let fm = FileManager.default
        // A symlinked destination (or a symlinked component of it) is refused outright: writing
        // through it would put the user's data somewhere they never chose, and Merge would follow it
        // silently — that exact case was measured writing outside the chosen folder.
        if let link = symlinkedComponent(of: destination, under: destination.deletingLastPathComponent()) {
            discard(batch)
            return .failure(.placement("destination path component is a symbolic link: \(link.path)"))
        }
        do { try fm.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch {
            discard(batch)
            return .failure(.placement("\(error)"))
        }

        var outcome = PlacementOutcome()
        // Protected identities are the archives (and selected sources) this batch must never overwrite:
        // measured in §2, a ZIP holding a leaf named like its own source replaced that source.
        let protectedPaths = Set(protected.map { $0.standardizedFileURL.path })

        switch policy {
        case .ask:
            // Should not be reached: the caller resolves Ask first. Never guess a write.
            discard(batch)
            return .success(outcome)

        case .keepBoth, .merge:
            let steps: [ArchiveEngine.MergeStep]
            if policy == .merge {
                steps = ArchiveEngine.mergePlan(items: stagedTree(of: batch), into: destination) { url in
                    if protectedPaths.contains(url.standardizedFileURL.path) { return .file }
                    return existingItem(at: url)
                }
            } else {
                // Keep Both numbers the whole incoming top-level item; a folder is never combined with
                // what is already there, so it is planned as a non-combining leaf.
                let topLevel = batch.items.map { ArchiveEngine.StagedItem(path: $0, isDirectory: false) }
                steps = ArchiveEngine.mergePlan(items: topLevel, into: destination) { url in
                    if protectedPaths.contains(url.standardizedFileURL.path) { return .file }
                    return existingItem(at: url)
                }
            }
            // Report the topmost renamed object only: a numbered folder is what the user will see, and
            // listing every inherited leaf inside it would describe renames that did not happen.
            outcome.renamed = ArchiveEngine.renamedLeafNames(steps)
            for step in steps {
                let src = batch.staging.appendingPathComponent(step.source)
                // Re-checked per target: the plan was computed from snapshots, and a link that appeared
                // where the archive wants to write since then must be refused, not quietly numbered.
                // Measured in spec §2: with `dest/folder` a symlink, Merge followed it and wrote outside
                // the folder the user chose. (The incoming side needs no check here: `stagedTree` never
                // lists a link, and moving a link never follows it.)
                if let link = symlinkedComponent(of: step.target, under: destination) {
                    outcome.failure = .placement("destination path component is a symbolic link: \(link.path)")
                    break
                }
                if step.isDirectory {
                    // Combining folders is the whole point of Merge; creating one that exists is a no-op.
                    if (try? fm.createDirectory(at: step.target, withIntermediateDirectories: true)) == nil {
                        outcome.failed.append(step.source)
                        outcome.failure = .placement("could not create \(step.target.lastPathComponent)")
                        break
                    }
                    continue
                }
                do {
                    try publishExclusively(from: src, to: step.target)
                    outcome.placed.append(step.target)
                } catch {
                    outcome.failed.append(step.source)
                    outcome.failure = .placement("\(error)")
                    break
                }
            }
        }

        if outcome.isComplete {
            batch.owned.removeIfOwned()
            return .success(outcome)
        }
        // Keep whatever is still staged instead of deleting it: the user can recover the items that
        // never landed, and the report names them (spec §7 — never claim all-or-nothing).
        outcome.recoveryRoot = recoverStagingRemainder(batch, root: recoveryRoot)
        return .success(outcome)
    }

    /// Publish one staged object at `target` without ever replacing what is already there.
    ///
    /// `renamex_np(…, RENAME_EXCL)` is the platform primitive for this: measured to return `EEXIST`
    /// and leave the existing file byte-identical. `moveItem` is the fallback (same volume ⇒ still a
    /// rename) but it *replaces*, so the caller's existence check has to hold — hence the explicit
    /// re-check before falling back.
    static func publishExclusively(from source: URL, to target: URL) throws {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return }
        if errno == EEXIST { throw PlacementError.alreadyExists(target) }
        // A cross-volume parent or a filesystem without renamex support: only then copy-move, and only
        // when the destination really is free.
        if FileManager.default.fileExists(atPath: target.path) { throw PlacementError.alreadyExists(target) }
        try FileManager.default.moveItem(at: source, to: target)
    }

    enum PlacementError: Error, CustomStringConvertible {
        case alreadyExists(URL)
        /// The system trashed the file but did not tell us where it went, so it cannot be restored.
        case originalNotRecoverable(URL)

        var description: String {
            switch self {
            case .alreadyExists(let url):
                return "something appeared at \(url.lastPathComponent) while placing; it was not replaced"
            case .originalNotRecoverable(let url):
                return "the old file was trashed but its Trash location is unknown: \(url.lastPathComponent)"
            }
        }
    }

    /// What is at `url` right now, without following a link at the final component.
    static func existingItem(at url: URL) -> ArchiveEngine.ExistingItem? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: return .link
        case S_IFDIR: return .directory
        default: return .file
        }
    }

    /// Every staged object, depth included, in the shape `ArchiveEngine.mergePlan` plans from.
    static func stagedTree(of batch: ExtractedBatch) -> [ArchiveEngine.StagedItem] {
        let fm = FileManager.default
        var items: [ArchiveEngine.StagedItem] = []
        for name in batch.items {
            let url = batch.staging.appendingPathComponent(name)
            var info = stat()
            let isDir = lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
            items.append(ArchiveEngine.StagedItem(path: name, isDirectory: isDir))
        }
        guard let walker = fm.enumerator(atPath: batch.staging.path) else { return items }
        var seen = Set(items.map(\.path))
        while let rel = walker.nextObject() as? String {
            guard !seen.contains(rel) else { continue }
            let url = batch.staging.appendingPathComponent(rel)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            if (info.st_mode & S_IFMT) == S_IFLNK { continue }   // links were judged by the manifest
            seen.insert(rel)
            items.append(ArchiveEngine.StagedItem(path: rel, isDirectory: (info.st_mode & S_IFMT) == S_IFDIR))
        }
        return items
    }

    /// Move whatever is still staged into the app-owned recovery root and return where it went.
    /// Only objects this job still owns are touched; the staging root itself is then removed.
    static func recoverStagingRemainder(_ batch: ExtractedBatch, root: URL? = ArchiveRecoveryStore.root) -> URL? {
        let fm = FileManager.default
        guard batch.owned.isStillOwned, let root else { return nil }
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch { return nil }
        let dest = root.appendingPathComponent("batch-\(UUID().uuidString)")
        do { try fm.moveItem(at: batch.staging, to: dest) } catch { return nil }
        return dest
    }

    static func discard(_ batch: ExtractedBatch) {
        batch.owned.removeIfOwned()
    }

    // MARK: Creation Replace (Boss approval point 5)

    /// Replace an existing file by a verified candidate, in an order that cannot lose the original.
    ///
    /// The old code trashed the existing archive *first* and then built the new one (spec §1), so a
    /// failed compression left the user with neither. Boss's transaction, implemented literally:
    ///
    /// 1. the candidate already exists and has been verified by `compress` (it is a value here, so
    ///    this function cannot run before that);
    /// 2. `trashItem(old, resultingItemURL:)` — the original goes to the Trash and we keep the URL the
    ///    system actually gave it, measured to be `~/.Trash/name`;
    /// 3. `renamex_np(candidate, target, RENAME_EXCL)` publishes only into a free name;
    /// 4. if (3) fails, the trashed original is moved **back** from `resultingItemURL` and the failure
    ///    is reported. Never `rm`, never a silent loss.
    ///
    /// `trash` and `publish` are injected so both failure branches are testable without touching the
    /// owner's Trash or racing the filesystem.
    static func replace(existing: URL, with candidate: URL,
                        trash: (URL) throws -> URL = { source in
                            var resulting: NSURL?
                            try FileManager.default.trashItem(at: source, resultingItemURL: &resulting)
                            guard let resulting = resulting as URL? else {
                                throw PlacementError.originalNotRecoverable(source)
                            }
                            return resulting
                        },
                        publish: (URL, URL) throws -> Void = { try publishExclusively(from: $0, to: $1) }) -> Result<URL, Failure>
    {
        let trashed: URL
        do { trashed = try trash(existing) }
        catch { return .failure(.placement("could not move the old file to the Trash: \(error)")) }

        do {
            try publish(candidate, existing)
            return .success(existing)
        } catch {
            // Put the original back where the user expects it, then report. A failed restore is named
            // in the message together with where the original still is.
            do {
                try FileManager.default.moveItem(at: trashed, to: existing)
                return .failure(.placement("could not publish the new file, so the old one was put back: \(error)"))
            } catch {
                return .failure(.placement("could not publish the new file; the old one is in the Trash at \(trashed.path) (\(error))"))
            }
        }
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
        case .spaceUnknown: return "Chưa kiểm tra được dung lượng trống của thư mục đích nên chưa giải nén gì."
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
        case .nothingToDo, .cancelled, .readerUnavailable, .spaceUnknown: return nil
        }
    }

    /// One value of every case — lets a test resolve every key against the shipped store.
    static let examples: [ArchiveRunner.Failure] = [
        .nothingToDo, .missingSource(["a"]), .staging("x"), .tool(status: 1, stderr: "x"),
        .missingData(stderr: "x"), .cancelled, .placement("x"), .unsafeLinks(["a"]),
        .unsafeArchive(reasons: [.escapesRoot("../x")], diagnostic: nil), .outOfSpace(required: 1, available: 0),
        .spaceUnknown, .archiveChanged("x"), .readerUnavailable,
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
