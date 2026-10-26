import XCTest

/// Wraps real `DirectoryWatcher` creation, counts it, and keeps the callbacks so a test can fire them.
@MainActor private final class WatcherFactorySpy {
    private(set) var created: Int = 0
    private(set) var paths: [String] = []
    private(set) var onChanges: [@MainActor () -> Void] = []
    private(set) var onGones: [@MainActor () -> Void] = []

    var factory: DirectoryLoadCoordinator.WatcherFactory {
        { [unowned self] path, onChange, onGone in
            self.created += 1
            self.paths.append(path)
            self.onChanges.append(onChange)
            self.onGones.append(onGone)
            return DirectoryWatcher(path: path, onChange: onChange, onGone: onGone)
        }
    }
}

/// Everything one subscriber received.
@MainActor private final class Recorder {
    private(set) var results: [Result<ListingDelivery, DirectoryReadError>] = []
    private(set) var goneCount: Int = 0

    var diskDeliveries: [ListingDelivery] {
        results.compactMap { result in
            if case .success(let delivery) = result, delivery.source == .disk { return delivery }
            return nil
        }
    }

    var failures: [DirectoryReadError] {
        results.compactMap { result in
            if case .failure(let error) = result { return error }
            return nil
        }
    }

    func onListing(_ result: Result<ListingDelivery, DirectoryReadError>) { results.append(result) }
    func onGone() { goneCount += 1 }
}

@MainActor final class DirectoryLoadCoordinatorTests: XCTestCase {
    private var root: URL!
    private var spy: WatcherFactorySpy!
    private var coordinator: DirectoryLoadCoordinator!

    override func setUp() async throws {
        let base: URL = FileManager.default.temporaryDirectory.appendingPathComponent("xf-coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt"] {
            try Data("x".utf8).write(to: base.appendingPathComponent("sub/\(name)"))
        }
        root = base
        spy = WatcherFactorySpy()
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: base.appendingPathComponent("listing-cache.sqlite"))
        coordinator = DirectoryLoadCoordinator(cache: cache, limiter: DirectoryWorkLimiter(maxConcurrent: 4),
                                               watcherFactory: spy.factory)
    }

    override func tearDown() async throws {
        coordinator = nil
        spy = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    private var folder: String { root.appendingPathComponent("sub").path }

    private func subscribe(_ path: String, _ recorder: Recorder) -> ListingSubscription {
        coordinator.subscribe(path: path,
                              onListing: { recorder.onListing($0) },
                              onGone: { recorder.onGone() })
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for: \(what)")
    }

    private func settle(_ seconds: TimeInterval = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Sharing

    func testTwoSubscribersSameFolderShareOneReadAndOneWatcher() async {
        let first: Recorder = Recorder(), second: Recorder = Recorder()
        let subA: ListingSubscription = subscribe(folder, first)
        let subB: ListingSubscription = subscribe(folder, second)
        await waitUntil("both delivered") { !first.results.isEmpty && !second.results.isEmpty }
        await settle()
        XCTAssertEqual(first.diskDeliveries.count, 1)
        XCTAssertEqual(second.diskDeliveries.count, 1)
        XCTAssertEqual(first.diskDeliveries.first?.entries.count, 3)
        XCTAssertEqual(first.diskDeliveries.first?.isFinal, true)
        XCTAssertEqual(spy.created, 1)
        XCTAssertEqual(coordinator.activeSessionCount(), 1)
        subA.cancel(); subB.cancel()
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
    }

    func testLateJoinerGetsLastDeliveryImmediatelyWithoutNewRead() async {
        let first: Recorder = Recorder(), late: Recorder = Recorder()
        let subA: ListingSubscription = subscribe(folder, first)
        await waitUntil("first delivered") { !first.results.isEmpty }
        let subB: ListingSubscription = subscribe(folder, late)
        XCTAssertEqual(late.diskDeliveries.count, 1, "replayed synchronously inside subscribe")
        await settle()
        XCTAssertEqual(first.diskDeliveries.count, 1, "joining does not trigger a second read")
        XCTAssertEqual(late.diskDeliveries.count, 1)
        XCTAssertEqual(spy.created, 1)
        subA.cancel(); subB.cancel()
    }

    func testDotDotTrailingSlashAndDotShareOneSession() async {
        let one: Recorder = Recorder(), two: Recorder = Recorder(), three: Recorder = Recorder()
        let rootPath: String = root.path
        let subs: [ListingSubscription] = [
            subscribe("\(rootPath)/sub/../sub", one),
            subscribe("\(rootPath)/sub/", two),
            subscribe("\(rootPath)/./sub", three)
        ]
        await waitUntil("all delivered") { !one.results.isEmpty && !two.results.isEmpty && !three.results.isEmpty }
        await settle()
        XCTAssertEqual(coordinator.activeSessionCount(), 1)
        XCTAssertEqual(spy.created, 1)
        XCTAssertEqual(one.diskDeliveries.count + two.diskDeliveries.count + three.diskDeliveries.count, 3,
                       "one read fanned out to three subscribers")
        XCTAssertEqual(spy.paths.first.map { ($0 as NSString).lastPathComponent }, "sub")
        XCTAssertFalse(spy.paths.first?.contains("..") ?? true)
        subs.forEach { $0.cancel() }
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
    }

    // MARK: - Cancellation

    func testCancelBeforeReadCompletesDeliversNothing() async {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(folder, recorder)
        subscription.cancel()
        subscription.cancel()   // idempotent
        await settle(0.4)
        XCTAssertTrue(recorder.results.isEmpty)
        XCTAssertEqual(recorder.goneCount, 0)
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
    }

    func testDroppingTheSubscriptionCancelsIt() async {
        let recorder: Recorder = Recorder()
        do {
            _ = subscribe(folder, recorder)
        }
        XCTAssertEqual(coordinator.activeSessionCount(), 0, "deinit cancelled the only subscriber")
        await settle()
        XCTAssertTrue(recorder.results.isEmpty)
    }

    func testOneSubscriberLeavingKeepsTheOtherFed() async {
        let leaving: Recorder = Recorder(), staying: Recorder = Recorder()
        let subA: ListingSubscription = subscribe(folder, leaving)
        let subB: ListingSubscription = subscribe(folder, staying)
        await waitUntil("delivered") { !staying.results.isEmpty }
        subA.cancel()
        XCTAssertEqual(coordinator.activeSessionCount(), 1)
        coordinator.reload(path: folder)
        await waitUntil("second read") { staying.diskDeliveries.count == 2 }
        XCTAssertEqual(leaving.diskDeliveries.count, 1, "no delivery after cancel")
        subB.cancel()
    }

    func testClosedSessionRestartsOnNextSubscribe() async {
        let first: Recorder = Recorder()
        let subA: ListingSubscription = subscribe(folder, first)
        await waitUntil("first") { !first.results.isEmpty }
        subA.cancel()
        let second: Recorder = Recorder()
        let subB: ListingSubscription = subscribe(folder, second)
        await waitUntil("second") { !second.results.isEmpty }
        XCTAssertEqual(spy.created, 2)
        XCTAssertEqual(second.diskDeliveries.count, 1)
        subB.cancel()
    }

    // MARK: - Gone

    func testOnGoneStopsDeliveriesAndClosesTheSession() async {
        let one: Recorder = Recorder(), two: Recorder = Recorder()
        let subA: ListingSubscription = subscribe(folder, one)
        let subB: ListingSubscription = subscribe(folder, two)
        await waitUntil("delivered") { !one.results.isEmpty && !two.results.isEmpty }
        spy.onGones.first?()
        XCTAssertEqual(one.goneCount, 1)
        XCTAssertEqual(two.goneCount, 1)
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
        let before: Int = one.results.count
        coordinator.reload(path: folder)
        spy.onChanges.first?()
        spy.onGones.first?()   // a second gone event is ignored
        try? Data("y".utf8).write(to: root.appendingPathComponent("sub/d.txt"))
        await settle(0.4)
        XCTAssertEqual(one.results.count, before)
        XCTAssertEqual(one.goneCount, 1)
        subA.cancel(); subB.cancel()   // harmless after gone
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
    }

    func testRenamingTheFolderFiresGoneThroughTheRealWatcher() async throws {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(folder, recorder)
        await waitUntil("delivered") { !recorder.results.isEmpty }
        try FileManager.default.moveItem(atPath: folder, toPath: root.appendingPathComponent("moved").path)
        await waitUntil("gone") { recorder.goneCount == 1 }
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
        subscription.cancel()
    }

    // MARK: - Reload / watcher

    func testFiveReloadsWithinTenMillisecondsCostAtMostTwoReads() async {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(folder, recorder)
        await waitUntil("initial") { recorder.diskDeliveries.count == 1 }
        for _ in 0..<5 { coordinator.reload(path: folder) }
        await waitUntil("reloaded") { recorder.diskDeliveries.count >= 2 }
        await settle(0.4)
        let reads: Int = recorder.diskDeliveries.count - 1
        XCTAssertGreaterThanOrEqual(reads, 1)
        XCTAssertLessThanOrEqual(reads, 2)
        subscription.cancel()
    }

    func testReloadDuringInitialReadIsCoalescedNotStacked() async {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(folder, recorder)
        // These reloads land before the initial read has even started, so that one read already satisfies them.
        for _ in 0..<5 { coordinator.reload(path: folder) }
        await waitUntil("delivered") { recorder.diskDeliveries.count >= 1 }
        await settle(0.4)
        XCTAssertEqual(recorder.diskDeliveries.count, 1, "reloads before the read began are folded into it")
        subscription.cancel()
    }

    func testReloadOfUnknownPathIsANoOp() async {
        coordinator.reload(path: folder)
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
        XCTAssertEqual(spy.created, 0)
    }

    func testWatcherChangeDeliversNewListing() async throws {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(folder, recorder)
        await waitUntil("initial") { recorder.diskDeliveries.count == 1 }
        try Data("new".utf8).write(to: root.appendingPathComponent("sub/new.txt"))
        await waitUntil("watcher reload") { recorder.diskDeliveries.last?.entries.count == 4 }
        XCTAssertTrue(recorder.diskDeliveries.last?.entries.contains { $0.name == "new.txt" } ?? false)
        subscription.cancel()
    }

    // MARK: - Failures

    func testMissingFolderDeliversNotFoundWithoutWatcher() async {
        let recorder: Recorder = Recorder()
        let missing: String = root.appendingPathComponent("nope").path
        let subscription: ListingSubscription = subscribe(missing, recorder)
        await waitUntil("failure") { !recorder.results.isEmpty }
        XCTAssertEqual(recorder.failures, [.notFound])
        XCTAssertEqual(spy.created, 1, "factory was asked; it returned nil because open() failed")
        let late: Recorder = Recorder()
        let lateSub: ListingSubscription = subscribe(missing, late)
        XCTAssertEqual(late.failures, [.notFound], "late joiners get the last failure too")
        subscription.cancel(); lateSub.cancel()
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
    }

    func testFileInsteadOfFolderDeliversNotDirectory() async {
        let recorder: Recorder = Recorder()
        let subscription: ListingSubscription = subscribe(root.appendingPathComponent("sub/a.txt").path, recorder)
        await waitUntil("failure") { !recorder.results.isEmpty }
        XCTAssertEqual(recorder.failures, [.notDirectory])
        subscription.cancel()
    }

    func testCallbackCancellingItselfStopsFurtherDeliveries() async {
        let recorder: Recorder = Recorder()
        var holder: ListingSubscription?
        holder = coordinator.subscribe(path: folder,
                                       onListing: { result in recorder.onListing(result); holder?.cancel() },
                                       onGone: { recorder.onGone() })
        await waitUntil("delivered") { !recorder.results.isEmpty }
        XCTAssertEqual(coordinator.activeSessionCount(), 0)
        coordinator.reload(path: folder)
        await settle()
        XCTAssertEqual(recorder.results.count, 1)
        holder = nil
    }
}
