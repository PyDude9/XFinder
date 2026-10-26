import XCTest

final class CloudProvidersTests: XCTestCase {
    private let root = "/Users/x/Library/CloudStorage"

    // MARK: parse — Google Drive

    func test_parse_googleDrive_email_account() {
        let provider = CloudProviders.parse(folderName: "GoogleDrive-dev3@howitwork.app", root: root)
        XCTAssertEqual(provider?.kind, .googleDrive)
        XCTAssertEqual(provider?.account, "dev3@howitwork.app")
        XCTAssertEqual(provider?.displayName, "dev3@howitwork.app")
        XCTAssertEqual(provider?.rootPath, root + "/GoogleDrive-dev3@howitwork.app")
    }

    /// 2026-10-26: `~/Library/CloudStorage/.DS_Store` showed up as a sidebar Location — hidden names are never roots.
    func test_parse_hiddenNames_areNotProviders() {
        for name in [".DS_Store", ".Trash", ".hidden-provider"] {
            XCTAssertNil(CloudProviders.parse(folderName: name, root: root), name)
        }
    }

    func test_parse_googleDrive_emptyAccount_fallsThroughToOther() {
        // "GoogleDrive-" with nothing after the dash is not a valid email account — not dropped entirely (spec §1:
        // unrecognized CloudStorage folders still show up), just not classified as Google Drive.
        let provider = CloudProviders.parse(folderName: "GoogleDrive-", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "GoogleDrive-")
    }

    func test_parse_googleDrive_bareWithoutDash_isOther() {
        // "GoogleDrive" with no trailing "-<email>" is not the documented shape — falls through to .other rather
        // than being silently dropped (spec §1: unrecognized CloudStorage folders still show up, Finder-style).
        let provider = CloudProviders.parse(folderName: "GoogleDrive", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "GoogleDrive")
    }

    // MARK: parse — Dropbox

    func test_parse_dropbox_singleAccount_noAccountField() {
        let provider = CloudProviders.parse(folderName: "Dropbox", root: root)
        XCTAssertEqual(provider?.kind, .dropbox)
        XCTAssertNil(provider?.account)
        XCTAssertEqual(provider?.displayName, "Dropbox")
    }

    func test_parse_dropbox_team() {
        let provider = CloudProviders.parse(folderName: "Dropbox-Acme Corp", root: root)
        XCTAssertEqual(provider?.kind, .dropbox)
        XCTAssertEqual(provider?.account, "Acme Corp")
        XCTAssertEqual(provider?.displayName, "Dropbox – Acme Corp")
    }

    func test_parse_dropbox_lookAlikeSuffix_isOther_notDropbox() {
        // "Dropbox2" is a folder that merely starts with "Dropbox" — must not be classified as the Dropbox provider
        // (explicit look-alike case called out in the task).
        let provider = CloudProviders.parse(folderName: "Dropbox2", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "Dropbox2")
    }

    func test_parse_dropbox_emptyTeamSuffix_isOther() {
        let provider = CloudProviders.parse(folderName: "Dropbox-", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "Dropbox-")
    }

    // MARK: parse — OneDrive

    func test_parse_oneDrive_personal_noAccountField() {
        let provider = CloudProviders.parse(folderName: "OneDrive-Personal", root: root)
        XCTAssertEqual(provider?.kind, .oneDrive)
        XCTAssertNil(provider?.account)
        XCTAssertEqual(provider?.displayName, "OneDrive")
    }

    func test_parse_oneDrive_business_name() {
        let provider = CloudProviders.parse(folderName: "OneDrive-Acme Corp", root: root)
        XCTAssertEqual(provider?.kind, .oneDrive)
        XCTAssertEqual(provider?.account, "Acme Corp")
        XCTAssertEqual(provider?.displayName, "OneDrive – Acme Corp")
    }

    func test_parse_oneDrive_lookAlikeSuffix_isOther() {
        let provider = CloudProviders.parse(folderName: "OneDriveBackup", root: root)
        XCTAssertEqual(provider?.kind, .other)
    }

    // MARK: parse — Box

    func test_parse_box_doublesOwnName() {
        let provider = CloudProviders.parse(folderName: "Box-Box", root: root)
        XCTAssertEqual(provider?.kind, .box)
        XCTAssertNil(provider?.account)
        XCTAssertEqual(provider?.displayName, "Box")
    }

    func test_parse_box_otherSuffix_isOther() {
        // Only the literal "Box-Box" is the documented shape; anything else under a "Box" prefix is not assumed to
        // be Box's own multi-account scheme (never observed/documented) — falls through to .other.
        let provider = CloudProviders.parse(folderName: "Box-Work", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "Box-Work")
    }

    // MARK: parse — iCloud Drive excluded, other, edge cases

    func test_parse_iCloudDriveFolder_isNil() {
        // iCloud Drive is surfaced through its own dedicated path (spec §1 "iCloud Drive riêng"), never through this
        // generic CloudStorage parser, even though macOS places its folder in the same directory (measured on this
        // machine: "iCloudDrive-iCloudDrive (21-4-25 21:57)").
        XCTAssertNil(CloudProviders.parse(folderName: "iCloudDrive-iCloudDrive (21-4-25 21:57)", root: root))
    }

    func test_parse_unknownProvider_isOther_withRawNameAsAccountAndDisplay() {
        let provider = CloudProviders.parse(folderName: "SomeFutureProvider-x", root: root)
        XCTAssertEqual(provider?.kind, .other)
        XCTAssertEqual(provider?.account, "SomeFutureProvider-x")
        XCTAssertEqual(provider?.displayName, "SomeFutureProvider-x")
        XCTAssertEqual(provider?.rootPath, root + "/SomeFutureProvider-x")
    }

    func test_parse_emptyFolderName_isNil() {
        XCTAssertNil(CloudProviders.parse(folderName: "", root: root))
    }

    // MARK: provider(containing:) — component-boundary matching

    func test_containing_pathInsideProviderRoot_matches() {
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        let found = CloudProviders.provider(containing: root + "/Dropbox/Reports/q3.pdf", in: [dropbox])
        XCTAssertEqual(found, dropbox)
    }

    func test_containing_exactRootPath_matches() {
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        XCTAssertEqual(CloudProviders.provider(containing: root + "/Dropbox", in: [dropbox]), dropbox)
    }

    func test_containing_lookAlikeSiblingFolder_doesNotMatch() {
        // The exact look-alike case named in the task: "/CloudStorage/Dropbox2" must not be treated as inside
        // "/CloudStorage/Dropbox" — a bare string-prefix check would wrongly match here.
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        XCTAssertNil(CloudProviders.provider(containing: root + "/Dropbox2/file.txt", in: [dropbox]))
    }

    func test_containing_lookAlikeSiblingFolder_exactPath_doesNotMatch() {
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        XCTAssertNil(CloudProviders.provider(containing: root + "/Dropbox2", in: [dropbox]))
    }

    func test_containing_unrelatedPath_doesNotMatch() {
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        XCTAssertNil(CloudProviders.provider(containing: "/Users/x/Desktop/file.txt", in: [dropbox]))
    }

    func test_containing_emptyProviderList_doesNotMatch() {
        XCTAssertNil(CloudProviders.provider(containing: root + "/Dropbox/file.txt", in: []))
    }

    func test_containing_picksCorrectProviderAmongMultiple() {
        let drive = CloudProvider(kind: .googleDrive, account: "a@x.com", displayName: "a@x.com", rootPath: root + "/GoogleDrive-a@x.com")
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        let found = CloudProviders.provider(containing: root + "/Dropbox/notes.txt", in: [drive, dropbox])
        XCTAssertEqual(found, dropbox)
    }

    func test_containing_parentOfRoot_doesNotMatch() {
        // A path that is an ancestor of a provider root (not inside it) must not match — only a path AT or BELOW the
        // root counts as "inside".
        let dropbox = CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox")
        XCTAssertNil(CloudProviders.provider(containing: root, in: [dropbox]))
    }

    // MARK: CloudMoveRules — copyOutBlocked / warnBeforeMovingOut

    private var dropbox: CloudProvider { CloudProvider(kind: .dropbox, account: nil, displayName: "Dropbox", rootPath: root + "/Dropbox") }
    private let notDownloaded = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"
    private let current = "NSURLUbiquitousItemDownloadingStatusCurrent"

    func test_copyOutBlocked_cloudOnlySource_destinationOutside_isBlocked() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertTrue(blocked)
    }

    func test_copyOutBlocked_cloudOnlySource_destinationStillInsideSameProvider_isNotBlocked() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: root + "/Dropbox/Archive/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(blocked)
    }

    func test_copyOutBlocked_cloudOnlySource_destinationInsideAnotherCloudProvider_isNotBlocked() {
        let drive = CloudProvider(kind: .googleDrive, account: "a@x.com", displayName: "a@x.com", rootPath: root + "/GoogleDrive-a@x.com")
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: root + "/GoogleDrive-a@x.com/report.pdf", providers: [dropbox, drive]
        )
        XCTAssertFalse(blocked)
    }

    func test_copyOutBlocked_downloadedSource_isNeverBlocked() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: true)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(blocked)
    }

    func test_copyOutBlocked_cloudOnlySource_notInAnyParsedProvider_isStillBlocked() {
        // The headline R28 acceptance scenario (contract §Nghiệm thu) is an iCloud Drive cloud-only item, and
        // `CloudProviders.parse` deliberately excludes iCloud Drive (§1 "iCloud Drive riêng") — an iCloud path never
        // appears in `providers`. Gating on source-path containment would make this permanently unblockable; the
        // real gate is `sourceFacts` alone.
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: "/Users/x/Mobile Documents/com~apple~CloudDocs/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertTrue(blocked)
    }

    func test_copyOutBlocked_plainLocalFile_isNotBlocked() {
        let facts = CloudFacts()
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: "/Users/x/Desktop/report.pdf",
            destinationPath: "/Users/x/Documents/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(blocked)
    }

    func test_copyOutBlocked_downloadFailedSource_stillCloudOnly_isBlocked() {
        // Spec §5: "Download failed: Transfer incomplete; file remains cloud-only" — `CloudRules.badge` reports
        // `.downloadFailed` (not `.cloudOnly`) for this combination, so the gate must not be `badge == .cloudOnly`.
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, hasDownloadError: true)
        let blocked = CloudMoveRules.copyOutBlocked(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertTrue(blocked)
    }

    func test_warnBeforeMovingOut_downloadedSource_destinationOutside_warns() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: true)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertTrue(warn)
    }

    func test_warnBeforeMovingOut_downloadedSource_destinationStillInside_doesNotWarn() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: true)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: root + "/Dropbox/Archive/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }

    func test_warnBeforeMovingOut_cloudOnlySource_doesNotWarn_blockedInstead() {
        // Mutually exclusive with copyOutBlocked by badge state — a cloud-only source is blocked, not warned.
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }

    func test_warnBeforeMovingOut_plainLocalFile_doesNotWarn() {
        let facts = CloudFacts()
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: "/Users/x/Desktop/report.pdf",
            destinationPath: "/Users/x/Documents/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }

    func test_warnBeforeMovingOut_downloadFailedSource_doesNotWarn_blockedInstead() {
        // Same fix as copyOutBlocked's counterpart: a download-failed item has no local bytes (spec §5 "remains
        // cloud-only"), so it must be blocked, not warned — `bytesPresentLocally` is false here.
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: notDownloaded, hasDownloadError: true)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }

    func test_warnBeforeMovingOut_uploadNeverReachedCloud_doesNotWarn() {
        // Spec §5: "Upload failed: File never reached cloud; Mac copy is the sole copy" — there is no cloud copy to
        // lose, so warning about losing cloud sync would be misleading.
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: false, hasUploadError: true)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }

    func test_warnBeforeMovingOut_notYetUploaded_doesNotWarn() {
        let facts = CloudFacts(isUbiquitous: true, downloadingStatus: current, isUploaded: false)
        let warn = CloudMoveRules.warnBeforeMovingOut(
            sourceFacts: facts, sourcePath: root + "/Dropbox/report.pdf",
            destinationPath: "/Users/x/Desktop/report.pdf", providers: [dropbox]
        )
        XCTAssertFalse(warn)
    }
}
