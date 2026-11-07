/// A file entry suitable for display and bounded ranking. `logicalSize` is
/// the file's byte length, not its physical/APFS allocation.
struct StorageScanFile: Sendable, Equatable, Identifiable {
    var id: String { relativePath }
    let name: String
    let relativePath: String
    let logicalSize: Int64
}

struct StorageScanProgress: Sendable, Equatable {
    let visitedEntries: Int
    let fileCount: Int
    let skippedCount: Int
    let currentRelativePath: String
}

enum StorageScanStatus: Sendable, Equatable {
    case completed
    case partial
    case cancelled
    case failed
}

enum StorageScanFailure: Sendable, Equatable {
    case unavailableRoot
    case rootIsNotDirectory
    case rootNotReadable
    case rootCloudOnly
}

struct StorageScanResult: Sendable, Equatable {
    let status: StorageScanStatus
    let failure: StorageScanFailure?
    let visitedEntries: Int
    let fileCount: Int
    let skippedCount: Int
    let logicalBytes: Int64
    let didOverflow: Bool
    let largestFiles: [StorageScanFile]
    var tree: StorageTree? = nil
}

/// Pure aggregation rules shared by the app scanner and logic tests.
struct StorageScanAccumulator: Sendable, Equatable {
    private(set) var visitedEntries = 0
    private(set) var fileCount = 0
    private(set) var skippedCount = 0
    private(set) var logicalBytes: Int64 = 0
    private(set) var largestFiles: [StorageScanFile] = []
    private(set) var didOverflow = false

    mutating func visitEntry() {
        if visitedEntries < Int.max { visitedEntries += 1 }
    }

    mutating func skipEntry() {
        visitEntry()
        markSkippedCurrentEntry()
    }

    mutating func markSkippedCurrentEntry() {
        if skippedCount < Int.max { skippedCount += 1 }
    }

    /// Inode identity of a file with more than one hard link (`st_nlink > 1`). Only such files are remembered, so
    /// ordinary folders keep O(1) extra memory.
    struct HardLinkID: Hashable, Sendable {
        let device: UInt64
        let inode: UInt64
    }
    private(set) var seenHardLinks: Set<HardLinkID> = []

    /// A second path to an already-counted hard-linked file is a visited entry, not a new file: its bytes exist once.
    mutating func include(_ file: StorageScanFile, hardLink: HardLinkID?, limit: Int = 50) {
        if let hardLink, !seenHardLinks.insert(hardLink).inserted {
            visitEntry()
            return
        }
        include(file, limit: limit)
    }

    mutating func include(_ file: StorageScanFile, limit: Int = 50) {
        visitEntry()
        guard file.logicalSize >= 0 else {
            if skippedCount < Int.max { skippedCount += 1 }
            return
        }

        if fileCount < Int.max { fileCount += 1 }
        let (sum, overflow) = logicalBytes.addingReportingOverflow(file.logicalSize)
        if overflow {
            logicalBytes = Int64.max
            didOverflow = true
        } else {
            logicalBytes = sum
        }

        StorageScanRules.insert(file, into: &largestFiles, limit: limit)
    }

    func result(status requestedStatus: StorageScanStatus, failure: StorageScanFailure? = nil) -> StorageScanResult {
        let status: StorageScanStatus
        if requestedStatus == .completed, skippedCount > 0 || didOverflow {
            status = .partial
        } else {
            status = requestedStatus
        }
        return StorageScanResult(
            status: status,
            failure: failure,
            visitedEntries: visitedEntries,
            fileCount: fileCount,
            skippedCount: skippedCount,
            logicalBytes: logicalBytes,
            didOverflow: didOverflow,
            largestFiles: largestFiles
        )
    }
}

enum StorageScanRules {
    static let largestFileLimit = 50

    /// Inserts into a deterministically sorted, bounded list without copying
    /// the whole top-N array for every scanned file.
    static func insert(_ file: StorageScanFile, into files: inout [StorageScanFile], limit: Int = largestFileLimit) {
        guard limit > 0 else {
            files.removeAll(keepingCapacity: true)
            return
        }

        var low = 0
        var high = files.count
        while low < high {
            let middle = low + (high - low) / 2
            if precedes(file, files[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        guard low < limit else { return }
        files.insert(file, at: low)
        if files.count > limit { files.removeLast() }
    }

    static func precedes(_ lhs: StorageScanFile, _ rhs: StorageScanFile) -> Bool {
        if lhs.logicalSize != rhs.logicalSize { return lhs.logicalSize > rhs.logicalSize }
        return lhs.relativePath.utf8.lexicographicallyPrecedes(rhs.relativePath.utf8)
    }
}
