import Foundation

/// Pure rules, data model, retention policy, and time-attribution math for local foreground app usage.
///
/// Privacy & honesty contract:
/// - Tracks ONLY foreground app identity (`appID`, minimal `displayName`) and aggregated seconds per local day.
/// - Never stores window titles, keystrokes, URLs, document paths, or screen content.
/// - Never reads macOS Screen Time / KnowledgeC databases or requests Full Disk Access.
/// - Retention is capped at `retentionDays` (30 calendar days including today).
enum LocalAppUsageRules {

    // MARK: - Policy & Sampling Constants

    /// UserDefaults key for explicit user opt-in. Default is `false` (never tracks without opt-in).
    static let trackingEnabledDefaultsKey = "notch.appUsage.trackingEnabled"

    /// Seconds of HID inactivity before the user is considered idle and accrual stops.
    static let defaultIdleThresholdSeconds: TimeInterval = 300

    /// Heartbeat interval while actively tracking (and not paused/locked/asleep) to detect idle
    /// transitions, day rollover, and periodic persistence. Zero timers run when tracking is off or paused.
    static let defaultSampleIntervalSeconds: TimeInterval = 15

    /// Maximum seconds credited from a single unconfirmed interval (guards against forward clock jumps
    /// or missed sleep notifications).
    static let defaultMaxSampleDeltaSeconds: TimeInterval = 120

    /// Maximum calendar days retained on disk, inclusive of today.
    static let retentionDays: Int = 30

    /// Number of days displayed in the 7-day summary chart.
    static let chartDays: Int = 7

    /// Maximum character length kept for a sanitized app display name.
    static let maxDisplayNameLength: Int = 80

    /// Safety cap on distinct app entries persisted per calendar day.
    static let maxAppsPerDay: Int = 200

    /// Current JSON persistence schema version.
    static let storeSchemaVersion: Int = 1

    /// Fallback app ID when both bundle identifier and localized name are missing.
    static let unknownAppID = "unidentified:unknown"

    // MARK: - Data Types

    struct AppIdentity: Equatable, Hashable, Codable, Sendable {
        let appID: String
        let displayName: String
    }

    struct AppDayEntry: Equatable, Codable, Sendable {
        let appID: String
        var displayName: String
        var seconds: Int
    }

    struct UsageStore: Equatable, Codable, Sendable {
        var version: Int
        var days: [String: [AppDayEntry]]

        init(version: Int = LocalAppUsageRules.storeSchemaVersion, days: [String: [AppDayEntry]] = [:]) {
            self.version = version
            self.days = days
        }

        var isEmpty: Bool {
            days.values.allSatisfy { entries in
                entries.allSatisfy { $0.seconds <= 0 }
            }
        }
    }

    struct ActiveSegment: Equatable, Sendable {
        let app: AppIdentity
        var startedAt: Date
        let historyEpoch: UInt64
    }

    struct DaySummary: Equatable, Identifiable, Sendable {
        let dayKey: String
        let date: Date
        let totalSeconds: Int
        let isToday: Bool

        var id: String { dayKey }
    }

    struct AppUsageRow: Equatable, Identifiable, Sendable {
        let appID: String
        let displayName: String
        let seconds: Int
        /// Share of today's total in `0...1`.
        let share: Double

        var id: String { appID }
    }

    struct DashboardSnapshot: Equatable, Sendable {
        let todayKey: String
        let todayTotalSeconds: Int
        let sevenDayTotalSeconds: Int
        let lastSevenDays: [DaySummary]
        let todayApps: [AppUsageRow]

        static func empty(referenceDate: Date = Date(), calendar: Calendar = .current) -> DashboardSnapshot {
            dashboardSnapshot(from: UsageStore(), referenceDate: referenceDate, calendar: calendar)
        }
    }

    struct DurationParts: Equatable, Sendable {
        let hours: Int
        let minutes: Int
        let seconds: Int
    }

    enum StoreError: Error, Equatable, Sendable {
        case unsupportedVersion(Int)
        case malformedData
    }

    // MARK: - App Identity Sanitization

    /// Produces a minimal, privacy-safe app identity from a bundle identifier and localized name.
    /// Never retains paths, control characters, or excessive text; falls back deterministically
    /// when bundle ID is missing.
    static func normalizeApp(bundleID: String?, localizedName: String?) -> AppIdentity {
        let cleanName = sanitizeDisplayName(localizedName)
        let cleanBundle = sanitizeIdentifier(bundleID)

        if !cleanBundle.isEmpty {
            let display = cleanName.isEmpty ? cleanBundle : cleanName
            return AppIdentity(appID: cleanBundle, displayName: display)
        }

        if !cleanName.isEmpty {
            let slug = cleanName
                .lowercased()
                .unicodeScalars
                .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            let collapsed = String(slug)
                .split(separator: "-")
                .joined(separator: "-")
            let fallbackID = collapsed.isEmpty ? unknownAppID : "unidentified:\(collapsed)"
            return AppIdentity(appID: fallbackID, displayName: cleanName)
        }

        return AppIdentity(appID: unknownAppID, displayName: "")
    }

    private static func sanitizeIdentifier(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw
            .components(separatedBy: .newlines).first ?? ""
        let stripped = trimmed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
        return String(stripped.prefix(128))
    }

    private static func sanitizeDisplayName(_ raw: String?) -> String {
        guard let raw else { return "" }
        let singleLine = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .filter { $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
        let collapsed = singleLine
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(maxDisplayNameLength))
    }

    // MARK: - Day Keys & Calendar Helpers

    /// Formats `date` as `YYYY-MM-DD` in the given calendar/timeZone.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Parses a strict `YYYY-MM-DD` key into the local start-of-day `Date`.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              (1...12).contains(m),
              (1...31).contains(d) else {
            return nil
        }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let date = calendar.date(from: comps) else { return nil }
        // Reject impossible dates like 2026-02-31 that rolled over.
        guard dayKey(for: date, calendar: calendar) == key else { return nil }
        return date
    }

    // MARK: - Interval Attribution & Idle Rules

    struct CreditDecision: Equatable, Sendable {
        let creditedStart: Date
        let creditedEnd: Date
        let isNowIdle: Bool
    }

    /// Evaluates an elapsed interval `[start, end]` against backward clock jumps, unconfirmed forward
    /// jump caps, and HID idle time.
    ///
    /// - Returns: `nil` if no time should be credited (e.g., backward clock jump or already idle for the whole span).
    /// - Note: `isNowIdle` reports whether the user is currently idle at `end`.
    static func evaluateInterval(
        from start: Date,
        to end: Date,
        idleSeconds: TimeInterval,
        idleThreshold: TimeInterval = defaultIdleThresholdSeconds,
        maxSampleDelta: TimeInterval = defaultMaxSampleDeltaSeconds
    ) -> (credit: (start: Date, end: Date)?, isNowIdle: Bool) {
        let sanitizedIdle = idleSeconds.isFinite ? max(0, idleSeconds) : idleThreshold
        let isIdle = sanitizedIdle >= idleThreshold

        let rawDelta = end.timeIntervalSince(start)
        guard rawDelta > 0, rawDelta.isFinite else {
            return (nil, isIdle)
        }

        let effectiveEnd: Date
        if isIdle {
            // Only the active portion before inactivity began can be credited.
            let activeEndedAt = end.addingTimeInterval(-sanitizedIdle)
            guard activeEndedAt > start else {
                return (nil, true)
            }
            effectiveEnd = activeEndedAt
        } else {
            effectiveEnd = end
        }

        let clampedDelta = min(effectiveEnd.timeIntervalSince(start), max(1, maxSampleDelta))
        guard clampedDelta > 0 else {
            return (nil, isIdle)
        }

        let boundedEnd = start.addingTimeInterval(clampedDelta)
        return ((start: start, end: boundedEnd), isIdle)
    }

    /// Splits a non-negative `[start, end]` interval across local calendar day boundaries (midnight rollovers).
    static func splitInterval(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [(dayKey: String, seconds: TimeInterval)] {
        guard end > start else { return [] }

        var slices: [(dayKey: String, seconds: TimeInterval)] = []
        var cursor = start
        // Guard against pathological calendar loops (max 32 day splits).
        var guardCount = 0

        while cursor < end && guardCount < 32 {
            guardCount += 1
            let key = dayKey(for: cursor, calendar: calendar)
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  nextDayStart > cursor else {
                slices.append((key, end.timeIntervalSince(cursor)))
                break
            }

            let sliceEnd = min(end, nextDayStart)
            let dt = sliceEnd.timeIntervalSince(cursor)
            if dt > 0 {
                slices.append((key, dt))
            }
            cursor = sliceEnd
        }

        return slices
    }

    /// Credits `[start, end]` into `store`, splitting across midnight and carrying sub-second fractions
    /// per `(dayKey, appID)` so short bursts neither lose time nor inflate seconds.
    @discardableResult
    static func recordInterval(
        from start: Date,
        to end: Date,
        for app: AppIdentity,
        calendar: Calendar,
        into store: inout UsageStore,
        fractionalCarry: inout [String: Double]
    ) -> Int {
        let slices = splitInterval(from: start, to: end, calendar: calendar)
        var totalWholeAdded = 0

        for slice in slices {
            let carryKey = "\(slice.dayKey)|\(app.appID)"
            let total = (fractionalCarry[carryKey] ?? 0) + slice.seconds
            let whole = Int(total.rounded(.towardZero))
            fractionalCarry[carryKey] = total - Double(whole)

            if whole > 0 {
                record(seconds: whole, for: app, dayKey: slice.dayKey, into: &store)
                totalWholeAdded += whole
            }
        }

        return totalWholeAdded
    }

    /// Adds whole positive seconds for `app` on `dayKey` into `store`.
    static func record(
        seconds: Int,
        for app: AppIdentity,
        dayKey: String,
        into store: inout UsageStore
    ) {
        guard seconds > 0 else { return }
        var entries = store.days[dayKey] ?? []
        if let idx = entries.firstIndex(where: { $0.appID == app.appID }) {
            entries[idx].seconds += seconds
            if !app.displayName.isEmpty {
                entries[idx].displayName = app.displayName
            }
        } else {
            guard entries.count < maxAppsPerDay else { return }
            entries.append(AppDayEntry(appID: app.appID, displayName: app.displayName, seconds: seconds))
        }
        store.days[dayKey] = entries
    }

    // MARK: - Retention & Sanitization

    /// Drops malformed and expired days. Tolerates one day ahead after westward
    /// travel, while keeping no more than the configured number of day buckets.
    static func pruneRetention(
        in store: inout UsageStore,
        referenceDate: Date,
        calendar: Calendar,
        retentionDays: Int = retentionDays
    ) {
        let clampedDays = max(1, retentionDays)
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: todayStart),
              let maxDate = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return
        }

        var kept: [String: [AppDayEntry]] = [:]
        for (key, entries) in store.days {
            guard let dayDate = date(fromDayKey: key, calendar: calendar),
                  dayDate >= cutoffDate,
                  dayDate <= maxDate else {
                continue
            }
            let validEntries = entries.filter { $0.seconds > 0 && !$0.appID.isEmpty }
            if !validEntries.isEmpty {
                kept[key] = validEntries
            }
        }
        if kept.count > clampedDays {
            for key in kept.keys.sorted().prefix(kept.count - clampedDays) {
                kept.removeValue(forKey: key)
            }
        }
        store.days = kept
    }

    /// Normalizes a decoded store (merges duplicate app IDs per day, sanitizes names, prunes retention).
    static func sanitizeStore(
        _ raw: UsageStore,
        referenceDate: Date,
        calendar: Calendar,
        retentionDays: Int = retentionDays
    ) -> UsageStore {
        var out = UsageStore(version: storeSchemaVersion, days: [:])
        for (key, entries) in raw.days {
            guard date(fromDayKey: key, calendar: calendar) != nil else { continue }
            for entry in entries where entry.seconds > 0 {
                let normalized = normalizeApp(
                    bundleID: entry.appID.hasPrefix("unidentified:") ? nil : entry.appID,
                    localizedName: entry.displayName
                )
                let finalID = entry.appID.hasPrefix("unidentified:") ? entry.appID : normalized.appID
                let identity = AppIdentity(appID: finalID, displayName: normalized.displayName)
                record(seconds: entry.seconds, for: identity, dayKey: key, into: &out)
            }
        }
        pruneRetention(in: &out, referenceDate: referenceDate, calendar: calendar, retentionDays: retentionDays)
        return out
    }

    // MARK: - Persistence Codec

    static func decodeStore(from data: Data) throws -> UsageStore {
        let decoder = JSONDecoder()
        let decoded: UsageStore
        do {
            decoded = try decoder.decode(UsageStore.self, from: data)
        } catch {
            throw StoreError.malformedData
        }
        guard decoded.version == storeSchemaVersion else {
            throw StoreError.unsupportedVersion(decoded.version)
        }
        return decoded
    }

    static func encodeStore(_ store: UsageStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store)
    }

    // MARK: - Dashboard Snapshot & Formatting

    /// Builds the Today + 7-day chart + per-app breakdown snapshot for the UI.
    static func dashboardSnapshot(
        from store: UsageStore,
        referenceDate: Date,
        calendar: Calendar,
        topAppsLimit: Int = 12
    ) -> DashboardSnapshot {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let todayKey = dayKey(for: todayStart, calendar: calendar)

        var sevenDays: [DaySummary] = []
        var sevenDayTotal = 0
        for offset in stride(from: -(chartDays - 1), through: 0, by: 1) {
            let dayDate = calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
            let key = dayKey(for: dayDate, calendar: calendar)
            let total = (store.days[key] ?? []).reduce(0) { $0 + max(0, $1.seconds) }
            sevenDayTotal += total
            sevenDays.append(
                DaySummary(
                    dayKey: key,
                    date: dayDate,
                    totalSeconds: total,
                    isToday: offset == 0
                )
            )
        }

        let rawToday = (store.days[todayKey] ?? [])
            .filter { $0.seconds > 0 }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let todayTotal = rawToday.reduce(0) { $0 + $1.seconds }
        let limited = rawToday.prefix(max(1, topAppsLimit))
        let rows: [AppUsageRow] = limited.map { entry in
            let share = todayTotal > 0 ? min(1, max(0, Double(entry.seconds) / Double(todayTotal))) : 0
            return AppUsageRow(
                appID: entry.appID,
                displayName: entry.displayName,
                seconds: entry.seconds,
                share: share
            )
        }

        return DashboardSnapshot(
            todayKey: todayKey,
            todayTotalSeconds: todayTotal,
            sevenDayTotalSeconds: sevenDayTotal,
            lastSevenDays: sevenDays,
            todayApps: rows
        )
    }

    /// Splits a non-negative second count into hours, minutes, seconds for localized formatting in views.
    static func durationParts(seconds: Int) -> DurationParts {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return DurationParts(hours: hours, minutes: minutes, seconds: secs)
    }
}
