import Foundation
import Darwin

/// Scans one user-selected folder off the main actor. `FileWalk` is used so
/// the scan sees AppleDouble files that Foundation's directory enumerator can
/// hide, never follows symlinks, and preserves XFinder's measured traversal
/// behavior. Results contain only bounded top-file metadata.
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
        var currentPath = ""
        var lastPublishedAt: TimeInterval = 0

        let walk = FileWalk.walk(
            root,
            limit: Int.max,
            isCancelled: { Task.isCancelled },
            onOther: { accumulator.skipEntry() }
        ) { url, isDirectory, byteSize in
            guard !Task.isCancelled else { return .skip }
            currentPath = relativePath(of: url, under: root)

            var itemStat = stat()
            guard lstat(url.path, &itemStat) == 0 else {
                accumulator.skipEntry()
                return isDirectory ? .skip : .descend
            }

            if isDirectory {
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
            } else {
                accumulator.include(StorageScanFile(
                    name: url.lastPathComponent,
                    relativePath: currentPath,
                    logicalSize: byteSize
                ))
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
        return accumulator.result(status: .completed)
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

    private static func isCloudOnly(_ url: URL, stat info: stat) -> Bool {
        if info.st_flags & UInt32(SF_DATALESS) != 0 { return true }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
              values.isUbiquitousItem == true,
              let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        else { return false }
        return status == .notDownloaded
    }
}
