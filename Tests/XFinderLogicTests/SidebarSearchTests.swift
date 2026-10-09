import XCTest
import Foundation

final class SidebarSearchTests: XCTestCase {
    private let groups: [(header: String, items: [String])] = [
        ("CHUNG", ["Tổng quan", "Mạng", "Ổ đĩa"]),
        ("CÔNG CỤ", ["Đổi tên hàng loạt", "Khay thả", "Nén & Giải nén"]),
    ]
    private func run(_ q: String) -> [String] {
        SidebarSearch.filter(groups, query: q) { header, item in [item, header] }.flatMap(\.items)
    }

    func testEmptyOrBlankQueryKeepsEverything() {
        XCTAssertEqual(run("").count, 6)
        XCTAssertEqual(run("   ").count, 6)
    }
    func testIgnoresCaseAndDiacriticsAndTreatsDAsD() {
        XCTAssertEqual(run("tong quan"), ["Tổng quan"])
        XCTAssertEqual(run("O DIA"), ["Ổ đĩa"])
        XCTAssertEqual(run("doi ten"), ["Đổi tên hàng loạt"])
        XCTAssertEqual(run("đổi"), ["Đổi tên hàng loạt"])
    }
    func testEveryWordMustMatchInAnyOrder() {
        XCTAssertEqual(run("loat hang"), ["Đổi tên hàng loạt"])
        XCTAssertEqual(run("khay mang"), [], "no single row has both words")
    }
    func testSectionNameIsSearchableAndEmptyGroupsDisappear() {
        XCTAssertEqual(run("cong cu"), ["Đổi tên hàng loạt", "Khay thả", "Nén & Giải nén"])
        let g = SidebarSearch.filter(groups, query: "mang") { h, i in [i, h] }
        XCTAssertEqual(g.map(\.header), ["CHUNG"], "the CÔNG CỤ group has no match and is dropped")
    }
    func testNoMatchReturnsNothing() {
        XCTAssertTrue(run("zzzz").isEmpty)
    }
    func testFoldIsStable() {
        XCTAssertEqual(SidebarSearch.fold("Đổi Tên"), "doi ten")
    }
}
