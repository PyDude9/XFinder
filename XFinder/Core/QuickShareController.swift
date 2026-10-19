import Foundation
import AppKit
import Network

/// Chia sẻ nhanh — serve selected files over the local network from a tiny
/// built-in HTTP server, and hand the user a link to paste anywhere.
///
/// **Why local, not a cloud.** A hosted bucket needs an account, a paid plan
/// and a server that sees the user's files — none of which XFinder has, and
/// promising it in the UI would be a lie. A LAN link is real, instant, needs no
/// account, and keeps the file on this Mac. For sharing beyond the LAN the page
/// says plainly to use AirDrop or an existing cloud client.
///
/// Safety: each share gets an unguessable token in its path, the server only
/// serves files that were explicitly shared, and everything stops when the
/// share expires or the app quits.
@MainActor
@Observable
final class QuickShareController {
    static let shared = QuickShareController()

    struct Share: Identifiable {
        let id = UUID()
        let token: String
        let url: URL          // local file
        let created = Date()
        var expiresAt: Date
        var name: String { url.lastPathComponent }
        var isExpired: Bool { Date() > expiresAt }
    }

    private(set) var shares: [Share] = []
    private(set) var isRunning = false
    /// One token per server run: `GET /<indexToken>` is an HTML page listing every live share, so a single QR code
    /// hands a phone all the files. Anyone with this link sees the whole list — the page says so.
    private(set) var indexToken = ""
    var lastError: String?

    private var listener: NWListener?
    private var port: UInt16 = 0
    private var sweepTimer: Timer?

    private init() {}

    /// XF-T21: the ONE reader of the catalog switch. Off ⇒ no server may start, and a running one stops (`applySettings`).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "quickShare.enabled") as? Bool ?? true
    }

    /// Called by FeatureHub (the page switch, "Tắt tất cả", bundles): switching off revokes every link and stops the server.
    func applySettings() {
        if !isEnabled, listener != nil || !shares.isEmpty { revokeAll() }
    }

    private var expiryHours: Double {
        UserDefaults.standard.object(forKey: "quickShare.expiryHours") as? Double ?? 24
    }

    /// The Mac's LAN address — what a phone on the same Wi-Fi can reach.
    var localAddress: String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // en0/en1 are the physical Wi-Fi / Ethernet interfaces.
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }

    // MARK: Sharing

    func share(files: [URL]) -> [Share] {
        guard isEnabled else { return [] }
        startIfNeeded()
        var made: [Share] = []
        for url in files {
            let share = Share(token: Self.makeToken(),
                              url: url,
                              expiresAt: Date().addingTimeInterval(expiryHours * 3600))
            shares.append(share)
            made.append(share)
        }
        return made
    }

    func link(for share: Share) -> String? {
        QuickShareRules.link(address: localAddress, port: port, token: share.token)
    }

    /// The link the shared QR code encodes; nil until the listener is ready.
    var indexLink: String? {
        QuickShareRules.link(address: localAddress, port: port, token: indexToken)
    }

    func revoke(_ share: Share) {
        shares.removeAll { $0.id == share.id }
        if shares.isEmpty { stop() }
    }

    func revokeAll() {
        shares.removeAll()
        stop()
    }

    // MARK: Server

    private func startIfNeeded() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInitiated))
                self?.receive(on: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.port = listener.port?.rawValue ?? 0
                        self?.isRunning = true
                    case .failed(let error):
                        self?.lastError = "\(L10n.t("Không mở được cổng: "))\(error.localizedDescription)"
                        self?.stop()
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            indexToken = Self.makeToken()
            startSweep()
        } catch {
            lastError = "\(L10n.t("Không khởi động được máy chủ: "))\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        isRunning = false
        indexToken = ""
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    /// Drop expired shares once a minute so a link cannot outlive its window.
    private func startSweep() {
        guard sweepTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.shares.removeAll(where: \.isExpired)
                if self.shares.isEmpty { self.stop() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        sweepTimer = t
    }

    private nonisolated func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let token = QuickShareRules.token(fromRequest: request)

            Task { @MainActor in
                if self.isEnabled, !token.isEmpty, token == self.indexToken {
                    let body = Data(self.indexPageHTML().utf8)
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nX-Content-Type-Options: nosniff\r\n"
                        + "Cache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    Self.send(connection, header: header, body: body)
                    return
                }
                guard self.isEnabled, !token.isEmpty,
                      let share = self.shares.first(where: { $0.token == token && !$0.isExpired }),
                      let payload = try? Data(contentsOf: share.url) else {
                    Self.send(connection, header: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", body: nil)
                    return
                }
                let header = """
                HTTP/1.1 200 OK\r
                Content-Type: application/octet-stream\r
                Content-Disposition: \(QuickShareRules.contentDisposition(filename: share.name))\r
                Content-Length: \(payload.count)\r
                Connection: close\r
                \r\n
                """
                Self.send(connection, header: header, body: payload)
            }
        }
    }

    /// The index page for the shares alive right now, in the app's language.
    private func indexPageHTML() -> String {
        let live = shares.filter { !$0.isExpired }
        let entries = live.map { share -> QuickShareRules.IndexEntry in
            let size = (try? FileManager.default.attributesOfItem(atPath: share.url.path)[.size] as? Int64) ?? 0
            let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            return QuickShareRules.IndexEntry(name: share.name, token: share.token, detail: sizeText)
        }
        return QuickShareRules.indexPage(entries: entries, strings: QuickShareRules.IndexStrings(
            title: L10n.t("File chia sẻ từ máy Mac"),
            empty: L10n.t("Không còn file nào đang chia sẻ."),
            footer: L10n.t("Chạm vào một file để tải về. Liên kết chỉ hoạt động trong cùng mạng Wi-Fi và tự hết hạn.")))
    }

    private nonisolated static func send(_ connection: NWConnection, header: String, body: Data?) {
        var out = Data(header.utf8)
        if let body { out.append(body) }
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// 160 bits of randomness — not guessable by scanning the LAN.
    private static func makeToken() -> String {
        (0..<20).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
