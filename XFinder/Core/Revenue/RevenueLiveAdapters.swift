import Foundation

/// Enforces verified provider hostnames, HTTPS transport, and canonical API paths before any outbound
/// credential header (`Authorization` or `X-Shopify-Access-Token`) is attached or transmitted.
public enum RevenueHostPolicy {
    public static let stripeHost = "api.stripe.com"
    public static let defaultShopifyAPIVersion = "2026-01"

    /// Normalizes and validates a Shopify store domain strictly to `<shop>.myshopify.com`.
    /// Rejects schemes, paths, ports, userinfo, IP addresses, and non-`myshopify.com` domains.
    public static func normalizedShopifyHost(from raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.hasPrefix("https://") {
            candidate = String(candidate.dropFirst("https://".count))
        }
        while candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        guard !candidate.isEmpty,
              !candidate.contains("/"),
              !candidate.contains(":"),
              !candidate.contains("@"),
              !candidate.contains("?"),
              !candidate.contains("#"),
              candidate.hasSuffix(".myshopify.com") else {
            return nil
        }
        let subdomain = String(candidate.dropLast(".myshopify.com".count))
        guard (1...63).contains(subdomain.count),
              !subdomain.contains("."),
              let first = subdomain.unicodeScalars.first,
              let last = subdomain.unicodeScalars.last,
              isASCIIAlphaNumeric(first),
              isASCIIAlphaNumeric(last),
              subdomain.unicodeScalars.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == "-" }) else {
            return nil
        }
        return "\(subdomain).myshopify.com"
    }

    public static func validatedStripeURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard path.hasPrefix("/v1/"), !path.contains("..") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = stripeHost
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url,
              validateOutboundURL(url, for: .stripe) else {
            return nil
        }
        return url
    }

    public static func validatedShopifyGraphQLURL(
        shopDomain: String,
        apiVersion: String = defaultShopifyAPIVersion
    ) -> URL? {
        guard let host = normalizedShopifyHost(from: shopDomain),
              isValidShopifyAPIVersion(apiVersion) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/admin/api/\(apiVersion)/graphql.json"
        guard let url = components.url,
              validateOutboundURL(url, for: .shopify) else {
            return nil
        }
        return url
    }

    /// Verifies that an outbound request targets only the official HTTPS host and path for `source`.
    public static func validateOutboundURL(_ url: URL, for source: RevenueSourceKind) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              (components.port == nil || components.port == 443),
              let host = components.host?.lowercased(),
              !components.path.contains("..") else {
            return false
        }
        switch source {
        case .stripe:
            return host == stripeHost && components.path.hasPrefix("/v1/")
        case .shopify:
            guard normalizedShopifyHost(from: host) == host else { return false }
            return components.path.hasPrefix("/admin/api/") && components.path.hasSuffix("/graphql.json")
        }
    }

    private static func isASCIIAlphaNumeric(_ scalar: UnicodeScalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }

    private static func isValidShopifyAPIVersion(_ version: String) -> Bool {
        let parts = version.split(separator: "-")
        guard parts.count == 2,
              parts[0].count == 4, parts[0].allSatisfy(\.isNumber),
              parts[1].count == 2, parts[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }
}

/// Mockable HTTP transport abstraction for contract and pagination unit tests.
public protocol RevenueHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Refuses HTTP redirects so secret headers (`Authorization`, `X-Shopify-Access-Token`) are never
/// forwarded to an unverified redirect target.
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Ephemeral `URLSession` transport with no persistent disk cache, no shared cookies, and redirects disabled.
public final class URLSessionRevenueHTTPTransport: RevenueHTTPTransport, Sendable {
    private let session: URLSession
    private let delegate: NoRedirectSessionDelegate

    public init(timeoutInterval: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = max(timeoutInterval * 2, 30)
        let delegate = NoRedirectSessionDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RevenueError.invalidData
        }
        return (data, http)
    }
}

/// Production read-only Stripe Balance Transactions adapter (`GET https://api.stripe.com/v1/balance_transactions`).
public final class StripeBalanceTransactionsAdapter: Sendable {
    private let transport: RevenueHTTPTransport
    private let credentialStore: RevenueCredentialStore
    private let pageLimit: Int
    private let maxPages: Int

    public init(
        transport: RevenueHTTPTransport = URLSessionRevenueHTTPTransport(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared,
        pageLimit: Int = 100,
        maxPages: Int = 20
    ) {
        self.transport = transport
        self.credentialStore = credentialStore
        self.pageLimit = max(1, min(100, pageLimit))
        self.maxPages = max(1, maxPages)
    }

    public func fetchLedger(
        for config: SourceAccountConfig,
        period: RevenuePeriod,
        cursor: String?,
        now: Date
    ) async throws -> RevenueFetchPage {
        guard config.source == .stripe else { throw RevenueError.invalidData }
        guard let token = credentialStore.token(for: .stripe, accountId: config.accountId), !token.isEmpty else {
            throw RevenueError.unauthorized
        }

        let window = RevenueAggregator.periodWindow(for: period, now: now, timeZone: config.timeZone)
        let startEpoch = Int64(window.start.timeIntervalSince1970)
        let endEpoch = Int64(window.end.timeIntervalSince1970)

        var collected: [RevenueLedgerEvent] = []
        var seenIds = Set<String>()
        var startingAfter: String? = nil
        var firstSeenId: String? = nil
        var pagesFetched = 0

        while pagesFetched < maxPages {
            try Task.checkCancellation()

            var queryItems = [
                URLQueryItem(name: "limit", value: String(pageLimit)),
                URLQueryItem(name: "created[gte]", value: String(startEpoch)),
                URLQueryItem(name: "created[lt]", value: String(endEpoch)),
            ]
            if let startingAfter {
                queryItems.append(URLQueryItem(name: "starting_after", value: startingAfter))
            }

            guard let url = RevenueHostPolicy.validatedStripeURL(path: "/v1/balance_transactions", queryItems: queryItems),
                  RevenueHostPolicy.validateOutboundURL(url, for: .stripe) else {
                throw RevenueError.invalidData
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (error as? RevenueError) == .cancelled { throw error }
                if pagesFetched > 0 {
                    return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                }
                throw error
            }

            if let httpError = Self.mapHTTPStatus(response.statusCode) {
                if pagesFetched > 0 && httpError.isRetryable {
                    return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                }
                throw httpError
            }

            let decoded: StripeBalanceListResponse
            do {
                decoded = try JSONDecoder().decode(StripeBalanceListResponse.self, from: data)
            } catch {
                if pagesFetched > 0 {
                    return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                }
                throw RevenueError.invalidData
            }

            if firstSeenId == nil {
                firstSeenId = decoded.data.first?.id
            }
            for item in decoded.data {
                guard let event = item.toLedgerEvent(accountId: config.accountId) else { continue }
                if seenIds.insert(event.id).inserted {
                    collected.append(event)
                }
            }
            pagesFetched += 1

            if decoded.hasMore, let lastId = decoded.data.last?.id, !lastId.isEmpty {
                startingAfter = lastId
            } else {
                let latestCursor = firstSeenId ?? cursor
                return RevenueFetchPage(events: collected, cursor: latestCursor, wasPaginationInterrupted: false)
            }
        }

        // Hit page cap while `has_more` was still true: treat as interrupted so we do not present a partial total as complete.
        return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
    }

    private static func mapHTTPStatus(_ status: Int) -> RevenueError? {
        switch status {
        case 200...299: return nil
        case 401: return .unauthorized
        case 403: return .scopeRestricted
        case 429: return .rateLimited
        case 500...599: return .paginationInterrupted
        default: return .unknown("HTTP \(status)")
        }
    }
}

private struct StripeBalanceListResponse: Decodable {
    let data: [StripeBalanceTransactionDTO]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

private struct StripeBalanceTransactionDTO: Decodable {
    let id: String
    let amount: Int64
    let fee: Int64
    let net: Int64
    let currency: String
    let created: TimeInterval
    let type: String
    let reportingCategory: String?
    let sourceId: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, fee, net, currency, created, type, source
        case reportingCategory = "reporting_category"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        amount = try c.decode(Int64.self, forKey: .amount)
        fee = try c.decode(Int64.self, forKey: .fee)
        net = try c.decode(Int64.self, forKey: .net)
        currency = try c.decode(String.self, forKey: .currency)
        created = try c.decode(TimeInterval.self, forKey: .created)
        type = try c.decode(String.self, forKey: .type)
        reportingCategory = try c.decodeIfPresent(String.self, forKey: .reportingCategory)
        if let rawSource = try? c.decodeIfPresent(String.self, forKey: .source) {
            sourceId = rawSource
        } else if let expanded = try? c.decodeIfPresent(StripeExpandedSource.self, forKey: .source) {
            sourceId = expanded.id
        } else {
            sourceId = nil
        }
    }

    private struct StripeExpandedSource: Decodable {
        let id: String
    }

    func toLedgerEvent(accountId: String) -> RevenueLedgerEvent? {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedId.isEmpty, normalizedCurrency.count == 3 else { return nil }

        let categoryString = (reportingCategory ?? type).lowercased()
        let mappedCategory: RevenueEventCategory
        let mappedGross: Int64
        let mappedFee: Int64?
        let mappedNet: Int64?

        switch categoryString {
        case "charge", "payment":
            mappedCategory = .charge
            mappedGross = amount
            mappedFee = fee
            mappedNet = net
        case "refund", "partial_refund", "payment_refund":
            mappedCategory = .refund
            mappedGross = abs(amount)
            mappedFee = fee
            mappedNet = net
        case "fee", "stripe_fee", "network_cost":
            mappedCategory = .fee
            mappedGross = abs(amount)
            mappedFee = fee != 0 ? fee : abs(amount)
            mappedNet = net
        case "payout":
            mappedCategory = .payout
            mappedGross = abs(amount)
            mappedFee = nil
            mappedNet = nil
        default:
            // Includes payout_reversal, refund_failure, dispute, reserve_transaction, etc.
            // Kept unclassified rather than misstating gross sales or payouts.
            mappedCategory = .unclassified
            mappedGross = amount
            mappedFee = nil
            mappedNet = nil
        }

        return RevenueLedgerEvent(
            id: trimmedId,
            source: .stripe,
            accountId: accountId,
            occurredAt: Date(timeIntervalSince1970: created),
            category: mappedCategory,
            reportingCategory: categoryString,
            sourceReferenceId: sourceId,
            reconciliationKey: sourceId,
            grossMinor: mappedGross,
            feeMinor: mappedFee,
            netMinor: mappedNet,
            currency: normalizedCurrency,
            stream: .stripeSettlement
        )
    }
}

/// Production read-only Shopify Admin GraphQL adapter (`POST https://<shop>.myshopify.com/admin/api/<version>/graphql.json`).
/// Uses `read_orders` for orders/refunds and queries `shopifyPaymentsAccount` only when `config.hasPayoutScope == true`.
public final class ShopifyAdminGraphQLAdapter: Sendable {
    private let transport: RevenueHTTPTransport
    private let credentialStore: RevenueCredentialStore
    private let apiVersion: String
    private let pageSize: Int
    private let maxPages: Int

    public init(
        transport: RevenueHTTPTransport = URLSessionRevenueHTTPTransport(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared,
        apiVersion: String = RevenueHostPolicy.defaultShopifyAPIVersion,
        pageSize: Int = 100,
        maxPages: Int = 20
    ) {
        self.transport = transport
        self.credentialStore = credentialStore
        self.apiVersion = apiVersion
        self.pageSize = max(1, min(100, pageSize))
        self.maxPages = max(1, maxPages)
    }

    public func fetchLedger(
        for config: SourceAccountConfig,
        period: RevenuePeriod,
        cursor: String?,
        now: Date
    ) async throws -> RevenueFetchPage {
        guard config.source == .shopify else { throw RevenueError.invalidData }
        guard let normalizedHost = RevenueHostPolicy.normalizedShopifyHost(from: config.accountId),
              let url = RevenueHostPolicy.validatedShopifyGraphQLURL(shopDomain: normalizedHost, apiVersion: apiVersion),
              RevenueHostPolicy.validateOutboundURL(url, for: .shopify) else {
            throw RevenueError.invalidData
        }
        guard let token = credentialStore.token(for: .shopify, accountId: config.accountId)
                ?? credentialStore.token(for: .shopify, accountId: normalizedHost),
              !token.isEmpty else {
            throw RevenueError.unauthorized
        }

        let window = RevenueAggregator.periodWindow(for: period, now: now, timeZone: config.timeZone)
        let isoStart = window.start.formatted(.iso8601)
        // Filter by `updated_at >= window.start` so late refunds issued inside the window against older orders
        // are still discovered; `RevenueAggregator` scopes each order/refund by its own `occurredAt` timestamp.
        let dateQuery = "updated_at:>='\(isoStart)'"

        var eventsById: [String: RevenueLedgerEvent] = [:]
        var eventOrder: [String] = []
        func appendDedup(_ event: RevenueLedgerEvent) {
            if eventsById[event.id] == nil {
                eventOrder.append(event.id)
            }
            eventsById[event.id] = event
        }

        var orderCursor: String? = nil
        var pagesFetched = 0
        var ordersHasMore = false

        // 1. Orders & order refunds (`read_orders` scope)
        while pagesFetched < maxPages {
            try Task.checkCancellation()
            let payload: [String: Any] = [
                "query": Self.ordersQuery,
                "variables": [
                    "first": pageSize,
                    "after": orderCursor as Any,
                    "query": dateQuery,
                ],
            ]
            let responseData: Data
            do {
                responseData = try await executeGraphQL(url: url, token: token, payload: payload)
            } catch is CancellationError {
                throw CancellationError()
            } catch let err as RevenueError {
                if err == .cancelled { throw err }
                if pagesFetched > 0 && err.isRetryable {
                    return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                }
                throw err
            }

            let envelope: ShopifyOrdersEnvelope
            do {
                envelope = try JSONDecoder().decode(ShopifyOrdersEnvelope.self, from: responseData)
            } catch {
                if pagesFetched > 0 {
                    return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                }
                throw RevenueError.invalidData
            }
            if let gqlError = Self.mapGraphQLErrors(envelope.errors) {
                throw gqlError
            }
            guard let orders = envelope.data?.orders else {
                throw RevenueError.invalidData
            }

            for order in orders.nodes {
                if let chargeEvent = order.toChargeEvent(accountId: config.accountId) {
                    appendDedup(chargeEvent)
                }
                for refund in order.refunds {
                    if let refundEvent = refund.toRefundEvent(accountId: config.accountId, orderId: order.id) {
                        appendDedup(refundEvent)
                    }
                }
            }
            pagesFetched += 1
            ordersHasMore = orders.pageInfo.hasNextPage

            if ordersHasMore, let next = orders.pageInfo.endCursor, !next.isEmpty {
                orderCursor = next
            } else {
                ordersHasMore = false
                break
            }
        }

        if ordersHasMore {
            return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
        }

        // 2. Optional Shopify Payments settlement balance transactions & independent payouts pagination
        //    (`read_shopify_payments_payouts` scope; Shopify Admin GraphQL 2026-01 schema).
        if config.hasPayoutScope {
            // 2a. Balance transactions (`amount`, `fee`, `net`, `transactionDate`, `type`, `associatedPayout`).
            //     Skip `type == "PAYOUT"` rows here because `payouts` below is the authoritative paginated payout feed.
            var txCursor: String? = nil
            var txPages = 0
            var txHasMore = false
            while txPages < maxPages {
                try Task.checkCancellation()
                let payload: [String: Any] = [
                    "query": Self.balanceTransactionsQuery,
                    "variables": [
                        "first": pageSize,
                        "after": txCursor as Any,
                    ],
                ]
                let responseData: Data
                do {
                    responseData = try await executeGraphQL(url: url, token: token, payload: payload)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let err as RevenueError {
                    if err == .cancelled { throw err }
                    if err.isRetryable {
                        return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                    }
                    throw err
                }

                let envelope: ShopifyBalanceTransactionsEnvelope
                do {
                    envelope = try JSONDecoder().decode(ShopifyBalanceTransactionsEnvelope.self, from: responseData)
                } catch {
                    throw RevenueError.invalidData
                }
                if let gqlError = Self.mapGraphQLErrors(envelope.errors) {
                    throw gqlError
                }
                guard let account = envelope.data?.shopifyPaymentsAccount else {
                    break
                }

                for tx in account.balanceTransactions.nodes {
                    if let ev = tx.toLedgerEvent(accountId: config.accountId) {
                        appendDedup(ev)
                    }
                }
                txPages += 1
                txHasMore = account.balanceTransactions.pageInfo.hasNextPage

                if txHasMore,
                   let next = account.balanceTransactions.pageInfo.endCursor,
                   !next.isEmpty {
                    txCursor = next
                } else {
                    txHasMore = false
                    break
                }
            }
            if txHasMore {
                return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
            }

            // 2b. Independent payouts pagination (`payouts(first: $first, after: $after, reverse: true)`).
            var payoutCursor: String? = nil
            var payoutPages = 0
            var payoutsHasMore = false
            while payoutPages < maxPages {
                try Task.checkCancellation()
                let payload: [String: Any] = [
                    "query": Self.payoutsQuery,
                    "variables": [
                        "first": pageSize,
                        "after": payoutCursor as Any,
                    ],
                ]
                let responseData: Data
                do {
                    responseData = try await executeGraphQL(url: url, token: token, payload: payload)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let err as RevenueError {
                    if err == .cancelled { throw err }
                    if err.isRetryable {
                        return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
                    }
                    throw err
                }

                let envelope: ShopifyPayoutsEnvelope
                do {
                    envelope = try JSONDecoder().decode(ShopifyPayoutsEnvelope.self, from: responseData)
                } catch {
                    throw RevenueError.invalidData
                }
                if let gqlError = Self.mapGraphQLErrors(envelope.errors) {
                    throw gqlError
                }
                guard let account = envelope.data?.shopifyPaymentsAccount else {
                    break
                }

                var passedWindowStart = false
                for payout in account.payouts.nodes {
                    if let issuedDate = try? Date(payout.issuedAt, strategy: .iso8601),
                       issuedDate < window.start {
                        passedWindowStart = true
                    }
                    if let ev = payout.toPayoutEvent(accountId: config.accountId) {
                        appendDedup(ev)
                    }
                }
                payoutPages += 1
                payoutsHasMore = account.payouts.pageInfo.hasNextPage && !passedWindowStart

                if payoutsHasMore,
                   let next = account.payouts.pageInfo.endCursor,
                   !next.isEmpty {
                    payoutCursor = next
                } else {
                    payoutsHasMore = false
                    break
                }
            }
            if payoutsHasMore {
                return RevenueFetchPage(events: [], cursor: cursor, wasPaginationInterrupted: true)
            }
        }

        let orderedEvents = eventOrder.compactMap { eventsById[$0] }
        let finalCursor = orderCursor ?? cursor
        return RevenueFetchPage(events: orderedEvents, cursor: finalCursor, wasPaginationInterrupted: false)
    }

    private func executeGraphQL(url: URL, token: String, payload: [String: Any]) async throws -> Data {
        guard RevenueHostPolicy.validateOutboundURL(url, for: .shopify) else {
            throw RevenueError.invalidData
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw RevenueError.unauthorized
        case 403:
            throw RevenueError.scopeRestricted
        case 429:
            throw RevenueError.rateLimited
        case 500...599:
            throw RevenueError.paginationInterrupted
        default:
            throw RevenueError.unknown("HTTP \(response.statusCode)")
        }
    }

    private static func mapGraphQLErrors(_ errors: [ShopifyGraphQLError]?) -> RevenueError? {
        guard let errors, !errors.isEmpty else { return nil }
        for err in errors {
            let code = err.extensions?.code?.uppercased() ?? ""
            if code == "ACCESS_DENIED" || err.message.lowercased().contains("access denied") {
                return .scopeRestricted
            }
            if code == "THROTTLED" {
                return .rateLimited
            }
        }
        return .unknown(errors.first?.message ?? "GraphQL error")
    }

    static func parseDecimalAmountToMinorUnits(_ raw: String, currency: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN, decimal.isFinite else {
            return nil
        }
        let exp = MoneyFormatting.minorExponent(for: currency)
        var scaled = decimal * pow(Decimal(10), exp)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static let ordersQuery = """
    query XFinderOrders($first: Int!, $after: String, $query: String!) {
      orders(first: $first, after: $after, query: $query, sortKey: UPDATED_AT) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          createdAt
          totalPriceSet { shopMoney { amount currencyCode } }
          refunds {
            id
            createdAt
            totalRefundedSet { shopMoney { amount currencyCode } }
          }
        }
      }
    }
    """

    static let balanceTransactionsQuery = """
    query XFinderShopifyPaymentsBalanceTransactions($first: Int!, $after: String) {
      shopifyPaymentsAccount {
        balanceTransactions(first: $first, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            type
            transactionDate
            amount { amount currencyCode }
            fee { amount currencyCode }
            net { amount currencyCode }
            associatedPayout { id status }
          }
        }
      }
    }
    """

    static let payoutsQuery = """
    query XFinderShopifyPaymentsPayouts($first: Int!, $after: String) {
      shopifyPaymentsAccount {
        payouts(first: $first, after: $after, reverse: true) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            issuedAt
            status
            transactionType
            net { amount currencyCode }
          }
        }
      }
    }
    """
}

private struct ShopifyGraphQLError: Decodable {
    struct Extensions: Decodable { let code: String? }
    let message: String
    let extensions: Extensions?
}

private struct ShopifyPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct ShopifyMoneyV2: Decodable {
    let amount: String
    let currencyCode: String
}

private struct ShopifyMoneyBag: Decodable {
    let shopMoney: ShopifyMoneyV2
}

private struct ShopifyOrdersEnvelope: Decodable {
    struct DataContainer: Decodable {
        struct OrdersConnection: Decodable {
            let pageInfo: ShopifyPageInfo
            let nodes: [ShopifyOrderNode]
        }
        let orders: OrdersConnection
    }
    let data: DataContainer?
    let errors: [ShopifyGraphQLError]?
}

private struct ShopifyOrderNode: Decodable {
    let id: String
    let createdAt: String
    let totalPriceSet: ShopifyMoneyBag?
    let refunds: [ShopifyRefundNode]

    func toChargeEvent(accountId: String) -> RevenueLedgerEvent? {
        guard let money = totalPriceSet?.shopMoney,
              let date = try? Date(createdAt, strategy: .iso8601),
              let minor = ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits(
                money.amount,
                currency: money.currencyCode
              ),
              minor > 0 else {
            return nil
        }
        return RevenueLedgerEvent(
            id: id,
            source: .shopify,
            accountId: accountId,
            occurredAt: date,
            category: .charge,
            reportingCategory: "order",
            sourceReferenceId: id,
            grossMinor: minor,
            feeMinor: nil,
            netMinor: nil,
            currency: money.currencyCode.uppercased(),
            stream: .shopifyOrders
        )
    }
}

private struct ShopifyRefundNode: Decodable {
    let id: String
    let createdAt: String?
    let totalRefundedSet: ShopifyMoneyBag?

    func toRefundEvent(accountId: String, orderId: String) -> RevenueLedgerEvent? {
        guard let createdAt,
              let money = totalRefundedSet?.shopMoney,
              let date = try? Date(createdAt, strategy: .iso8601),
              let minor = ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits(
                money.amount,
                currency: money.currencyCode
              ),
              abs(minor) > 0 else {
            return nil
        }
        return RevenueLedgerEvent(
            id: id,
            source: .shopify,
            accountId: accountId,
            occurredAt: date,
            category: .refund,
            reportingCategory: "refund",
            sourceReferenceId: orderId,
            grossMinor: abs(minor),
            feeMinor: nil,
            netMinor: nil,
            currency: money.currencyCode.uppercased(),
            stream: .shopifyOrders
        )
    }
}

private struct ShopifyBalanceTransactionsEnvelope: Decodable {
    struct DataContainer: Decodable {
        struct PaymentsAccount: Decodable {
            struct BalanceTxConnection: Decodable {
                let pageInfo: ShopifyPageInfo
                let nodes: [ShopifyBalanceTxNode]
            }
            let balanceTransactions: BalanceTxConnection
        }
        let shopifyPaymentsAccount: PaymentsAccount?
    }
    let data: DataContainer?
    let errors: [ShopifyGraphQLError]?
}

private struct ShopifyPayoutsEnvelope: Decodable {
    struct DataContainer: Decodable {
        struct PaymentsAccount: Decodable {
            struct PayoutsConnection: Decodable {
                let pageInfo: ShopifyPageInfo
                let nodes: [ShopifyPayoutNode]
            }
            let payouts: PayoutsConnection
        }
        let shopifyPaymentsAccount: PaymentsAccount?
    }
    let data: DataContainer?
    let errors: [ShopifyGraphQLError]?
}

private struct ShopifyBalanceTxNode: Decodable {
    struct AssociatedPayout: Decodable { let id: String?; let status: String? }
    let id: String
    let type: String
    let transactionDate: String
    let amount: ShopifyMoneyV2?
    let fee: ShopifyMoneyV2?
    let net: ShopifyMoneyV2?
    let associatedPayout: AssociatedPayout?

    func toLedgerEvent(accountId: String) -> RevenueLedgerEvent? {
        let kind = type.uppercased()
        // Payout rows in `balanceTransactions` are intentionally skipped because `shopifyPaymentsAccount.payouts`
        // is paginated independently as the authoritative payout ledger, avoiding double-counting.
        if kind == "PAYOUT" { return nil }

        guard let amount,
              let date = try? Date(transactionDate, strategy: .iso8601),
              let grossMinor = ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits(amount.amount, currency: amount.currencyCode) else {
            return nil
        }
        let feeMinor = fee.flatMap {
            ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits($0.amount, currency: $0.currencyCode)
        }
        let netMinor = net.flatMap {
            ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits($0.amount, currency: $0.currencyCode)
        }

        let category: RevenueEventCategory
        switch kind {
        case "CHARGE": category = .charge
        case "REFUND": category = .refund
        case "ADJUSTMENT", "DISPUTE": category = .fee
        default: category = .unclassified
        }
        return RevenueLedgerEvent(
            id: id,
            source: .shopify,
            accountId: accountId,
            occurredAt: date,
            category: category,
            reportingCategory: kind.lowercased(),
            sourceReferenceId: associatedPayout?.id,
            grossMinor: category == .unclassified ? grossMinor : abs(grossMinor),
            feeMinor: category == .unclassified ? nil : feeMinor,
            netMinor: category == .unclassified ? nil : netMinor,
            currency: amount.currencyCode.uppercased(),
            stream: .shopifyPaymentsSettlement
        )
    }
}

private struct ShopifyPayoutNode: Decodable {
    let id: String
    let issuedAt: String
    let status: String?
    let transactionType: String?
    let net: ShopifyMoneyV2?

    func toPayoutEvent(accountId: String) -> RevenueLedgerEvent? {
        if let status = status?.uppercased(), status == "FAILED" || status == "CANCELED" {
            return nil
        }
        guard let net,
              let date = try? Date(issuedAt, strategy: .iso8601),
              let minor = ShopifyAdminGraphQLAdapter.parseDecimalAmountToMinorUnits(net.amount, currency: net.currencyCode) else {
            return nil
        }
        let isWithdrawal = transactionType?.uppercased() == "WITHDRAWAL"
        let signedPayout = isWithdrawal ? -abs(minor) : abs(minor)
        return RevenueLedgerEvent(
            id: id,
            source: .shopify,
            accountId: accountId,
            occurredAt: date,
            category: .payout,
            reportingCategory: (transactionType ?? "deposit").lowercased(),
            sourceReferenceId: id,
            grossMinor: signedPayout,
            feeMinor: nil,
            netMinor: nil,
            currency: net.currencyCode.uppercased(),
            stream: .shopifyPaymentsSettlement
        )
    }
}

/// Production composite `RevenueProvider` routing Stripe and Shopify to their read-only HTTPS adapters.
public final class LiveRevenueProvider: RevenueProvider, Sendable {
    public let id = "live-revenue-provider"
    private let stripeAdapter: StripeBalanceTransactionsAdapter
    private let shopifyAdapter: ShopifyAdminGraphQLAdapter

    public init(
        transport: RevenueHTTPTransport = URLSessionRevenueHTTPTransport(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared,
        shopifyAPIVersion: String = RevenueHostPolicy.defaultShopifyAPIVersion
    ) {
        self.stripeAdapter = StripeBalanceTransactionsAdapter(
            transport: transport,
            credentialStore: credentialStore
        )
        self.shopifyAdapter = ShopifyAdminGraphQLAdapter(
            transport: transport,
            credentialStore: credentialStore,
            apiVersion: shopifyAPIVersion
        )
    }

    public func fetchLedger(
        for config: SourceAccountConfig,
        period: RevenuePeriod,
        cursor: String?,
        now: Date
    ) async throws -> RevenueFetchPage {
        switch config.source {
        case .stripe:
            return try await stripeAdapter.fetchLedger(for: config, period: period, cursor: cursor, now: now)
        case .shopify:
            return try await shopifyAdapter.fetchLedger(for: config, period: period, cursor: cursor, now: now)
        }
    }
}
