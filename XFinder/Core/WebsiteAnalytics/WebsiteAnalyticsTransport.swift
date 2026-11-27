import Foundation

public enum WebsiteAnalyticsLimits {
    /// Maximum HTTP response payload size accepted per endpoint (2 MiB).
    public static let maxResponseBytes: Int = 2 * 1024 * 1024
    /// Maximum number of time-series points retained.
    public static let maxSeriesPoints: Int = 90
    /// Maximum number of breakdown rows decoded per endpoint.
    public static let maxBreakdownRows: Int = 25
    /// Maximum number of top pages / referrers displayed in the island card.
    public static let maxTopDisplayRows: Int = 5
}

public enum WebsiteAnalyticsHostPolicy {
    public static let dataFastHost = "datafa.st"
    public static let dataFastAPIPrefix = "/api/v1/"
    public static let ga4DataHost = "analyticsdata.googleapis.com"
    public static let googleOAuthAuthHost = "accounts.google.com"
    public static let googleOAuthTokenHost = "oauth2.googleapis.com"
    public static let ga4ReadOnlyScope = "https://www.googleapis.com/auth/analytics.readonly"

    /// Validates that a DataFast key is a read-only website API key (`df_...`) and explicitly
    /// rejects `dft_` account-management tokens.
    public static func validateDataFastAPIKey(_ raw: String) -> Result<String, WebsiteAnalyticsError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.unconfigured(.missingCredentials))
        }
        if trimmed.hasPrefix("dft_") {
            return .failure(.invalidConfiguration("datafast_account_token_rejected"))
        }
        guard trimmed.hasPrefix("df_"), trimmed.count > 3, !trimmed.contains(where: \.isWhitespace) else {
            return .failure(.invalidConfiguration("datafast_key_prefix_required"))
        }
        return .success(trimmed)
    }

    public static func validatedDataFastURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard path.hasPrefix(dataFastAPIPrefix), !path.contains("..") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = dataFastHost
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url, validateDataFastOutboundURL(url) else { return nil }
        return url
    }

    public static func validateDataFastOutboundURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              (components.port == nil || components.port == 443),
              components.host?.lowercased() == dataFastHost,
              components.path.hasPrefix(dataFastAPIPrefix),
              !components.path.contains("..") else {
            return false
        }
        return true
    }

    public static func validatedGA4EndpointURL(propertyId: String, method: String) -> URL? {
        let normalized = GA4PropertyConfig.normalizePropertyId(propertyId)
        guard !normalized.isEmpty, normalized.count <= 20, normalized.allSatisfy(\.isNumber) else {
            return nil
        }
        guard method == "runReport" || method == "runRealtimeReport" else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = ga4DataHost
        components.path = "/v1beta/properties/\(normalized):\(method)"
        guard let url = components.url, validateGA4OutboundURL(url) else { return nil }
        return url
    }

    public static func validateGA4OutboundURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              (components.port == nil || components.port == 443),
              components.host?.lowercased() == ga4DataHost,
              components.path.hasPrefix("/v1beta/properties/"),
              (components.path.hasSuffix(":runReport") || components.path.hasSuffix(":runRealtimeReport")),
              !components.path.contains("..") else {
            return false
        }
        return true
    }

    public static func validatedGoogleTokenURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = googleOAuthTokenHost
        components.path = "/token"
        return components.url
    }

    public static func validatedGoogleRevokeURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = googleOAuthTokenHost
        components.path = "/revoke"
        return components.url
    }

    /// Strips any known secret values from diagnostic or error strings so credentials can never leak.
    public static func sanitize(_ text: String, redacting secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        return result
    }

    public static func mapHTTPStatus(_ statusCode: Int, retryAfterHeader: String? = nil) -> WebsiteAnalyticsError? {
        switch statusCode {
        case 200..<300:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .revokedOrForbidden
        case 429:
            let retryAfter = retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 500..<600:
            return .serverUnavailable(statusCode: statusCode)
        default:
            return .malformedResponse("http_\(statusCode)")
        }
    }
}

/// Mockable HTTP transport abstraction for provider tests.
public protocol WebsiteAnalyticsHTTPTransport: Sendable {
    func send(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse)
}

public extension WebsiteAnalyticsHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request, maxBytes: WebsiteAnalyticsLimits.maxResponseBytes)
    }
}

/// Refuses HTTP redirects so `Authorization: Bearer ...` headers are never forwarded to unverified hosts.
private final class WebsiteAnalyticsNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
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

/// Ephemeral `URLSession` transport with no persistent disk cache, no cookies, redirects disabled,
/// and strict response byte bounds.
public final class URLSessionWebsiteAnalyticsTransport: WebsiteAnalyticsHTTPTransport, Sendable {
    private let session: URLSession
    private let delegate: WebsiteAnalyticsNoRedirectDelegate

    public init(timeoutInterval: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = max(timeoutInterval * 2, 30)
        let delegate = WebsiteAnalyticsNoRedirectDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func send(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WebsiteAnalyticsError.malformedResponse("non_http_response")
            }
            if http.expectedContentLength > 0, Int(http.expectedContentLength) > maxBytes {
                throw WebsiteAnalyticsError.oversizedPayload(byteCount: Int(http.expectedContentLength), limit: maxBytes)
            }
            if data.count > maxBytes {
                throw WebsiteAnalyticsError.oversizedPayload(byteCount: data.count, limit: maxBytes)
            }
            return (data, http)
        } catch let err as WebsiteAnalyticsError {
            throw err
        } catch is CancellationError {
            throw WebsiteAnalyticsError.cancelled
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                throw WebsiteAnalyticsError.cancelled
            case .timedOut:
                throw WebsiteAnalyticsError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .dataNotAllowed:
                throw WebsiteAnalyticsError.offline
            default:
                throw WebsiteAnalyticsError.offline
            }
        } catch {
            throw WebsiteAnalyticsError.offline
        }
    }
}
