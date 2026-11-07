import Foundation
import CryptoKit
import Darwin

enum DuplicateIOError: Error { case changed, unavailable, cancelled }

enum DuplicateScanEngine {
    static func fingerprint(_ url: URL) throws -> DuplicateFingerprint {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_flags & UInt32(SF_DATALESS) == 0 else { throw DuplicateIOError.unavailable }
        return value(info)
    }

    private static func value(_ info: stat) -> DuplicateFingerprint {
        .init(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino), size: Int64(info.st_size),
              modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec),
              changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec))
    }

    private static func openFile(_ file: DuplicateFile) throws -> FileHandle {
        guard DuplicateRules.fingerprintsMatch(try fingerprint(file.url), file.fingerprint) else { throw DuplicateIOError.changed }
        let fd = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw DuplicateIOError.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try check(handle, file); return handle }
        catch { try? handle.close(); throw error }
    }

    private static func check(_ handle: FileHandle, _ file: DuplicateFile) throws {
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_flags & UInt32(SF_DATALESS) == 0, DuplicateRules.fingerprintsMatch(value(info), file.fingerprint),
              DuplicateRules.fingerprintsMatch(try fingerprint(file.url), file.fingerprint) else { throw DuplicateIOError.changed }
    }

    static func digest(_ file: DuplicateFile, cancelled: () -> Bool = { Task.isCancelled }) throws -> String {
        let handle = try openFile(file)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            guard !cancelled() else { throw DuplicateIOError.cancelled }
            let data = try handle.read(upToCount: DuplicateRules.chunkSize) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        try check(handle, file)
        let alphabet = Array("0123456789abcdef".utf8)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(64)
        for byte in hash.finalize() {
            encoded.append(alphabet[Int(byte >> 4)])
            encoded.append(alphabet[Int(byte & 15)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    static func equalBytes(_ a: DuplicateFile, _ b: DuplicateFile,
                           cancelled: () -> Bool = { Task.isCancelled }) throws -> Bool {
        guard a.fingerprint.size == b.fingerprint.size else { return false }
        let left = try openFile(a)
        defer { try? left.close() }
        let right = try openFile(b)
        defer { try? right.close() }
        var equal = true
        while true {
            guard !cancelled() else { throw DuplicateIOError.cancelled }
            let x = try left.read(upToCount: DuplicateRules.chunkSize) ?? Data()
            let y = try right.read(upToCount: DuplicateRules.chunkSize) ?? Data()
            if x != y { equal = false; break }
            if x.isEmpty { break }
        }
        try check(left, a)
        try check(right, b)
        return equal
    }

    static func verify(_ move: DuplicateMove, cancelled: () -> Bool = { Task.isCancelled },
                       hash: (DuplicateFile) throws -> String = { try digest($0) }) throws -> Bool {
        guard move.file.id != move.keeper.id,
              move.file.fingerprint.identity != move.keeper.fingerprint.identity else { return false }
        guard try hash(move.file) == hash(move.keeper) else { return false }
        return try equalBytes(move.file, move.keeper, cancelled: cancelled)
    }

    static func scan(root: URL, progress: @escaping @Sendable (DuplicateProgress) -> Void) async -> DuplicateResult {
        let worker = Task.detached(priority: .utility) { await perform(root: root, progress: progress) }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }

    private static func perform(root: URL, progress: @escaping @Sendable (DuplicateProgress) -> Void) async -> DuplicateResult {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, (rootInfo.st_mode & S_IFMT) == S_IFDIR,
              rootInfo.st_flags & UInt32(SF_DATALESS) == 0, root.pathExtension.lowercased() != "app" else {
            return .init(groups: [], status: .failed, scanned: 0, skipped: 0)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              access(root.path, R_OK | X_OK) == 0 else {
            return .init(groups: [], status: .failed, scanned: 0, skipped: 0)
        }
        var files: [DuplicateFile] = []
        var identities: [String: Int] = [:]
        var skipped = 0
        var limited = false
        var incomplete = false
        var lastPublished = 0.0
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        _ = FileWalk.walk(root, limit: Int.max, isCancelled: { Task.isCancelled || limited }, onOther: { skipped += 1; incomplete = true }, onLink: { skipped += 1 }) { url, directory, _ in
            if directory {
                if url.pathExtension.lowercased() == "app" { skipped += 1; return .skip }
                var info = stat()
                if lstat(url.path, &info) != 0 || info.st_flags & UInt32(SF_DATALESS) != 0 { skipped += 1; return .skip }
                if info.st_dev != rootInfo.st_dev { skipped += 1; incomplete = true; return .skip }
                return .descend
            }
            do {
                if try url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true { skipped += 1; return .descend }
                let fp = try fingerprint(url)
                let candidate = DuplicateFile(url: url, relativePath: String(url.path.dropFirst(prefix.count)), fingerprint: fp)
                if let index = identities[fp.identity] {
                    if DuplicateRules.keeperFirst(candidate, files[index]) { files[index] = candidate }
                } else {
                    identities[fp.identity] = files.count
                    files.append(candidate)
                    if files.count >= DuplicateRules.fileLimit { limited = true }
                }
            } catch { skipped += 1; incomplete = true }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPublished >= 0.2 {
                lastPublished = now
                progress(.init(phase: .grouping, processed: files.count, skipped: skipped))
            }
            return .descend
        }
        if Task.isCancelled { return .init(groups: [], status: .cancelled, scanned: files.count, skipped: skipped) }
        let candidates = DuplicateRules.sizeCandidates(files).flatMap { $0 }
        let counter = DuplicateHashProgress(progress: progress, skipped: skipped)
        progress(.init(phase: .hashing, processed: 0, skipped: skipped))
        let hashed = await withTaskGroup(of: [(DuplicateFile, String?)].self, returning: [(DuplicateFile, String?)].self) { group in
            for worker in 0..<DuplicateRules.workers {
                group.addTask {
                    var output: [(DuplicateFile, String?)] = []
                    for index in stride(from: worker, to: candidates.count, by: DuplicateRules.workers) {
                        if Task.isCancelled { break }
                        let file = candidates[index]
                        output.append((file, try? digest(file)))
                        await counter.completed()
                    }
                    return output
                }
            }
            var output: [(DuplicateFile, String?)] = []
            for await batch in group { output.append(contentsOf: batch) }
            return output
        }
        var buckets: [String: [DuplicateFile]] = [:]
        for (file, hash) in hashed {
            if let hash { buckets[hash, default: []].append(file) } else { skipped += 1; incomplete = true }
        }
        var groups: [DuplicateGroup] = []
        var compared = 0
        for hash in buckets.keys.sorted() {
            if Task.isCancelled { break }
            var remaining = buckets[hash]!.sorted(by: DuplicateRules.keeperFirst)
            while !remaining.isEmpty && !Task.isCancelled {
                let keeper = remaining.removeFirst()
                var equal = [keeper]
                var different: [DuplicateFile] = []
                for file in remaining {
                    do {
                        if try equalBytes(keeper, file) { equal.append(file) } else { different.append(file) }
                    } catch { skipped += 1; incomplete = true }
                    compared += 1
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastPublished >= 0.2 {
                        lastPublished = now
                        progress(.init(phase: .comparing, processed: compared, skipped: skipped))
                    }
                }
                if equal.count > 1 { groups.append(.init(files: equal)) }
                remaining = different
            }
        }
        var finalRoot = stat()
        if lstat(root.path, &finalRoot) != 0 || finalRoot.st_dev != rootInfo.st_dev || finalRoot.st_ino != rootInfo.st_ino { incomplete = true }
        let status: DuplicateScanStatus = Task.isCancelled ? .cancelled :
            (limited || incomplete || access(root.path, R_OK | X_OK) != 0 ? .incomplete : .complete)
        return .init(groups: groups.sorted { $0.id < $1.id }, status: status, scanned: files.count, skipped: skipped)
    }
}

private actor DuplicateHashProgress {
    private var count = 0
    private var published = 0.0
    private let progress: @Sendable (DuplicateProgress) -> Void
    private let skipped: Int
    init(progress: @escaping @Sendable (DuplicateProgress) -> Void, skipped: Int) {
        self.progress = progress; self.skipped = skipped
    }
    func completed() {
        count += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now - published >= 0.2 {
            published = now
            progress(.init(phase: .hashing, processed: count, skipped: skipped))
        }
    }
}
