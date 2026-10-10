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
    }

    // MARK: Process

    /// Runs `command` off the main thread. Cancelling the calling task terminates the child.
    static func run(_ command: ArchiveEngine.Command) async -> ProcessResult {
        let pid = OSAllocatedUnfairLock<pid_t>(initialState: 0)
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
                pid.withLock { $0 = p.processIdentifier }
                let data = err.fileHandleForReading.readDataToEndOfFile()   // BEFORE wait
                p.waitUntilExit()
                return ProcessResult(status: p.terminationStatus, stderr: String(decoding: data, as: UTF8.self))
            }.value
        } onCancel: {
            let id = pid.withLock { $0 }
            if id > 0 { kill(id, SIGTERM) }
        }
    }

    // MARK: Compress

    /// `output` must already be resolved through `ArchiveEngine.destination` — the runner never
    /// picks names. A partial output is removed on any failure.
    static func compress(sources: [URL], format: ArchiveEngine.Format, level: Int = ArchiveEngine.defaultLevel,
                         password: String? = nil, output: URL) async -> Result<URL, Failure> {
        guard !sources.isEmpty else { return .failure(.nothingToDo) }
        let fm = FileManager.default
        let missing = sources.filter { !fm.fileExists(atPath: $0.path) }.map(\.lastPathComponent)
        guard missing.isEmpty else { return .failure(.missingSource(missing)) }
        var staging: URL?
        defer { if let staging { try? fm.removeItem(at: staging) } }
        if ArchiveEngine.needsStaging(sourceCount: sources.count, format: format, level: level,
                                      hasPassword: !(password ?? "").isEmpty) {
            do {
                let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                     appropriateFor: output.deletingLastPathComponent(), create: true)
                for (src, name) in zip(sources, ArchiveEngine.entryNames(for: sources)) {
                    try fm.createSymbolicLink(at: dir.appendingPathComponent(name), withDestinationURL: src)
                }
                staging = dir
            } catch { return .failure(.staging("\(error)")) }
        }
        let command = ArchiveEngine.compressCommand(sources: sources, format: format, level: level,
                                                    password: password, output: output, stagingDir: staging)
        let result = await run(command)
        if Task.isCancelled { try? fm.removeItem(at: output); return .failure(.cancelled) }
        if result.status != 0 { try? fm.removeItem(at: output); return .failure(.tool(status: result.status, stderr: result.stderr)) }
        if ArchiveEngine.stderrSignalsMissingData(result.stderr) {
            try? fm.removeItem(at: output); return .failure(.missingData(stderr: result.stderr))
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
                try? fm.removeItem(at: output)
                return .failure(.missingData(stderr: "not in the archive: \(lost.joined(separator: ", "))"))
            }
        }
        return .success(output)
    }

    // MARK: Extract

    /// An archive extracted into a private folder, not yet placed.
    struct ExtractedBatch: Equatable {
        let staging: URL
        let items: [String]
    }

    /// Step 1: extract into a staging folder on `destination`'s volume (so placing is a rename).
    static func extractToStaging(archive: URL, near destination: URL) async -> Result<ExtractedBatch, Failure> {
        let fm = FileManager.default
        let dir: URL
        do {
            dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        } catch { return .failure(.staging("\(error)")) }
        let result = await run(ArchiveEngine.extractCommand(archive: archive, into: dir))
        if Task.isCancelled { try? fm.removeItem(at: dir); return .failure(.cancelled) }
        guard result.status == 0 else {
            try? fm.removeItem(at: dir); return .failure(.tool(status: result.status, stderr: result.stderr))
        }
        // ditto -x -k leaves a __MACOSX folder only for archives made elsewhere; it is resource-fork
        // debris, never user content.
        let items = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "__MACOSX" && $0 != ".DS_Store" }.sorted()
        return .success(ExtractedBatch(staging: dir, items: items))
    }

    /// Names in the batch that already exist in `destination` — what an `.ask` prompt must list.
    static func conflicts(_ batch: ExtractedBatch, in destination: URL) -> [String] {
        batch.items.filter { FileManager.default.fileExists(atPath: destination.appendingPathComponent($0).path) }
    }

    /// Step 2: move the items into `destination`. `.keepBoth` renames, `.merge` replaces files and
    /// merges folders. `.ask` must be resolved by the caller first — passing it places nothing that
    /// conflicts. The staging folder is removed afterwards.
    static func place(_ batch: ExtractedBatch, into destination: URL,
                      policy: ArchiveEngine.ConflictPolicy) async -> Result<[URL], Failure> {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: batch.staging) }
        do { try fm.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch { return .failure(.placement("\(error)")) }
        var placed: [URL] = []
        let plan = ArchiveEngine.placements(items: batch.items, into: destination, policy: policy,
                                            exists: { fm.fileExists(atPath: $0.path) })
        for (name, d) in plan {
            guard case .write(let target) = d else { continue }       // an unresolved .ask conflict
            let src = batch.staging.appendingPathComponent(name)
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
        try? FileManager.default.removeItem(at: batch.staging)
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
        }
    }

    var detail: String? {
        switch self {
        case .missingSource(let names): return names.joined(separator: ", ")
        case .staging(let s), .placement(let s): return s
        case .tool(_, let stderr), .missingData(let stderr): return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        case .nothingToDo, .cancelled: return nil
        }
    }

    /// One value of every case — lets a test resolve every key against the shipped store.
    static let examples: [ArchiveRunner.Failure] = [
        .nothingToDo, .missingSource(["a"]), .staging("x"), .tool(status: 1, stderr: "x"),
        .missingData(stderr: "x"), .cancelled, .placement("x"),
    ]
}
