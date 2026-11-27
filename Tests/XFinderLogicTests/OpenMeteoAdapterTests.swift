import XCTest

final class OpenMeteoAdapterTests: XCTestCase {

    private func makeLocation(id: String = "loc-danang") -> WeatherLocation {
        WeatherLocation(
            id: id,
            name: "Đà Nẵng",
            region: "Đà Nẵng",
            country: "Việt Nam",
            latitude: 16.0678,
            longitude: 108.2208,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh"
        )
    }

    // MARK: - 1. Geocoding Parsing with Unicode (Vietnamese, Diacritics)
    func testGeocodingUnicodeParsing() throws {
        let jsonString = """
        {
          "results": [
            {
              "id": 1566083,
              "name": "Thành phố Hồ Chí Minh",
              "latitude": 10.823,
              "longitude": 106.6296,
              "timezone": "Asia/Ho_Chi_Minh",
              "country": "Việt Nam",
              "admin1": "Thành phố Hồ Chí Minh"
            },
            {
              "id": 1583992,
              "name": "Đà Nẵng",
              "latitude": 16.0678,
              "longitude": 108.2208,
              "timezone": "Asia/Ho_Chi_Minh",
              "country": "Việt Nam",
              "admin1": "Đà Nẵng"
            }
          ]
        }
        """
        let data = jsonString.data(using: .utf8)!
        let locations = try OpenMeteoAdapter.decodeGeocodingResponse(data: data)

        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].id, "open-meteo:1566083")
        XCTAssertEqual(locations[0].name, "Thành phố Hồ Chí Minh")
        XCTAssertEqual(locations[0].country, "Việt Nam")
        XCTAssertEqual(locations[0].timeZoneIdentifier, "Asia/Ho_Chi_Minh")

        XCTAssertEqual(locations[1].id, "open-meteo:1583992")
        XCTAssertEqual(locations[1].name, "Đà Nẵng")
    }

    // MARK: - 2. Forecast Decoding with Unix Time & DST
    func testForecastUnixTimeAndDSTDecoding() throws {
        // Unix times: 1784116800 (12:00 UTC), 1784120400 (13:00 UTC)
        let jsonString = """
        {
          "hourly": {
            "time": [1784116800, 1784120400],
            "temperature_2m": [31.5, 30.2],
            "precipitation_probability": [25, 60],
            "weather_code": [0, 80]
          }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let loc = makeLocation()
        let attribution = WeatherAttribution(providerId: "open-meteo", serviceName: "Open-Meteo")

        let snapshot = try OpenMeteoAdapter.decodeForecastResponse(
            data: data,
            for: loc,
            attribution: attribution
        )

        XCTAssertEqual(snapshot.hourly.count, 2)
        XCTAssertEqual(snapshot.hourly[0].date, Date(timeIntervalSince1970: 1784116800))
        XCTAssertEqual(snapshot.hourly[0].temperatureCelsius, 31.5)
        XCTAssertEqual(snapshot.hourly[0].precipitationProbability, 25.0)
        XCTAssertEqual(snapshot.hourly[0].condition, .clear)

        XCTAssertEqual(snapshot.hourly[1].date, Date(timeIntervalSince1970: 1784120400))
        XCTAssertEqual(snapshot.hourly[1].temperatureCelsius, 30.2)
        XCTAssertEqual(snapshot.hourly[1].precipitationProbability, 60.0)
        XCTAssertEqual(snapshot.hourly[1].condition, .heavyRain)
    }

    // MARK: - 3. Mismatched, null, and partial arrays
    func testMismatchedAndNullArraysSafety() throws {
        // 3 timestamps, but temperature has 1 null, precip array has only 1 element
        let jsonString = """
        {
          "hourly": {
            "time": [1784116800, 1784120400, 1784124000],
            "temperature_2m": [28.0, null, 27.5],
            "precipitation_probability": [10],
            "weather_code": [1, 2, 3]
          }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let loc = makeLocation()
        let attribution = WeatherAttribution(providerId: "open-meteo", serviceName: "Open-Meteo")

        let snapshot = try OpenMeteoAdapter.decodeForecastResponse(
            data: data,
            for: loc,
            attribution: attribution
        )

        // Index 1 has null temp, so it is skipped. Total decoded items = 2
        XCTAssertEqual(snapshot.hourly.count, 2)
        XCTAssertEqual(snapshot.hourly[0].date, Date(timeIntervalSince1970: 1784116800))
        XCTAssertEqual(snapshot.hourly[0].precipitationProbability, 10.0)

        // Index 2 is beyond precipitation array bounds, safely decoded as nil!
        XCTAssertEqual(snapshot.hourly[1].date, Date(timeIntervalSince1970: 1784124000))
        XCTAssertNil(snapshot.hourly[1].precipitationProbability)
        XCTAssertEqual(snapshot.hourly[1].condition, .cloudy)
    }

    // MARK: - 4. Transport Error Handling: 429, 503, Offline, Cancellation
    func testTransportErrorHandling() async {
        let loc = makeLocation()

        // 4.1. Rate Limited (HTTP 429)
        let rateLimitedTransport: OpenMeteoAdapter.HTTPTransport = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.open-meteo.com")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let adapter429 = OpenMeteoAdapter(transport: rateLimitedTransport)
        do {
            _ = try await adapter429.fetchForecast(for: loc)
            XCTFail("Expected rateLimited error")
        } catch let err as WeatherError {
            XCTAssertEqual(err, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 4.2. Server Error (HTTP 503)
        let serverErrorTransport: OpenMeteoAdapter.HTTPTransport = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.open-meteo.com")!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let adapter503 = OpenMeteoAdapter(transport: serverErrorTransport)
        do {
            _ = try await adapter503.fetchForecast(for: loc)
            XCTFail("Expected serverError")
        } catch let err as WeatherError {
            XCTAssertEqual(err, .serverError(statusCode: 503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 4.3. Offline Network Error
        let offlineTransport: OpenMeteoAdapter.HTTPTransport = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let adapterOffline = OpenMeteoAdapter(transport: offlineTransport)
        do {
            _ = try await adapterOffline.fetchForecast(for: loc)
            XCTFail("Expected networkUnavailable error")
        } catch let err as WeatherError {
            XCTAssertEqual(err, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 4.4. Cancellation Error
        let cancelledTransport: OpenMeteoAdapter.HTTPTransport = { _ in
            throw URLError(.cancelled)
        }
        let adapterCancelled = OpenMeteoAdapter(transport: cancelledTransport)
        do {
            _ = try await adapterCancelled.fetchForecast(for: loc)
            XCTFail("Expected cancelled error")
        } catch let err as WeatherError {
            XCTAssertEqual(err, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
