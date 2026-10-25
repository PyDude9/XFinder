import AppKit
import CryptoKit

/// XF-T30 W6 — folder merge: plans (walks both trees off main, then the pure `FolderMerge.plan`) and performs ONE
/// plan step at a time. The run itself is a `.merge` job in `FileOperationQueue` (Operations panel, pause/resume,
/// Problems list, persistent undo, crash journal) — the queue calls `planned` once and `execute` per step. Same
/// volume: `rename(2)`; across disks: copy, SHA-256 both sides, then trash the source; a replaced item and every
/// source folder the merge empties go to Trash (never a hard delete).
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

    // MARK: - Queue entry points

    /// The person confirmed a policy in the merge preview: queue the merge.
    @discardableResult
    func enqueue(source: String, destination: String, policy: MergePolicy) -> UUID? {
        FileOperationQueue.shared.enqueueMerge(source: source, destination: destination, policy: policy)
    }

    /// What one executed step did.
    enum StepOutcome: Equatable, Sendable {
        /// Moved `from` (in the source tree) to `to` (in the destination tree).
        case moved(from: String, to: String)
        case skipped
        case failed(path: String, message: String?)
    }

    /// Plans fresh at run time (the tree may have changed since the preview).
    nonisolated static func planned(source: String, destination: String, policy: MergePolicy) async -> MergePlan {
        let sourceNodes: [MergeNode] = walk(source)
        let destinationNodes: [MergeNode] = walk(destination)
        let fat: Bool = DirectoryReader.hasCoarseTimestamps(source) || DirectoryReader.hasCoarseTimestamps(destination)
        return FolderMerge.plan(source: sourceNodes, destination: destinationNodes, policy: policy, fat: fat)
    }

    /// The steps that touch disk (copy / replace / keep both); skip and excluded steps do not.
    nonisolated static func actionableSteps(of plan: MergePlan) -> [MergePlan.Step] {
        plan.steps.filter { step in
            switch step {
            case .copy, .replace, .keepBoth: return true
            case .skip, .excluded: return false
            }
        }
    }

    nonisolated static func onSameVolume(_ a: String, _ b: String) -> Bool {
        guard let left: Int32 = DirectoryReader.volumeID(of: a), let right: Int32 = DirectoryReader.volumeID(of: b) else { return false }
        return left == right
    }

    /// Performs one plan step.
    nonisolated static func execute(_ step: MergePlan.Step, source: String, destination: String, sameVolume: Bool) async -> StepOutcome {
        let pair: (from: String, to: String, trashExisting: String?)
        switch step {
        case .skip, .excluded:
            return .skipped
        case .copy(let relative):
            pair = ((source as NSString).appendingPathComponent(relative), (destination as NSString).appendingPathComponent(relative), nil)
        case .replace(let relative):
            let target: String = (destination as NSString).appendingPathComponent(relative)
            pair = ((source as NSString).appendingPathComponent(relative), target, target)
        case .keepBoth(let from, let to):
            pair = ((source as NSString).appendingPathComponent(from), (destination as NSString).appendingPathComponent(to), nil)
        }
        let ok: Bool = await moveVerified(pair.from, to: pair.to, sameVolume: sameVolume, trashExistingAt: pair.trashExisting)
        return ok ? .moved(from: pair.from, to: pair.to) : .failed(path: pair.from, message: nil)
    }

    // MARK: - Per-step disk work

    /// Same-volume: a plain `rename(2)` (atomic, no verification needed — the kernel guarantees it or it fails
    /// outright). Cross-volume: copy the bytes, verify with SHA-256 on both sides (contract §2 "SHA-256 khi khác
    /// ổ"), THEN remove the source — mirroring `FileOperationQueue.copyVerifyTrashOrCopy`'s own measured strategy
    /// for a cross-volume move, kept independent here since this is a plain function the merge steps call directly
    /// rather than going through a `FileJob` (neither this nor the trash-emptied-folders step below goes through
    /// `FileOperationQueue` yet — see the type-level deviation note).
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
    nonisolated static func trashEmptiedFolders(under root: String) async -> Int {
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
