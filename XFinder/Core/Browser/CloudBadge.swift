import Foundation

/// XF-T28 §1 (2026-10-24) — the badge state for one `DirectoryEntry` under cloud storage (iCloud Drive, and anything
/// else that publishes the same `NSURLResourceKey`s, e.g. OneDrive via File Provider — T-T28-9, not yet measured on
/// this machine). Reading these resource values never triggers a download (measured: a not-downloaded iCloud item
/// reports `size: 183024, alloc: 0` without the file being fetched) — a reader elsewhere fills `CloudFacts` from
/// `URLResourceValues`; this file only classifies what it is handed.
enum CloudBadge: String, Sendable {
    case none, cloudOnly, downloading, uploading, downloadFailed, uploadFailed
}

/// The raw resource-value facts a badge is computed from. Every field is optional because
/// `URLResourceValues` leaves a key `nil` when the file system has no opinion (a local-only file has no
/// `isUbiquitousItem` story at all), and `CloudRules.badge` must tell "not on the cloud" apart from
/// "cloud status unknown".
struct CloudFacts: Equatable, Sendable {
    var isUbiquitous: Bool?
    /// Raw `URLUbiquitousItemDownloadingStatus` value: "NSURLUbiquitousItemDownloadingStatusCurrent" |
    /// "…Downloaded" | "…NotDownloaded".
    var downloadingStatus: String?
    var isDownloading: Bool?
    var isUploading: Bool?
    var isUploaded: Bool?
    var hasDownloadError: Bool
    var hasUploadError: Bool

    init(
        isUbiquitous: Bool? = nil, downloadingStatus: String? = nil, isDownloading: Bool? = nil,
        isUploading: Bool? = nil, isUploaded: Bool? = nil, hasDownloadError: Bool = false,
        hasUploadError: Bool = false
    ) {
        self.isUbiquitous = isUbiquitous
        self.downloadingStatus = downloadingStatus
        self.isDownloading = isDownloading
        self.isUploading = isUploading
        self.isUploaded = isUploaded
        self.hasDownloadError = hasDownloadError
        self.hasUploadError = hasUploadError
    }
}

enum CloudRules {
    private static let currentStatus = "NSURLUbiquitousItemDownloadingStatusCurrent"
    private static let downloadedStatus = "NSURLUbiquitousItemDownloadingStatusDownloaded"
    private static let notDownloadedStatus = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"

    /// Priority (spec §1/CloudBadge contract): download error > upload error > downloading > uploading >
    /// cloud-only (not downloaded) > none. `isUbiquitous != true` with no status at all is a plain local file:
    /// `none`. An error flag wins even over a concurrent downloading/uploading flag — a transfer that already
    /// errored is not "in progress" from the user's point of view.
    static func badge(_ facts: CloudFacts) -> CloudBadge {
        if facts.isUbiquitous != true && facts.downloadingStatus == nil {
            return .none
        }
        if facts.hasDownloadError { return .downloadFailed }
        if facts.hasUploadError { return .uploadFailed }
        if facts.isDownloading == true { return .downloading }
        if facts.isUploading == true { return .uploading }
        if facts.downloadingStatus == notDownloadedStatus { return .cloudOnly }
        return .none
    }

    /// "Tải về ngay" is offered only for an item that is actually sitting on the cloud and not already in flight.
    static func canDownload(_ facts: CloudFacts) -> Bool {
        facts.downloadingStatus == notDownloadedStatus && facts.isDownloading != true
    }

    /// "Gỡ bản tải" (`evictUbiquitousItem`) needs the item to be safely on the cloud already — otherwise evicting
    /// would destroy the only copy — so it is offered only once downloaded, uploaded, and not mid-upload.
    static func canEvict(_ facts: CloudFacts) -> Bool {
        let downloaded = facts.downloadingStatus == currentStatus || facts.downloadingStatus == downloadedStatus
        return downloaded && facts.isUploaded == true && facts.isUploading != true
    }
}
