import Foundation

/// Open-Meteo Weather API adapter with injectable HTTP transport.
/// Uses zero network when an in-memory transport is injected (ideal for tests with static fixtures).
///
/// NOTE on terms & licensing:
/// Open-Meteo Free API (https://open-meteo.com/en/terms) is restricted to non-commercial use.
/// Because XFinder contains commercial Pro features, this adapter must not be enabled as a default
/// commercial provider without an approved Open-Meteo commercial subscription or explicit owner decision.

public final class OpenMeteoAdapter: WeatherProvider, Sendable {
    public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let id: String = "open-meteo"
    public let attribution: WeatherAttribution

    public let forecastBaseURL: URL
    public let geocodingBaseURL: URL
    private let transport: HTTPTransport
    private let clock: @Sendable () -> Date

    public init(
        forecastBaseURL: URL = URL(string: "https://api.open-meteo.com")!,
        geocodingBaseURL: URL = URL(string: "https://geocoding-api.open-meteo.com")!,
        attribution: WeatherAttribution = WeatherAttribution(
            providerId: "open-meteo",
            serviceName: "Open-Meteo",
            legalURL: URL(string: "https://open-meteo.com/"),
            markSymbol: "cloud.sun.fill"
        ),
        transport: HTTPTransport? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.forecastBaseURL = forecastBaseURL
        self.geocodingBaseURL = geocodingBaseURL
        self.attribution = attribution
        self.clock = clock
        if let transport = transport {
            self.transport = transport
        } else {
            self.transport = { request in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw WeatherError.invalidData
                }
                return (data, httpResponse)
            }
        }
    }

    // MARK: - WeatherProvider

    public func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
        guard var components = URLComponents(url: forecastBaseURL.appendingPathComponent("v1/forecast"), resolvingAgainstBaseURL: false) else {
            throw WeatherError.invalidData
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]

        guard let url = components.url else {
            throw WeatherError.invalidData
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport(request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw WeatherError.cancelled
            }
            if let urlErr = error as? URLError {
                switch urlErr.code {
                case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                    throw WeatherError.networkUnavailable
                case .timedOut:
                    throw WeatherError.timeout
                default:
                    throw WeatherError.networkUnavailable
                }
            }
            throw WeatherError.unknown(error.localizedDescription)
        }

        if response.statusCode == 429 {
            throw WeatherError.rateLimited
        } else if response.statusCode >= 500 {
            throw WeatherError.serverError(statusCode: response.statusCode)
        } else if response.statusCode != 200 {
            throw WeatherError.serverError(statusCode: response.statusCode)
        }

        return try Self.decodeForecastResponse(
            data: data,
            for: location,
            attribution: attribution,
            fetchedAt: clock()
        )
    }

    public func searchLocations(query: String) async throws -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        guard var components = URLComponents(url: geocodingBaseURL.appendingPathComponent("v1/search"), resolvingAgainstBaseURL: false) else {
            throw WeatherError.invalidData
        }

        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "vi,en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else {
            throw WeatherError.invalidData
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport(request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw WeatherError.cancelled
            }
            if let urlErr = error as? URLError {
                switch urlErr.code {
                case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost:
                    throw WeatherError.networkUnavailable
                case .timedOut:
                    throw WeatherError.timeout
                default:
                    throw WeatherError.networkUnavailable
                }
            }
            throw WeatherError.unknown(error.localizedDescription)
        }

        if response.statusCode == 429 {
            throw WeatherError.rateLimited
        } else if response.statusCode != 200 {
            throw WeatherError.serverError(statusCode: response.statusCode)
        }

        return try Self.decodeGeocodingResponse(data: data)
    }

    // MARK: - Decoding helpers (Pure)

    public static func decodeGeocodingResponse(data: Data) throws -> [WeatherLocation] {
        struct GeocodingRoot: Decodable {
            struct ResultItem: Decodable {
                let id: Int
                let name: String
                let latitude: Double
                let longitude: Double
                let timezone: String?
                let country: String?
                let admin1: String?
            }
            let results: [ResultItem]?
        }

        let root: GeocodingRoot
        do {
            root = try JSONDecoder().decode(GeocodingRoot.self, from: data)
        } catch {
            throw WeatherError.invalidData
        }

        guard let items = root.results, !items.isEmpty else {
            return []
        }

        return items.map { item in
            WeatherLocation(
                id: "open-meteo:\(item.id)",
                name: item.name,
                region: item.admin1 ?? "",
                country: item.country ?? "",
                latitude: item.latitude,
                longitude: item.longitude,
                timeZoneIdentifier: item.timezone ?? "UTC",
                isCurrentLocation: false
            )
        }
    }

    public static func decodeForecastResponse(
        data: Data,
        for location: WeatherLocation,
        attribution: WeatherAttribution,
        fetchedAt: Date = Date()
    ) throws -> WeatherSnapshot {
        struct ForecastRoot: Decodable {
            struct HourlyData: Decodable {
                let time: [Int]?
                let temperature_2m: [Double?]?
                let precipitation_probability: [Double?]?
                let weather_code: [Int?]?
            }
            let hourly: HourlyData?
        }

        let root: ForecastRoot
        do {
            root = try JSONDecoder().decode(ForecastRoot.self, from: data)
        } catch {
            throw WeatherError.invalidData
        }

        guard let hourly = root.hourly,
              let times = hourly.time,
              let temps = hourly.temperature_2m,
              let codes = hourly.weather_code,
              !times.isEmpty else {
            throw WeatherError.invalidData
        }

        // Handle array size discrepancies safely by taking the minimum non-nil count
        let count = min(times.count, temps.count, codes.count)
        guard count > 0 else {
            throw WeatherError.invalidData
        }

        var forecasts: [HourlyForecast] = []
        forecasts.reserveCapacity(count)

        let precips = hourly.precipitation_probability

        for i in 0..<count {
            let unixTime = times[i]
            guard let temp = temps[i] else {
                continue
            }
            let code = codes[i] ?? -1
            let precip: Double? = (precips != nil && i < precips!.count) ? precips![i] : nil

            let date = Date(timeIntervalSince1970: TimeInterval(unixTime))
            let condition = mapWMOWeatherCode(code)

            forecasts.append(
                HourlyForecast(
                    date: date,
                    temperatureCelsius: temp,
                    precipitationProbability: precip,
                    condition: condition
                )
            )
        }

        guard !forecasts.isEmpty else {
            throw WeatherError.invalidData
        }

        return WeatherSnapshot(
            location: location,
            fetchedAt: fetchedAt,
            attribution: attribution,
            hourly: forecasts
        )
    }

    /// Maps standard WMO Weather interpretation codes to WeatherCondition.
    public static func mapWMOWeatherCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0:
            return .clear
        case 1, 2:
            return .partlyCloudy
        case 3:
            return .cloudy
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57:
            return .drizzle
        case 61, 63, 65:
            return .rain
        case 66, 67:
            return .snow
        case 71, 73, 75, 77:
            return .snow
        case 80, 81, 82:
            return .heavyRain
        case 85, 86:
            return .snow
        case 95, 96, 99:
            return .thunderstorm
        default:
            return .unknown
        }
    }
}
