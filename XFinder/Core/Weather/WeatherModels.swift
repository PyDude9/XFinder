import Foundation

/// Pure Weather domain models for Dynamic Island Phase 2.
/// Kept Foundation-only so unit tests verify timezones, DST, serialization, and freshness without AppKit.

public struct WeatherLocation: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let region: String
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String
    public let isCurrentLocation: Bool

    public init(
        id: String,
        name: String,
        region: String = "",
        country: String = "",
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        isCurrentLocation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isCurrentLocation = isCurrentLocation
    }

    /// Formatted display name distinguishing cities with duplicate names
    /// (e.g. "Paris, Texas, Hoa Kỳ" vs "Paris, Île-de-France, Pháp").
    public var displayName: String {
        var parts: [String] = [name]
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRegion.isEmpty && cleanRegion.caseInsensitiveCompare(name) != .orderedSame {
            parts.append(cleanRegion)
        }
        if !cleanCountry.isEmpty {
            parts.append(cleanCountry)
        }
        return parts.joined(separator: ", ")
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
    }
}

public enum WeatherCondition: String, Equatable, Hashable, Codable, CaseIterable, Sendable {
    case clear
    case partlyCloudy
    case cloudy
    case drizzle
    case rain
    case heavyRain
    case thunderstorm
    case snow
    case fog
    case unknown

    public var sfSymbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .snow: return "snowflake"
        case .fog: return "cloud.fog.fill"
        case .unknown: return "cloud.fill"
        }
    }

    public var accessibilityLabelKey: String {
        switch self {
        case .clear: return "Trời quang"
        case .partlyCloudy: return "Ít mây"
        case .cloudy: return "Nhiều mây"
        case .drizzle: return "Mưa phùn"
        case .rain: return "Có mưa"
        case .heavyRain: return "Mưa to"
        case .thunderstorm: return "Dông sét"
        case .snow: return "Tuyết rơi"
        case .fog: return "Sương mù"
        case .unknown: return "Thời tiết không xác định"
        }
    }
}

public struct HourlyForecast: Equatable, Hashable, Codable, Sendable {
    public let date: Date
    public let temperatureCelsius: Double
    /// Optional precipitation probability in percent (0...100). Never fabricated if missing.
    public let precipitationProbability: Double?
    public let condition: WeatherCondition

    public init(
        date: Date,
        temperatureCelsius: Double,
        precipitationProbability: Double? = nil,
        condition: WeatherCondition
    ) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
        self.precipitationProbability = precipitationProbability
        self.condition = condition
    }

    /// Formats the hour strictly according to the location's specific TimeZone (accounting for DST).
    public func formattedHour(using timeZone: TimeZone, locale: Locale = Locale(identifier: "vi_VN")) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    public func formattedTemperature(useFahrenheit: Bool = false) -> String {
        if useFahrenheit {
            let f = (temperatureCelsius * 9.0 / 5.0) + 32.0
            return "\(Int(round(f)))°F"
        } else {
            return "\(Int(round(temperatureCelsius)))°"
        }
    }
}

public struct WeatherAttribution: Equatable, Hashable, Codable, Sendable {
    public let providerId: String
    public let serviceName: String
    public let legalURL: URL?
    public let markSymbol: String?

    public init(
        providerId: String,
        serviceName: String,
        legalURL: URL? = nil,
        markSymbol: String? = nil
    ) {
        self.providerId = providerId
        self.serviceName = serviceName
        self.legalURL = legalURL
        self.markSymbol = markSymbol
    }
}

public enum WeatherFreshness: Equatable, Sendable {
    case fresh
    case stale(age: TimeInterval)
    case expired

    public static func evaluate(
        fetchedAt: Date,
        now: Date,
        freshLimit: TimeInterval = 900,      // 15 minutes
        staleLimit: TimeInterval = 21600     // 6 hours
    ) -> WeatherFreshness {
        let age = max(0, now.timeIntervalSince(fetchedAt))
        if age < freshLimit {
            return .fresh
        } else if age <= staleLimit {
            return .stale(age: age)
        } else {
            return .expired
        }
    }
}

public struct WeatherSnapshot: Equatable, Codable, Sendable {
    public let location: WeatherLocation
    public let fetchedAt: Date
    public let attribution: WeatherAttribution
    public let hourly: [HourlyForecast]

    public init(
        location: WeatherLocation,
        fetchedAt: Date,
        attribution: WeatherAttribution,
        hourly: [HourlyForecast]
    ) {
        self.location = location
        self.fetchedAt = fetchedAt
        self.attribution = attribution
        self.hourly = hourly.sorted(by: { $0.date < $1.date })
    }

    /// Prunes past hours and extracts the upcoming 12 hours from `now`.
    /// If no future hours remain, returns an empty list.
    public func upcoming12Hours(from now: Date) -> [HourlyForecast] {
        let upcoming = hourly.filter { $0.date >= now }
        return Array(upcoming.prefix(12))
    }

    public func freshness(
        at now: Date,
        freshLimit: TimeInterval = 900,
        staleLimit: TimeInterval = 21600
    ) -> WeatherFreshness {
        WeatherFreshness.evaluate(
            fetchedAt: fetchedAt,
            now: now,
            freshLimit: freshLimit,
            staleLimit: staleLimit
        )
    }
}
