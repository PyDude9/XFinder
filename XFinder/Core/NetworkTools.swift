import Foundation

/// Network speed test: downloads a known-size file and measures throughput
/// with a monotonic clock. Endpoint is Cloudflare's public speed-test bucket
/// (`speed.cloudflare.com/__down?bytes=N`); the measurement itself runs
/// 100% locally — no SDK, no account, no telemetry.
@MainActor
@Observable
final class SpeedTest {
    static let shared = SpeedTest()

    enum State: Equatable {
        case idle
        case running(received: Int64, total: Int64)
        case done(mbps: Double, seconds: Double)
        case failed(String)
    }

    var state: State = .idle
    /// History persisted in UserDefaults: newest-first, capped at 10.
    var history: [SpeedRecord] = []

    struct SpeedRecord: Codable, Identifiable {
        var id = UUID()
        var date = Date()
        var mbps: Double
        var seconds: Double
        var dateString: String {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            return f.string(from: date)
        }
    }

    private let historyKey = "XFinder.SpeedTestHistory"
    private var task: URLSessionDataTask?
    private var expected: Int64 = 25 * 1024 * 1024

    private init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([SpeedRecord].self, from: data) {
            history = decoded
        }
    }

    func start() {
        guard case .running = state else {
            state = .running(received: 0, total: expected)
            run(bytes: expected)
            return
        }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    private func run(bytes: Int64) {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
        let start = Date()
        let session = URLSession(configuration: .ephemeral)
        task = session.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = max(Date().timeIntervalSince(start), 0.001)
                if let error = error as NSError?, error.code != NSURLErrorCancelled {
                    self.state = .failed("Không đo được — kiểm tra kết nối mạng.")
                    return
                }
                let received = Int64(data?.count ?? 0)
                guard received > 1024 else {
                    self.state = .failed("Kết quả quá nhỏ để đo — thử lại.")
                    return
                }
                let mbps = Double(received) * 8 / elapsed / 1_000_000
                self.state = .done(mbps: mbps, seconds: elapsed)
                self.history.insert(SpeedRecord(mbps: mbps, seconds: elapsed), at: 0)
                self.history = Array(self.history.prefix(10))
                if let encoded = try? JSONEncoder().encode(self.history) {
                    UserDefaults.standard.set(encoded, forKey: self.historyKey)
                }
            }
        }
        task?.resume()
    }
}

/// Per-app network via `nettop -P` sampling (public binary, no entitlement).
/// Cumulative counters → deltas between samples → KB/s. Approximation only:
/// the timestamps come second-precision, so rates are labeled "≈".
struct NettopSampler {
    struct Row: Identifiable {
        var id: String { name }
        var name: String
        var downKBs: Double
        var upKBs: Double
    }

    /// One accumulated sample: run nettop in the background, diff consecutive
    /// snapshots, return rows sorted by traffic. Runs off-main via detached task.
    static func sample(duration: Int = 2) async -> [Row] {
        await Task.detached(priority: .background) {
            runSample(duration: duration)
        }.value
    }

    private nonisolated static func runSample(duration: Int) -> [Row] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        proc.arguments = ["-P", "-L", "\(max(duration, 1))", "-s", "1"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var snapshots: [[String: (rx: UInt64, tx: UInt64)]] = []
        var current: [String: (rx: UInt64, tx: UInt64)] = [:]
        var count = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("time,") {
                if !current.isEmpty { snapshots.append(current); current = [:]; count += 1 }
                continue
            }
            // Fields: timestamp, name.pid, ..., bytes_in, bytes_out, ...
            let cols = trimmed.components(separatedBy: ",")
            guard cols.count > 6,
                  let rx = UInt64(cols[4].trimmingCharacters(in: .whitespaces)),
                  let tx = UInt64(cols[5].trimmingCharacters(in: .whitespaces))
            else { continue }
            let ident = cols[1].trimmingCharacters(in: .whitespaces)
            let base = ident.components(separatedBy: ".").dropLast().joined(separator: ".")
            let key = base.isEmpty ? ident : base
            current[key] = (rx, tx)
        }
        if !current.isEmpty { snapshots.append(current) }
        guard snapshots.count >= 2 else { return [] }
        var rows: [Row] = []
        let span = Double(max(snapshots.count - 1, 1))
        for (name, last) in snapshots.last! {
            var firstRX = last.rx, firstTX = last.tx
            for snap in snapshots.dropLast().reversed() {
                if let prev = snap[name] { firstRX = prev.rx; firstTX = prev.tx }
            }
            let dRx = last.rx >= firstRX ? Double(last.rx - firstRX) : 0
            let dTx = last.tx >= firstTX ? Double(last.tx - firstTX) : 0
            guard dRx + dTx > 0 else { continue }
            rows.append(Row(name: name, downKBs: dRx / 1024 / span, upKBs: dTx / 1024 / span))
        }
        return rows.sorted { ($0.downKBs + $0.upKBs) > ($1.downKBs + $1.upKBs) }.prefix(10).map { $0 }
    }
}
