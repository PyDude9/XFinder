import XCTest
import Foundation

final class LiveActivityTests: XCTestCase {
    typealias A = LiveActivity
    func p(_ ac: Bool, _ pct: Int?, charging: Bool = false, charged: Bool = false) -> A.PowerState {
        A.PowerState(onAC: ac, percent: pct, charging: charging, charged: charged)
    }

    func testTheFirstReadingIsABaselineNotNews() {
        XCTAssertEqual(A.powerItems(old: nil, new: p(false, 5)), [])
        XCTAssertNil(A.networkItem(wasOnline: nil, isOnline: false))
        XCTAssertNil(A.capsLockItem(wasOn: nil, isOn: true))
    }

    /// Measured: on AC at 80 % with optimised charging, IsCharging and IsCharged are both false.
    func testPluggingInSaysChargingOrHoldingTruthfully() {
        XCTAssertEqual(A.powerItems(old: p(false, 80), new: p(true, 80, charging: true)).first?.titleKey, "Đang sạc")
        XCTAssertEqual(A.powerItems(old: p(false, 80), new: p(true, 80)).first?.titleKey, "Đã cắm sạc, đang giữ mức pin")
        XCTAssertEqual(A.powerItems(old: p(true, 80), new: p(false, 80)).first?.titleKey, "Đang dùng pin")
    }

    func testFullOnlyWhenTheOSSaysCharged() {
        XCTAssertEqual(A.powerItems(old: p(true, 99, charging: true), new: p(true, 100, charging: true)), [],
                       "100 % alone is not 'charged'")
        XCTAssertEqual(A.powerItems(old: p(true, 99, charging: true), new: p(true, 100, charged: true)).map(\.titleKey), ["Pin đã đầy"])
    }

    func testLowAndCriticalFireOnceWhenCrossingDownOnBattery() {
        XCTAssertEqual(A.powerItems(old: p(false, 21), new: p(false, 20)).map(\.titleKey), ["Pin yếu"])
        XCTAssertEqual(A.powerItems(old: p(false, 20), new: p(false, 19)), [], "already low — no repeat every percent")
        XCTAssertEqual(A.powerItems(old: p(false, 11), new: p(false, 10)).map(\.titleKey), ["Pin rất yếu"])
        XCTAssertEqual(A.powerItems(old: p(true, 21), new: p(true, 15)), [], "on AC a low level is not a warning")
        XCTAssertEqual(A.powerItems(old: p(false, 25), new: p(false, 8)).map(\.titleKey), ["Pin rất yếu"], "a big drop says the worse one")
    }

    func testNetworkAndCapsLockOnlyOnChange() {
        XCTAssertEqual(A.networkItem(wasOnline: true, isOnline: false)?.titleKey, "Mất kết nối mạng")
        XCTAssertNil(A.networkItem(wasOnline: true, isOnline: true))
        XCTAssertEqual(A.capsLockItem(wasOn: false, isOn: true)?.titleKey, "Caps Lock đang bật")
    }

    // MARK: Queue

    func item(_ k: A.Kind, _ key: String) -> A.Item { A.Item(kind: k, symbol: "x", titleKey: key, detail: nil, tint: .neutral) }

    func testSameKindReplacesSoFlappingNeverStacks() {
        var q = A.Queue()
        q.push(item(.network, "lost"))
        q.push(item(.network, "back"))
        XCTAssertEqual(q.current?.titleKey, "back")
        XCTAssertTrue(q.pending.isEmpty)
        q.push(item(.power, "plug")); q.push(item(.power, "unplug"))
        XCTAssertEqual(q.pending.map(\.titleKey), ["unplug"], "a waiting notice is replaced by a newer one of its kind")
    }

    func testDifferentKindsWaitTheirTurnAndTheBacklogIsBounded() {
        var q = A.Queue()
        q.push(item(.alert, "a"))
        for k in [A.Kind.power, .network, .capsLock, .bluetooth] { q.push(item(k, k.rawValue)) }
        XCTAssertEqual(q.current?.titleKey, "a")
        XCTAssertEqual(q.pending.count, 4)
        XCTAssertEqual(q.advance()?.titleKey, "power")
        q.clear(); XCTAssertNil(q.current)
        XCTAssertNil(q.advance())
    }

    /// Exhaustive: any 6 pushes/advances keep at most one item per kind in the whole queue and never
    /// exceed the bound.
    func testNoSequenceHoldsTwoOfAKind() {
        let kinds: [A.Kind] = [.power, .network, .capsLock]
        func walk(_ q: A.Queue, _ depth: Int) {
            let all = (q.current.map { [$0] } ?? []) + q.pending
            XCTAssertEqual(Set(all.map(\.kind)).count, all.count, "duplicate kind: \(all.map(\.kind))")
            XCTAssertLessThanOrEqual(q.pending.count, A.Queue.maxPending)
            guard depth < 6 else { return }
            for k in kinds { var n = q; n.push(item(k, "\(depth)")); walk(n, depth + 1) }
            var a = q; a.advance(); walk(a, depth + 1)
        }
        walk(A.Queue(), 0)
    }

    func testEveryHeadlineIsInTheStore() throws {
        let store = try L10nFixture.load()
        var keys = Set<String>()
        for (o, n) in [(p(false, 80), p(true, 80, charging: true)), (p(false, 80), p(true, 80)), (p(true, 80), p(false, 80)),
                       (p(true, 99), p(true, 100, charged: true)), (p(false, 21), p(false, 20)), (p(false, 11), p(false, 10))] {
            A.powerItems(old: o, new: n).forEach { keys.insert($0.titleKey) }
        }
        for b in [true, false] {
            A.networkItem(wasOnline: !b, isOnline: b).map { keys.insert($0.titleKey) }
            A.capsLockItem(wasOn: !b, isOn: b).map { keys.insert($0.titleKey) }
            keys.insert(A.bluetoothItem(name: "x", connected: b).titleKey)
        }
        XCTAssertEqual(keys.count, 12, "the vocabulary walk collapsed")
        for k in keys { XCTAssertNotNil(store.entries[k], k) }
    }
}
