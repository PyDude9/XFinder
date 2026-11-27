import Foundation

public enum RevenueSourceKind: String, CaseIterable, Hashable, Codable, Identifiable, Sendable {
    case stripe
    case shopify

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stripe: return "Stripe"
        case .shopify: return "Shopify"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .stripe: return "creditcard.fill"
        case .shopify: return "bag.fill"
        }
    }
}

public enum RevenuePeriod: String, CaseIterable, Hashable, Codable, Identifiable, Sendable {
    case today
    case sevenDays
    case thirtyDays

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .today: return "Hôm nay"
        case .sevenDays: return "7 ngày"
        case .thirtyDays: return "30 ngày"
        }
    }

    public var dayCount: Int {
        switch self {
        case .today: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        }
    }
}

public enum RevenueEventCategory: String, Equatable, Hashable, Codable, Sendable {
    case charge
    case refund
    case fee
    case payout
    case unclassified
}

public enum RevenueLedgerStream: String, Equatable, Hashable, Codable, Sendable {
    case stripeSettlement
    case shopifyOrders
    case shopifyPaymentsSettlement
}

/// Exact integer-minor-unit ledger entry pinned to portal account and reporting currency.
public struct RevenueLedgerEvent: Equatable, Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let source: RevenueSourceKind
    public let accountId: String
    public let stream: RevenueLedgerStream?
    public let occurredAt: Date
    public let category: RevenueEventCategory
    public let reportingCategory: String
    public let sourceReferenceId: String?
    public let reconciliationKey: String?
    public let grossMinor: Int64
    public let feeMinor: Int64?
    public let netMinor: Int64?
    public let currency: String

    public init(
        id: String,
        source: RevenueSourceKind,
        accountId: String,
        occurredAt: Date,
        category: RevenueEventCategory,
        reportingCategory: String,
        sourceReferenceId: String? = nil,
        reconciliationKey: String? = nil,
        grossMinor: Int64,
        feeMinor: Int64? = nil,
        netMinor: Int64? = nil,
        currency: String,
        stream: RevenueLedgerStream? = nil
    ) {
        self.id = id
        self.source = source
        self.accountId = accountId
        self.stream = stream
        self.occurredAt = occurredAt
        self.category = category
        self.reportingCategory = reportingCategory
        self.sourceReferenceId = sourceReferenceId
        self.reconciliationKey = reconciliationKey
        self.grossMinor = grossMinor
        self.feeMinor = feeMinor
        self.netMinor = netMinor
        self.currency = currency.uppercased()
    }
}

public enum MoneyFormatting {
    private static let zeroDecimalCurrencies: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "HUF", "IDR"]
    private static let threeDecimalCurrencies: Set<String> = ["KWD", "BHD", "OMR", "JOD", "TND", "IQD", "LYD"]

    public static func minorExponent(for currency: String) -> Int {
        let code = currency.uppercased()
        if zeroDecimalCurrencies.contains(code) { return 0 }
        if threeDecimalCurrencies.contains(code) { return 3 }
        return 2
    }

    /// Formats integer minor units cleanly without binary floating-point rounding drift.
    /// Accepts an explicit `english` flag (defaulting to `true`) so formatting stays pure and
    /// independent of global `L10n` state inside SwiftPM logic tests.
    public static func format(minorUnits: Int64, currency: String, english: Bool = true) -> String {
        let isEnglish = english
        let code = currency.uppercased()
        let exp = minorExponent(for: code)
        let negative = minorUnits < 0
        let absUnits: UInt64 = minorUnits == Int64.min ? UInt64(Int64.max) + 1 : UInt64(negative ? -minorUnits : minorUnits)

        let groupSep = isEnglish ? "," : "."
        let decSep = isEnglish ? "." : ","
        let numberPart: String
        if exp == 0 {
            numberPart = groupedInteger(absUnits, separator: groupSep)
        } else {
            let divisor: UInt64 = exp == 3 ? 1_000 : 100
            let major = absUnits / divisor
            let frac = absUnits % divisor
            let majorStr = groupedInteger(major, separator: groupSep)
            let fracStr = exp == 3 ? String(format: "%03d", Int(frac)) : String(format: "%02d", Int(frac))
            numberPart = "\(majorStr)\(decSep)\(fracStr)"
        }

        let symbolPrefix: String
        switch code {
        case "USD": symbolPrefix = "$"
        case "EUR": symbolPrefix = "€"
        case "GBP": symbolPrefix = "£"
        case "JPY": symbolPrefix = "¥"
        case "VND": return "\(negative ? "-" : "")\(numberPart) ₫"
        default: symbolPrefix = ""
        }
        let sign = negative ? "-" : ""
        return symbolPrefix.isEmpty
            ? "\(sign)\(numberPart) \(code)"
            : "\(sign)\(symbolPrefix)\(numberPart) \(code)"
    }

    private static func groupedInteger(_ value: UInt64, separator: String) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var chunks: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            chunks.append(String(digits[start..<end]))
            end = start
        }
        return chunks.reversed().joined(separator: separator)
    }
}

public struct SourceAccountConfig: Equatable, Hashable, Codable, Sendable {
    public let source: RevenueSourceKind
    public let accountId: String
    public let accountLabel: String
    public let timeZoneIdentifier: String
    public let hasPayoutScope: Bool
    public let historyLimitedDays: Int?
    /// True ONLY when cross-source deduplication keys or disjoint accounts are explicitly confirmed.
    public let reconciliationProvenDisjoint: Bool

    public init(
        source: RevenueSourceKind,
        accountId: String,
        accountLabel: String,
        timeZoneIdentifier: String = "America/New_York",
        hasPayoutScope: Bool = true,
        historyLimitedDays: Int? = nil,
        reconciliationProvenDisjoint: Bool = false
    ) {
        self.source = source
        self.accountId = accountId
        self.accountLabel = accountLabel
        self.timeZoneIdentifier = timeZoneIdentifier
        self.hasPayoutScope = hasPayoutScope
        self.historyLimitedDays = historyLimitedDays
        self.reconciliationProvenDisjoint = reconciliationProvenDisjoint
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "America/New_York") ?? .current
    }
}

public struct CurrencyRevenueTotals: Equatable, Hashable, Codable, Identifiable, Sendable {
    public var id: String { currency }
    public let currency: String
    public let transactionCount: Int
    public let grossMinor: Int64
    public let refundMinor: Int64
    public let feeMinor: Int64?
    public let netMinor: Int64?
    public let payoutMinor: Int64?
    public let hasIncompleteData: Bool

    public init(
        currency: String,
        transactionCount: Int,
        grossMinor: Int64,
        refundMinor: Int64,
        feeMinor: Int64?,
        netMinor: Int64?,
        payoutMinor: Int64?,
        hasIncompleteData: Bool
    ) {
        self.currency = currency
        self.transactionCount = transactionCount
        self.grossMinor = grossMinor
        self.refundMinor = refundMinor
        self.feeMinor = feeMinor
        self.netMinor = netMinor
        self.payoutMinor = payoutMinor
        self.hasIncompleteData = hasIncompleteData
    }
}

public struct RevenueChartBucket: Equatable, Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let label: String
    public let bucketStart: Date
    public let grossMinor: Int64

    public init(id: String, label: String, bucketStart: Date, grossMinor: Int64) {
        self.id = id
        self.label = label
        self.bucketStart = bucketStart
        self.grossMinor = grossMinor
    }
}

public struct SourceRevenueReport: Equatable, Sendable {
    public let source: RevenueSourceKind
    public let config: SourceAccountConfig
    public let period: RevenuePeriod
    public let windowStart: Date
    public let windowEnd: Date
    public let windowBoundaryLabel: String
    public let currencyTotals: [CurrencyRevenueTotals]
    public let bucketsByCurrency: [String: [RevenueChartBucket]]
    public let fetchedAt: Date
    public let cursor: String?
    public let wasPaginationInterrupted: Bool
    public let historyLimitedNoticeKey: String?

    public init(
        source: RevenueSourceKind,
        config: SourceAccountConfig,
        period: RevenuePeriod,
        windowStart: Date,
        windowEnd: Date,
        windowBoundaryLabel: String,
        currencyTotals: [CurrencyRevenueTotals],
        bucketsByCurrency: [String: [RevenueChartBucket]],
        fetchedAt: Date,
        cursor: String?,
        wasPaginationInterrupted: Bool = false,
        historyLimitedNoticeKey: String? = nil
    ) {
        self.source = source
        self.config = config
        self.period = period
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.windowBoundaryLabel = windowBoundaryLabel
        self.currencyTotals = currencyTotals
        self.bucketsByCurrency = bucketsByCurrency
        self.fetchedAt = fetchedAt
        self.cursor = cursor
        self.wasPaginationInterrupted = wasPaginationInterrupted
        self.historyLimitedNoticeKey = historyLimitedNoticeKey
    }
}

public enum SourceSyncState: Equatable, Sendable {
    case unconfigured
    case loadingInitial
    case loaded(SourceRevenueReport, refreshing: Bool)
    case empty(SourceRevenueReport, refreshing: Bool)
    case failedWithCache(SourceRevenueReport, error: RevenueError)
    case failedNoCache(error: RevenueError)

    public var report: SourceRevenueReport? {
        switch self {
        case .loaded(let r, _), .empty(let r, _), .failedWithCache(let r, _):
            return r
        case .unconfigured, .loadingInitial, .failedNoCache:
            return nil
        }
    }

    public var isRefreshing: Bool {
        switch self {
        case .loadingInitial: return true
        case .loaded(_, let r), .empty(_, let r): return r
        case .unconfigured, .failedWithCache, .failedNoCache: return false
        }
    }

    public var error: RevenueError? {
        switch self {
        case .failedWithCache(_, let e), .failedNoCache(let e): return e
        default: return nil
        }
    }
}

public enum RevenueReconciliationStatus: Equatable, Hashable, Sendable {
    case singleSourceOrNone
    case ambiguousOverlap(unmatchedCount: Int)
    case verifiedDisjoint(linkedMatches: Int)
}

public struct RevenueSnapshot: Equatable, Sendable {
    public let period: RevenuePeriod
    public let stripeState: SourceSyncState
    public let shopifyState: SourceSyncState
    public let reconciliationStatus: RevenueReconciliationStatus
    /// Non-nil ONLY when `reconciliationStatus` proves cross-source totals can be combined safely.
    public let combinedTotalsByCurrency: [CurrencyRevenueTotals]?

    public init(
        period: RevenuePeriod,
        stripeState: SourceSyncState,
        shopifyState: SourceSyncState,
        reconciliationStatus: RevenueReconciliationStatus,
        combinedTotalsByCurrency: [CurrencyRevenueTotals]? = nil
    ) {
        self.period = period
        self.stripeState = stripeState
        self.shopifyState = shopifyState
        self.reconciliationStatus = reconciliationStatus
        self.combinedTotalsByCurrency = combinedTotalsByCurrency
    }
}
