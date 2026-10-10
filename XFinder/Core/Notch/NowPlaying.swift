import Foundation

/// The pure half of "Đang phát" on the notch (B6): what the helper reports, how a line of its output
/// becomes a snapshot, where the playhead is without polling, and when a dying helper is restarted or
/// given up on. Foundation-only so every rule is tested; the process and the pixels live elsewhere.
///
/// Reading now-playing info needs the private MediaRemote framework, which since macOS 15.4 answers
/// only Apple-signed processes (measured 2026-10-10 on macOS 27: nothing for the app, everything for
/// a dylib hosted by /usr/bin/perl). `NowPlayingMonitor` runs that helper; this file owns the rules.
enum NowPlaying {

    struct Snapshot: Equatable {
        var title: String?
        var artist: String?
        var album: String?
        /// Seconds. `elapsed` is where the playhead was at `timestamp`; the real position is derived
        /// by `position(of:at:)` — the helper does NOT tick once a second.
        var duration: Double?
        var elapsed: Double?
        var rate: Double?
        var timestamp: Date?
        var playing: Bool
        var pid: Int32?
        var artworkID: String?
        var artworkMIME: String?

        /// Something worth showing: at least a title or an artist.
        var hasTrack: Bool { !(title ?? "").isEmpty || !(artist ?? "").isEmpty }
        var headline: String { (title?.isEmpty == false ? title : artist) ?? "" }
        /// "Artist · Album", whichever parts exist (never the title twice).
        var subline: String {
            var parts: [String] = []
            if title?.isEmpty == false, let a = artist, !a.isEmpty { parts.append(a) }
            if let al = album, !al.isEmpty { parts.append(al) }
            return parts.joined(separator: " · ")
        }
    }

    /// One line of the helper's stdout.
    enum Line: Equatable {
        case hello(version: Int)
        /// Nothing is playing (or the player went away).
        case empty
        /// Metadata, plus the artwork bytes when the helper decided they are new.
        case snapshot(Snapshot, artwork: Data?)
        case error(reason: String)
        /// Anything else — ignored, never crashes the reader.
        case other
    }

    static func parse(_ line: String) -> Line {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let t = dict["t"] as? String else { return .other }
        switch t {
        case "hello":
            return .hello(version: (dict["v"] as? NSNumber)?.intValue ?? 0)
        case "error":
            return .error(reason: dict["reason"] as? String ?? "")
        case "np":
            if (dict["empty"] as? Bool) == true { return .empty }
            let ts = (dict["ts"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let s = Snapshot(title: dict["title"] as? String,
                             artist: dict["artist"] as? String,
                             album: dict["album"] as? String,
                             duration: (dict["duration"] as? NSNumber)?.doubleValue,
                             elapsed: (dict["elapsed"] as? NSNumber)?.doubleValue,
                             rate: (dict["rate"] as? NSNumber)?.doubleValue,
                             timestamp: ts,
                             playing: (dict["playing"] as? Bool) ?? false,
                             pid: (dict["pid"] as? NSNumber)?.int32Value,
                             artworkID: dict["artworkId"] as? String,
                             artworkMIME: dict["artworkMime"] as? String)
            let art = (dict["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
            return .snapshot(s, artwork: art)
        default:
            return .other
        }
    }

    /// Where the playhead is `now`: the reported elapsed time advanced by the time since the report
    /// at the playback rate — ZERO while paused, whatever rate the player claims (a paused publisher
    /// was measured still reporting rate 1.0). Clamped to the track. nil when nothing was reported.
    static func position(of s: Snapshot, at now: Date) -> Double? {
        guard let elapsed = s.elapsed else { return nil }
        let rate = s.playing ? (s.rate ?? 1) : 0
        var p = elapsed + (s.timestamp.map { now.timeIntervalSince($0) } ?? 0) * rate
        if let d = s.duration, d > 0 { p = min(p, d) }
        return max(0, p)
    }

    /// "m:ss", or "h:mm:ss" from one hour. Negative / non-finite input reads 0:00 — never a crash.
    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Restart policy for the helper process. A helper that dies right after starting is a crash loop
    /// and is given up on after `maxAttempts`; one that ran for a while and then died (sleep/wake,
    /// memory pressure) starts the count over, because that is not the same failure repeating.
    struct Supervisor: Equatable {
        private(set) var attempts = 0
        static let maxAttempts = 5
        /// A run this long proves the helper works; its death is not counted against it.
        static let stableAfter: TimeInterval = 60

        enum Action: Equatable { case restart(after: TimeInterval), giveUp }

        static func delay(forAttempt n: Int) -> TimeInterval {
            min(8, 0.5 * pow(2, Double(max(0, n - 1))))      // 0.5, 1, 2, 4, 8, 8…
        }

        mutating func helperExited(afterUptime uptime: TimeInterval) -> Action {
            if uptime >= Self.stableAfter { attempts = 0 }
            attempts += 1
            return attempts > Self.maxAttempts ? .giveUp : .restart(after: Self.delay(forAttempt: attempts))
        }
    }

    /// What the settings page says about the mechanism. Keys into the L10n store.
    enum Availability: Equatable {
        case off, starting, ready, missingHelper, missingPerl, gaveUp

        var messageKey: String {
            switch self {
            case .off: return "Tắt"
            case .starting: return "Đang khởi động trợ giúp…"
            case .ready: return "Sẵn sàng"
            case .missingHelper: return "Không khả dụng: thiếu thư viện trợ giúp trong gói ứng dụng."
            case .missingPerl: return "Không khả dụng: máy này không có /usr/bin/perl."
            case .gaveUp: return "Không khả dụng: tiến trình trợ giúp thoát liên tục."
            }
        }

        static let allCases: [Availability] = [.off, .starting, .ready, .missingHelper, .missingPerl, .gaveUp]

        /// Only a READY helper's snapshot may be shown as live. A dead or restarting helper knows
        /// nothing about the player any more (review 2026-10-11: the old track stayed on the badge
        /// at "playing" opacity while the helper was down, and the page read "Đang khởi động… · Đang phát: …").
        var isLive: Bool { self == .ready }
    }

    /// The perl one-liner that hosts the dylib. `select` with no descriptors is a plain sleep; the
    /// dylib's stdin watcher exits the process when XFinder closes the pipe.
    static func hostScript() -> String {
        "use DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error(); 1 while select(undef, undef, undef, 3600);"
    }
}
