import Foundation
import os

/// Smart Selection E6 — the ONE reader of `smartSelect.currency` and the only code that fetches a rate table.
///
/// No timer: a request is made when the user turns the switch on, or when a selection that is an amount of money
/// settles and the table is older than 12 hours (`CurrencyConversion.shouldFetch`). The request is a plain GET of a
/// public table — no cookies, no selected text, nothing about the user. The table is kept in
/// `~/Library/Application Support/XFinder/CurrencyRates.json` so a relaunch does not fetch again.
@MainActor
@Observable
final class CurrencyRateStore {
    static let shared = CurrencyRateStore()
    private init() {}

    private(set) var table: CurrencyConversion.Table?
    private(set) var inFlight = false
    private(set) var lastFailure: Date?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "SmartSelect")

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "smartSelect.currency") as? Bool ?? false }

    /// The region's currency, read every time (it follows System Settings ▸ Language & Region without a relaunch).
    var localCurrency: String? { Locale.autoupdatingCurrent.currency?.identifier }

    var source: CurrencyConversion.Source? { CurrencyConversion.source(forLocalCurrency: localCurrency) }

    /// nil ⇒ no currency row at all (switch off, or no public source quotes the local currency).
    func context() -> CurrencyConversion.Context? {
        guard isEnabled, let local = localCurrency, let src = source else { return nil }
        loadIfNeeded()
        return .init(localCode: local, source: src, table: table, failed: lastFailure != nil && !inFlight)
    }

    /// The page's switch calls this. It prefetches only while the watcher actually runs (Smart Selection on AND
    /// Accessibility granted) — otherwise no selection can arrive, and a request would serve nothing.
    func applySettings() {
        guard isEnabled, SelectionWatcher.shared.isRunning else { return }
        refreshIfNeeded()
    }

    func refreshIfNeeded(now: Date = Date()) {
        guard isEnabled, let src = source else { return }
        loadIfNeeded()
        guard CurrencyConversion.shouldFetch(now: now, table: table, source: src, lastFailure: lastFailure,
                                             inFlight: inFlight) else { return }
        inFlight = true
        log.notice("currency fetch start source=\(src.rawValue, privacy: .public) cached=\(self.table != nil)")
        SmartSelectionBadge.shared.refreshCurrency()
        Task { [weak self] in
            let data = await Self.download(src.url)
            self?.finish(data: data, source: src)
        }
    }

    private func finish(data: Data?, source: CurrencyConversion.Source) {
        inFlight = false
        let now = Date()
        let parsed: CurrencyConversion.Table? = data.flatMap {
            switch source {
            case .ecb: return CurrencyConversion.parseECB($0, fetchedAt: now)
            case .vietcombank: return CurrencyConversion.parseVietcombank($0, fetchedAt: now)
            }
        }
        if let parsed {
            table = parsed
            lastFailure = nil
            save(parsed)
            log.notice("currency fetch ok source=\(source.rawValue, privacy: .public) rates=\(parsed.rates.count) bytes=\(data?.count ?? 0)")
        } else {
            lastFailure = now
            log.notice("currency fetch failed source=\(source.rawValue, privacy: .public) bytes=\(data?.count ?? -1)")
        }
        SmartSelectionBadge.shared.refreshCurrency()
    }

    nonisolated private static func download(_ url: URL) async -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: Cache file

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("XFinder", isDirectory: true).appendingPathComponent("CurrencyRates.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        table = try? d.decode(CurrencyConversion.Table.self, from: data)
    }

    private func save(_ t: CurrencyConversion.Table) {
        guard let url = fileURL else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(t) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
