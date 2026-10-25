import XCTest
import Foundation

final class FileInfoRulesTests: XCTestCase {

    private func facts(
        name: String = "Report.pdf", path: String = "/Users/me/Report.pdf", isFolder: Bool = false,
        isPackage: Bool = false, logicalSize: Int64? = 1024, physicalSize: Int64? = 4096,
        created: Date = Date(timeIntervalSince1970: 1), modified: Date = Date(timeIntervalSince1970: 2),
        accessed: Date? = Date(timeIntervalSince1970: 3), posixMode: UInt16 = 0o644, ownerName: String = "me",
        groupName: String = "staff", ownerIsMe: Bool = true, locked: Bool = false, hidesExtension: Bool = false,
        tags: [String] = [], kind: String = "Tài liệu PDF"
    ) -> FileInfoFacts {
        FileInfoFacts(name: name, path: path, isFolder: isFolder, isPackage: isPackage, logicalSize: logicalSize,
                     physicalSize: physicalSize, created: created, modified: modified, accessed: accessed,
                     posixMode: posixMode, ownerName: ownerName, groupName: groupName, ownerIsMe: ownerIsMe,
                     locked: locked, hidesExtension: hidesExtension, tags: tags, kind: kind)
    }

    // MARK: - Permissions: access(mode:who:)

    func test_access_rw_isReadWrite() {
        // rw-r--r-- (0o644): owner rw, group r, everyone r
        XCTAssertEqual(FileInfoRules.access(mode: 0o644, who: .owner), .readWrite)
        XCTAssertEqual(FileInfoRules.access(mode: 0o644, who: .group), .readOnly)
        XCTAssertEqual(FileInfoRules.access(mode: 0o644, who: .everyone), .readOnly)
    }

    func test_access_rwx_stillReadWrite() {
        // Execute bit doesn't change the Finder-visible r/w category.
        XCTAssertEqual(FileInfoRules.access(mode: 0o744, who: .owner), .readWrite)
    }

    func test_access_writeOnly() {
        XCTAssertEqual(FileInfoRules.access(mode: 0o244, who: .owner), .writeOnly)
    }

    func test_access_none() {
        XCTAssertEqual(FileInfoRules.access(mode: 0o044, who: .owner), .none)
    }

    func test_access_executeOnly_isNone() {
        // A lone execute bit grants neither readable nor writable access in Finder's popup.
        XCTAssertEqual(FileInfoRules.access(mode: 0o144, who: .owner), .none)
    }

    func test_access_group_and_everyone_independent() {
        let mode: UInt16 = 0o604   // owner rw-, group ---, everyone r--
        XCTAssertEqual(FileInfoRules.access(mode: mode, who: .owner), .readWrite)
        XCTAssertEqual(FileInfoRules.access(mode: mode, who: .group), .none)
        XCTAssertEqual(FileInfoRules.access(mode: mode, who: .everyone), .readOnly)
    }

    // MARK: - Permissions: mode(setting:for:in:)

    func test_mode_setReadWrite_setsBothBits() {
        let result = FileInfoRules.mode(setting: .readWrite, for: .owner, in: 0o000)
        XCTAssertEqual(FileInfoRules.access(mode: result, who: .owner), .readWrite)
    }

    func test_mode_setReadOnly_clearsWriteKeepsRead() {
        let result = FileInfoRules.mode(setting: .readOnly, for: .owner, in: 0o600)
        XCTAssertEqual(FileInfoRules.access(mode: result, who: .owner), .readOnly)
    }

    func test_mode_setNone_clearsExecuteToo() {
        let result = FileInfoRules.mode(setting: .none, for: .owner, in: 0o700)
        XCTAssertEqual(result & 0o700, 0)
    }

    func test_mode_settingOneWho_leavesOthersUntouched() {
        let start: UInt16 = 0o644
        let result = FileInfoRules.mode(setting: .none, for: .everyone, in: start)
        XCTAssertEqual(FileInfoRules.access(mode: result, who: .owner), .readWrite)
        XCTAssertEqual(FileInfoRules.access(mode: result, who: .group), .readOnly)
        XCTAssertEqual(FileInfoRules.access(mode: result, who: .everyone), .none)
    }

    func test_mode_setReadOnly_preservesExecuteBit() {
        // Spec: the popup only ever changes r/w (except .none); an existing execute bit survives a readOnly set.
        let result = FileInfoRules.mode(setting: .readOnly, for: .owner, in: 0o744)
        XCTAssertEqual(result & 0o700, 0o500)
    }

    func test_mode_roundTrip_everyAccessValue() {
        for access in Access.allCases {
            let result = FileInfoRules.mode(setting: access, for: .group, in: 0o700)
            XCTAssertEqual(FileInfoRules.access(mode: result, who: .group), access)
        }
    }

    func test_access_titleKeys_areDistinct() {
        let keys = Set(Access.allCases.map(\.titleKey))
        XCTAssertEqual(keys.count, Access.allCases.count)
    }

    // MARK: - generalRows

    func test_generalRows_includesKindSizeDatesWhereLocked() {
        let rows = FileInfoRules.generalRows(facts(), sizeText: { "\($0 ?? -1) B" }, dateText: { "\($0.timeIntervalSince1970)" })
        let labels = rows.map(\.labelKey)
        XCTAssertTrue(labels.contains("Loại:"))
        XCTAssertTrue(labels.contains("Kích thước:"))
        XCTAssertTrue(labels.contains("Nơi lưu:"))
        XCTAssertTrue(labels.contains("Ngày tạo:"))
        XCTAssertTrue(labels.contains("Ngày sửa đổi:"))
        XCTAssertTrue(labels.contains("Khoá:"))
    }

    func test_generalRows_whereIsParentDirectory() {
        let rows = FileInfoRules.generalRows(facts(path: "/Users/me/Docs/Report.pdf"),
                                             sizeText: { _ in "" }, dateText: { _ in "" })
        let where_ = rows.first { $0.labelKey == "Nơi lưu:" }
        XCTAssertEqual(where_?.value, "/Users/me/Docs")
    }

    func test_generalRows_omitsAccessedWhenNil() {
        let rows = FileInfoRules.generalRows(facts(accessed: nil), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertFalse(rows.map(\.labelKey).contains("Mở lần cuối:"))
    }

    func test_generalRows_includesAccessedWhenPresent() {
        let rows = FileInfoRules.generalRows(facts(accessed: Date()), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertTrue(rows.map(\.labelKey).contains("Mở lần cuối:"))
    }

    // MARK: - generalRows: app version (apps only)

    func test_generalRows_omitsVersionWhenNil() {
        let rows = FileInfoRules.generalRows(facts(), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertFalse(rows.map(\.labelKey).contains("Phiên bản:"))
    }

    func test_generalRows_includesVersionWhenPresent() {
        var f = facts()
        f = FileInfoFacts(name: f.name, path: f.path, isFolder: f.isFolder, isPackage: f.isPackage,
                           logicalSize: f.logicalSize, physicalSize: f.physicalSize, created: f.created,
                           modified: f.modified, accessed: f.accessed, posixMode: f.posixMode,
                           ownerName: f.ownerName, groupName: f.groupName, ownerIsMe: f.ownerIsMe,
                           locked: f.locked, hidesExtension: f.hidesExtension, tags: f.tags, kind: f.kind,
                           appVersion: "1.4.0")
        let rows = FileInfoRules.generalRows(f, sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertEqual(rows.first { $0.labelKey == "Phiên bản:" }?.value, "1.4.0")
    }

    // MARK: - generalRows: cloud status (cloud items only)

    func test_generalRows_omitsCloudStatusWhenNilBadge() {
        let rows = FileInfoRules.generalRows(facts(), sizeText: { _ in "" }, dateText: { _ in "" }, cloudBadge: nil)
        XCTAssertFalse(rows.map(\.labelKey).contains("Trạng thái đám mây:"))
    }

    func test_generalRows_omitsCloudStatusWhenBadgeNone() {
        let rows = FileInfoRules.generalRows(facts(), sizeText: { _ in "" }, dateText: { _ in "" }, cloudBadge: .none)
        XCTAssertFalse(rows.map(\.labelKey).contains("Trạng thái đám mây:"))
    }

    func test_generalRows_includesCloudStatusWhenCloudOnly() {
        let rows = FileInfoRules.generalRows(facts(), sizeText: { _ in "" }, dateText: { _ in "" }, cloudBadge: .cloudOnly)
        XCTAssertEqual(rows.first { $0.labelKey == "Trạng thái đám mây:" }?.value, "Chỉ trên đám mây")
    }

    func test_cloudStatusValueKey_everyBadgeHasDistinctKey() {
        let badges: [CloudBadge] = [.none, .cloudOnly, .downloading, .uploading, .downloadFailed, .uploadFailed]
        let keys = Set(badges.map(FileInfoRules.cloudStatusValueKey))
        XCTAssertEqual(keys.count, badges.count)
    }

    func test_generalRows_omitsSizeOnDiskWhenPhysicalSizeNil() {
        // A folder whose background walk hasn't finished: no "Dung lượng trên đĩa" row yet.
        let rows = FileInfoRules.generalRows(facts(logicalSize: nil, physicalSize: nil),
                                             sizeText: { _ in "Đang tính…" }, dateText: { _ in "" })
        XCTAssertFalse(rows.map(\.labelKey).contains("Dung lượng trên đĩa:"))
    }

    func test_generalRows_includesSizeOnDiskWhenKnown() {
        let rows = FileInfoRules.generalRows(facts(physicalSize: 4096), sizeText: { _ in "4 KB" }, dateText: { _ in "" })
        XCTAssertTrue(rows.map(\.labelKey).contains("Dung lượng trên đĩa:"))
    }

    func test_generalRows_lockedReflectsFacts() {
        let lockedRows = FileInfoRules.generalRows(facts(locked: true), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertEqual(lockedRows.first { $0.labelKey == "Khoá:" }?.value, "Có")
        let unlockedRows = FileInfoRules.generalRows(facts(locked: false), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertEqual(unlockedRows.first { $0.labelKey == "Khoá:" }?.value, "Không")
    }

    // MARK: - additionalRows

    func test_additionalRows_emptyWhenNothingKnown() {
        let rows = FileInfoRules.additionalRows(pixelSize: nil, pdfPageCount: nil, mediaDuration: nil, durationText: { "\($0)" })
        XCTAssertTrue(rows.isEmpty)
    }

    func test_additionalRows_pixelSize() {
        let rows = FileInfoRules.additionalRows(pixelSize: (1920, 1080), pdfPageCount: nil, mediaDuration: nil, durationText: { "\($0)" })
        XCTAssertEqual(rows.first?.value, "1920 × 1080")
    }

    func test_additionalRows_pdfPageCount() {
        let rows = FileInfoRules.additionalRows(pixelSize: nil, pdfPageCount: 42, mediaDuration: nil, durationText: { "\($0)" })
        XCTAssertEqual(rows.first?.value, "42")
    }

    func test_additionalRows_mediaDurationUsesCallerFormatter() {
        let rows = FileInfoRules.additionalRows(pixelSize: nil, pdfPageCount: nil, mediaDuration: 90, durationText: { "\(Int($0))s" })
        XCTAssertEqual(rows.first?.value, "90s")
    }

    func test_additionalRows_allTogetherKeepOrder() {
        // Image dims/colour/camera, then media duration/codecs, then PDF pages — a file is never more than one
        // kind, but the order is still a fixed contract for a window that is handed every field at once.
        let rows = FileInfoRules.additionalRows(pixelSize: (10, 20), colorSpace: "sRGB", camera: "iPhone 15 Pro",
                                                 pdfPageCount: 3, mediaDuration: 5, codecs: ["h264"],
                                                 durationText: { "\($0)" })
        XCTAssertEqual(rows.map(\.labelKey), [
            "Kích thước ảnh:", "Không gian màu:", "Máy ảnh:", "Thời lượng:", "Codec:", "Số trang:",
        ])
    }

    func test_additionalRows_colorSpaceAndCamera() {
        let rows = FileInfoRules.additionalRows(colorSpace: "Display P3", camera: "Canon EOS R5", durationText: { "\($0)" })
        XCTAssertEqual(rows.first { $0.labelKey == "Không gian màu:" }?.value, "Display P3")
        XCTAssertEqual(rows.first { $0.labelKey == "Máy ảnh:" }?.value, "Canon EOS R5")
    }

    func test_additionalRows_codecsJoined() {
        let rows = FileInfoRules.additionalRows(codecs: ["h264", "aac"], durationText: { "\($0)" })
        XCTAssertEqual(rows.first { $0.labelKey == "Codec:" }?.value, "h264, aac")
    }

    func test_additionalRows_emptyCodecsOmitsRow() {
        let rows = FileInfoRules.additionalRows(codecs: [], durationText: { "\($0)" })
        XCTAssertFalse(rows.map(\.labelKey).contains("Codec:"))
    }

    // MARK: - Rename validation (reusing Finder rules)

    func test_renameRejectionKey_empty() {
        XCTAssertNotNil(FileInfoRules.renameRejectionKey(for: ""))
        XCTAssertNotNil(FileInfoRules.renameRejectionKey(for: "   "))
    }

    func test_renameRejectionKey_slash() {
        XCTAssertNotNil(FileInfoRules.renameRejectionKey(for: "a/b"))
    }

    func test_renameRejectionKey_colon() {
        XCTAssertNotNil(FileInfoRules.renameRejectionKey(for: "a:b"))
    }

    func test_renameRejectionKey_validName_isNil() {
        XCTAssertNil(FileInfoRules.renameRejectionKey(for: "Report Final.pdf"))
    }

    func test_renameRejectionKey_trimsWhitespaceBeforeCheckingEmpty() {
        XCTAssertNotNil(FileInfoRules.renameRejectionKey(for: "  \n  "))
    }

    func test_renameRejectionKey_leadingTrailingSpaceOtherwiseValid() {
        XCTAssertNil(FileInfoRules.renameRejectionKey(for: "  Report.pdf  "))
    }

    // MARK: - renameSelection

    func test_renameSelection_splitsStemAndExtension() {
        let result = FileInfoRules.renameSelection(for: "Report.pdf", isFolder: false)
        XCTAssertEqual(result.stem, "Report")
        XCTAssertEqual(result.ext, "pdf")
    }

    func test_renameSelection_folderSelectsWholeName() {
        let result = FileInfoRules.renameSelection(for: "My Folder.old", isFolder: true)
        XCTAssertEqual(result.stem, "My Folder.old")
        XCTAssertEqual(result.ext, "")
    }

    func test_renameSelection_dotfileSelectsWholeName() {
        let result = FileInfoRules.renameSelection(for: ".zshrc", isFolder: false)
        XCTAssertEqual(result.stem, ".zshrc")
        XCTAssertEqual(result.ext, "")
    }

    func test_renameSelection_noExtensionSelectsWholeName() {
        let result = FileInfoRules.renameSelection(for: "README", isFolder: false)
        XCTAssertEqual(result.stem, "README")
        XCTAssertEqual(result.ext, "")
    }

    func test_renameSelection_trailingDotSelectsWholeName() {
        // "Name." has a dot with nothing after it — no real extension to protect, so the whole name (dot included)
        // is selected, same as a name with no dot at all.
        let result = FileInfoRules.renameSelection(for: "Name.", isFolder: false)
        XCTAssertEqual(result.stem, "Name.")
        XCTAssertEqual(result.ext, "")
    }

    func test_renameSelection_multipleDots_onlyLastIsExtension() {
        let result = FileInfoRules.renameSelection(for: "archive.tar.gz", isFolder: false)
        XCTAssertEqual(result.stem, "archive.tar")
        XCTAssertEqual(result.ext, "gz")
    }

    // MARK: - Multi-selection summary

    func test_summary_countsItems() {
        let summary = FileInfoRules.summary(kinds: ["Tài liệu PDF", "Hình ảnh"], sizes: [100, 200])
        XCTAssertEqual(summary.count, 2)
    }

    func test_summary_sumsKnownSizes() {
        let summary = FileInfoRules.summary(kinds: ["A", "A"], sizes: [100, 200])
        XCTAssertEqual(summary.totalLogicalSize, 300)
        XCTAssertTrue(summary.isComplete)
    }

    func test_summary_incompleteWhenAnySizeUnknown() {
        let summary = FileInfoRules.summary(kinds: ["A", "A"], sizes: [100, nil])
        XCTAssertEqual(summary.totalLogicalSize, 100)
        XCTAssertFalse(summary.isComplete)
    }

    func test_summary_sameKind_reportsThatKind() {
        let summary = FileInfoRules.summary(kinds: ["Tài liệu PDF", "Tài liệu PDF"], sizes: [1, 2])
        XCTAssertEqual(summary.kindSummary, "Tài liệu PDF")
    }

    func test_summary_differentKinds_reportsManyKindsKey() {
        let summary = FileInfoRules.summary(kinds: ["Tài liệu PDF", "Hình ảnh"], sizes: [1, 2])
        XCTAssertEqual(summary.kindSummary, "Nhiều loại")
    }

    func test_summary_singleItem_reportsItsOwnKind() {
        let summary = FileInfoRules.summary(kinds: ["Thư mục"], sizes: [nil])
        XCTAssertEqual(summary.kindSummary, "Thư mục")
        XCTAssertFalse(summary.isComplete)
    }

    func test_summary_emptySelection() {
        let summary = FileInfoRules.summary(kinds: [], sizes: [])
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.totalLogicalSize, 0)
        XCTAssertTrue(summary.isComplete)
    }

    func test_summary_allNilSizes_totalZero() {
        let summary = FileInfoRules.summary(kinds: ["Thư mục", "Thư mục"], sizes: [nil, nil])
        XCTAssertEqual(summary.totalLogicalSize, 0)
        XCTAssertFalse(summary.isComplete)
    }

    // MARK: - FileInfoFacts is a plain value type (Equatable round trip)

    func test_facts_equatable() {
        XCTAssertEqual(facts(), facts())
        XCTAssertNotEqual(facts(name: "A"), facts(name: "B"))
    }

    // MARK: - Locked restrictions (isControlEnabled)

    func test_isControlEnabled_readOnlyDisablesEverythingButLockAndTags() {
        for control in [FileInfoRules.EditableControl.rename, .trash, .hideExtension, .permissions] {
            XCTAssertFalse(FileInfoRules.isControlEnabled(control, readOnly: true, locked: false))
        }
        XCTAssertTrue(FileInfoRules.isControlEnabled(.tags, readOnly: false, locked: false))
        XCTAssertTrue(FileInfoRules.isControlEnabled(.lock, readOnly: false, locked: false))
    }

    func test_isControlEnabled_readOnlyDisablesLockToo() {
        // Spec §5.8: a search-result window is read-only in-window for every editable surface.
        XCTAssertFalse(FileInfoRules.isControlEnabled(.lock, readOnly: true, locked: false))
        XCTAssertFalse(FileInfoRules.isControlEnabled(.tags, readOnly: true, locked: false))
    }

    func test_isControlEnabled_lockedDisablesRenameTrashHideExtensionPermissions() {
        for control in [FileInfoRules.EditableControl.rename, .trash, .hideExtension, .permissions] {
            XCTAssertFalse(FileInfoRules.isControlEnabled(control, readOnly: false, locked: true))
        }
    }

    func test_isControlEnabled_lockedStillAllowsTagsAndLockToggle() {
        // Tags aren't protected by Locked (spec §5.7 names rename/trash/extension/permissions only); the Lock
        // checkbox itself must stay enabled so a locked item can be unlocked again.
        XCTAssertTrue(FileInfoRules.isControlEnabled(.tags, readOnly: false, locked: true))
        XCTAssertTrue(FileInfoRules.isControlEnabled(.lock, readOnly: false, locked: true))
    }

    func test_isControlEnabled_unlockedNotReadOnly_allowsEverything() {
        for control in [FileInfoRules.EditableControl.rename, .trash, .hideExtension, .permissions, .tags, .lock] {
            XCTAssertTrue(FileInfoRules.isControlEnabled(control, readOnly: false, locked: false))
        }
    }

    // MARK: - Open With ordering

    private func app(_ name: String, bundleID: String? = nil) -> FileInfoRules.OpenWithApp {
        FileInfoRules.OpenWithApp(name: name, path: "/Applications/\(name).app", bundleID: bundleID ?? "com.example.\(name)")
    }

    func test_orderedOpenWithApps_noDefault_sortsAlphabetically() {
        let result = FileInfoRules.orderedOpenWithApps([app("Zed"), app("Acorn"), app("Mimic")], defaultBundleID: nil)
        XCTAssertEqual(result.map(\.name), ["Acorn", "Mimic", "Zed"])
    }

    func test_orderedOpenWithApps_defaultFirst_restAlphabetical() {
        let result = FileInfoRules.orderedOpenWithApps(
            [app("Zed"), app("Acorn", bundleID: "com.default.app"), app("Mimic")],
            defaultBundleID: "com.default.app"
        )
        XCTAssertEqual(result.map(\.name), ["Acorn", "Mimic", "Zed"])
    }

    func test_orderedOpenWithApps_defaultNotInList_fallsBackToAlphabetical() {
        let result = FileInfoRules.orderedOpenWithApps([app("Zed"), app("Acorn")], defaultBundleID: "com.missing.app")
        XCTAssertEqual(result.map(\.name), ["Acorn", "Zed"])
    }

    func test_orderedOpenWithApps_empty() {
        XCTAssertTrue(FileInfoRules.orderedOpenWithApps([], defaultBundleID: nil).isEmpty)
    }
}
