import XCTest

/// 2026-10-26 — a refresh of the folder on screen keeps the listing (no spinner, no table rebuild).
final class LoadRulesTests: XCTestCase {
    func testSameFolderAlreadyLoadedIsARefresh() {
        XCTAssertTrue(LoadRules.isRefresh(of: "/Users/me", loadedPath: "/Users/me", isLoaded: true))
        XCTAssertTrue(LoadRules.isRefresh(of: "/Users/me/", loadedPath: "/Users/me", isLoaded: true))
        XCTAssertTrue(LoadRules.isRefresh(of: "/Users/./me", loadedPath: "/Users/me", isLoaded: true))
    }

    func testAnythingElseShowsTheSpinner() {
        XCTAssertFalse(LoadRules.isRefresh(of: "/Users/me/Desktop", loadedPath: "/Users/me", isLoaded: true), "another folder")
        XCTAssertFalse(LoadRules.isRefresh(of: "/Users/me", loadedPath: nil, isLoaded: true), "nothing loaded yet")
        XCTAssertFalse(LoadRules.isRefresh(of: "/Users/me", loadedPath: "/Users/me", isLoaded: false), "loading or failed")
        XCTAssertFalse(LoadRules.isRefresh(of: "", loadedPath: "", isLoaded: true), "empty path")
    }
}
