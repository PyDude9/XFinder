import Foundation
import Darwin

/// Scans one user-selected folder off the main actor. `FileWalk` is used so
/// the scan sees AppleDouble files that Foundation's directory enumerator can
/// hide, never follows symlinks, and preserves XFinder's measured traversal
/// behavior. Results retain bounded top-file metadata and a bounded chart hierarchy.
enum StorageScanEngine {
    static func scan(
        rootURL: URL,
        onProgress: @escaping @Sendable (StorageScanProgress) -> Void
    ) async -> StorageScanResult {
        let worker = Task.detached(priority: .utility) {
            scanSynchronously(rootURL: rootURL, onProgress: onProgress)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func scanSynchronously(
        rootURL: URL,
        onProgress: @Sendable (StorageScanProgress) -> Void
    ) -> StorageScanResult {
        let root = rootURL.standardizedFileURL
        let startedAccess = root.startAccessingSecurityScopedResource()
        defer {
            if startedAccess { root.stopAccessingSecurityScopedResource() }
        }

        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0 else {
            return StorageScanAccumulator().result(status: .failed, failure: .unavailableRoot)
        }
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            return StorageScanAccumulator().result(status: .failed, failure: .rootIsNotDirectory)
        }
        guard !isCloudOnly(root, stat: rootStat) else {
            return StorageScanAccumulator().result(status: .failed, failure: .rootCloudOnly)
        }

        guard access(root.path, R_OK | X_OK) == 0 else {
            return StorageScanAccumulator().result(status: .failed, failure: .rootNotReadable)
        }

        var accumulator = StorageScanAccumulator()
        var tree = StorageTreeBuilder(name: root.lastPathComponent)
        var currentPath = ""
        var lastPublishedAt: TimeInterval = 0

        let walk = FileWalk.walk(
            root,
            limit: Int.max,
            isCancelled: { Task.isCancelled },
            onOther: { accumulator.skipEntry(); tree.recordSkippedEntry() },
            // A link is deliberately not followed; that is not a gap, so it must not make the result "partial".
            onLink: { accumulator.visitEntry() }
        ) { url, isDirectory, byteSize in
            guard !Task.isCancelled else { return .skip }
            currentPath = relativePath(of: url, under: root)

            var itemStat = stat()
            guard lstat(url.path, &itemStat) == 0 else {
                accumulator.skipEntry()
                tree.recordSkippedEntry()
                return isDirectory ? .skip : .descend
            }

            if isDirectory {
                tree.directory(currentPath, skipped: itemStat.st_dev != rootStat.st_dev || isCloudOnly(url, stat: itemStat))
                accumulator.visitEntry()
                // FileWalk does not descend through mount points. Count that
                // boundary as skipped so the UI labels the result partial.
                if itemStat.st_dev != rootStat.st_dev {
                    accumulator.markSkippedCurrentEntry()
                    return .skip
                }
                if isCloudOnly(url, stat: itemStat) {
                    accumulator.markSkippedCurrentEntry()
                    return .skip
                }
            } else if isCloudOnly(url, stat: itemStat) {
                accumulator.skipEntry()
                tree.recordSkippedEntry()
            } else {
                let previousCount = accumulator.fileCount
                accumulator.include(StorageScanFile(
                    name: url.lastPathComponent,
                    relativePath: currentPath,
                    logicalSize: byteSize
                ), hardLink: itemStat.st_nlink > 1
                    ? .init(device: UInt64(UInt32(bitPattern: itemStat.st_dev)), inode: UInt64(itemStat.st_ino)) : nil)
                if accumulator.fileCount > previousCount {
                    tree.file(.init(name: url.lastPathComponent, relativePath: currentPath, logicalSize: byteSize))
                }
            }

            if accumulator.visitedEntries.isMultiple(of: 128) {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastPublishedAt >= 0.2 {
                    lastPublishedAt = now
                    onProgress(progress(from: accumulator, path: currentPath))
                }
            }
            return .descend
        }

        if Task.isCancelled || walk.cancelled {
            onProgress(progress(from: accumulator, path: currentPath))
            return accumulator.result(status: .cancelled)
        }
        if walk.truncated { accumulator.markSkippedCurrentEntry() }

        // The root can disappear or lose access after the initial permission
        // check. Do not present a zero-entry result as a successful empty scan.
        if access(root.path, R_OK | X_OK) != 0 {
            accumulator.markSkippedCurrentEntry()
        }

        onProgress(progress(from: accumulator, path: currentPath))
        var result = accumulator.result(status: .completed)
        result.tree = tree.finish()
        return result
    }

    private static func progress(from accumulator: StorageScanAccumulator, path: String) -> StorageScanProgress {
        StorageScanProgress(
            visitedEntries: accumulator.visitedEntries,
            fileCount: accumulator.fileCount,
            skippedCount: accumulator.skippedCount,
            currentRelativePath: path
        )
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(url.path.dropFirst(rootPath.count))
    }

    /// `SF_DATALESS` alone. Measured 2026-11-06: on 2 340 iCloud Drive entries it matched
    /// `ubiquitousItemDownloadingStatus == .notDownloaded` for all 1 932 cloud-only files (0 disagreements), while the
    /// per-entry `resourceValues` lookup made the scan 6–8× slower on local folders and 23× slower on iCloud Drive.
    private static func isCloudOnly(_ url: URL, stat info: stat) -> Bool {
        info.st_flags & UInt32(SF_DATALESS) != 0
    }
}
