import Foundation
import Darwin
import os
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Seams for Production & Unit Testing

public protocol GA4SystemBrowserOpener: Sendable {
    func open(_ url: URL) async -> Bool
}

public struct WorkspaceGA4BrowserOpener: GA4SystemBrowserOpener, Sendable {
    public init() {}

    public func open(_ url: URL) async -> Bool {
        #if canImport(AppKit)
        return await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        #else
        return false
        #endif
    }
}

public protocol GA4LoopbackListenerSession: Sendable {
    /// Exact IPv4 loopback redirect URI bound to an OS-assigned ephemeral port (e.g. `http://127.0.0.1:54321/oauth2/callback`).
    var redirectURI: String { get }

    /// Waits for a single valid OAuth callback on `expectedPath`.
    func waitForCallback(
        expectedPath: String,
        expectedState: String,
        timeoutSeconds: TimeInterval
    ) async throws -> URL

    /// Deterministically closes the underlying listener socket and cancels any pending wait. Idempotent.
    func stop()
}

public protocol GA4LoopbackListenerFactory: Sendable {
    func startLoopbackListener(callbackPath: String) throws -> GA4LoopbackListenerSession
}

// MARK: - Pure Loopback HTTP Request Parser & HTML Responses

public enum GA4LoopbackHTTPDisposition: Equatable, Sendable {
    case acceptCallback(callbackURL: URL, responseHTML: String)
    case rejectStateMismatch(responseHTML: String)
    case ignoreNonMatching(statusCode: Int, statusText: String, responseHTML: String)
}

public enum GA4LoopbackHTTPParser {
    /// Maximum HTTP request bytes accepted on the loopback callback socket (8 KiB).
    public static let maxRequestBytes: Int = 8 * 1024

    public static func parseAndValidate(
        requestData: Data,
        expectedPath: String,
        expectedState: String,
        redirectBaseURI: String,
        maxBytes: Int = maxRequestBytes
    ) -> GA4LoopbackHTTPDisposition {
        if requestData.count > maxBytes {
            return .ignoreNonMatching(
                statusCode: 413,
                statusText: "Payload Too Large",
                responseHTML: htmlPage(title: "Request Too Large", body: "The authorization callback exceeded the allowed size.")
            )
        }
        guard !requestData.isEmpty,
              let rawString = String(data: requestData, encoding: .utf8) else {
            return .ignoreNonMatching(
                statusCode: 400,
                statusText: "Bad Request",
                responseHTML: htmlPage(title: "Bad Request", body: "Malformed HTTP request.")
            )
        }

        // Extract the HTTP request line (`METHOD SP TARGET SP HTTP/1.x`).
        let firstLine: String
        if let crlfRange = rawString.range(of: "\r\n") {
            firstLine = String(rawString[..<crlfRange.lowerBound])
        } else if let lfRange = rawString.range(of: "\n") {
            firstLine = String(rawString[..<lfRange.lowerBound])
        } else {
            firstLine = rawString
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else {
            return .ignoreNonMatching(
                statusCode: 400,
                statusText: "Bad Request",
                responseHTML: htmlPage(title: "Bad Request", body: "Invalid HTTP request line.")
            )
        }

        let method = String(parts[0])
        guard method == "GET" else {
            return .ignoreNonMatching(
                statusCode: 405,
                statusText: "Method Not Allowed",
                responseHTML: htmlPage(title: "Method Not Allowed", body: "Only GET callbacks are accepted.")
            )
        }

        let target = String(parts[1])
        guard target.hasPrefix("/"),
              let baseComponents = URLComponents(string: redirectBaseURI),
              let scheme = baseComponents.scheme,
              let host = baseComponents.host,
              let port = baseComponents.port,
              let targetComponents = URLComponents(string: target) else {
            return .ignoreNonMatching(
                statusCode: 400,
                statusText: "Bad Request",
                responseHTML: htmlPage(title: "Bad Request", body: "Invalid callback target.")
            )
        }

        guard targetComponents.path == expectedPath else {
            return .ignoreNonMatching(
                statusCode: 404,
                statusText: "Not Found",
                responseHTML: htmlPage(title: "Not Found", body: "Unknown callback path.")
            )
        }

        var fullComponents = URLComponents()
        fullComponents.scheme = scheme
        fullComponents.host = host
        fullComponents.port = port
        fullComponents.path = targetComponents.path
        fullComponents.queryItems = targetComponents.queryItems
        guard let callbackURL = fullComponents.url else {
            return .ignoreNonMatching(
                statusCode: 400,
                statusText: "Bad Request",
                responseHTML: htmlPage(title: "Bad Request", body: "Could not reconstruct callback URL.")
            )
        }

        let items = targetComponents.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        // Validate OAuth state before accepting either code or error.
        if let errorParam = query["error"]?.lowercased() {
            if let returnedState = query["state"], returnedState != expectedState {
                return .rejectStateMismatch(
                    responseHTML: htmlPage(title: "Authorization Failed", body: "OAuth state verification failed. You may close this tab.")
                )
            }
            let bodyText = (errorParam == "access_denied")
                ? "Sign-in was cancelled. You may close this tab and return to XFinder."
                : "Authorization could not be completed. You may close this tab and return to XFinder."
            return .acceptCallback(
                callbackURL: callbackURL,
                responseHTML: htmlPage(title: "XFinder — Google Analytics", body: bodyText)
            )
        }

        guard let returnedState = query["state"], returnedState == expectedState else {
            return .rejectStateMismatch(
                responseHTML: htmlPage(title: "Authorization Failed", body: "OAuth state mismatch. You may close this tab.")
            )
        }

        guard let code = query["code"], !code.isEmpty else {
            return .ignoreNonMatching(
                statusCode: 400,
                statusText: "Bad Request",
                responseHTML: htmlPage(title: "Bad Request", body: "Missing authorization code.")
            )
        }

        return .acceptCallback(
            callbackURL: callbackURL,
            responseHTML: htmlPage(
                title: "XFinder — Google Analytics",
                body: "Authorization complete. You may close this tab and return to XFinder."
            )
        )
    }

    public static func buildHTTPResponse(statusCode: Int, statusText: String, htmlBody: String) -> Data {
        let bodyData = Data(htmlBody.utf8)
        let header = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Pragma: no-cache",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var data = Data(header.utf8)
        data.append(bodyData)
        return data
    }

    public static func htmlPage(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#111;color:#f5f5f7;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}main{max-width:420px;padding:24px 28px;border-radius:14px;background:#1d1d1f;border:1px solid #333;text-align:center}h1{font-size:17px;margin:0 0 10px}p{font-size:14px;color:#c7c7cc;margin:0;line-height:1.45}</style>
        </head><body><main><h1>\(title)</h1><p>\(body)</p></main></body></html>
        """
    }
}

// MARK: - POSIX IPv4 Loopback Listener (127.0.0.1:<ephemeral-port>)

public struct POSIXIPv4LoopbackListenerFactory: GA4LoopbackListenerFactory, Sendable {
    public init() {}

    public func startLoopbackListener(callbackPath: String) throws -> GA4LoopbackListenerSession {
        try POSIXIPv4LoopbackListenerSession(callbackPath: callbackPath)
    }
}

public final class POSIXIPv4LoopbackListenerSession: GA4LoopbackListenerSession, Sendable {
    public let redirectURI: String

    private struct State: Sendable {
        var listenFD: Int32
        var isStopped: Bool = false
        var hasSettled: Bool = false
        var continuation: CheckedContinuation<URL, Error>?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let queue: DispatchQueue
    private let sourcesLock = OSAllocatedUnfairLock<(read: DispatchSourceRead?, timer: DispatchSourceTimer?)>(
        initialState: (nil, nil)
    )

    public init(callbackPath: String = "/oauth2/callback") throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // OS-assigned ephemeral port
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian) // Strictly 127.0.0.1

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }

        guard Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(fd, sockPtr, &boundLen)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }

        let port = UInt16(bigEndian: boundAddr.sin_port)
        guard port > 0 else {
            Darwin.close(fd)
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_loopback_bind_failed")
        }

        let normalizedPath = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
        self.redirectURI = "http://127.0.0.1:\(port)\(normalizedPath)"
        self.state = OSAllocatedUnfairLock(initialState: State(listenFD: fd))
        self.queue = DispatchQueue(label: "com.xfinder.ga4.oauth.loopback", qos: .userInitiated)
    }

    deinit {
        stop()
    }

    public func waitForCallback(
        expectedPath: String,
        expectedState: String,
        timeoutSeconds: TimeInterval
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let fdToWatch: Int32? = state.withLock { st in
                    if st.isStopped || st.hasSettled || st.listenFD < 0 {
                        return nil
                    }
                    st.continuation = continuation
                    return st.listenFD
                }

                guard let listenFD = fdToWatch else {
                    continuation.resume(throwing: WebsiteAnalyticsError.oauthCancelled)
                    return
                }

                let readSource = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
                readSource.setEventHandler { [weak self] in
                    self?.handleIncomingConnection(
                        listenFD: listenFD,
                        expectedPath: expectedPath,
                        expectedState: expectedState
                    )
                }

                let timer = DispatchSource.makeTimerSource(queue: queue)
                let clampedTimeout = max(1.0, timeoutSeconds)
                timer.schedule(deadline: .now() + clampedTimeout)
                timer.setEventHandler { [weak self] in
                    self?.settle(with: .failure(WebsiteAnalyticsError.timeout))
                }

                sourcesLock.withLock { sources in
                    sources.read = readSource
                    sources.timer = timer
                }

                readSource.resume()
                timer.resume()
            }
        } onCancel: {
            self.stop()
        }
    }

    public func stop() {
        settle(with: .failure(WebsiteAnalyticsError.oauthCancelled))
    }

    private func handleIncomingConnection(listenFD: Int32, expectedPath: String, expectedState: String) {
        var clientAddr = sockaddr_in()
        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(listenFD, sockPtr, &clientLen)
            }
        }
        guard clientFD >= 0 else { return }
        defer { Darwin.close(clientFD) }

        var noSigPipe: Int32 = 1
        _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // If already settled, reject duplicate callbacks immediately.
        let alreadySettled = state.withLock { $0.hasSettled || $0.isStopped }
        if alreadySettled {
            let response = GA4LoopbackHTTPParser.buildHTTPResponse(
                statusCode: 409,
                statusText: "Conflict",
                htmlBody: GA4LoopbackHTTPParser.htmlPage(
                    title: "XFinder — Google Analytics",
                    body: "This sign-in session has already completed."
                )
            )
            Self.writeAll(response, to: clientFD)
            return
        }

        let requestData = Self.readBoundedRequest(from: clientFD, maxBytes: GA4LoopbackHTTPParser.maxRequestBytes + 1)
        let disposition = GA4LoopbackHTTPParser.parseAndValidate(
            requestData: requestData,
            expectedPath: expectedPath,
            expectedState: expectedState,
            redirectBaseURI: redirectURI,
            maxBytes: GA4LoopbackHTTPParser.maxRequestBytes
        )

        switch disposition {
        case .acceptCallback(let callbackURL, let html):
            let response = GA4LoopbackHTTPParser.buildHTTPResponse(statusCode: 200, statusText: "OK", htmlBody: html)
            Self.writeAll(response, to: clientFD)
            settle(with: .success(callbackURL))
        case .rejectStateMismatch(let html):
            let response = GA4LoopbackHTTPParser.buildHTTPResponse(statusCode: 400, statusText: "Bad Request", htmlBody: html)
            Self.writeAll(response, to: clientFD)
            settle(with: .failure(WebsiteAnalyticsError.malformedResponse("oauth_state_mismatch")))
        case .ignoreNonMatching(let code, let text, let html):
            let response = GA4LoopbackHTTPParser.buildHTTPResponse(statusCode: code, statusText: text, htmlBody: html)
            Self.writeAll(response, to: clientFD)
        }
    }

    private func settle(with result: Result<URL, Error>) {
        let (cont, fdToClose): (CheckedContinuation<URL, Error>?, Int32) = state.withLock { st in
            let c = st.continuation
            st.continuation = nil
            st.hasSettled = true
            st.isStopped = true
            let fd = st.listenFD
            st.listenFD = -1
            return (c, fd)
        }

        let sources = sourcesLock.withLock { s -> (read: DispatchSourceRead?, timer: DispatchSourceTimer?) in
            let copy = s
            s = (nil, nil)
            return copy
        }
        sources.timer?.cancel()
        sources.read?.cancel()

        if fdToClose >= 0 {
            Darwin.close(fdToClose)
        }

        if let cont {
            switch result {
            case .success(let url): cont.resume(returning: url)
            case .failure(let err): cont.resume(throwing: err)
            }
        }
    }

    private static func readBoundedRequest(from fd: Int32, maxBytes: Int) -> Data {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var collected = Data()
        let headerEndMarker = Data("\r\n\r\n".utf8)
        let altEndMarker = Data("\n\n".utf8)

        while collected.count < maxBytes {
            let remaining = maxBytes - collected.count
            let toRead = min(buffer.count, remaining)
            let n = Darwin.read(fd, &buffer, toRead)
            if n <= 0 { break }
            collected.append(buffer, count: n)
            if collected.range(of: headerEndMarker) != nil || collected.range(of: altEndMarker) != nil {
                break
            }
        }
        return collected
    }

    private static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var written = 0
            while written < data.count {
                let n = Darwin.write(fd, base.advanced(by: written), data.count - written)
                if n <= 0 { break }
                written += n
            }
        }
    }
}

// MARK: - Production GA4 Loopback OAuth Driver

/// Installed-desktop Google OAuth 2.0 driver using an ephemeral IPv4 loopback listener
/// (`http://127.0.0.1:<ephemeral-port>/oauth2/callback`) and the system browser.
/// Never uses an embedded web view or custom URL scheme.
public final class GA4LoopbackOAuthDriver: GA4OAuthAuthorizationDriver, Sendable {
    public static let defaultCallbackPath = "/oauth2/callback"
    public static let defaultTimeoutSeconds: TimeInterval = 180

    private let listenerFactory: GA4LoopbackListenerFactory
    private let browserOpener: GA4SystemBrowserOpener
    private let callbackPath: String
    private let timeoutSeconds: TimeInterval

    public init(
        listenerFactory: GA4LoopbackListenerFactory = POSIXIPv4LoopbackListenerFactory(),
        browserOpener: GA4SystemBrowserOpener = WorkspaceGA4BrowserOpener(),
        callbackPath: String = GA4LoopbackOAuthDriver.defaultCallbackPath,
        timeoutSeconds: TimeInterval = GA4LoopbackOAuthDriver.defaultTimeoutSeconds
    ) {
        self.listenerFactory = listenerFactory
        self.browserOpener = browserOpener
        self.callbackPath = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
        self.timeoutSeconds = max(1.0, timeoutSeconds)
    }

    public func authorize(
        expectedState: String,
        buildAuthorizationURL: @Sendable (String) throws -> URL
    ) async throws -> GA4OAuthAuthorizationResult {
        try Task.checkCancellation()

        // 1. Allocate ephemeral IPv4 loopback listener BEFORE constructing the authorization URL.
        let session = try listenerFactory.startLoopbackListener(callbackPath: callbackPath)
        defer { session.stop() }

        let redirectURI = session.redirectURI
        let authURL = try buildAuthorizationURL(redirectURI)

        try Task.checkCancellation()

        // 2. Open authorization URL in the user's default system browser.
        let opened = await browserOpener.open(authURL)
        guard opened else {
            throw WebsiteAnalyticsError.invalidConfiguration("oauth_browser_open_failed")
        }

        // 3. Await exactly one validated callback on the loopback port.
        let callbackURL = try await withTaskCancellationHandler {
            try await session.waitForCallback(
                expectedPath: callbackPath,
                expectedState: expectedState,
                timeoutSeconds: timeoutSeconds
            )
        } onCancel: {
            session.stop()
        }

        return GA4OAuthAuthorizationResult(callbackURL: callbackURL, redirectURI: redirectURI)
    }
}
