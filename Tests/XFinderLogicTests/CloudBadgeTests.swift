import XCTest

final class CloudBadgeTests: XCTestCase {
    private let current = "NSURLUbiquitousItemDownloadingStatusCurrent"
    private let downloaded = "NSURLUbiquitousItemDownloadingStatusDownloaded"
    private let notDownloaded = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"

    // MARK: badge — plain local file

    func test_badge_noUbiquityNoStatus_isNone() {
        let facts = CloudFacts()
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    func test_badge_isUbiquitousExplicitlyFalse_noStatus_isNone() {
        let facts = CloudFacts(isUbiquitous: false)
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    /// A local file guard must trigger on `isUbiquitous != true`, not `isUbiquitous == true` — stray error flags on
    /// a plain non-cloud file (no status at all) must not leak through as a cloud badge.
    func test_badge_isUbiquitousFalse_noStatus_errorFlagsIgnored_isNone() {
        let facts = CloudFacts(isUbiquitous: false, hasDownloadError: true, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    /// "isUbiquitous != true and no status" only skips to none when BOTH are absent/false — a status alone
    /// (e.g. a File Provider item that never set isUbiquitousItem but does report a downloading status) must
    /// still be classified, per the written rule "isUbiquitous != true **và không có status** ⇒ none".
    func test_badge_isUbiquitousFalse_butStatusPresent_isNotForcedToNone() {
        let facts = CloudFacts(isUbiquitous: false, downloadingStatus: notDownloaded)
        XCTAssertEqual(CloudRules.badge(facts), .cloudOnly)
    }

    // MARK: badge — cloud-only

    func test_badge_notDownloaded_isCloudOnly() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        XCTAssertEqual(CloudRules.badge(facts), .cloudOnly)
    }

    func test_badge_current_noOtherFlags_isNone() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current)
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    func test_badge_downloadedStatus_noOtherFlags_isNone() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: downloaded)
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    // MARK: badge — downloading / uploading

    func test_badge_isDownloading_isDownloading() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isDownloading: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloading)
    }

    func test_badge_isUploading_isUploading() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploading: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploading)
    }

    // MARK: badge — priority order

    /// downloading beats uploading when (hypothetically) both flags are set.
    func test_badge_downloadingBeatsUploading() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isDownloading: true, isUploading: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloading)
    }

    /// downloading beats cloudOnly.
    func test_badge_downloadingBeatsCloudOnly() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isDownloading: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloading)
    }

    /// uploading beats cloudOnly.
    func test_badge_uploadingBeatsCloudOnly() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isUploading: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploading)
    }

    func test_badge_downloadErrorBeatsUploadError() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, hasDownloadError: true, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloadFailed)
    }

    func test_badge_uploadErrorAlone_isUploadFailed() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploadFailed)
    }

    /// An error flag wins even over a concurrent transfer flag: an errored download is not "in progress".
    func test_badge_downloadErrorBeatsIsDownloading() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isDownloading: true, hasDownloadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloadFailed)
    }

    func test_badge_uploadErrorBeatsIsUploading() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploading: true, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploadFailed)
    }

    /// Error flags also outrank cloudOnly.
    func test_badge_downloadErrorBeatsCloudOnly() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, hasDownloadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloadFailed)
    }

    func test_badge_uploadErrorBeatsCloudOnly() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploadFailed)
    }

    /// Unrecognized / nil status with isUbiquitous true and no flags falls through to none (e.g. a status the
    /// OS hasn't reported yet for a brand-new ubiquitous placeholder).
    func test_badge_isUbiquitousTrue_statusNil_noFlags_isNone() {
        let facts = CloudFacts(isUbiquitous: true)
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    func test_badge_unknownStatusString_noFlags_isNone() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: "SomeFutureStatus")
        XCTAssertEqual(CloudRules.badge(facts), .none)
    }

    // MARK: canDownload

    func test_canDownload_notDownloaded_notInFlight_true() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        XCTAssertTrue(CloudRules.canDownload(facts))
    }

    func test_canDownload_notDownloaded_butAlreadyDownloading_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isDownloading: true)
        XCTAssertFalse(CloudRules.canDownload(facts))
    }

    func test_canDownload_current_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current)
        XCTAssertFalse(CloudRules.canDownload(facts))
    }

    func test_canDownload_downloadedStatus_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: downloaded)
        XCTAssertFalse(CloudRules.canDownload(facts))
    }

    func test_canDownload_noStatus_false() {
        XCTAssertFalse(CloudRules.canDownload(CloudFacts()))
    }

    /// isDownloading == nil (unknown) must not be treated as "in flight" and block the offer.
    func test_canDownload_isDownloadingNil_stillTrue() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isDownloading: nil)
        XCTAssertTrue(CloudRules.canDownload(facts))
    }

    // MARK: canEvict

    func test_canEvict_current_uploaded_notUploading_true() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: true)
        XCTAssertTrue(CloudRules.canEvict(facts))
    }

    func test_canEvict_downloadedStatus_uploaded_true() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: downloaded, isUploaded: true)
        XCTAssertTrue(CloudRules.canEvict(facts))
    }

    func test_canEvict_notDownloaded_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, isUploaded: true)
        XCTAssertFalse(CloudRules.canEvict(facts))
    }

    /// Evicting the only copy of a file that never finished uploading would destroy data — must stay false.
    func test_canEvict_isUploadedFalse_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: false)
        XCTAssertFalse(CloudRules.canEvict(facts))
    }

    /// isUploaded unknown (nil) must not be treated as uploaded — evicting needs certainty.
    func test_canEvict_isUploadedNil_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: nil)
        XCTAssertFalse(CloudRules.canEvict(facts))
    }

    func test_canEvict_currentlyUploading_false() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploading: true, isUploaded: true)
        XCTAssertFalse(CloudRules.canEvict(facts))
    }

    func test_canEvict_noStatus_false() {
        XCTAssertFalse(CloudRules.canEvict(CloudFacts(isUploaded: true)))
    }

    // MARK: CloudFacts defaults

    func test_cloudFacts_defaultInit_allNilOrFalse() {
        let facts = CloudFacts()
        XCTAssertNil(facts.isUbiquitous)
        XCTAssertNil(facts.downloadingStatus)
        XCTAssertNil(facts.isDownloading)
        XCTAssertNil(facts.isUploading)
        XCTAssertNil(facts.isUploaded)
        XCTAssertFalse(facts.hasDownloadError)
        XCTAssertFalse(facts.hasUploadError)
    }

    func test_cloudFacts_equatable() {
        let a = CloudFacts(isUbiquitous: true, downloadingStatus: current)
        let b = CloudFacts(isUbiquitous: true, downloadingStatus: current)
        XCTAssertEqual(a, b)
    }

    // MARK: CloudBadge raw values (contract: String rawValue, case set is exact)

    func test_cloudBadge_allCasesPresent() {
        XCTAssertEqual(CloudBadge.none.rawValue, "none")
        XCTAssertEqual(CloudBadge.cloudOnly.rawValue, "cloudOnly")
        XCTAssertEqual(CloudBadge.downloading.rawValue, "downloading")
        XCTAssertEqual(CloudBadge.uploading.rawValue, "uploading")
        XCTAssertEqual(CloudBadge.downloadFailed.rawValue, "downloadFailed")
        XCTAssertEqual(CloudBadge.uploadFailed.rawValue, "uploadFailed")
    }

    // MARK: adversarial — isUbiquitous real-world values (measured: a plain local file reports `nil`, never `false`
    // — see scratchpad probe; these only exercise the written rule's literal "!= true", not a claim that `false`
    // occurs in practice)

    /// `URLResourceValues.isUbiquitousItem` is measured `nil` (not `false`) for a file with no cloud story at all.
    /// `badge`'s guard is `!= true`, so `nil` must take the same "no opinion yet" path as explicit `false` — this
    /// pins that the guard doesn't accidentally require `isUbiquitous == false` specifically.
    func test_badge_isUbiquitousNil_statusPresent_isNotForcedToNone() {
        let facts = CloudFacts(isUbiquitous: nil, downloadingStatus: notDownloaded)
        XCTAssertEqual(CloudRules.badge(facts), .cloudOnly)
    }

    /// Error flags take priority even with no downloading status at all (e.g. an upload that failed before the
    /// system ever attached a downloading-status key) — not just when a status happens to be present.
    func test_badge_isUbiquitousTrue_noStatus_downloadError_isDownloadFailed() {
        let facts = CloudFacts(isUbiquitous: true, hasDownloadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .downloadFailed)
    }

    func test_badge_isUbiquitousTrue_noStatus_uploadError_isUploadFailed() {
        let facts = CloudFacts(isUbiquitous: true, hasUploadError: true)
        XCTAssertEqual(CloudRules.badge(facts), .uploadFailed)
    }

    // MARK: adversarial — canDownload/canEvict consistency with badge's permissive isUbiquitous reading

    /// `canDownload` keys off `downloadingStatus` alone (no `isUbiquitous` check), so it must agree with `badge`
    /// treating a present status as significant even when `isUbiquitous` is `false`/`nil` (File Provider domains
    /// that never set `isUbiquitousItem` — spec T-T28-9, not yet measured on this machine).
    func test_canDownload_isUbiquitousFalse_statusNotDownloaded_true() {
        let facts = CloudFacts(isUbiquitous: false, downloadingStatus: notDownloaded)
        XCTAssertTrue(CloudRules.canDownload(facts))
    }

    func test_canEvict_isUbiquitousFalse_downloadedAndUploaded_true() {
        let facts = CloudFacts(isUbiquitous: false, downloadingStatus: current, isUploaded: true)
        XCTAssertTrue(CloudRules.canEvict(facts))
    }

    /// `canDownload`/`canEvict` can never agree for the same facts: the former requires `notDownloaded`, the
    /// latter requires `current`/`downloaded` — mutually exclusive string values. Pin the contradiction-free
    /// property directly so a future edit that breaks it (e.g. loosening one status check) is caught here even
    /// if no single existing example test happens to exercise the new overlap.
    func test_canDownload_and_canEvict_areMutuallyExclusive_acrossAllThreeStatuses() {
        for status in [current, downloaded, notDownloaded, nil] {
            for isDownloading in [true, false, nil] {
                for isUploading in [true, false, nil] {
                    for isUploaded in [true, false, nil] {
                        let facts = CloudFacts(
                            isUbiquitous: true, downloadingStatus: status, isDownloading: isDownloading,
                            isUploading: isUploading, isUploaded: isUploaded
                        )
                        XCTAssertFalse(
                            CloudRules.canDownload(facts) && CloudRules.canEvict(facts),
                            "canDownload and canEvict both true for \(facts)"
                        )
                    }
                }
            }
        }
    }

    /// `canDownload` still offers a retry on a failed download (Finder lets you retry) — an error flag alone must
    /// not suppress the offer as long as the item is genuinely not-downloaded and not currently in flight.
    func test_canDownload_notDownloaded_withDownloadError_stillTrue() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, hasDownloadError: true)
        XCTAssertTrue(CloudRules.canDownload(facts))
    }
}
