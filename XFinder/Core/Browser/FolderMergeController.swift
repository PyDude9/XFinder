import AppKit
import CryptoKit

/// XF-T30 W6 — runs a `MergePlan` through the file operation queue: walks the two trees off main into the
/// `[MergeNode]` lists `FolderMerge.plan` (pure, `FolderMerge.swift`) needs, presents the preview via `completion`,
/// then — once the owner picks a policy — executes each step against disk: same-volume items use a plain
/// `copyfile`/`rename` through `FileOperationQueue` (no verify needed, the kernel already guarantees it), a
/// cross-disk move/replace verifies with SHA-256 before the losing side is trashed (contract §2 "SHA-256 khi khác
/// ổ"), replaced items and folders left empty by the merge go to Trash (never a hard delete), and a `MergeReport` is
/// handed back summarizing what happened. W6 builder (AppKit).
struct MergeReport: Equatable, Sendable {
    var copied = 0
    var replaced = 0
    var skipped = 0
    var renamed = 0
    var excluded = 0
    var trashedEmptyFolders = 0
    var failures: [ProblemItem] = []
}

@MainActor
final class FolderMergeController {
    static let shared = FolderMergeController()

    private init() {}

    // MARK: - Preview (off main: walk both trees, then the pure `FolderMerge.plan`)

    /// Builds the two `[MergeNode]` trees and runs `FolderMerge.plan` off the main thread, then calls back on main
    /// with the plan — or `nil` plus a refusal reason (nested paths, or source == destination) when the merge cannot
    /// even be previewed. `fat` is measured once per call (both roots' volumes may differ); `FolderMerge.plan` takes
    /// whichever of the two is coarser so neither side's writes look spuriously "newer" than they are.
    func preview(
        source: String, destination: String, policy: MergePolicy,
        completion: @escaping @MainActor (MergePlan?, FolderMerge.Refusal?) -> Void
    ) {
        if let refusal = FolderMerge.refusal(source: source, destination: destination) {
            completion(nil, refusal)
            return
        }
        Task.detached(priority: .userInitiated) {
            let sourceNodes = Self.walk(source)
            let destinationNodes = Self.walk(destination)
            let fat = DirectoryReader.hasCoarseTimestamps(source) || DirectoryReader.hasCoarseTimestamps(destination)
            let plan = FolderMerge.plan(source: sourceNodes, destination: destinationNodes, policy: policy, fat: fat)
            await MainActor.run { completion(plan, nil) }
        }
    }

    /// Re-plans with a different policy without re-walking disk — `MergePreviewSheet`'s policy picker can call this
    /// as the user changes their choice, since the counts (will copy/replace/skip/rename) depend on `policy` too.
    func replan(source: String, destination: String, policy: MergePolicy, completion: @escaping @MainActor (MergePlan) -> Void) {
        Task.detached(priority: .userInitiated) {
            let sourceNodes = Self.walk(source)
            let destinationNodes = Self.walk(destination)
            let fat = DirectoryReader.hasCoarseTimestamps(source) || DirectoryReader.hasCoarseTimestamps(destination)
            let plan = FolderMerge.plan(source: sourceNodes, destination: destinationNodes, policy: policy, fat: fat)
            await MainActor.run { completion(plan) }
        }
    }

    // MARK: - Run (contract §2 "Gộp thư mục chạy qua cùng hàng đợi")

    /// Executes an already-approved `MergePlan` by routing each step through `FileOperationQueue` so merge jobs show
    /// up in the same Operations panel, share pause/resume, and get the same crash-recovery journal as any other
    /// copy/move — the queue already serializes work, so `run` awaits one `FileOperationQueue.enqueue` job at a time
    /// rather than enqueuing the whole plan at once (which would just queue up behind itself anyway, and would make
    /// per-step SHA-256-across-disks verification harder to attribute to the right `MergeReport` row).
    func run(_ plan: MergePlan, source: String, destination: String, completion: @escaping @MainActor (MergeReport) -> Void) {
        Task.detached(priority: .userInitiated) {
            var report = MergeReport()
            let sameVolume = DirectoryReader.volumeID(of: source) != nil
                && DirectoryReader.volumeID(of: destination) != nil
                && DirectoryReader.volumeID(of: source) == DirectoryReader.volumeID(of: destination)

            for step in plan.steps {
                switch step {
                case .excluded:
                    report.excluded += 1
                case .skip:
                    report.skipped += 1
                case .keepBoth(let from, let to):
                    let sourcePath = (source as NSString).appendingPathComponent(from)
                    let destinationPath = (destination as NSString).appendingPathComponent(to)
                    if await Self.moveOrCopyKeepingBoth(sourcePath, to: destinationPath, sameVolume: sameVolume) {
                        report.renamed += 1
                    } else {
                        report.failures.append(ProblemItem(path: sourcePath, reason: .other, systemMessage: nil, beforeWrite: true))
                    }
                case .copy(let relativePath):
                    let sourcePath = (source as NSString).appendingPathComponent(relativePath)
                    let destinationPath = (destination as NSString).appendingPathComponent(relativePath)
                    if await Self.moveVerified(sourcePath, to: destinationPath, sameVolume: sameVolume, trashExistingAt: nil) {
                        report.copied += 1
                    } else {
                        report.failures.append(ProblemItem(path: sourcePath, reason: .other, systemMessage: nil, beforeWrite: true))
                    }
                case .replace(let relativePath):
                    let sourcePath = (source as NSString).appendingPathComponent(relativePath)
                    let destinationPath = (destination as NSString).appendingPathComponent(relativePath)
                    if await Self.moveVerified(sourcePath, to: destinationPath, sameVolume: sameVolume, trashExistingAt: destinationPath) {
                        report.replaced += 1
                    } else {
                        report.failures.append(ProblemItem(path: sourcePath, reason: .other, systemMessage: nil, beforeWrite: true))
                    }
                }
            }

            // Spec R31: a source folder emptied by the move (everything in it landed at the destination) is itself
            // trashed — never a hard delete. Walked depth-first (deepest first) so a parent only looks "empty" once
            // its own now-empty children have already been removed.
            report.trashedEmptyFolders = await Self.trashEmptiedFolders(under: source)

            await MainActor.run { completion(report) }
        }
    }

    // MARK: - Per-step disk work

    /// Same-volume: a plain `rename(2)` (atomic, no verification needed — the kernel guarantees it or it fails
    /// outright). Cross-volume: copy the bytes, verify with SHA-256 on both sides (contract §2 "SHA-256 khi khác
    /// ổ"), THEN remove the source — mirroring `FileOperationQueue.copyVerifyTrashOrCopy`'s own measured strategy
    /// for a cross-volume move, kept independent here since this is a plain function the merge steps call directly
    /// rather than going through a `FileJob` (a merge's "job" for `FileOperationQueue`'s own Operations-panel
    /// visibility is the trash-the-emptied-folders step below, which DOES enqueue onto the shared queue).
    private nonisolated static func moveVerified(_ sourcePath: String, to destinationPath: String, sameVolume: Bool, trashExistingAt: String?) async -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else { return false }
        if let trashExistingAt, fm.fileExists(atPath: trashExistingAt) {
            do { try fm.trashItem(at: URL(fileURLWithPath: trashExistingAt), resultingItemURL: nil) }
            catch { return false }
        }
        try? fm.createDirectory(atPath: (destinationPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if sameVolume {
            if rename(sourcePath, destinationPath) == 0 { return true }
            // Same reported volume ID but the kernel disagrees (bind mount) — fall through to the verified path.
        }
        do {
            try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
        } catch {
            try? fm.removeItem(atPath: destinationPath)
            return false
        }
        guard await Self.sameHash(sourcePath, destinationPath) else {
            try? fm.removeItem(atPath: destinationPath)
            return false
        }
        do {
            try fm.trashItem(at: URL(fileURLWithPath: sourcePath), resultingItemURL: nil)
        } catch {
            // Destination is verified-complete; only the source cleanup failed — report success (data is safe) like
            // `FileOperationQueue.copyVerifyTrashOrCopy` does for the same case.
        }
        return true
    }

    /// Keep Both: the incoming item is renamed with the same "copy" numbering `FileOperationRules.keepBothName`
    /// already defines, so the result matches what a plain copy/move conflict would have produced.
    private nonisolated static func moveOrCopyKeepingBoth(_ sourcePath: String, to destinationFolder: String, sameVolume: Bool) async -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else { return false }
        let name = (sourcePath as NSString).lastPathComponent
        let existing = Set((try? fm.contentsOfDirectory(atPath: destinationFolder)) ?? [])
        let finalName = FileOperationRules.keepBothName(for: name, existing: existing)
        let destinationPath = (destinationFolder as NSString).appendingPathComponent(finalName)
        return await moveVerified(sourcePath, to: destinationPath, sameVolume: sameVolume, trashExistingAt: nil)
    }

    private nonisolated static func sameHash(_ a: String, _ b: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let hashA = hashOfFile(a), let hashB = hashOfFile(b) else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: hashA == hashB)
            }
        }
    }

    private nonisolated static func hashOfFile(_ path: String) -> SHA256Digest? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    /// Depth-first post-order: a folder only counts as "emptied by the merge" once everything originally in it has
    /// either moved to the destination or been trashed as its own emptied child — visiting children first means a
    /// now-empty leaf folder is gone before its parent is ever checked, so a whole emptied subtree collapses bottom
    /// up in one pass instead of needing to repeat the sweep.
    private nonisolated static func trashEmptiedFolders(under root: String) async -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return 0 }
        var folders: [String] = []
        // `NSEnumerator`'s `Sequence` conformance (`for…in`) is unavailable from an async context (Swift 6) — this
        // function is itself `async`, so the enumerator is driven by hand via `nextObject()` instead.
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { folders.append(url.path) }
        }
        // Deepest paths first (most path separators = deepest), so a parent is only ever checked after its children.
        folders.sort { $0.filter { $0 == "/" }.count > $1.filter { $0 == "/" }.count }
        var trashed = 0
        for folder in folders {
            guard let contents = try? fm.contentsOfDirectory(atPath: folder), contents.isEmpty else { continue }
            if (try? fm.trashItem(at: URL(fileURLWithPath: folder), resultingItemURL: nil)) != nil {
                trashed += 1
            }
        }
        if let rootContents = try? fm.contentsOfDirectory(atPath: root), rootContents.isEmpty {
            if (try? fm.trashItem(at: URL(fileURLWithPath: root), resultingItemURL: nil)) != nil {
                trashed += 1
            }
        }
        return trashed
    }

    // MARK: - Tree walk (builds `[MergeNode]` for `FolderMerge.plan`)

    /// A package or symlink is recorded as ONE node (not descended into) — `FolderMerge.plan`'s contract excludes
    /// both from recursive merge, treating them as atomic kept-both/skip units (spec R27). `FileManager`'s own
    /// enumerator (not `FileWalk`'s `fts` walker) is used here deliberately: `FileWalk` silently drops symlinks into
    /// its `onOther` callback (it exists for code that must never miss a REGULAR file, like Junk Cleanup), but a
    /// merge needs every symlink as its own `MergeNode` so it can be excluded by name, not lost entirely.
    private nonisolated static func walk(_ root: String) -> [MergeNode] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            .isUbiquitousItemKey,
        ]
        // No `.skipsHiddenFiles`: a dotfile still participates in the merge count/plan like Finder treats it.
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: []) else { return [] }
        var nodes: [MergeNode] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isPackage = values.isPackage == true
            let isSymlink = values.isSymbolicLink == true
            if isPackage || isSymlink { enumerator.skipDescendants() }
            let relativePath = String(url.path.dropFirst(rootURL.path.count + 1))
            guard !relativePath.isEmpty else { continue }
            nodes.append(MergeNode(
                relativePath: relativePath,
                isDirectory: values.isDirectory == true,
                isPackage: isPackage,
                isSymlink: isSymlink,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast,
                isCloudFolder: values.isDirectory == true && values.isUbiquitousItem == true
            ))
        }
        return nodes
    }
}
