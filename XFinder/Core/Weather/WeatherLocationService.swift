import Foundation

/// Persistent store abstraction for the user's manual city selection.
/// Strictly refuses to store precise device coordinates when `isCurrentLocation == true`.
public protocol WeatherLocationStore: Sendable {
    func loadSavedLocation() -> WeatherLocation?
    func saveLocation(_ location: WeatherLocation)
    func clearSavedLocation()
}

/// UserDefaults-backed implementation of `WeatherLocationStore`.
public final class UserDefaultsWeatherLocationStore: WeatherLocationStore, @unchecked Sendable {
    public static let defaultKey = "weather.savedLocation"

    private let key: String
    private let defaults: UserDefaults

    public init(key: String = defaultKey, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func loadSavedLocation() -> WeatherLocation? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let location = try? JSONDecoder().decode(WeatherLocation.self, from: data) else { return nil }
        // Defensive check: never restore device coordinates from disk
        if location.isCurrentLocation {
            return nil
        }
        return location
    }

    public func saveLocation(_ location: WeatherLocation) {
        // Enforce privacy rule: Do not persist device coordinates if marked as currentLocation
        guard !location.isCurrentLocation else { return }
        if let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: key)
        }
    }

    public func clearSavedLocation() {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory implementation of `WeatherLocationStore` for tests and previews.
public final class InMemoryWeatherLocationStore: WeatherLocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: WeatherLocation?

    public init(initial: WeatherLocation? = nil) {
        self.stored = initial
    }

    public func loadSavedLocation() -> WeatherLocation? {
        lock.lock()
        defer { lock.unlock() }
        if let s = stored, s.isCurrentLocation { return nil }
        return stored
    }

    public func saveLocation(_ location: WeatherLocation) {
        lock.lock()
        defer { lock.unlock() }
        guard !location.isCurrentLocation else { return }
        self.stored = location
    }

    public func clearSavedLocation() {
        lock.lock()
        defer { lock.unlock() }
        self.stored = nil
    }
}

/// Abstraction for location services.
/// Fulfills opt-in location rule without hardcoding secrets or unauthorized system calls.
public protocol WeatherLocationService: Sendable {
    func requestCurrentLocation() async throws -> WeatherLocation
}

/// Default implementation when CoreLocation entitlement is not configured in Info.plist.
/// Cleanly reports `WeatherError.locationDenied` so the UI falls back to manual city selection.
public struct DefaultWeatherLocationService: WeatherLocationService {
    public init() {}

    public func requestCurrentLocation() async throws -> WeatherLocation {
        // XFinder does not declare NSLocationWhenInUseUsageDescription in Info.plist.
        // Editing Info.plist is strictly forbidden for Builders.
        // Therefore, native device location is denied / unavailable by configuration.
        throw WeatherError.locationDenied
    }
}

/// Mock location service for tests.
public struct MockWeatherLocationService: WeatherLocationService {
    private let stubbedLocation: WeatherLocation?
    private let errorToThrow: WeatherError?

    public init(stubbedLocation: WeatherLocation? = nil, errorToThrow: WeatherError? = nil) {
        self.stubbedLocation = stubbedLocation
        self.errorToThrow = errorToThrow
    }

    public func requestCurrentLocation() async throws -> WeatherLocation {
        if let err = errorToThrow {
            throw err
        }
        guard let loc = stubbedLocation else {
            throw WeatherError.locationDenied
        }
        return loc
    }
}
