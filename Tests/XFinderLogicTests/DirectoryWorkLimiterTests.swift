import XCTest

/// Records concurrency and order from inside limiter bodies.
private actor LimiterProbe {
    private(set) var current: Int = 0
    private(set) var peak: Int = 0
    private(set) var order: [Int] = []
    private(set) var realWork: [Int] = []

    func enter(_ index: Int) {
        current += 1
        peak = max(peak, current)
        order.append(index)
        realWork.append(index)
    }

    func leave() { current -= 1 }
}

/// A gate the first body waits on, opened by the test.
private actor Gate {
    private var isOpen: Bool = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in waiters.append(continuation) }
    }

    func open() {
        isOpen = true
        let pending: [CheckedContinuation<Void, Never>] = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

final class DirectoryWorkLimiterTests: XCTestCase {

    func testNeverMoreThanMaxConcurrentBodies() async {
        let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: 2)
        let probe: LimiterProbe = LimiterProbe()
        await withTaskGroup(of: Int.self) { group in
            for index in 0..<8 {
                group.addTask {
                    await limiter.run { () async -> Int in
                        await probe.enter(index)
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await probe.leave()
                        return index
                    }
                }
            }
            var results: [Int] = []
            for await value in group { results.append(value) }
            XCTAssertEqual(results.sorted(), Array(0..<8))
        }
        let peak: Int = await probe.peak
        XCTAssertEqual(peak, 2)
        let inFlight: Int = await limiter.inFlight()
        XCTAssertEqual(inFlight, 0)
    }

    func testZeroOrNegativeMaxBehavesAsOne() async {
        for limit in [0, -3] {
            let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: limit)
            let probe: LimiterProbe = LimiterProbe()
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<4 {
                    group.addTask {
                        _ = await limiter.run { () async -> Int in
                            await probe.enter(index)
                            try? await Task.sleep(nanoseconds: 5_000_000)
                            await probe.leave()
                            return index
                        }
                    }
                }
            }
            let peak: Int = await probe.peak
            XCTAssertEqual(peak, 1, "limit \(limit)")
        }
    }

    func testWaitersRunInArrivalOrder() async {
        let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: 1)
        let probe: LimiterProbe = LimiterProbe()
        let gate: Gate = Gate()
        let blocker: Task<Int, Never> = Task {
            await limiter.run { () async -> Int in
                await probe.enter(-1)
                await gate.wait()
                await probe.leave()
                return -1
            }
        }
        await waitUntil { await limiter.inFlight() == 1 }
        var tasks: [Task<Int, Never>] = []
        for index in 0..<5 {
            tasks.append(Task {
                await limiter.run { () async -> Int in
                    await probe.enter(index)
                    await probe.leave()
                    return index
                }
            })
            // Let this task reach the queue before the next one is created.
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await gate.open()
        _ = await blocker.value
        for task in tasks { _ = await task.value }
        let order: [Int] = await probe.order
        XCTAssertEqual(order, [-1, 0, 1, 2, 3, 4])
        let inFlight: Int = await limiter.inFlight()
        XCTAssertEqual(inFlight, 0)
    }

    func testCancelledWaiterSkipsWorkAndLeavesQueueAtOnce() async {
        let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: 1)
        let probe: LimiterProbe = LimiterProbe()
        let gate: Gate = Gate()
        let blocker: Task<String, Never> = Task {
            await limiter.run { () async -> String in
                await probe.enter(0)
                await gate.wait()
                await probe.leave()
                return "blocker"
            }
        }
        await waitUntil { await limiter.inFlight() == 1 }
        let waiter: Task<String, Never> = Task {
            await limiter.run { () async -> String in
                if Task.isCancelled { return "skipped" }
                await probe.enter(1)
                await probe.leave()
                return "ran"
            }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        waiter.cancel()
        // The cancelled waiter returns while the blocker still holds the only slot.
        let waiterResult: String = await waiter.value
        XCTAssertEqual(waiterResult, "skipped")
        let inFlightWhileBlocked: Int = await limiter.inFlight()
        XCTAssertEqual(inFlightWhileBlocked, 1)
        // A later waiter still gets the slot once the blocker finishes (the cancelled one did not wedge the queue).
        let later: Task<String, Never> = Task { await limiter.run { () async -> String in "later" } }
        await gate.open()
        let blockerResult: String = await blocker.value
        let laterResult: String = await later.value
        XCTAssertEqual(blockerResult, "blocker")
        XCTAssertEqual(laterResult, "later")
        let work: [Int] = await probe.realWork
        XCTAssertEqual(work, [0], "the cancelled body never did real work")
        let inFlight: Int = await limiter.inFlight()
        XCTAssertEqual(inFlight, 0)
    }

    func testAlreadyCancelledTaskTakesNoSlot() async {
        let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter(maxConcurrent: 1)
        let task: Task<Bool, Never> = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await limiter.run { () async -> Bool in Task.isCancelled }
        }
        let sawCancelled: Bool = await task.value
        XCTAssertTrue(sawCancelled)
        let inFlight: Int = await limiter.inFlight()
        XCTAssertEqual(inFlight, 0)
    }

    func testSharedUsesDiskReadConcurrency() async {
        let probe: LimiterProbe = LimiterProbe()
        let limiter: DirectoryWorkLimiter = DirectoryWorkLimiter.shared
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    _ = await limiter.run { () async -> Int in
                        await probe.enter(index)
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await probe.leave()
                        return index
                    }
                }
            }
        }
        let peak: Int = await probe.peak
        XCTAssertEqual(peak, LoadCoordinatorRules.diskReadConcurrency)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @Sendable () async -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("condition not met within \(timeout) s")
    }
}
