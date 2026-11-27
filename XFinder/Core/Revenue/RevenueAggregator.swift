import Foundation

/// Pure DST-aware financial aggregation and cross-source reconciliation engine.
/// Keeps Stripe and Shopify separate whenever transaction deduplication is not proven,
/// separates refunds/fees/payouts, and formats totals strictly per ISO currency in minor units.
public enum RevenueAggregator {

    /// Computes exact reporting window `[windowStart, windowEnd]` anchored in account timezone.
    public static func periodWindow(
        for period: RevenuePeriod,
        now: Date,
        timeZone: TimeZone
    ) -> (start: Date, end: Date, boundaryLabel: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfToday = cal.startOfDay(for: now)
        let windowStart: Date
        switch period {
        case .today:
            windowStart = startOfToday
        case .sevenDays:
            windowStart = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .thirtyDays:
            windowStart = cal.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        }
        let endOfWindow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let tzName = timeZone.abbreviation(for: now) ?? timeZone.identifier
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZone
        df.dateFormat = "dd/MM"
        let label = period == .today
            ? "\(df.string(from: windowStart)) · \(tzName)"
            : "\(df.string(from: windowStart))–\(df.string(from: startOfToday)) · \(tzName)"
        return (windowStart, endOfWindow, label)
    }

    public static func buildSourceReport(
        config: SourceAccountConfig,
        events: [RevenueLedgerEvent],
        period: RevenuePeriod,
        now: Date,
        fetchedAt: Date,
        cursor: String?,
        wasPaginationInterrupted: Bool
    ) -> SourceRevenueReport {
        let tz = config.timeZone
        let window = periodWindow(for: period, now: now, timeZone: tz)
        let deduped = deduplicateById(events.filter { $0.source == config.source && $0.accountId == config.accountId })
        let scoped = deduped.filter { $0.occurredAt >= window.start && $0.occurredAt < window.end }

        var byCurrency: [String: [RevenueLedgerEvent]] = [:]
        for event in scoped {
            byCurrency[event.currency, default: []].append(event)
        }

        let orderedCurrencies = byCurrency.keys.sorted()
        var summaries: [CurrencyRevenueTotals] = []
        var bucketsByCurrency: [String: [RevenueChartBucket]] = [:]

        let limitNotice: String? = {
            if let limit = config.historyLimitedDays, period.dayCount > limit {
                return "Lịch sử bị giới hạn bởi quyền hiện tại"
            }
            if config.source == .shopify && !config.hasPayoutScope {
                return "Thiếu quyền payout Shopify Payments — phí/thực nhận chưa có dữ liệu"
            }
            return nil
        }()

        for currency in orderedCurrencies {
            let group = byCurrency[currency] ?? []
            summaries.append(summarize(group, currency: currency, config: config))
            bucketsByCurrency[currency] = bucketSeries(
                group,
                period: period,
                windowStart: window.start,
                windowEnd: window.end,
                timeZone: tz
            )
        }

        return SourceRevenueReport(
            source: config.source,
            config: config,
            period: period,
            windowStart: window.start,
            windowEnd: window.end,
            windowBoundaryLabel: window.boundaryLabel,
            currencyTotals: summaries,
            bucketsByCurrency: bucketsByCurrency,
            fetchedAt: fetchedAt,
            cursor: cursor,
            wasPaginationInterrupted: wasPaginationInterrupted,
            historyLimitedNoticeKey: limitNotice
        )
    }

    /// Reconciles Stripe + Shopify strictly per rule: combine across sources ONLY when both
    /// accounts prove disjointness or share deterministic reconciliation keys with zero unmatched overlap.
    public static func evaluateCrossSource(
        stripeReport: SourceRevenueReport?,
        shopifyReport: SourceRevenueReport?,
        stripeEvents: [RevenueLedgerEvent],
        shopifyEvents: [RevenueLedgerEvent],
        period: RevenuePeriod,
        now: Date
    ) -> (status: RevenueReconciliationStatus, combined: [CurrencyRevenueTotals]?) {
        guard let sReport = stripeReport, let shReport = shopifyReport else {
            return (.singleSourceOrNone, nil)
        }
        let sSales = inWindowSales(events: stripeEvents, report: sReport)
        let shSales = inWindowSales(events: shopifyEvents, report: shReport)

        if sReport.config.reconciliationProvenDisjoint && shReport.config.reconciliationProvenDisjoint {
            // Even when proven reconcilable, deduplicate records linked via common (reconciliationKey, category).
            let stripeKeys = Set(sSales.compactMap { e -> String? in
                guard let k = e.reconciliationKey else { return nil }
                return "\(e.category.rawValue)::\(k)"
            })
            let linkedMatches = shSales.filter {
                guard let k = $0.reconciliationKey else { return false }
                return stripeKeys.contains("\($0.category.rawValue)::\(k)")
            }.count
            let combinedEvents = deduplicateCrossSource(stripe: sSales, shopify: shSales)
            let shopifyMissingPayoutScope = shReport.config.source == .shopify && !shReport.config.hasPayoutScope
            var byCurr: [String: [RevenueLedgerEvent]] = [:]
            for e in combinedEvents { byCurr[e.currency, default: []].append(e) }
            let totals = byCurr.keys.sorted().map { curr in
                summarize(
                    byCurr[curr] ?? [],
                    currency: curr,
                    config: sReport.config,
                    forceIncompleteIfMissing: shopifyMissingPayoutScope
                )
            }
            return (.verifiedDisjoint(linkedMatches: linkedMatches), totals)
        }

        let stripeKeys = Set(sSales.compactMap { e -> String? in
            guard let k = e.reconciliationKey else { return nil }
            return "\(e.category.rawValue)::\(k)"
        })
        let unmatchedShopify = shSales.filter {
            guard let k = $0.reconciliationKey else { return true }
            return !stripeKeys.contains("\($0.category.rawValue)::\(k)")
        }.count
        let totalUnmatched = unmatchedShopify + sSales.filter { $0.reconciliationKey == nil }.count
        return (.ambiguousOverlap(unmatchedCount: totalUnmatched), nil)
    }

    private static func inWindowSales(events: [RevenueLedgerEvent], report: SourceRevenueReport) -> [RevenueLedgerEvent] {
        let filtered = events.filter {
            $0.source == report.source
            && $0.accountId == report.config.accountId
            && $0.occurredAt >= report.windowStart
            && $0.occurredAt < report.windowEnd
            && $0.category != .payout
        }
        return deduplicateById(filtered)
    }

    private static func summarize(
        _ events: [RevenueLedgerEvent],
        currency: String,
        config: SourceAccountConfig,
        forceIncompleteIfMissing: Bool = false
    ) -> CurrencyRevenueTotals {
        // When Shopify carries both commercial orders and Payments settlement streams, avoid double-counting sales
        // by taking gross/refund counts from commercial orders while reading fees/payouts from settlement.
        let hasShopifyOrders = events.contains { $0.stream == .shopifyOrders }
        let hasShopifySettlement = events.contains { $0.stream == .shopifyPaymentsSettlement }
        let dualShopifyStreams = config.source == .shopify && hasShopifyOrders && hasShopifySettlement

        var gross: Int64 = 0
        var refund: Int64 = 0
        var txCount = 0
        var feeAccum: Int64 = 0
        var netAccum: Int64 = 0
        var payoutAccum: Int64 = 0
        var hasPayout = false
        var sawMissingNet = false

        for event in events {
            let skipOrderTotalsForSettlement = dualShopifyStreams && event.stream == .shopifyPaymentsSettlement
            let skipSettlementMathForOrder = dualShopifyStreams && event.stream == .shopifyOrders

            switch event.category {
            case .charge:
                if !skipOrderTotalsForSettlement {
                    txCount += 1
                    gross += event.grossMinor
                }
                if !skipSettlementMathForOrder {
                    if let fee = event.feeMinor, let net = event.netMinor {
                        feeAccum += fee
                        netAccum += net
                    } else {
                        sawMissingNet = true
                    }
                }
            case .refund:
                if !skipOrderTotalsForSettlement {
                    txCount += 1
                    refund += event.grossMinor >= 0 ? event.grossMinor : -event.grossMinor
                }
                if !skipSettlementMathForOrder {
                    if let fee = event.feeMinor {
                        feeAccum += fee
                    }
                    if let net = event.netMinor {
                        netAccum += net
                    } else {
                        sawMissingNet = true
                    }
                }
            case .fee:
                let feeAmount = event.feeMinor ?? abs(event.grossMinor)
                feeAccum += feeAmount
                if let explicitNet = event.netMinor {
                    netAccum += explicitNet
                } else {
                    netAccum -= feeAmount
                }
            case .payout:
                hasPayout = true
                payoutAccum += event.grossMinor
            case .unclassified:
                sawMissingNet = true
            }
        }

        if config.source == .shopify && !config.hasPayoutScope {
            sawMissingNet = true
        }
        let incomplete = sawMissingNet || forceIncompleteIfMissing || (config.source == .shopify && !config.hasPayoutScope)
        let resolvedFee: Int64? = incomplete ? nil : feeAccum
        let resolvedNet: Int64? = incomplete ? nil : netAccum
        return CurrencyRevenueTotals(
            currency: currency,
            transactionCount: txCount,
            grossMinor: gross,
            refundMinor: refund,
            feeMinor: resolvedFee,
            netMinor: resolvedNet,
            payoutMinor: hasPayout ? payoutAccum : nil,
            hasIncompleteData: incomplete
        )
    }

    private static func deduplicateById(_ events: [RevenueLedgerEvent]) -> [RevenueLedgerEvent] {
        // Deduplicate strictly within (source, accountId, id) so cross-account/portal records never collide.
        var ordered: [RevenueLedgerEvent] = []
        var indexByKey: [String: Int] = [:]
        for event in events {
            let key = "\(event.source.rawValue):\(event.accountId)/\(event.id)"
            if let existing = indexByKey[key] {
                ordered[existing] = event
            } else {
                indexByKey[key] = ordered.count
                ordered.append(event)
            }
        }
        return ordered
    }

    private static func deduplicateCrossSource(
        stripe: [RevenueLedgerEvent],
        shopify: [RevenueLedgerEvent]
    ) -> [RevenueLedgerEvent] {
        // Match by (category, reconciliationKey) so a Shopify refund sharing a charge's reconciliationKey is not dropped.
        let stripeKeys = Set(stripe.compactMap { e -> String? in
            guard let k = e.reconciliationKey else { return nil }
            return "\(e.category.rawValue)::\(k)"
        })
        var out = stripe
        for event in shopify {
            if let key = event.reconciliationKey, stripeKeys.contains("\(event.category.rawValue)::\(key)") {
                continue
            }
            out.append(event)
        }
        return out
    }

    private static func bucketSeries(
        _ events: [RevenueLedgerEvent],
        period: RevenuePeriod,
        windowStart: Date,
        windowEnd: Date,
        timeZone: TimeZone
    ) -> [RevenueChartBucket] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hasShopifyOrders = events.contains { $0.stream == .shopifyOrders }
        let sales = events.filter {
            $0.category == .charge && !(hasShopifyOrders && $0.stream == .shopifyPaymentsSettlement)
        }

        switch period {
        case .today:
            // Step by actual elapsed 1-hour intervals in [windowStart, windowEnd) so 23h spring-forward and
            // 25h fall-back DST days keep every real hour distinct with exact bucketStart timestamps.
            var buckets: [RevenueChartBucket] = []
            var cursor = windowStart
            var idx = 0
            while cursor < windowEnd {
                let next = min(cursor.addingTimeInterval(3_600), windowEnd)
                let total = sales
                    .filter { $0.occurredAt >= cursor && $0.occurredAt < next }
                    .reduce(Int64(0)) { $0 + $1.grossMinor }
                let hour = cal.component(.hour, from: cursor)
                buckets.append(
                    RevenueChartBucket(
                        id: "h\(idx)",
                        label: String(format: "%02dh", hour),
                        bucketStart: cursor,
                        grossMinor: total
                    )
                )
                cursor = next
                idx += 1
            }
            return buckets
        case .sevenDays, .thirtyDays:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = timeZone
            df.dateFormat = "d/M"
            var buckets: [RevenueChartBucket] = []
            var cursor = cal.startOfDay(for: windowStart)
            var offset = 0
            while cursor < windowEnd {
                let nextDay = min(cal.date(byAdding: .day, value: 1, to: cursor) ?? windowEnd, windowEnd)
                let total = sales
                    .filter { $0.occurredAt >= cursor && $0.occurredAt < nextDay }
                    .reduce(Int64(0)) { $0 + $1.grossMinor }
                buckets.append(
                    RevenueChartBucket(
                        id: "d\(offset)",
                        label: df.string(from: cursor),
                        bucketStart: cursor,
                        grossMinor: total
                    )
                )
                cursor = nextDay
                offset += 1
            }
            return buckets
        }
    }
}
