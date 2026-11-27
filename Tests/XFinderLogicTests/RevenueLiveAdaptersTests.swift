import XCTest
import Foundation

private actor MockRevenueHTTPTransport: RevenueHTTPTransport {
    struct RecordedRequest: Sendable {
        let url: URL
        let method: String
        let authorization: String?
        let shopifyToken: String?
        let body: Data?
    }

    typealias Handler = @Sendable (URLRequest, Int) async throws -> (Data, Int)

    private var handler: Handler
    private(set) var requests: [RecordedRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func setHandler(_ newHandler: @escaping Handler) {
        self.handler = newHandler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let idx = requests.count
        let url = request.url!
        requests.append(
            RecordedRequest(
                url: url,
                method: request.httpMethod ?? "GET",
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                shopifyToken: request.value(forHTTPHeaderField: "X-Shopify-Access-Token"),
                body: request.httpBody
            )
        )
        let (data, status) = try await handler(request, idx)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

final class RevenueLiveAdaptersTests: XCTestCase {

    // MARK: - Verified Provider Host & Outbound Credential Security

    func testHostPolicyRestrictsOutboundCredentialsToVerifiedStripeAndShopifyHosts() {
        XCTAssertNotNil(RevenueHostPolicy.validatedStripeURL(path: "/v1/balance_transactions"))
        XCTAssertNil(RevenueHostPolicy.validatedStripeURL(path: "/v1/../admin"))
        XCTAssertFalse(RevenueHostPolicy.validateOutboundURL(URL(string: "http://api.stripe.com/v1/balance_transactions")!, for: .stripe))
        XCTAssertFalse(RevenueHostPolicy.validateOutboundURL(URL(string: "https://api.stripe.com.evil.com/v1/balance_transactions")!, for: .stripe))
        XCTAssertFalse(RevenueHostPolicy.validateOutboundURL(URL(string: "https://user:pass@api.stripe.com/v1/balance_transactions")!, for: .stripe))

        XCTAssertEqual(RevenueHostPolicy.normalizedShopifyHost(from: "https://Acme-Store.myshopify.com/"), "acme-store.myshopify.com")
        XCTAssertNotNil(RevenueHostPolicy.validatedShopifyGraphQLURL(shopDomain: "acme-store.myshopify.com"))
        for badHost in [
            "evil.com",
            "acme.myshopify.com.evil.com",
            "https://evil@acme.myshopify.com",
            "acme.myshopify.com:8443",
            "sub.acme.myshopify.com",
            "-bad.myshopify.com",
            "127.0.0.1",
            "",
        ] {
            XCTAssertNil(RevenueHostPolicy.normalizedShopifyHost(from: badHost), "Must reject \(badHost)")
            XCTAssertNil(RevenueHostPolicy.validatedShopifyGraphQLURL(shopDomain: badHost), "Must reject \(badHost)")
        }
        XCTAssertFalse(RevenueHostPolicy.validateOutboundURL(URL(string: "http://acme.myshopify.com/admin/api/2026-01/graphql.json")!, for: .shopify))
    }

    // MARK: - Stripe Mocked Pagination, Partial Refund, Fee, Payout & Interrupted Page

    func testStripePaginationPartialRefundFeePayoutAndInterruptedSecondPage() async throws {
        let t0 = try Date("2026-11-01T18:00:00Z", strategy: .iso8601)
        let creds = InMemoryRevenueCredentialStore()
        creds.setToken("rk_mock_readonly_1234", for: .stripe, accountId: "acct_us_1")

        let page1JSON = """
        {
          "has_more": true,
          "data": [
            {
              "id": "txn_1",
              "amount": 10000,
              "fee": 320,
              "net": 9680,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 3600),
              "type": "charge",
              "reporting_category": "charge",
              "source": "ch_1"
            }
          ]
        }
        """
        let page2JSON = """
        {
          "has_more": false,
          "data": [
            {
              "id": "txn_2",
              "amount": -3500,
              "fee": 0,
              "net": -3500,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 1800),
              "type": "refund",
              "reporting_category": "refund",
              "source": "re_1"
            },
            {
              "id": "txn_3",
              "amount": -500,
              "fee": 500,
              "net": -500,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 900),
              "type": "stripe_fee",
              "reporting_category": "fee",
              "source": null
            },
            {
              "id": "txn_4",
              "amount": -5000,
              "fee": 0,
              "net": -5000,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 600),
              "type": "payout",
              "reporting_category": "payout",
              "source": "po_1"
            }
          ]
        }
        """

        let transport = MockRevenueHTTPTransport { req, idx in
            XCTAssertEqual(req.url?.host, "api.stripe.com")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer rk_mock_readonly_1234")
            if idx == 0 {
                return (Data(page1JSON.utf8), 200)
            } else {
                XCTAssertTrue(req.url?.query?.contains("starting_after=txn_1") ?? false)
                return (Data(page2JSON.utf8), 200)
            }
        }

        let provider = LiveRevenueProvider(transport: transport, credentialStore: creds)
        let cfg = SourceAccountConfig(source: .stripe, accountId: "acct_us_1", accountLabel: "Stripe US")
        let coord = RevenueCoordinator(
            provider: provider,
            accountStore: InMemoryRevenueAccountStore(initial: [.stripe: cfg]),
            credentialStore: creds,
            clock: { t0 }
        )

        await coord.openPage()
        let snap = await coord.snapshot
        let usd = try XCTUnwrap(snap.stripeState.report?.currencyTotals.first { $0.currency == "USD" })
        XCTAssertEqual(usd.grossMinor, 10_000)
        XCTAssertEqual(usd.refundMinor, 3_500)
        XCTAssertEqual(usd.feeMinor, 820)
        XCTAssertEqual(usd.netMinor, 5_680)
        XCTAssertEqual(usd.payoutMinor, 5_000)

        // Second sync interrupts on page 2 (HTTP 502): coordinator must preserve prior complete cache.
        await transport.setHandler { _, idx in
            if idx == 2 { return (Data(page1JSON.utf8), 200) }
            return (Data("{}".utf8), 502)
        }
        await coord.refresh(force: true)
        let afterInterrupt = await coord.snapshot
        XCTAssertEqual(afterInterrupt.stripeState.error, .paginationInterrupted)
        XCTAssertEqual(afterInterrupt.stripeState.report?.currencyTotals.first?.grossMinor, 10_000)
    }

    // MARK: - Shopify Mocked GraphQL Pagination, Partial Refunds & Optional Payout Scope

    func testShopifyGraphQLPaginationPartialRefundsAndOptionalPayoutScope() async throws {
        let t0 = try Date("2026-11-01T18:00:00Z", strategy: .iso8601)
        let creds = InMemoryRevenueCredentialStore()
        creds.setToken("shpat_mock_readonly_9999", for: .shopify, accountId: "acme-app.myshopify.com")

        let ordersPage1 = """
        {
          "data": {
            "orders": {
              "pageInfo": { "hasNextPage": true, "endCursor": "cur_ord_1" },
              "nodes": [
                {
                  "id": "gid://shopify/Order/101",
                  "createdAt": "2026-11-01T14:00:00Z",
                  "totalPriceSet": { "shopMoney": { "amount": "120.00", "currencyCode": "USD" } },
                  "refunds": [
                    {
                      "id": "gid://shopify/Refund/201",
                      "createdAt": "2026-11-01T15:30:00Z",
                      "totalRefundedSet": { "shopMoney": { "amount": "35.50", "currencyCode": "USD" } }
                    }
                  ]
                }
              ]
            }
          }
        }
        """
        let ordersPage2 = """
        {
          "data": {
            "orders": {
              "pageInfo": { "hasNextPage": false, "endCursor": null },
              "nodes": [
                {
                  "id": "gid://shopify/Order/102",
                  "createdAt": "2026-11-01T16:15:00Z",
                  "totalPriceSet": { "shopMoney": { "amount": "80.00", "currencyCode": "USD" } },
                  "refunds": []
                }
              ]
            }
          }
        }
        """

        let transport = MockRevenueHTTPTransport { req, idx in
            XCTAssertEqual(req.url?.host, "acme-app.myshopify.com")
            XCTAssertEqual(req.url?.path, "/admin/api/2026-01/graphql.json")
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Shopify-Access-Token"), "shpat_mock_readonly_9999")
            return (Data((idx == 0 ? ordersPage1 : ordersPage2).utf8), 200)
        }

        let provider = LiveRevenueProvider(transport: transport, credentialStore: creds)
        let cfg = SourceAccountConfig(
            source: .shopify,
            accountId: "acme-app.myshopify.com",
            accountLabel: "Acme Store",
            hasPayoutScope: false,
            historyLimitedDays: 60
        )
        let coord = RevenueCoordinator(
            provider: provider,
            accountStore: InMemoryRevenueAccountStore(initial: [.shopify: cfg]),
            credentialStore: creds,
            clock: { t0 }
        )

        await coord.openPage()
        let snapshot = await coord.snapshot
        let usd = try XCTUnwrap(snapshot.shopifyState.report?.currencyTotals.first { $0.currency == "USD" })
        XCTAssertEqual(usd.grossMinor, 20_000)
        XCTAssertEqual(usd.refundMinor, 3_550)
        XCTAssertNil(usd.feeMinor, "read_orders only must keep feeMinor nil")
        XCTAssertNil(usd.netMinor, "read_orders only must keep netMinor nil")
        let reqCount = await transport.requests.count
        XCTAssertEqual(reqCount, 2, "Must not query shopifyPaymentsAccount when hasPayoutScope == false")
    }

    // MARK: - Auth Failure, Scope Restriction, Account Change & Disconnect Lifecycle

    func testAuthFailureMissingTokenAndDisconnectWipeLifecycle() async throws {
        let t0 = try Date("2026-11-01T18:00:00Z", strategy: .iso8601)
        let creds = InMemoryRevenueCredentialStore()

        // 1. Missing token throws .unauthorized without issuing any HTTP call.
        let transport = MockRevenueHTTPTransport { _, _ in (Data("{}".utf8), 401) }
        let provider = LiveRevenueProvider(transport: transport, credentialStore: creds)
        let stripeCfg = SourceAccountConfig(source: .stripe, accountId: "acct_1", accountLabel: "Stripe 1")
        let coord = RevenueCoordinator(
            provider: provider,
            accountStore: InMemoryRevenueAccountStore(initial: [.stripe: stripeCfg]),
            credentialStore: creds,
            clock: { t0 }
        )
        await coord.openPage()
        let missingToken = await coord.snapshot
        XCTAssertEqual(missingToken.stripeState.error, .unauthorized)
        let sentWhenMissingToken = await transport.requests.count
        XCTAssertEqual(sentWhenMissingToken, 0, "No outbound HTTP request when Keychain token is absent")

        // 2. HTTP 401 from Stripe maps to .unauthorized; GraphQL ACCESS_DENIED from Shopify maps to .scopeRestricted.
        creds.setToken("rk_expired", for: .stripe, accountId: "acct_1")
        await coord.refresh(force: true)
        let rejectedToken = await coord.snapshot
        XCTAssertEqual(rejectedToken.stripeState.error, .unauthorized)

        let deniedJSON = """
        { "errors": [{ "message": "Access denied for orders field", "extensions": { "code": "ACCESS_DENIED" } }] }
        """
        await transport.setHandler { _, _ in (Data(deniedJSON.utf8), 200) }
        creds.setToken("shpat_limited", for: .shopify, accountId: "limited.myshopify.com")
        let shopCfg = SourceAccountConfig(source: .shopify, accountId: "limited.myshopify.com", accountLabel: "Limited", hasPayoutScope: false)
        await coord.configureSource(shopCfg)
        let restrictedScope = await coord.snapshot
        XCTAssertEqual(restrictedScope.shopifyState.error, .scopeRestricted)

        // 3. Switching Stripe accountId deletes old account's Keychain token and clears old cache.
        let okJSON = """
        { "has_more": false, "data": [{ "id": "txn_b", "amount": 4200, "fee": 150, "net": 4050, "currency": "usd", "created": \(Int(t0.timeIntervalSince1970) - 300), "type": "charge", "reporting_category": "charge" }] }
        """
        await transport.setHandler { _, _ in (Data(okJSON.utf8), 200) }
        creds.setToken("rk_account_2", for: .stripe, accountId: "acct_2")
        let stripeCfg2 = SourceAccountConfig(source: .stripe, accountId: "acct_2", accountLabel: "Stripe 2")
        await coord.configureSource(stripeCfg2)
        XCTAssertNil(creds.token(for: .stripe, accountId: "acct_1"), "Old account Keychain token must be deleted on account change")
        let switchedAccount = await coord.snapshot
        XCTAssertEqual(switchedAccount.stripeState.report?.currencyTotals.first?.grossMinor, 4_200)

        // 4. Disconnecting Stripe deletes acct_2 Keychain token + cache while leaving Shopify config/token intact.
        await coord.disconnectSource(.stripe)
        XCTAssertNil(creds.token(for: .stripe, accountId: "acct_2"))
        let disconnected = await coord.snapshot
        XCTAssertEqual(disconnected.stripeState, .unconfigured)
        XCTAssertEqual(creds.token(for: .shopify, accountId: "limited.myshopify.com"), "shpat_limited")
    }

    // MARK: - Shopify 2026-01 Schema, Independent Payouts Pagination, Late Refunds & Missing/Duplicate Amounts

    func testShopify202601SchemaIndependentPayoutsPaginationLateRefundsAndMissingAmounts() async throws {
        let t0 = try Date("2026-11-01T18:00:00Z", strategy: .iso8601)
        let creds = InMemoryRevenueCredentialStore()
        // Case-insensitive domain canonicalization in Keychain store.
        creds.setToken("shpat_schema_2026_01", for: .shopify, accountId: "Acme-App.myshopify.com")
        XCTAssertEqual(creds.token(for: .shopify, accountId: "acme-app.myshopify.com"), "shpat_schema_2026_01")

        // Orders page 1: includes a 5-day-old order updated today with a late partial refund, a restock-only $0 refund,
        // and a refund with null totalRefundedSet/createdAt, plus a same-day order duplicated across page 1 & 2.
        let ordersPage1 = """
        {
          "data": {
            "orders": {
              "pageInfo": { "hasNextPage": true, "endCursor": "ord_cur_1" },
              "nodes": [
                {
                  "id": "gid://shopify/Order/old_90",
                  "createdAt": "2026-10-27T12:00:00Z",
                  "totalPriceSet": { "shopMoney": { "amount": "90.00", "currencyCode": "USD" } },
                  "refunds": [
                    {
                      "id": "gid://shopify/Refund/late_90_1",
                      "createdAt": "2026-11-01T15:30:00Z",
                      "totalRefundedSet": { "shopMoney": { "amount": "25.00", "currencyCode": "USD" } }
                    },
                    {
                      "id": "gid://shopify/Refund/restock_zero",
                      "createdAt": "2026-11-01T15:35:00Z",
                      "totalRefundedSet": { "shopMoney": { "amount": "0.00", "currencyCode": "USD" } }
                    },
                    {
                      "id": "gid://shopify/Refund/missing_amount",
                      "createdAt": null,
                      "totalRefundedSet": null
                    }
                  ]
                },
                {
                  "id": "gid://shopify/Order/today_101",
                  "createdAt": "2026-11-01T14:00:00Z",
                  "totalPriceSet": { "shopMoney": { "amount": "100.00", "currencyCode": "USD" } },
                  "refunds": []
                }
              ]
            }
          }
        }
        """
        let ordersPage2 = """
        {
          "data": {
            "orders": {
              "pageInfo": { "hasNextPage": false, "endCursor": null },
              "nodes": [
                {
                  "id": "gid://shopify/Order/today_101",
                  "createdAt": "2026-11-01T14:00:00Z",
                  "totalPriceSet": { "shopMoney": { "amount": "100.00", "currencyCode": "USD" } },
                  "refunds": []
                }
              ]
            }
          }
        }
        """

        // ShopifyPaymentsBalanceTransaction uses official `amount` field (NOT `gross`), plus a `PAYOUT` row
        // that must be skipped so payouts are not double-counted against `shopifyPaymentsAccount.payouts`.
        let balanceTxPage1 = """
        {
          "data": {
            "shopifyPaymentsAccount": {
              "balanceTransactions": {
                "pageInfo": { "hasNextPage": false, "endCursor": null },
                "nodes": [
                  {
                    "id": "gid://shopify/ShopifyPaymentsBalanceTransaction/bt_1",
                    "type": "CHARGE",
                    "transactionDate": "2026-11-01T14:01:00Z",
                    "amount": { "amount": "100.00", "currencyCode": "USD" },
                    "fee": { "amount": "3.20", "currencyCode": "USD" },
                    "net": { "amount": "96.80", "currencyCode": "USD" },
                    "associatedPayout": { "id": "gid://shopify/ShopifyPaymentsPayout/po_1", "status": "PAID" }
                  },
                  {
                    "id": "gid://shopify/ShopifyPaymentsBalanceTransaction/bt_refund_1",
                    "type": "REFUND",
                    "transactionDate": "2026-11-01T15:31:00Z",
                    "amount": { "amount": "-25.00", "currencyCode": "USD" },
                    "fee": { "amount": "0.00", "currencyCode": "USD" },
                    "net": { "amount": "-25.00", "currencyCode": "USD" },
                    "associatedPayout": { "id": "gid://shopify/ShopifyPaymentsPayout/po_1", "status": "PAID" }
                  },
                  {
                    "id": "gid://shopify/ShopifyPaymentsBalanceTransaction/bt_payout_dup",
                    "type": "PAYOUT",
                    "transactionDate": "2026-11-01T16:00:00Z",
                    "amount": { "amount": "-71.80", "currencyCode": "USD" },
                    "fee": { "amount": "0.00", "currencyCode": "USD" },
                    "net": { "amount": "-71.80", "currencyCode": "USD" },
                    "associatedPayout": { "id": "gid://shopify/ShopifyPaymentsPayout/po_1", "status": "PAID" }
                  }
                ]
              }
            }
          }
        }
        """

        // Independent 2-page payouts pagination: page 1 has PAID $50.00, page 2 has PAID $21.80 + FAILED $999.00 (ignored).
        let payoutsPage1 = """
        {
          "data": {
            "shopifyPaymentsAccount": {
              "payouts": {
                "pageInfo": { "hasNextPage": true, "endCursor": "po_cur_1" },
                "nodes": [
                  {
                    "id": "gid://shopify/ShopifyPaymentsPayout/po_1",
                    "issuedAt": "2026-11-01T16:00:00Z",
                    "status": "PAID",
                    "transactionType": "DEPOSIT",
                    "net": { "amount": "50.00", "currencyCode": "USD" }
                  }
                ]
              }
            }
          }
        }
        """
        let payoutsPage2 = """
        {
          "data": {
            "shopifyPaymentsAccount": {
              "payouts": {
                "pageInfo": { "hasNextPage": false, "endCursor": null },
                "nodes": [
                  {
                    "id": "gid://shopify/ShopifyPaymentsPayout/po_2",
                    "issuedAt": "2026-11-01T16:30:00Z",
                    "status": "PAID",
                    "transactionType": "DEPOSIT",
                    "net": { "amount": "21.80", "currencyCode": "USD" }
                  },
                  {
                    "id": "gid://shopify/ShopifyPaymentsPayout/po_failed",
                    "issuedAt": "2026-11-01T16:45:00Z",
                    "status": "FAILED",
                    "transactionType": "DEPOSIT",
                    "net": { "amount": "999.00", "currencyCode": "USD" }
                  }
                ]
              }
            }
          }
        }
        """

        let transport = MockRevenueHTTPTransport { req, idx in
            let bodyText = req.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            switch idx {
            case 0:
                XCTAssertTrue(bodyText.contains("updated_at:>="), "Orders query must use updated_at to capture late refunds")
                return (Data(ordersPage1.utf8), 200)
            case 1:
                XCTAssertTrue(bodyText.contains("ord_cur_1"))
                return (Data(ordersPage2.utf8), 200)
            case 2:
                XCTAssertTrue(bodyText.contains("amount { amount currencyCode }"), "2026-01 schema uses `amount`, not `gross`")
                XCTAssertFalse(bodyText.contains("gross {"))
                return (Data(balanceTxPage1.utf8), 200)
            case 3:
                return (Data(payoutsPage1.utf8), 200)
            default:
                XCTAssertTrue(bodyText.contains("po_cur_1"), "Payouts must paginate independently with its own cursor")
                return (Data(payoutsPage2.utf8), 200)
            }
        }

        let provider = LiveRevenueProvider(transport: transport, credentialStore: creds)
        let cfg = SourceAccountConfig(
            source: .shopify,
            accountId: "acme-app.myshopify.com",
            accountLabel: "Acme",
            hasPayoutScope: true,
            historyLimitedDays: 60
        )
        let coord = RevenueCoordinator(
            provider: provider,
            accountStore: InMemoryRevenueAccountStore(initial: [.shopify: cfg]),
            credentialStore: creds,
            clock: { t0 }
        )

        await coord.openPage()
        let finalSnapshot = await coord.snapshot
        let usd = try XCTUnwrap(finalSnapshot.shopifyState.report?.currencyTotals.first { $0.currency == "USD" })
        XCTAssertEqual(usd.grossMinor, 10_000, "Duplicate order deduplicated; 5-day-old order excluded from today")
        XCTAssertEqual(usd.refundMinor, 2_500, "Late partial refund captured; $0 restock and null refunds ignored")
        XCTAssertEqual(usd.feeMinor, 320)
        XCTAssertEqual(usd.netMinor, 7_180)
        XCTAssertEqual(usd.payoutMinor, 7_180, "Paginated payouts summed ($50 + $21.80) without duplicating PAYOUT balance tx or FAILED payout")

        // Interrupted payouts page 2 preserves prior complete cache.
        await transport.setHandler { _, idx in
            let step = idx - 5
            switch step {
            case 0: return (Data(ordersPage2.utf8), 200)
            case 1: return (Data(balanceTxPage1.utf8), 200)
            case 2: return (Data(payoutsPage1.utf8), 200)
            default: return (Data("{}".utf8), 503)
            }
        }
        await coord.refresh(force: true)
        let interruptedSnap = await coord.snapshot
        XCTAssertEqual(interruptedSnap.shopifyState.error, .paginationInterrupted)
        XCTAssertEqual(interruptedSnap.shopifyState.report?.currencyTotals.first?.payoutMinor, 7_180)

        // CancellationError mid-pagination must NOT mark .paginationInterrupted and must preserve cache.
        await transport.setHandler { _, idx in
            let step = idx - 9
            if step == 0 { return (Data(ordersPage1.utf8), 200) }
            throw CancellationError()
        }
        await coord.refresh(force: true)
        let afterCancel = await coord.snapshot
        XCTAssertEqual(afterCancel.shopifyState.report?.currencyTotals.first?.grossMinor, 10_000)
    }

    func testStripeCursorTracksFirstSeenIdAndPayoutReversalRemainsUnclassified() async throws {
        let t0 = try Date("2026-11-01T18:00:00Z", strategy: .iso8601)
        let creds = InMemoryRevenueCredentialStore()
        creds.setToken("rk_stripe_map_test", for: .stripe, accountId: "acct_map")

        let page1 = """
        {
          "has_more": true,
          "data": [
            {
              "id": "txn_newest_1",
              "amount": 5000,
              "fee": 175,
              "net": 4825,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 600),
              "type": "charge",
              "reporting_category": "charge"
            }
          ]
        }
        """
        let page2 = """
        {
          "has_more": false,
          "data": [
            {
              "id": "txn_older_rev",
              "amount": 5000,
              "fee": 0,
              "net": 5000,
              "currency": "usd",
              "created": \(Int(t0.timeIntervalSince1970) - 1200),
              "type": "payout_failure",
              "reporting_category": "payout_reversal"
            }
          ]
        }
        """

        let transport = MockRevenueHTTPTransport { _, idx in
            (Data((idx == 0 ? page1 : page2).utf8), 200)
        }
        let adapter = StripeBalanceTransactionsAdapter(transport: transport, credentialStore: creds)
        let cfg = SourceAccountConfig(source: .stripe, accountId: "acct_map", accountLabel: "Stripe Map")
        let fetched = try await adapter.fetchLedger(for: cfg, period: .today, cursor: nil, now: t0)
        XCTAssertFalse(fetched.wasPaginationInterrupted)
        XCTAssertEqual(fetched.cursor, "txn_newest_1", "Cursor must preserve newest page-1 ID, not older page-2 ID")
        XCTAssertEqual(fetched.events.count, 2)
        XCTAssertEqual(fetched.events[1].category, .unclassified, "payout_reversal must stay unclassified rather than inflating payoutMinor")
    }
}
