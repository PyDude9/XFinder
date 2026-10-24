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
        XCTAssertFalse(rows.map(\.labelKey).contains("Ngày mở gần nhất:"))
    }

    func test_generalRows_includesAccessedWhenPresent() {
        let rows = FileInfoRules.generalRows(facts(accessed: Date()), sizeText: { _ in "" }, dateText: { _ in "" })
        XCTAssertTrue(rows.map(\.labelKey).contains("Ngày mở gần nhất:"))
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

    func test_additionalRows_allThreeTogetherKeepOrder() {
        let rows = FileInfoRules.additionalRows(pixelSize: (10, 20), pdfPageCount: 3, mediaDuration: 5, durationText: { "\($0)" })
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].labelKey, "Kích thước ảnh:")
        XCTAssertEqual(rows[1].labelKey, "Số trang:")
        XCTAssertEqual(rows[2].labelKey, "Thời lượng:")
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
}
