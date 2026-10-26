import XCTest

final class LoadCoordinatorRulesTests: XCTestCase {
    private let tokenA: ListingToken = ListingToken(modifiedNs: 1, changedNs: 2, size: 3, inode: 4)

    private func token(modified: Int64 = 1, changed: Int64 = 2, size: Int64 = 3, inode: UInt64 = 4) -> ListingToken {
        ListingToken(modifiedNs: modified, changedNs: changed, size: size, inode: inode)
    }

    // MARK: plan

    func testNoCacheReadsDisk() {
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: false, stored: nil, current: tokenA), [.readDisk])
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: false, stored: nil, current: nil), [.readDisk])
        // A token without a cache row means nothing to show.
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: false, stored: tokenA, current: tokenA), [.readDisk])
    }

    func testCacheWithoutStoredTokenReadsDisk() {
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: nil, current: tokenA), [.readDisk])
    }

    func testMatchingTokenDeliversFinalCacheOnly() {
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: token()),
                       [.deliverCache(final: true)])
    }

    func testEveryTokenFieldMismatchRevalidates() {
        let stale: [LoadCoordinatorRules.Decision] = [.deliverCache(final: false), .readDisk]
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: token(modified: 9)), stale)
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: token(changed: 9)), stale)
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: token(size: 9)), stale)
        // Folder renamed/replaced: same times, different inode.
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: token(inode: 9)), stale)
    }

    func testFailedStatIsNeverFresh() {
        XCTAssertEqual(LoadCoordinatorRules.plan(hasCache: true, stored: tokenA, current: nil),
                       [.deliverCache(final: false), .readDisk])
    }

    func testPlanAlwaysEndsInEitherFinalCacheOrDiskRead() {
        let tokens: [ListingToken?] = [nil, tokenA, token(inode: 7)]
        for hasCache in [false, true] {
            for stored in tokens {
                for current in tokens {
                    let plan: [LoadCoordinatorRules.Decision] = LoadCoordinatorRules.plan(hasCache: hasCache, stored: stored, current: current)
                    XCTAssertFalse(plan.isEmpty)
                    let last: LoadCoordinatorRules.Decision? = plan.last
                    XCTAssertTrue(last == .readDisk || last == .deliverCache(final: true), "\(plan)")
                    if plan.contains(.deliverCache(final: false)) { XCTAssertEqual(plan.last, .readDisk) }
                    if !hasCache { XCTAssertEqual(plan, [.readDisk]) }
                }
            }
        }
    }

    func testDiskReadConcurrency() {
        XCTAssertEqual(LoadCoordinatorRules.diskReadConcurrency, 4)
    }

    // MARK: SessionBook

    func testBookStartedJoinedLeftClosed() {
        var book: LoadCoordinatorRules.SessionBook = LoadCoordinatorRules.SessionBook()
        let a: UUID = UUID(), b: UUID = UUID()
        XCTAssertEqual(book.count(path: "/x"), 0)
        XCTAssertEqual(book.subscribe(path: "/x", id: a), .started)
        XCTAssertEqual(book.subscribe(path: "/x", id: b), .joined)
        XCTAssertEqual(book.count(path: "/x"), 2)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .left)
        XCTAssertEqual(book.count(path: "/x"), 1)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: b), .closed)
        XCTAssertEqual(book.count(path: "/x"), 0)
        XCTAssertEqual(book, LoadCoordinatorRules.SessionBook(), "a closed path leaves no empty entry behind")
    }

    func testBookUnknownUnsubscribes() {
        var book: LoadCoordinatorRules.SessionBook = LoadCoordinatorRules.SessionBook()
        let a: UUID = UUID()
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .unknown)
        _ = book.subscribe(path: "/x", id: a)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: UUID()), .unknown)
        XCTAssertEqual(book.unsubscribe(path: "/y", id: a), .unknown)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .closed)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .unknown, "double cancel is harmless")
    }

    func testBookDuplicateSubscribeCountsOnce() {
        var book: LoadCoordinatorRules.SessionBook = LoadCoordinatorRules.SessionBook()
        let a: UUID = UUID()
        XCTAssertEqual(book.subscribe(path: "/x", id: a), .started)
        XCTAssertEqual(book.subscribe(path: "/x", id: a), .joined)
        XCTAssertEqual(book.count(path: "/x"), 1)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .closed)
    }

    func testBookPathsAreIndependentAndRestartable() {
        var book: LoadCoordinatorRules.SessionBook = LoadCoordinatorRules.SessionBook()
        let a: UUID = UUID(), b: UUID = UUID()
        XCTAssertEqual(book.subscribe(path: "/x", id: a), .started)
        XCTAssertEqual(book.subscribe(path: "/y", id: b), .started)
        XCTAssertEqual(book.unsubscribe(path: "/x", id: a), .closed)
        XCTAssertEqual(book.count(path: "/y"), 1)
        XCTAssertEqual(book.subscribe(path: "/x", id: a), .started, "a closed path starts a fresh session")
    }
}
