import Foundation

/// The cloud-badge facts a file view shows per visible item (List, Icons, Columns), cached per path. One copy of
/// what three views used to duplicate privately.
///
/// An item can only be ubiquitous inside a ubiquitous folder (iCloud Drive, a File Provider domain such as
/// `~/Library/CloudStorage/…`, Desktop & Documents when synced), so the folder is asked once and the per-item read —
/// an XPC round trip to the cloud daemons — is skipped everywhere else. Measured 2026-10-26 on the owner's home
/// folder: the per-row read was ~100 ms of a 3,3 s main-thread stall while scrolling, in a folder with no cloud item.
@MainActor
final class CloudFactsCache {
    private var factsByPath: [String: CloudFacts] = [:]
    private var folderIsCloud: [String: Bool] = [:]

    /// Reads ubiquity of a folder; injectable so the gating is testable without a cloud account.
    typealias FolderProbe = (String) -> Bool
    /// Reads the full facts of one item.
    typealias ItemReader = (String) -> CloudFacts

    private let probeFolder: FolderProbe
    private let readItem: ItemReader

    init(probeFolder: @escaping FolderProbe = CloudFactsCache.isUbiquitousFolder,
         readItem: @escaping ItemReader = CloudFactsReader.read(path:)) {
        self.probeFolder = probeFolder
        self.readItem = readItem
    }

    func facts(for path: String) -> CloudFacts {
        if let cached = factsByPath[path] { return cached }
        let parent: String = (path as NSString).deletingLastPathComponent
        let inCloudFolder: Bool
        if let known = folderIsCloud[parent] {
            inCloudFolder = known
        } else {
            inCloudFolder = !parent.isEmpty && parent != path && probeFolder(parent)
            folderIsCloud[parent] = inCloudFolder
        }
        let facts: CloudFacts = inCloudFolder ? readItem(path) : CloudFacts()
        factsByPath[path] = facts
        return facts
    }

    /// A new listing: download/upload state may have changed, and so may a folder's sync setting.
    func removeAll() {
        factsByPath.removeAll()
        folderIsCloud.removeAll()
    }

    nonisolated static func isUbiquitousFolder(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem ?? false
    }
}

/// The one disk read of an item's cloud facts (an XPC round trip to the cloud daemons — never per row on main
/// without `CloudFactsCache`'s folder gate in front of it).
enum CloudFactsReader {
    nonisolated static func read(path: String) -> CloudFacts {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return CloudFacts() }
        return CloudFacts(
            isUbiquitous: values.isUbiquitousItem,
            downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
            isDownloading: values.ubiquitousItemIsDownloading,
            isUploading: values.ubiquitousItemIsUploading,
            isUploaded: values.ubiquitousItemIsUploaded,
            hasDownloadError: values.ubiquitousItemDownloadingError != nil,
            hasUploadError: values.ubiquitousItemUploadingError != nil)
    }
}
