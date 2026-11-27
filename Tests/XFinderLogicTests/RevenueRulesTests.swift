import XCTest
import Foundation

private actor ScriptedRevenueProvider: RevenueProvider {
    let id = "qa-revenue-test"
    var eventsBySource: [RevenueSourceKind: [RevenueLedgerEvent]] = [:]
    var errorsBySource: [RevenueSourceKind: RevenueError] = [:]
    var interruptedSources: Set<RevenueSourceKind> = []

    func configure(
        events: [RevenueSourceKind: [RevenueLedgerEvent]] = [:],
        errors: [RevenueSourceKind: RevenueError] = [:],
        interrupted: Set<RevenueSourceKind> = []
    ) {
        self.eventsBySource = events
        self.errorsBySource = errors
        self.interruptedSources = interrupted
    }

    func fetchLedger(
        for config: SourceAccountConfig,
        period: RevenuePeriod,
        cursor: String?,
        now: Date
    ) async throws -> RevenueFetchPage {
        if let err = errorsBySource[config.source] {
            throw err
        }
        return RevenueFetchPage(
            events: eventsBySource[config.source] ?? [],
            cursor: "cur-\(config.source.rawValue)-\(period.rawValue)",
            wasPaginationInterrupted: interruptedSources.contains(config.source)
        )
    }
}

final class RevenueRulesTests: XCTestCase {
    private let nyTZ = TimeZone(identifier: "America/New_York")!

    func testDoesNotCombineStripeAndShopifyWhenCrossSourceOverlapUnresolved() async {
        let now = Date()
        let stripeCfg = SourceAccountConfig(source: .stripe, accountId: "acct_s1", accountLabel: "Main Stripe", reconciliationProvenDisjoint: false)
        let shopifyCfg = SourceAccountConfig(source: .shopify, accountId: "shop_1", accountLabel: "Main Store", reconciliationProvenDisjoint: false)
        let events: [RevenueSourceKind: [RevenueLedgerEvent]] = [
            .stripe: [
                RevenueLedgerEvent(id: "bt_1", source: .stripe, accountId: "acct_s1", occurredAt: now.addingTimeInterval(-600), category: .charge, reportingCategory: "charge", sourceReferenceId: "ch_1", reconciliationKey: nil, grossMinor: 4900, feeMinor: 172, netMinor: 4728, currency: "USD"),
            ],
            .shopify: [
                RevenueLedgerEvent(id: "ord_1", source: .shopify, accountId: "shop_1", occurredAt: now.addingTimeInterval(-500), category: .charge, reportingCategory: "order", sourceReferenceId: "ord_1", reconciliationKey: nil, grossMinor: 4900, feeMinor: 172, netMinor: 4728, currency: "USD"),
            ],
        ]

        let provider = ScriptedRevenueProvider()
        await provider.configure(events: events)
        let store = InMemoryRevenueAccountStore(initial: [.stripe: stripeCfg, .shopify: shopifyCfg])
        let coord = RevenueCoordinator(provider: provider, accountStore: store, clock: { now })
        await coord.openPage()

        let snap = await coord.snapshot
        XCTAssertNil(snap.combinedTotalsByCurrency, "Ambiguous overlap MUST NOT produce merged cross-source totals")
        if case .ambiguousOverlap = snap.reconciliationStatus {
            // expected
        } else {
            XCTFail("Expected ambiguousOverlap status")
        }
        XCTAssertEqual(snap.stripeState.report?.currencyTotals.first?.grossMinor, 4900)
        XCTAssertEqual(snap.shopifyState.report?.currencyTotals.first?.grossMinor, 4900)
    }

    func testReconciledCrossSourceDeduplicatesLinkedPaymentsAcrossStripeAndShopify() {
        let now = Date()
        let stripeCfg = SourceAccountConfig(source: .stripe, accountId: "acct_s1", accountLabel: "Stripe", reconciliationProvenDisjoint: true)
        let shopifyCfg = SourceAccountConfig(source: .shopify, accountId: "shop_1", accountLabel: "Shopify", reconciliationProvenDisjoint: true)
        let sEvents = [
            RevenueLedgerEvent(id: "bt_linked", source: .stripe, accountId: "acct_s1", occurredAt: now, category: .charge, reportingCategory: "charge", sourceReferenceId: "pi_99", reconciliationKey: "pi_99", grossMinor: 5000, feeMinor: 200, netMinor: 4800, currency: "USD"),
        ]
        let shEvents = [
            RevenueLedgerEvent(id: "ord_linked", source: .shopify, accountId: "shop_1", occurredAt: now, category: .charge, reportingCategory: "order", sourceReferenceId: "ord_99", reconciliationKey: "pi_99", grossMinor: 5000, feeMinor: 200, netMinor: 4800, currency: "USD"),
            RevenueLedgerEvent(id: "ord_native", source: .shopify, accountId: "shop_1", occurredAt: now, category: .charge, reportingCategory: "order", sourceReferenceId: "ord_100", reconciliationKey: "shoppay_100", grossMinor: 2500, feeMinor: 100, netMinor: 2400, currency: "USD"),
        ]

        let sRep = RevenueAggregator.buildSourceReport(config: stripeCfg, events: sEvents, period: .today, now: now, fetchedAt: now, cursor: nil, wasPaginationInterrupted: false)
        let shRep = RevenueAggregator.buildSourceReport(config: shopifyCfg, events: shEvents, period: .today, now: now, fetchedAt: now, cursor: nil, wasPaginationInterrupted: false)
        let res = RevenueAggregator.evaluateCrossSource(stripeReport: sRep, shopifyReport: shRep, stripeEvents: sEvents, shopifyEvents: shEvents, period: .today, now: now)

        XCTAssertEqual(res.status, .verifiedDisjoint(linkedMatches: 1))
        XCTAssertEqual(res.combined?.first?.grossMinor, 7500)
        XCTAssertEqual(res.combined?.first?.transactionCount, 2)
    }

    func testMultiCurrencyFormattingMinorUnitsRefundsAndMissingPayoutScope() {
        let now = Date()
        let shopifyNoPayout = SourceAccountConfig(
            source: .shopify, accountId: "shop_jp", accountLabel: "Store", hasPayoutScope: false
        )
        let events = [
            RevenueLedgerEvent(id: "o_usd", source: .shopify, accountId: "shop_jp", occurredAt: now, category: .charge, reportingCategory: "order", grossMinor: 10500, feeMinor: nil, netMinor: nil, currency: "USD"),
            RevenueLedgerEvent(id: "o_jpy", source: .shopify, accountId: "shop_jp", occurredAt: now, category: .charge, reportingCategory: "order", grossMinor: 15000, feeMinor: nil, netMinor: nil, currency: "JPY"),
            RevenueLedgerEvent(id: "r_usd", source: .shopify, accountId: "shop_jp", occurredAt: now, category: .refund, reportingCategory: "refund", grossMinor: 2500, feeMinor: nil, netMinor: nil, currency: "USD"),
            RevenueLedgerEvent(id: "p_usd", source: .shopify, accountId: "shop_jp", occurredAt: now, category: .payout, reportingCategory: "payout", grossMinor: 8000, currency: "USD"),
        ]
        let rep = RevenueAggregator.buildSourceReport(config: shopifyNoPayout, events: events, period: .today, now: now, fetchedAt: now, cursor: nil, wasPaginationInterrupted: false)
        XCTAssertEqual(rep.currencyTotals.count, 2) // JPY and USD separated
        let jpy = rep.currencyTotals.first { $0.currency == "JPY" }
        let usd = rep.currencyTotals.first { $0.currency == "USD" }
        XCTAssertEqual(MoneyFormatting.format(minorUnits: jpy?.grossMinor ?? 0, currency: "JPY", english: true), "¥15,000 JPY")
        XCTAssertEqual(MoneyFormatting.format(minorUnits: usd?.grossMinor ?? 0, currency: "USD", english: true), "$105.00 USD")
        XCTAssertEqual(usd?.refundMinor, 2500)
        XCTAssertNil(usd?.netMinor, "Missing read_shopify_payments_payouts must leave netMinor nil")
        XCTAssertEqual(usd?.payoutMinor, 8000)
        XCTAssertTrue(usd?.hasIncompleteData ?? false)
    }

    func testInterruptedPaginationKeepsCacheAndDisconnectWipesOnlyTargetSource() async {
        let now = Date()
        let stripeCfg = SourceAccountConfig(source: .stripe, accountId: "acct_s1", accountLabel: "Stripe")
        let shopifyCfg = SourceAccountConfig(source: .shopify, accountId: "shop_1", accountLabel: "Shopify")
        let provider = ScriptedRevenueProvider()
        await provider.configure(events: [
            .stripe: [RevenueLedgerEvent(id: "bt_1", source: .stripe, accountId: "acct_s1", occurredAt: now, category: .charge, reportingCategory: "charge", grossMinor: 3000, feeMinor: 100, netMinor: 2900, currency: "USD")],
            .shopify: [RevenueLedgerEvent(id: "ord_1", source: .shopify, accountId: "shop_1", occurredAt: now, category: .charge, reportingCategory: "order", grossMinor: 4000, feeMinor: 120, netMinor: 3880, currency: "USD")],
        ])
        let store = InMemoryRevenueAccountStore(initial: [.stripe: stripeCfg, .shopify: shopifyCfg])
        let coord = RevenueCoordinator(provider: provider, accountStore: store, clock: { now })
        await coord.openPage()

        // Next sync hits interrupted pagination on Stripe ONLY -> keeps cached $30 USD and preserves Shopify intact.
        await provider.configure(
            events: [
                .stripe: [RevenueLedgerEvent(id: "bt_bad", source: .stripe, accountId: "acct_s1", occurredAt: now, category: .charge, reportingCategory: "charge", grossMinor: 999999, currency: "USD")],
                .shopify: [RevenueLedgerEvent(id: "ord_1", source: .shopify, accountId: "shop_1", occurredAt: now, category: .charge, reportingCategory: "order", grossMinor: 4000, feeMinor: 120, netMinor: 3880, currency: "USD")],
            ],
            interrupted: [.stripe]
        )
        await coord.refresh(force: true)
        let afterInterrupt = await coord.snapshot
        XCTAssertEqual(afterInterrupt.stripeState.error, .paginationInterrupted)
        XCTAssertEqual(afterInterrupt.stripeState.report?.currencyTotals.first?.grossMinor, 3000)
        XCTAssertNil(afterInterrupt.shopifyState.error)

        // Disconnecting Stripe removes only Stripe cache/config; Shopify remains active.
        await coord.disconnectSource(.stripe)
        let afterDisconnect = await coord.snapshot
        XCTAssertEqual(afterDisconnect.stripeState, .unconfigured)
        XCTAssertNotNil(afterDisconnect.shopifyState.report)
    }

    func testDSTDayBoundaryRespectsAccountTimeZone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyTZ
        // 2026-11-01 is US Eastern DST fall-back day (25-hour day in America/New_York)
        let dstDayEvening = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 21, minute: 30))!
        let win = RevenueAggregator.periodWindow(for: .today, now: dstDayEvening, timeZone: nyTZ)
        let midnight = cal.startOfDay(for: dstDayEvening)
        XCTAssertEqual(win.start, midnight)
        XCTAssertTrue(win.end.timeIntervalSince(win.start) >= 25 * 3600 - 1)
    }

    func testAllRevenueL10nKeysExistInStore() throws {
        let store = try L10nFixture.load()
        for p in RevenuePeriod.allCases {
            XCTAssertNotNil(store.entries[p.titleKey], "Missing period L10n key \(p.titleKey)")
        }
        let errors: [RevenueError] = [.networkUnavailable, .rateLimited, .timeout, .unauthorized, .scopeRestricted, .paginationInterrupted, .invalidData]
        for err in errors {
            let p = RevenueErrorPresentation(for: err)
            XCTAssertNotNil(store.entries[p.titleKey], "Missing error L10n title \(p.titleKey)")
            if let h = p.hintKey {
                XCTAssertNotNil(store.entries[h], "Missing error L10n hint \(h)")
            }
        }
    }

    func testHalfOpenMidnightExclusionAndDST23h25hHourlyBuckets() throws {
        let cfg = SourceAccountConfig(source: .stripe, accountId: "acct_dst", accountLabel: "Stripe NY", timeZoneIdentifier: "America/New_York")

        // 1. Fall-back day (2026-11-01, 25h in America/New_York): repeated 01:30 EDT (05:30Z) and 01:30 EST (06:30Z),
        // plus exact next-day midnight 2026-11-02T05:00:00Z which must be excluded by half-open `< windowEnd`.
        let fallNow = try Date("2026-11-02T04:55:00Z", strategy: .iso8601)
        let fallEvents = [
            RevenueLedgerEvent(id: "e1", source: .stripe, accountId: "acct_dst", occurredAt: try Date("2026-11-01T05:30:00Z", strategy: .iso8601), category: .charge, reportingCategory: "charge", grossMinor: 10_000, feeMinor: 300, netMinor: 9_700, currency: "USD"),
            RevenueLedgerEvent(id: "e2", source: .stripe, accountId: "acct_dst", occurredAt: try Date("2026-11-01T06:30:00Z", strategy: .iso8601), category: .charge, reportingCategory: "charge", grossMinor: 5_000, feeMinor: 150, netMinor: 4_850, currency: "USD"),
            RevenueLedgerEvent(id: "next_midnight", source: .stripe, accountId: "acct_dst", occurredAt: try Date("2026-11-02T05:00:00Z", strategy: .iso8601), category: .charge, reportingCategory: "charge", grossMinor: 99_900, feeMinor: 900, netMinor: 99_000, currency: "USD"),
        ]
        let fallRep = RevenueAggregator.buildSourceReport(config: cfg, events: fallEvents, period: .today, now: fallNow, fetchedAt: fallNow, cursor: nil, wasPaginationInterrupted: false)
        let fallUSD = try XCTUnwrap(fallRep.currencyTotals.first { $0.currency == "USD" })
        XCTAssertEqual(fallUSD.grossMinor, 15_000, "Exact next-day midnight event must be excluded")
        let fallBuckets = try XCTUnwrap(fallRep.bucketsByCurrency["USD"])
        XCTAssertEqual(fallBuckets.count, 25)
        XCTAssertEqual(fallBuckets[1].grossMinor, 10_000)
        XCTAssertEqual(fallBuckets[2].grossMinor, 5_000)
        XCTAssertEqual(fallBuckets.reduce(Int64(0)) { $0 + $1.grossMinor }, fallUSD.grossMinor)

        // 2. Spring-forward day (2026-03-08, 23h in America/New_York): 01:45 EST (06:45Z) and 03:15 EDT (07:15Z).
        let springNow = try Date("2026-03-09T02:00:00Z", strategy: .iso8601)
        let springEvents = [
            RevenueLedgerEvent(id: "s1", source: .stripe, accountId: "acct_dst", occurredAt: try Date("2026-03-08T06:45:00Z", strategy: .iso8601), category: .charge, reportingCategory: "charge", grossMinor: 4_000, feeMinor: 120, netMinor: 3_880, currency: "USD"),
            RevenueLedgerEvent(id: "s2", source: .stripe, accountId: "acct_dst", occurredAt: try Date("2026-03-08T07:15:00Z", strategy: .iso8601), category: .charge, reportingCategory: "charge", grossMinor: 6_000, feeMinor: 180, netMinor: 5_820, currency: "USD"),
        ]
        let springRep = RevenueAggregator.buildSourceReport(config: cfg, events: springEvents, period: .today, now: springNow, fetchedAt: springNow, cursor: nil, wasPaginationInterrupted: false)
        let springBuckets = try XCTUnwrap(springRep.bucketsByCurrency["USD"])
        XCTAssertEqual(springBuckets.count, 23)
        XCTAssertEqual(springBuckets[1].grossMinor, 4_000)
        XCTAssertEqual(springBuckets[2].grossMinor, 6_000)
        XCTAssertFalse(springBuckets.contains { $0.label == "02h" })
    }

    func testAccountIsolationStandaloneFeeNetMathDualShopifyStreamsAndFormatting() async throws {
        let t0 = try Date("2026-11-01T16:00:00Z", strategy: .iso8601)

        // 1. Standalone fee with grossMinor == 0, feeMinor == 500 must reduce netMinor by 500;
        //    unclassified event must withhold netMinor without altering grossMinor.
        let stripeCfg = SourceAccountConfig(source: .stripe, accountId: "acct_a", accountLabel: "A")
        let feeEvents = [
            RevenueLedgerEvent(id: "ch_1", source: .stripe, accountId: "acct_a", occurredAt: t0, category: .charge, reportingCategory: "charge", grossMinor: 10_000, feeMinor: 320, netMinor: 9_680, currency: "USD"),
            RevenueLedgerEvent(id: "fee_1", source: .stripe, accountId: "acct_a", occurredAt: t0, category: .fee, reportingCategory: "fee", grossMinor: 0, feeMinor: 500, netMinor: nil, currency: "USD"),
        ]
        let feeRep = RevenueAggregator.buildSourceReport(config: stripeCfg, events: feeEvents, period: .today, now: t0, fetchedAt: t0, cursor: nil, wasPaginationInterrupted: false)
        let feeUSD = try XCTUnwrap(feeRep.currencyTotals.first)
        XCTAssertEqual(feeUSD.feeMinor, 820)
        XCTAssertEqual(feeUSD.netMinor, 9_180)

        let withUnclassified = feeEvents + [
            RevenueLedgerEvent(id: "unk_1", source: .stripe, accountId: "acct_a", occurredAt: t0, category: .unclassified, reportingCategory: "unknown", grossMinor: -200, currency: "USD"),
        ]
        let unkRep = RevenueAggregator.buildSourceReport(config: stripeCfg, events: withUnclassified, period: .today, now: t0, fetchedAt: t0, cursor: nil, wasPaginationInterrupted: false)
        XCTAssertEqual(unkRep.currencyTotals.first?.grossMinor, 10_000)
        XCTAssertNil(unkRep.currencyTotals.first?.netMinor)

        // 2. Dual Shopify streams (shopifyOrders + shopifyPaymentsSettlement) must not double-count grossMinor.
        let shopCfg = SourceAccountConfig(source: .shopify, accountId: "shop_a", accountLabel: "Shop", hasPayoutScope: true)
        let dualEvents = [
            RevenueLedgerEvent(id: "ord_1", source: .shopify, accountId: "shop_a", occurredAt: t0, category: .charge, reportingCategory: "order", grossMinor: 10_000, currency: "USD", stream: .shopifyOrders),
            RevenueLedgerEvent(id: "sp_1", source: .shopify, accountId: "shop_a", occurredAt: t0, category: .charge, reportingCategory: "charge", grossMinor: 10_000, feeMinor: 320, netMinor: 9_680, currency: "USD", stream: .shopifyPaymentsSettlement),
        ]
        let dualRep = RevenueAggregator.buildSourceReport(config: shopCfg, events: dualEvents, period: .today, now: t0, fetchedAt: t0, cursor: nil, wasPaginationInterrupted: false)
        XCTAssertEqual(dualRep.currencyTotals.first?.grossMinor, 10_000)
        XCTAssertEqual(dualRep.currencyTotals.first?.netMinor, 9_680)

        // 3. Account switch on RevenueCoordinator clears prior account's cache/cursor.
        let provider = ScriptedRevenueProvider()
        await provider.configure(events: [
            .stripe: [RevenueLedgerEvent(id: "shared_id", source: .stripe, accountId: "acct_a", occurredAt: t0, category: .charge, reportingCategory: "charge", grossMinor: 3_000, feeMinor: 100, netMinor: 2_900, currency: "USD")],
        ])
        let coord = RevenueCoordinator(provider: provider, accountStore: InMemoryRevenueAccountStore(initial: [.stripe: stripeCfg]), clock: { t0 })
        await coord.openPage()
        let reportA = await coord.snapshot.stripeState.report
        XCTAssertEqual(reportA?.currencyTotals.first?.grossMinor, 3_000)

        let stripeCfgB = SourceAccountConfig(source: .stripe, accountId: "acct_b", accountLabel: "B")
        await provider.configure(events: [
            .stripe: [RevenueLedgerEvent(id: "shared_id", source: .stripe, accountId: "acct_b", occurredAt: t0, category: .charge, reportingCategory: "charge", grossMinor: 7_000, feeMinor: 200, netMinor: 6_800, currency: "USD")],
        ])
        await coord.configureSource(stripeCfgB)
        let reportB = await coord.snapshot.stripeState.report
        XCTAssertEqual(reportB?.currencyTotals.first?.grossMinor, 7_000)
        XCTAssertEqual(reportB?.config.accountId, "acct_b")

        // 4. 3-decimal ISO currency & locale-aware decimal formatting without L10n.isEnglish dependency.
        XCTAssertEqual(MoneyFormatting.format(minorUnits: 12_345, currency: "KWD", english: true), "12.345 KWD")
        XCTAssertEqual(MoneyFormatting.format(minorUnits: 123_456, currency: "USD", english: false), "$1.234,56 USD")
    }
}
