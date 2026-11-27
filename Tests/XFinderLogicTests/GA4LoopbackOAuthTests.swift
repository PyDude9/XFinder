import XCTest
import Foundation
import Darwin
import os

// MARK: - Injected Seams for Loopback OAuth Tests (Never Opens Browser)

private final class StubBrowserOpener: GA4SystemBrowserOpener, Sendable {
    private struct State: Sendable {
        var openedURLs: [URL] = []
    }

    private let shouldSucceed: Bool
    private let onOpen: (@Sendable (URL) -> Void)?
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(shouldSucceed: Bool = true, onOpen: (@Sendable (URL) -> Void)? = nil) {
        self.shouldSucceed = shouldSucceed
        self.onOpen = onOpen
    }

    func open(_ url: URL) async -> Bool {
        state.withLock { $0.openedURLs.append(url) }
        onOpen?(url)
        return shouldSucceed
    }

    var openedURLs: [URL] {
        state.withLock { $0.openedURLs }
    }
}

private final class StubLoopbackSession: GA4LoopbackListenerSession, Sendable {
    let redirectURI: String

    private struct State: Sendable {
        var stopCount: Int = 0
        var waitCalls: Int = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let waitHandler: @Sendable (String, String, TimeInterval) async throws -> URL

    init(
        redirectURI: String,
        waitHandler: @escaping @Sendable (String, String, TimeInterval) async throws -> URL
    ) {
        self.redirectURI = redirectURI
        self.waitHandler = waitHandler
    }

    func waitForCallback(expectedPath: String, expectedState: String, timeoutSeconds: TimeInterval) async throws -> URL {
        state.withLock { $0.waitCalls += 1 }
        return try await waitHandler(expectedPath, expectedState, timeoutSeconds)
    }

    func stop() {
        state.withLock { $0.stopCount += 1 }
    }

    var stopCount: Int {
        state.withLock { $0.stopCount }
    }
}

private final class StubLoopbackFactory: GA4LoopbackListenerFactory, Sendable {
    private let builder: @Sendable (String) throws -> GA4LoopbackListenerSession

    init(_ builder: @escaping @Sendable (String) throws -> GA4LoopbackListenerSession) {
        self.builder = builder
    }

    func startLoopbackListener(callbackPath: String) throws -> GA4LoopbackListenerSession {
        try builder(callbackPath)
    }
}

private final class LoopbackMockTransport: WebsiteAnalyticsHTTPTransport, Sendable {
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

// MARK: - Tests

final class GA4LoopbackOAuthTests: XCTestCase {

    // MARK: 1. Pure HTTP Request Parsing & Validation

    func testHTTPParserAcceptsValidCallbackAndRejectsInvalidRequests() {
        let base = "http://127.0.0.1:54321/oauth2/callback"
        let expectedPath = "/oauth2/callback"
        let expectedState = "high_entropy_state_token_123456"

        // Valid GET callback
        let validReq = Data("GET /oauth2/callback?code=4/0AfJoh&state=\(expectedState) HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n".utf8)
        let validDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: validReq,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .acceptCallback(let callbackURL, let html) = validDisp else {
            return XCTFail("Expected acceptCallback, got \(validDisp)")
        }
        XCTAssertEqual(callbackURL.absoluteString, "http://127.0.0.1:54321/oauth2/callback?code=4/0AfJoh&state=\(expectedState)")
        XCTAssertTrue(html.contains("Authorization complete"))

        // Browser cancel (error=access_denied)
        let cancelReq = Data("GET /oauth2/callback?error=access_denied&state=\(expectedState) HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n".utf8)
        let cancelDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: cancelReq,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .acceptCallback(let cancelURL, let cancelHTML) = cancelDisp else {
            return XCTFail("Expected acceptCallback for access_denied, got \(cancelDisp)")
        }
        XCTAssertTrue(cancelHTML.contains("cancelled"))
        XCTAssertEqual(GA4OAuthPKCE.parseCallbackURL(cancelURL, expectedState: expectedState), .failure(.oauthCancelled))

        // State mismatch -> rejectStateMismatch
        let badStateReq = Data("GET /oauth2/callback?code=abc&state=wrong_state HTTP/1.1\r\n\r\n".utf8)
        let badStateDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: badStateReq,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .rejectStateMismatch = badStateDisp else {
            return XCTFail("Expected rejectStateMismatch, got \(badStateDisp)")
        }

        // Wrong path (/favicon.ico) -> 404 ignore
        let faviconReq = Data("GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1:54321\r\n\r\n".utf8)
        let faviconDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: faviconReq,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .ignoreNonMatching(404, _, _) = faviconDisp else {
            return XCTFail("Expected 404 ignoreNonMatching, got \(faviconDisp)")
        }

        // Non-GET method -> 405 ignore
        let postReq = Data("POST /oauth2/callback?code=abc&state=\(expectedState) HTTP/1.1\r\n\r\n".utf8)
        let postDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: postReq,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .ignoreNonMatching(405, _, _) = postDisp else {
            return XCTFail("Expected 405 ignoreNonMatching, got \(postDisp)")
        }

        // Oversized request -> 413 ignore
        let oversized = Data(repeating: UInt8(ascii: "A"), count: GA4LoopbackHTTPParser.maxRequestBytes + 1)
        let overDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: oversized,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .ignoreNonMatching(413, _, _) = overDisp else {
            return XCTFail("Expected 413 ignoreNonMatching, got \(overDisp)")
        }

        // Malformed request line -> 400 ignore
        let malformed = Data("GARBAGE_NO_HTTP\r\n\r\n".utf8)
        let malDisp = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: malformed,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: base
        )
        guard case .ignoreNonMatching(400, _, _) = malDisp else {
            return XCTFail("Expected 400 ignoreNonMatching, got \(malDisp)")
        }
    }

    // MARK: 2. Driver Seams: Bind Failure, Browser Failure, Timeout, Cancellation & Teardown

    func testDriverListenerStartFailureNeverOpensBrowser() async {
        let browser = StubBrowserOpener()
        let factory = StubLoopbackFactory { _ in
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }
        let driver = GA4LoopbackOAuthDriver(listenerFactory: factory, browserOpener: browser)

        do {
            _ = try await driver.authorize(expectedState: "st1") { redirect in
                URL(string: "https://accounts.google.com/o/oauth2/v2/auth?redirect_uri=\(redirect)")!
            }
            XCTFail("Expected listener bind failure")
        } catch let err as WebsiteAnalyticsError {
            XCTAssertEqual(err, .invalidConfiguration("oauth_loopback_bind_failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(browser.openedURLs.isEmpty)
    }

    func testDriverBrowserOpenFailureDeterministicallyStopsListener() async {
        let session = StubLoopbackSession(redirectURI: "http://127.0.0.1:49999/oauth2/callback") { _, _, _ in
            XCTFail("waitForCallback must not run if browser open failed")
            return URL(string: "http://127.0.0.1:49999/oauth2/callback")!
        }
        let factory = StubLoopbackFactory { _ in session }
        let browser = StubBrowserOpener(shouldSucceed: false)
        let driver = GA4LoopbackOAuthDriver(listenerFactory: factory, browserOpener: browser)

        do {
            _ = try await driver.authorize(expectedState: "st2") { redirect in
                URL(string: "https://accounts.google.com/o/oauth2/v2/auth?redirect_uri=\(redirect)")!
            }
            XCTFail("Expected browser open failure")
        } catch let err as WebsiteAnalyticsError {
            XCTAssertEqual(err, .invalidConfiguration("oauth_browser_open_failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertGreaterThanOrEqual(session.stopCount, 1)
    }

    func testDriverTaskCancellationDeterministicallyStopsListener() async {
        let session = StubLoopbackSession(redirectURI: "http://127.0.0.1:49998/oauth2/callback") { _, _, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return URL(string: "http://127.0.0.1:49998/oauth2/callback?code=late&state=st3")!
        }
        let factory = StubLoopbackFactory { _ in session }
        let browser = StubBrowserOpener(shouldSucceed: true)
        let driver = GA4LoopbackOAuthDriver(listenerFactory: factory, browserOpener: browser)

        let task = Task {
            try await driver.authorize(expectedState: "st3") { redirect in
                URL(string: "https://accounts.google.com/o/oauth2/v2/auth?redirect_uri=\(redirect)")!
            }
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            // Either CancellationError or WebsiteAnalyticsError.oauthCancelled is valid
        }
        XCTAssertGreaterThanOrEqual(session.stopCount, 1)
    }

    func testDriverTimeoutStopsListener() async {
        let session = StubLoopbackSession(redirectURI: "http://127.0.0.1:49997/oauth2/callback") { _, _, _ in
            throw WebsiteAnalyticsError.timeout
        }
        let factory = StubLoopbackFactory { _ in session }
        let browser = StubBrowserOpener(shouldSucceed: true)
        let driver = GA4LoopbackOAuthDriver(listenerFactory: factory, browserOpener: browser, timeoutSeconds: 1)

        do {
            _ = try await driver.authorize(expectedState: "st4") { redirect in
                URL(string: "https://accounts.google.com/o/oauth2/v2/auth?redirect_uri=\(redirect)")!
            }
            XCTFail("Expected timeout")
        } catch let err as WebsiteAnalyticsError {
            XCTAssertEqual(err, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertGreaterThanOrEqual(session.stopCount, 1)
    }

    // MARK: 3. End-to-End Local IPv4 Loopback Socket Round-Trip (No Browser, No Network)

    func testPOSIXIPv4LoopbackRoundTripIgnoresFaviconHandlesOneCallbackAndTearsDown() async throws {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .googleAnalytics4,
            ga4Config: GA4PropertyConfig(
                propertyId: "556677889",
                propertyLabel: "Desktop OAuth Site",
                oauthClientId: "desktop-client-id.apps.googleusercontent.com",
                redirectURI: nil,
                timeZoneIdentifier: "UTC"
            )
        )

        let capturedRedirect = OSAllocatedUnfairLock<String?>(initialState: nil)

        // Browser opener seam simulates the browser hitting the local 127.0.0.1:<ephemeral-port>
        // first with /favicon.ico (404), then with the real OAuth callback.
        let simulatedBrowser = StubBrowserOpener(shouldSucceed: true) { authURL in
            let comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
            let redirect = comps.queryItems?.first(where: { $0.name == "redirect_uri" })?.value ?? ""
            let state = comps.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
            capturedRedirect.withLock { $0 = redirect }

            guard let redirectURL = URL(string: redirect),
                  let port = redirectURL.port else {
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                // 1. Stray /favicon.ico request -> must be ignored (404) without aborting flow.
                let favResp = Self.sendRawLoopbackHTTP(port: UInt16(port), raw: "GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n")
                XCTAssertTrue(favResp.contains("404 Not Found"))

                // 2. Real OAuth callback -> 200 OK HTML + settles flow.
                let okResp = Self.sendRawLoopbackHTTP(
                    port: UInt16(port),
                    raw: "GET /oauth2/callback?code=loopback_code_42&state=\(state) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
                )
                XCTAssertTrue(okResp.contains("200 OK"))
                XCTAssertTrue(okResp.contains("Authorization complete"))
            }
        }

        let driver = GA4LoopbackOAuthDriver(
            listenerFactory: POSIXIPv4LoopbackListenerFactory(),
            browserOpener: simulatedBrowser,
            timeoutSeconds: 5
        )

        let tokenTransport = LoopbackMockTransport { req in
            XCTAssertEqual(req.url?.absoluteString, "https://oauth2.googleapis.com/token")
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("code=loopback_code_42"))
            XCTAssertTrue(body.contains("code_verifier="))
            XCTAssertFalse(body.contains("client_secret="))
            if let expectedRedirect = capturedRedirect.withLock({ $0 }) {
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._~")
                let encoded = expectedRedirect.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                XCTAssertTrue(body.contains("redirect_uri=\(encoded)"))
            } else {
                XCTFail("Expected captured redirect URI")
            }
            let json = #"{"access_token":"ya29.loopback_tok","refresh_token":"1//loopback_ref","expires_in":3600}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(json.utf8), resp)
        }

        let adapter = GA4DataAPIAdapter(
            transport: tokenTransport,
            credentialStore: creds,
            configStore: configs,
            oauthDriver: driver
        )

        let tokens = try await adapter.authorizeWithPKCE()
        XCTAssertEqual(tokens.accessToken, "ya29.loopback_tok")
        XCTAssertEqual(creds.secret(for: .ga4AccessToken, accountKey: "556677889"), "ya29.loopback_tok")
        XCTAssertEqual(creds.secret(for: .ga4RefreshToken, accountKey: "556677889"), "1//loopback_ref")

        // Verify redirect URI was strictly IPv4 loopback http://127.0.0.1:<port>/oauth2/callback
        let usedRedirect = try XCTUnwrap(capturedRedirect.withLock { $0 })
        let usedURL = try XCTUnwrap(URL(string: usedRedirect))
        XCTAssertEqual(usedURL.scheme, "http")
        XCTAssertEqual(usedURL.host, "127.0.0.1")
        XCTAssertEqual(usedURL.path, "/oauth2/callback")
        let usedPort = try XCTUnwrap(usedURL.port)
        XCTAssertGreaterThan(usedPort, 0)

        // Verify listener is deterministically closed after completion (duplicate callback cannot connect).
        let duplicateResp = Self.sendRawLoopbackHTTP(
            port: UInt16(usedPort),
            raw: "GET /oauth2/callback?code=dup&state=dup HTTP/1.1\r\nHost: 127.0.0.1:\(usedPort)\r\n\r\n"
        )
        XCTAssertTrue(duplicateResp.isEmpty || duplicateResp.contains("409 Conflict"))

        // Verify auth code / PKCE verifier were never persisted in credential store.
        let storedKeys = creds.allStoredKeys()
        XCTAssertEqual(storedKeys.count, 2)
        for key in storedKeys {
            XCTAssertFalse(key.contains("verifier"))
            XCTAssertFalse(key.contains("code"))
        }
    }

    private static func sendRawLoopbackHTTP(port: UInt16, raw: String) -> String {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "" }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return "" }

        let reqData = Data(raw.utf8)
        reqData.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            _ = Darwin.write(fd, base, reqData.count)
        }

        var buf = [UInt8](repeating: 0, count: 4096)
        var collected = Data()
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            collected.append(buf, count: n)
        }
        return String(data: collected, encoding: .utf8) ?? ""
    }
}
