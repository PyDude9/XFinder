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

    /// Alias for `canEvict` — spec §W8/contract ROLE names the action `canRemoveDownload` ("Gỡ bản tải") while
    /// `CloudBadgeTests`/`canEvict` already named the underlying mechanism (`evictUbiquitousItem`); both must refuse
    /// identically, so this simply forwards rather than duplicating the rule a second time.
    static func canRemoveDownload(_ facts: CloudFacts) -> Bool {
        canEvict(facts)
    }
}

/// XF-T30 W8 — pure rules for copying/moving items across a cloud-folder boundary. Spec §W8 / `spec-cloud.md` §7 (R28,
/// R29): a cloud-only file cannot leave its cloud folder at all (the bytes do not exist on disk to copy), while an
/// already-downloaded item leaving a cloud folder loses its cloud copy and sync to other devices — not catastrophic,
/// so that case is a warning, not a block.
///
/// Both rules gate on `sourceFacts` alone for "are the bytes here" (not on whether `sourcePath` happens to fall
/// inside a parsed `CloudProvider` root): the acceptance test for R28 (`docs/specs/XF-T30-w5b-w8-contract.md` §Nghiệm
/// thu) is an **iCloud Drive** cloud-only item, and `CloudProviders.parse` deliberately excludes iCloud Drive (§1 "iCloud
/// Drive riêng") — iCloud paths never appear in `providers`, so a source-path containment check would make `copyOutBlocked`
/// permanently false for the headline acceptance scenario. `CloudFacts`/`CloudRules.badge` already carries per-file cloud
/// status independent of which provider or mechanism (iCloud `NSMetadataItem` vs. CloudStorage provider) produced it.
enum CloudMoveRules {
    /// Bytes are present on this Mac: `.downloadingStatus` is Current or Downloaded. Deliberately does **not** go
    /// through `CloudRules.badge`, whose enum collapses "not downloaded" together with `downloadFailed`/`uploadFailed`
    /// (measured: `badge()` checks `hasDownloadError`/`hasUploadError` before `downloadingStatus`, so a failed download
    /// of a still-cloud-only file reports `.downloadFailed`, not `.cloudOnly` — using `badge == .cloudOnly` as the gate
    /// here would let a download-failed item, which per spec §5 "remains cloud-only," copy/move out unblocked).
    private static func bytesPresentLocally(_ facts: CloudFacts) -> Bool {
        facts.downloadingStatus == "NSURLUbiquitousItemDownloadingStatusCurrent"
            || facts.downloadingStatus == "NSURLUbiquitousItemDownloadingStatusDownloaded"
    }

    /// True when `source` has no local bytes (cloud-only, including a failed download that never completed) and
    /// `destination` falls outside every provider's root — this copy/move must be refused outright (contract:
    /// "chép/chuyển tệp chỉ-trên-mây ra ngoài thư mục đám mây ⇒ chặn"). A destination still inside the SAME or ANY
    /// cloud folder is never blocked here: moving a cloud-only item between two cloud folders (e.g. reorganizing
    /// inside Dropbox) does not need materialized bytes any more than leaving it in place does — provider apps
    /// reconcile that themselves. Source containment in `providers` is irrelevant — an iCloud Drive item (never a
    /// `CloudProvider`, §1) is blocked the same as a CloudStorage-provider one, driven entirely by `sourceFacts`.
    static func copyOutBlocked(sourceFacts: CloudFacts, sourcePath: String, destinationPath: String, providers: [CloudProvider]) -> Bool {
        guard sourceFacts.isUbiquitous == true, !bytesPresentLocally(sourceFacts) else { return false }
        return CloudProviders.provider(containing: destinationPath, in: providers) == nil
    }

    /// True when a fully-downloaded cloud item is about to leave every cloud folder it was in — worth a confirm
    /// ("xoá khỏi đám mây và các máy khác đang đồng bộ") rather than a silent move, per spec §7 "Moving an already-
    /// downloaded item out ... shows a warning." Never fires for a cloud-only item (that path is `copyOutBlocked`
    /// instead — the two are mutually exclusive on `bytesPresentLocally`) nor for a move that stays inside a cloud
    /// folder, nor for a plain local file (`isUbiquitous != true`) or one whose upload never reached the cloud
    /// (`hasUploadError`/not yet uploaded — spec §5 "Mac copy is the sole copy," so there is no cloud copy to warn
    /// about losing).
    static func warnBeforeMovingOut(sourceFacts: CloudFacts, sourcePath: String, destinationPath: String, providers: [CloudProvider]) -> Bool {
        guard sourceFacts.isUbiquitous == true, bytesPresentLocally(sourceFacts) else { return false }
        guard sourceFacts.hasUploadError != true, sourceFacts.isUploaded == true else { return false }
        return CloudProviders.provider(containing: destinationPath, in: providers) == nil
    }
}
