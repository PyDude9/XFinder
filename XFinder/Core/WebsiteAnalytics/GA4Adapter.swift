import Foundation
import CryptoKit
import Security

// MARK: - GA4 OAuth 2.0 PKCE

public struct GA4PKCESession: Equatable, Sendable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let state: String

    public init(codeVerifier: String, codeChallenge: String, state: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.state = state
    }
}

public struct GA4OAuthTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresInSeconds: Int?
    public let scope: String?

    public init(accessToken: String, refreshToken: String?, expiresInSeconds: Int?, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresInSeconds = expiresInSeconds
        self.scope = scope
    }
}

public struct GA4OAuthAuthorizationResult: Equatable, Sendable {
    public let callbackURL: URL
    public let redirectURI: String

    public init(callbackURL: URL, redirectURI: String) {
        self.callbackURL = callbackURL
        self.redirectURI = redirectURI
    }
}

/// Interactive OAuth authorization driver abstraction.
/// Production builds use `GA4LoopbackOAuthDriver` (ephemeral IPv4 loopback `http://127.0.0.1:<port>`
/// + system browser); unit tests inject a deterministic mock driver.
public protocol GA4OAuthAuthorizationDriver: Sendable {
    func authorize(
        expectedState: String,
        buildAuthorizationURL: @Sendable (String) throws -> URL
    ) async throws -> GA4OAuthAuthorizationResult
}

/// Explicit unconfigured driver for callers that disable interactive OAuth.
/// Never fakes a connection or returns sample tokens.
public struct UnconfiguredGA4OAuthDriver: GA4OAuthAuthorizationDriver, Sendable {
    public init() {}

    public func authorize(
        expectedState: String,
        buildAuthorizationURL: @Sendable (String) throws -> URL
    ) async throws -> GA4OAuthAuthorizationResult {
        throw WebsiteAnalyticsError.unconfigured(.oauthNotConfigured)
    }
}

public enum GA4OAuthPKCE {
    public static func generateSession() throws -> GA4PKCESession {
        let verifier = try randomBase64URL(byteCount: 48)
        let state = try randomBase64URL(byteCount: 24)
        let challenge = s256Challenge(for: verifier)
        return GA4PKCESession(codeVerifier: verifier, codeChallenge: challenge, state: state)
    }

    public static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    public static func buildAuthorizationURL(
        clientId: String,
        redirectURI: String,
        session: GA4PKCESession
    ) -> Result<URL, WebsiteAnalyticsError> {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientId.isEmpty, !trimmedRedirect.isEmpty else {
            return .failure(.unconfigured(.oauthNotConfigured))
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = WebsiteAnalyticsHostPolicy.googleOAuthAuthHost
        components.path = "/o/oauth2/v2/auth"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientId),
            URLQueryItem(name: "redirect_uri", value: trimmedRedirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: WebsiteAnalyticsHostPolicy.ga4ReadOnlyScope),
            URLQueryItem(name: "code_challenge", value: session.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: session.state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components.url else {
            return .failure(.invalidConfiguration("invalid_oauth_auth_url"))
        }
        return .success(url)
    }

    public static func parseCallbackURL(
        _ callbackURL: URL,
        expectedState: String
    ) -> Result<String, WebsiteAnalyticsError> {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedResponse("invalid_oauth_callback_url"))
        }
        let items = components.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        if let err = query["error"]?.lowercased() {
            if let returnedState = query["state"], returnedState != expectedState {
                return .failure(.malformedResponse("oauth_state_mismatch"))
            }
            if err == "access_denied" || err == "cancelled" || err == "user_cancelled" {
                return .failure(.oauthCancelled)
            }
            return .failure(.revokedOrForbidden)
        }
        guard let state = query["state"], state == expectedState else {
            return .failure(.malformedResponse("oauth_state_mismatch"))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .failure(.malformedResponse("oauth_missing_code"))
        }
        return .success(code)
    }

    /// Exchanges an authorization code for access + refresh tokens using PKCE and the exact ephemeral
    /// loopback `redirectURI` (no client secret).
    public static func exchangeCodeForTokens(
        clientId: String,
        redirectURI: String,
        code: String,
        codeVerifier: String,
        transport: WebsiteAnalyticsHTTPTransport
    ) async throws -> GA4OAuthTokens {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientId.isEmpty, !trimmedRedirect.isEmpty else {
            throw WebsiteAnalyticsError.unconfigured(.oauthNotConfigured)
        }
        guard let url = WebsiteAnalyticsHostPolicy.validatedGoogleTokenURL() else {
            throw WebsiteAnalyticsError.invalidConfiguration("invalid_google_token_url")
        }
        let params: [(String, String)] = [
            ("client_id", trimmedClientId),
            ("code", code),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", trimmedRedirect),
        ]
        return try await sendTokenRequest(url: url, formParams: params, transport: transport)
    }

    /// Refreshes an expired GA4 access token using the stored refresh token (no client secret).
    public static func refreshAccessToken(
        config: GA4PropertyConfig,
        refreshToken: String,
        transport: WebsiteAnalyticsHTTPTransport
    ) async throws -> GA4OAuthTokens {
        guard !config.oauthClientId.isEmpty else {
            throw WebsiteAnalyticsError.unconfigured(.oauthNotConfigured)
        }
        guard let url = WebsiteAnalyticsHostPolicy.validatedGoogleTokenURL() else {
            throw WebsiteAnalyticsError.invalidConfiguration("invalid_google_token_url")
        }
        let params: [(String, String)] = [
            ("client_id", config.oauthClientId),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
        ]
        return try await sendTokenRequest(url: url, formParams: params, transport: transport)
    }

    /// Best-effort token revocation on explicit disconnect.
    public static func revokeToken(
        _ token: String,
        transport: WebsiteAnalyticsHTTPTransport
    ) async {
        guard !token.isEmpty, let url = WebsiteAnalyticsHostPolicy.validatedGoogleRevokeURL() else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([("token", token)])
        _ = try? await transport.send(request, maxBytes: 64 * 1024)
    }

    private static func sendTokenRequest(
        url: URL,
        formParams: [(String, String)],
        transport: WebsiteAnalyticsHTTPTransport
    ) async throws -> GA4OAuthTokens {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncodedBody(formParams)

        let (data, response) = try await transport.send(request, maxBytes: 256 * 1024)
        if response.statusCode == 400 || response.statusCode == 401 {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = (dict["error"] as? String)?.lowercased(),
               err == "invalid_grant" || err == "unauthorized_client" {
                throw WebsiteAnalyticsError.revokedOrForbidden
            }
            throw WebsiteAnalyticsError.unauthorized
        }
        if let httpError = WebsiteAnalyticsHostPolicy.mapHTTPStatus(
            response.statusCode,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw httpError
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = dict["access_token"] as? String,
              !accessToken.isEmpty else {
            throw WebsiteAnalyticsError.malformedResponse("oauth_missing_access_token")
        }
        let refreshToken = dict["refresh_token"] as? String
        let expiresIn = (dict["expires_in"] as? NSNumber)?.intValue
        let scope = dict["scope"] as? String
        return GA4OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresInSeconds: expiresIn,
            scope: scope
        )
    }

    private static func formEncodedBody(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw WebsiteAnalyticsError.invalidConfiguration("rng_failed")
        }
        return base64URLEncode(Data(bytes))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - GA4 Data API v1beta Adapter

/// Read-only Google Analytics 4 Data API v1beta adapter (`runReport` & `runRealtimeReport`).
/// Validates response `metricHeaders` and `dimensionHeaders` before decoding positional rows.
public final class GA4DataAPIAdapter: WebsiteAnalyticsSourceAdapter, Sendable {
    public let provider: WebsiteAnalyticsProviderKind = .googleAnalytics4

    private let transport: WebsiteAnalyticsHTTPTransport
    private let credentialStore: WebsiteAnalyticsCredentialStore
    private let configStore: WebsiteAnalyticsConfigStore
    private let oauthDriver: GA4OAuthAuthorizationDriver
    private let maxResponseBytes: Int

    public init(
        transport: WebsiteAnalyticsHTTPTransport = URLSessionWebsiteAnalyticsTransport(),
        credentialStore: WebsiteAnalyticsCredentialStore = WebsiteAnalyticsKeychainStore.shared,
        configStore: WebsiteAnalyticsConfigStore = UserDefaultsWebsiteAnalyticsConfigStore(),
        oauthDriver: GA4OAuthAuthorizationDriver = GA4LoopbackOAuthDriver(),
        maxResponseBytes: Int = WebsiteAnalyticsLimits.maxResponseBytes
    ) {
        self.transport = transport
        self.credentialStore = credentialStore
        self.configStore = configStore
        self.oauthDriver = oauthDriver
        self.maxResponseBytes = max(1024, maxResponseBytes)
    }

    /// Runs the installed-desktop PKCE OAuth flow using an ephemeral IPv4 loopback redirect URI
    /// and persists only the returned access/refresh tokens in Keychain (never codes or verifiers).
    public func authorizeWithPKCE() async throws -> GA4OAuthTokens {
        try Task.checkCancellation()
        guard let config = configStore.loadGA4Config(), config.isPropertyIdValid else {
            throw WebsiteAnalyticsError.unconfigured(.missingProperty)
        }
        guard config.hasOAuthClientConfig else {
            throw WebsiteAnalyticsError.unconfigured(.oauthNotConfigured)
        }

        let session = try GA4OAuthPKCE.generateSession()
        let clientId = config.oauthClientId
        let authResult = try await oauthDriver.authorize(expectedState: session.state) { redirectURI in
            switch GA4OAuthPKCE.buildAuthorizationURL(clientId: clientId, redirectURI: redirectURI, session: session) {
            case .success(let url): return url
            case .failure(let err): throw err
            }
        }
        try Task.checkCancellation()

        let code: String
        switch GA4OAuthPKCE.parseCallbackURL(authResult.callbackURL, expectedState: session.state) {
        case .success(let authCode): code = authCode
        case .failure(let err): throw err
        }

        let tokens = try await GA4OAuthPKCE.exchangeCodeForTokens(
            clientId: clientId,
            redirectURI: authResult.redirectURI,
            code: code,
            codeVerifier: session.codeVerifier,
            transport: transport
        )
        try Task.checkCancellation()

        credentialStore.setSecret(tokens.accessToken, for: .ga4AccessToken, accountKey: config.propertyId)
        if let refresh = tokens.refreshToken, !refresh.isEmpty {
            credentialStore.setSecret(refresh, for: .ga4RefreshToken, accountKey: config.propertyId)
        }
        return tokens
    }

    /// Best-effort revokes stored OAuth tokens before clearing Keychain.
    public func revokeStoredTokens(for propertyId: String) async {
        let normalized = GA4PropertyConfig.normalizePropertyId(propertyId)
        guard !normalized.isEmpty else { return }
        if let refresh = credentialStore.secret(for: .ga4RefreshToken, accountKey: normalized) {
            await GA4OAuthPKCE.revokeToken(refresh, transport: transport)
        } else if let access = credentialStore.secret(for: .ga4AccessToken, accountKey: normalized) {
            await GA4OAuthPKCE.revokeToken(access, transport: transport)
        }
    }

    public func fetchReport(range: WebsiteAnalyticsRange, now: Date) async throws -> WebsiteAnalyticsReport {
        try Task.checkCancellation()

        guard let config = configStore.loadGA4Config() else {
            throw WebsiteAnalyticsError.unconfigured(.missingProperty)
        }
        guard config.isPropertyIdValid else {
            throw WebsiteAnalyticsError.invalidConfiguration("ga4_invalid_property_id")
        }

        let initialToken = try await resolveAccessToken(for: config)
        do {
            return try await fetchAllReports(config: config, range: range, now: now, accessToken: initialToken)
        } catch WebsiteAnalyticsError.unauthorized {
            // Attempt one token refresh if a refresh token and OAuth client ID exist.
            guard let refreshToken = credentialStore.secret(for: .ga4RefreshToken, accountKey: config.propertyId),
                  !refreshToken.isEmpty,
                  !config.oauthClientId.isEmpty else {
                throw WebsiteAnalyticsError.unauthorized
            }
            let refreshed = try await GA4OAuthPKCE.refreshAccessToken(
                config: config,
                refreshToken: refreshToken,
                transport: transport
            )
            credentialStore.setSecret(refreshed.accessToken, for: .ga4AccessToken, accountKey: config.propertyId)
            if let nextRefresh = refreshed.refreshToken, !nextRefresh.isEmpty {
                credentialStore.setSecret(nextRefresh, for: .ga4RefreshToken, accountKey: config.propertyId)
            }
            return try await fetchAllReports(config: config, range: range, now: now, accessToken: refreshed.accessToken)
        }
    }

    private func resolveAccessToken(for config: GA4PropertyConfig) async throws -> String {
        if let token = credentialStore.secret(for: .ga4AccessToken, accountKey: config.propertyId), !token.isEmpty {
            return token
        }
        if let refreshToken = credentialStore.secret(for: .ga4RefreshToken, accountKey: config.propertyId),
           !refreshToken.isEmpty,
           !config.oauthClientId.isEmpty {
            let refreshed = try await GA4OAuthPKCE.refreshAccessToken(
                config: config,
                refreshToken: refreshToken,
                transport: transport
            )
            credentialStore.setSecret(refreshed.accessToken, for: .ga4AccessToken, accountKey: config.propertyId)
            return refreshed.accessToken
        }
        if !config.hasOAuthClientConfig {
            throw WebsiteAnalyticsError.unconfigured(.oauthNotConfigured)
        }
        throw WebsiteAnalyticsError.unconfigured(.missingCredentials)
    }

    private func fetchAllReports(
        config: GA4PropertyConfig,
        range: WebsiteAnalyticsRange,
        now: Date,
        accessToken: String
    ) async throws -> WebsiteAnalyticsReport {
        let window = WebsiteAnalyticsDateRules.dateWindow(for: range, now: now, timeZone: config.timeZone)
        let dateRanges: [[String: Any]] = [
            ["startDate": window.startDateKey, "endDate": window.endDateKey]
        ]

        // 1. Overview KPIs
        let overviewBody: [String: Any] = [
            "dateRanges": dateRanges,
            "metrics": [
                ["name": "activeUsers"],
                ["name": "screenPageViews"],
                ["name": "bounceRate"],
                ["name": "averageSessionDuration"],
            ],
        ]
        let overviewData = try await postReport(
            propertyId: config.propertyId,
            method: "runReport",
            body: overviewBody,
            accessToken: accessToken
        )
        let kpis = try Self.decodeOverviewResponse(overviewData)

        try Task.checkCancellation()

        // 2. Daily Timeseries
        let seriesBody: [String: Any] = [
            "dateRanges": dateRanges,
            "dimensions": [["name": "date"]],
            "metrics": [
                ["name": "activeUsers"],
                ["name": "screenPageViews"],
            ],
            "orderBys": [
                ["dimension": ["dimensionName": "date"], "desc": false]
            ],
            "limit": String(WebsiteAnalyticsLimits.maxSeriesPoints),
        ]
        let seriesData = try await postReport(
            propertyId: config.propertyId,
            method: "runReport",
            body: seriesBody,
            accessToken: accessToken
        )
        let timeseries = try Self.decodeTimeseriesResponse(seriesData)

        try Task.checkCancellation()

        // 3. Top Pages
        let pagesBody: [String: Any] = [
            "dateRanges": dateRanges,
            "dimensions": [["name": "pagePath"]],
            "metrics": [
                ["name": "activeUsers"],
                ["name": "screenPageViews"],
            ],
            "orderBys": [
                ["metric": ["metricName": "screenPageViews"], "desc": true]
            ],
            "limit": String(WebsiteAnalyticsLimits.maxBreakdownRows),
        ]
        let pagesData = try await postReport(
            propertyId: config.propertyId,
            method: "runReport",
            body: pagesBody,
            accessToken: accessToken
        )
        let topPages = try Self.decodeBreakdownResponse(pagesData, expectedDimension: "pagePath", kind: "pages")

        try Task.checkCancellation()

        // 4. Top Referrers
        let referrersBody: [String: Any] = [
            "dateRanges": dateRanges,
            "dimensions": [["name": "sessionSource"]],
            "metrics": [
                ["name": "activeUsers"],
                ["name": "screenPageViews"],
            ],
            "orderBys": [
                ["metric": ["metricName": "activeUsers"], "desc": true]
            ],
            "limit": String(WebsiteAnalyticsLimits.maxBreakdownRows),
        ]
        let referrersData = try await postReport(
            propertyId: config.propertyId,
            method: "runReport",
            body: referrersBody,
            accessToken: accessToken
        )
        let topReferrers = try Self.decodeBreakdownResponse(
            referrersData,
            expectedDimension: "sessionSource",
            kind: "referrers"
        )

        try Task.checkCancellation()

        // 5. Realtime activeUsers (past 30 minutes)
        let realtime = try await fetchRealtime(propertyId: config.propertyId, accessToken: accessToken)

        let label = config.propertyLabel.isEmpty ? "GA4 \(config.propertyId)" : config.propertyLabel
        return WebsiteAnalyticsReport(
            provider: .googleAnalytics4,
            siteLabel: label,
            range: range,
            windowStartDateKey: window.startDateKey,
            windowEndDateKey: window.endDateKey,
            timeZoneIdentifier: window.timeZoneIdentifier,
            kpis: kpis,
            realtime: realtime,
            timeseries: timeseries,
            topPages: topPages,
            topReferrers: topReferrers,
            fetchedAt: now
        )
    }

    private func fetchRealtime(propertyId: String, accessToken: String) async throws -> WebsiteAnalyticsRealtime {
        let body: [String: Any] = [
            "metrics": [["name": "activeUsers"]],
        ]
        guard let url = WebsiteAnalyticsHostPolicy.validatedGA4EndpointURL(
            propertyId: propertyId,
            method: "runRealtimeReport"
        ) else {
            throw WebsiteAnalyticsError.invalidConfiguration("ga4_invalid_property_id")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request, maxBytes: maxResponseBytes)
        if response.statusCode == 404 || response.statusCode == 501 {
            return .unsupported
        }
        if let httpError = WebsiteAnalyticsHostPolicy.mapHTTPStatus(
            response.statusCode,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw httpError
        }
        return try Self.decodeRealtimeResponse(data)
    }

    private func postReport(
        propertyId: String,
        method: String,
        body: [String: Any],
        accessToken: String
    ) async throws -> Data {
        try Task.checkCancellation()
        guard let url = WebsiteAnalyticsHostPolicy.validatedGA4EndpointURL(propertyId: propertyId, method: method),
              WebsiteAnalyticsHostPolicy.validateGA4OutboundURL(url) else {
            throw WebsiteAnalyticsError.invalidConfiguration("ga4_invalid_property_id")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request, maxBytes: maxResponseBytes)
        if data.count > maxResponseBytes {
            throw WebsiteAnalyticsError.oversizedPayload(byteCount: data.count, limit: maxResponseBytes)
        }
        if let httpError = WebsiteAnalyticsHostPolicy.mapHTTPStatus(
            response.statusCode,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw httpError
        }
        return data
    }

    // MARK: - Pure Header-Validated Decoders

    public static func decodeOverviewResponse(_ data: Data) throws -> WebsiteAnalyticsKPIs {
        let root = try parseJSONObject(data)
        let metricIndex = try parseMetricHeaders(root, required: ["activeUsers", "screenPageViews"])
        let rows = try parseRows(root)
        guard let firstRow = rows.first else {
            // Empty report: return all-nil KPIs so caller marks report as empty (never synthesize zeros).
            return WebsiteAnalyticsKPIs(
                visitors: nil,
                pageviews: nil,
                bounceRatePercent: nil,
                averageSessionDurationSeconds: nil
            )
        }

        let metricValues = try extractMetricValues(from: firstRow, expectedCount: metricIndex.count)
        let usersIdx = metricIndex["activeUsers"]!
        let viewsIdx = metricIndex["screenPageViews"]!

        let visitors = try parseNonNegativeIntString(metricValues[usersIdx], field: "activeUsers")
        let pageviews = try parseNonNegativeIntString(metricValues[viewsIdx], field: "screenPageViews")

        var bouncePercent: Double? = nil
        if let bounceIdx = metricIndex["bounceRate"] {
            let fraction = try parseFiniteDoubleString(metricValues[bounceIdx], field: "bounceRate", min: 0, max: 1.0)
            bouncePercent = fraction * 100.0
        }

        var avgDuration: Double? = nil
        if let durationIdx = metricIndex["averageSessionDuration"] {
            avgDuration = try parseFiniteDoubleString(
                metricValues[durationIdx],
                field: "averageSessionDuration",
                min: 0,
                max: 86_400 * 7
            )
        }

        return WebsiteAnalyticsKPIs(
            visitors: visitors,
            pageviews: pageviews,
            bounceRatePercent: bouncePercent,
            averageSessionDurationSeconds: avgDuration
        )
    }

    public static func decodeTimeseriesResponse(_ data: Data) throws -> [WebsiteAnalyticsSeriesPoint] {
        let root = try parseJSONObject(data)
        let dimIndex = try parseDimensionHeaders(root, required: ["date"])
        let metricIndex = try parseMetricHeaders(root, required: ["activeUsers", "screenPageViews"])
        let rows = try parseRows(root)
        if rows.count > WebsiteAnalyticsLimits.maxSeriesPoints {
            throw WebsiteAnalyticsError.oversizedPayload(byteCount: rows.count, limit: WebsiteAnalyticsLimits.maxSeriesPoints)
        }

        let dateIdx = dimIndex["date"]!
        let usersIdx = metricIndex["activeUsers"]!
        let viewsIdx = metricIndex["screenPageViews"]!

        var points: [WebsiteAnalyticsSeriesPoint] = []
        points.reserveCapacity(rows.count)
        for row in rows {
            let dims = try extractDimensionValues(from: row, expectedCount: dimIndex.count)
            let metrics = try extractMetricValues(from: row, expectedCount: metricIndex.count)
            guard let dateKey = WebsiteAnalyticsDateRules.normalizeDateKey(dims[dateIdx]) else {
                throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_date_\(dims[dateIdx])")
            }
            let visitors = try parseNonNegativeIntString(metrics[usersIdx], field: "activeUsers")
            let pageviews = try parseNonNegativeIntString(metrics[viewsIdx], field: "screenPageViews")
            points.append(
                WebsiteAnalyticsSeriesPoint(
                    dateKey: dateKey,
                    label: WebsiteAnalyticsDateRules.shortDayLabel(from: dateKey),
                    visitors: visitors,
                    pageviews: pageviews
                )
            )
        }
        return points.sorted { $0.dateKey < $1.dateKey }
    }

    public static func decodeBreakdownResponse(
        _ data: Data,
        expectedDimension: String,
        kind: String
    ) throws -> [WebsiteAnalyticsBreakdownItem] {
        let root = try parseJSONObject(data)
        let dimIndex = try parseDimensionHeaders(root, required: [expectedDimension])
        let metricIndex = try parseMetricHeaders(root, required: ["activeUsers", "screenPageViews"])
        let rows = try parseRows(root)

        let dimIdx = dimIndex[expectedDimension]!
        let usersIdx = metricIndex["activeUsers"]!
        let viewsIdx = metricIndex["screenPageViews"]!

        let capped = rows.prefix(WebsiteAnalyticsLimits.maxBreakdownRows)
        var items: [WebsiteAnalyticsBreakdownItem] = []
        items.reserveCapacity(capped.count)
        for (index, row) in capped.enumerated() {
            let dims = try extractDimensionValues(from: row, expectedCount: dimIndex.count)
            let metrics = try extractMetricValues(from: row, expectedCount: metricIndex.count)
            let name = dims[dimIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let visitors = try parseNonNegativeIntString(metrics[usersIdx], field: "activeUsers")
            let pageviews = try parseNonNegativeIntString(metrics[viewsIdx], field: "screenPageViews")
            items.append(
                WebsiteAnalyticsBreakdownItem(
                    id: "ga4:\(kind):\(index):\(name)",
                    name: name,
                    visitors: visitors,
                    pageviews: pageviews
                )
            )
        }
        return items
    }

    public static func decodeRealtimeResponse(_ data: Data) throws -> WebsiteAnalyticsRealtime {
        let root = try parseJSONObject(data)
        let metricIndex = try parseMetricHeaders(root, required: ["activeUsers"])
        let rows = try parseRows(root)
        guard let firstRow = rows.first else {
            return WebsiteAnalyticsRealtime(activeVisitors: 0, isSupported: true, windowMinutes: 30)
        }
        let metrics = try extractMetricValues(from: firstRow, expectedCount: metricIndex.count)
        let usersIdx = metricIndex["activeUsers"]!
        let active = try parseNonNegativeIntString(metrics[usersIdx], field: "activeUsers")
        return WebsiteAnalyticsRealtime(activeVisitors: active, isSupported: true, windowMinutes: 30)
    }

    // MARK: - Header & Row Validation Helpers

    private static func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_empty_body")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_json")
        }
        guard let dict = obj as? [String: Any] else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_expected_object")
        }
        return dict
    }

    private static func parseMetricHeaders(_ root: [String: Any], required: [String]) throws -> [String: Int] {
        guard let headers = root["metricHeaders"] as? [[String: Any]], !headers.isEmpty else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_missing_metric_headers")
        }
        var map: [String: Int] = [:]
        for (idx, header) in headers.enumerated() {
            guard let name = header["name"] as? String, !name.isEmpty else {
                throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_metric_header")
            }
            map[name] = idx
        }
        for req in required where map[req] == nil {
            throw WebsiteAnalyticsError.malformedResponse("ga4_missing_metric_\(req)")
        }
        return map
    }

    private static func parseDimensionHeaders(_ root: [String: Any], required: [String]) throws -> [String: Int] {
        guard let headers = root["dimensionHeaders"] as? [[String: Any]], !headers.isEmpty else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_missing_dimension_headers")
        }
        var map: [String: Int] = [:]
        for (idx, header) in headers.enumerated() {
            guard let name = header["name"] as? String, !name.isEmpty else {
                throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_dimension_header")
            }
            map[name] = idx
        }
        for req in required where map[req] == nil {
            throw WebsiteAnalyticsError.malformedResponse("ga4_missing_dimension_\(req)")
        }
        return map
    }

    private static func parseRows(_ root: [String: Any]) throws -> [[String: Any]] {
        guard let rawRows = root["rows"] else {
            return []
        }
        guard let rows = rawRows as? [[String: Any]] else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_rows")
        }
        return rows
    }

    private static func extractDimensionValues(from row: [String: Any], expectedCount: Int) throws -> [String] {
        guard let raw = row["dimensionValues"] as? [[String: Any]], raw.count == expectedCount else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_dimension_values_count_mismatch")
        }
        return try raw.map { entry in
            guard let value = entry["value"] as? String else {
                throw WebsiteAnalyticsError.malformedResponse("ga4_missing_dimension_value")
            }
            return value
        }
    }

    private static func extractMetricValues(from row: [String: Any], expectedCount: Int) throws -> [String] {
        guard let raw = row["metricValues"] as? [[String: Any]], raw.count == expectedCount else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_metric_values_count_mismatch")
        }
        return try raw.map { entry in
            guard let value = entry["value"] as? String else {
                throw WebsiteAnalyticsError.malformedResponse("ga4_missing_metric_value")
            }
            return value
        }
    }

    private static func parseNonNegativeIntString(_ raw: String, field: String) throws -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dbl = Double(trimmed), dbl.isFinite, dbl >= 0, dbl <= Double(Int.max), floor(dbl) == dbl else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_int_\(field)")
        }
        return Int(dbl)
    }

    private static func parseFiniteDoubleString(
        _ raw: String,
        field: String,
        min: Double,
        max: Double
    ) throws -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dbl = Double(trimmed), dbl.isFinite, dbl >= min, dbl <= max else {
            throw WebsiteAnalyticsError.malformedResponse("ga4_invalid_double_\(field)")
        }
        return dbl
    }
}
