import Foundation

/// Pure Weather cache management with strict TTL limits and corrupted/version miss handling.
/// 15 minutes fresh, max 6 hours stale. Prunes past entries and caps total stored entries.

public struct WeatherCacheRecord: Codable, Sendable {
    public let version: Int
    public let providerId: String
    public let locationId: String
    public let snapshot: WeatherSnapshot

    public init(providerId: String, locationId: String, snapshot: WeatherSnapshot, version: Int = 1) {
        self.version = version
        self.providerId = providerId
        self.locationId = locationId
        self.snapshot = snapshot
    }
}

public final class WeatherCacheStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: WeatherCacheRecord] = [:]
    public let maxStoredEntries: Int
    public let freshLimit: TimeInterval
    public let staleLimit: TimeInterval

    public static let currentVersion = 1

    public init(
        maxStoredEntries: Int = 10,
        freshLimit: TimeInterval = 900,      // 15 mins
        staleLimit: TimeInterval = 21600     // 6 hours
    ) {
        self.maxStoredEntries = maxStoredEntries
        self.freshLimit = freshLimit
        self.staleLimit = staleLimit
    }

    public static func makeCacheKey(providerId: String, locationId: String) -> String {
        "\(providerId):\(locationId)"
    }

    public func get(
        providerId: String,
        locationId: String,
        now: Date
    ) -> (snapshot: WeatherSnapshot, freshness: WeatherFreshness)? {
        lock.lock()
        defer { lock.unlock() }

        let key = Self.makeCacheKey(providerId: providerId, locationId: locationId)
        guard let record = entries[key] else {
            return nil
        }

        // Version mismatch or provider mismatch treated as cache miss
        guard record.version == Self.currentVersion, record.providerId == providerId else {
            entries.removeValue(forKey: key)
            return nil
        }

        let freshness = WeatherFreshness.evaluate(
            fetchedAt: record.snapshot.fetchedAt,
            now: now,
            freshLimit: freshLimit,
            staleLimit: staleLimit
        )

        switch freshness {
        case .fresh, .stale:
            // Check if upcoming hours still exist from `now`
            let upcoming = record.snapshot.upcoming12Hours(from: now)
            guard !upcoming.isEmpty else {
                // If all hours in the cache are in the past, treat as expired miss
                return nil
            }
            return (record.snapshot, freshness)
        case .expired:
            entries.removeValue(forKey: key)
            return nil
        }
    }

    public func set(snapshot: WeatherSnapshot, providerId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let effectiveProviderId = providerId ?? snapshot.attribution.providerId
        let key = Self.makeCacheKey(providerId: effectiveProviderId, locationId: snapshot.location.id)
        let record = WeatherCacheRecord(
            providerId: effectiveProviderId,
            locationId: snapshot.location.id,
            snapshot: snapshot,
            version: Self.currentVersion
        )
        entries[key] = record

        // Enforce max count by removing oldest fetched records
        if entries.count > maxStoredEntries {
            let sortedKeys = entries.keys.sorted { k1, k2 in
                let t1 = entries[k1]?.snapshot.fetchedAt ?? .distantPast
                let t2 = entries[k2]?.snapshot.fetchedAt ?? .distantPast
                return t1 < t2
            }
            let overflowCount = entries.count - maxStoredEntries
            for oldKey in sortedKeys.prefix(overflowCount) {
                entries.removeValue(forKey: oldKey)
            }
        }
    }

    public func remove(providerId: String, locationId: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.makeCacheKey(providerId: providerId, locationId: locationId)
        entries.removeValue(forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
