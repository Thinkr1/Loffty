//
//  WeatherTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Weather")
struct WeatherTests {
    @Test func temperatureConvertsAndRounds() {
        #expect(WeatherFormatting.temperature(16.4, metric: true) == 16)
        #expect(WeatherFormatting.temperature(16.6, metric: true) == 17)
        #expect(WeatherFormatting.temperature(0, metric: false) == 32)
        #expect(WeatherFormatting.temperature(16, metric: false) == 61)
        #expect(WeatherFormatting.temperatureLabel(16, metric: true) == "16°")
    }

    @Test func windLabelUsesLocaleUnits() {
        #expect(WeatherFormatting.windLabel(13, metric: true) == "13 km/h")
        #expect(WeatherFormatting.windLabel(16.093_44, metric: false) == "10 mph")
    }

    @Test func uvLabelRounds() {
        #expect(WeatherFormatting.uvLabel(3.2) == "UV 3")
        #expect(WeatherFormatting.uvLabel(3.6) == "UV 4")
    }

    @Test func weatherSymbolsMapWMOCodes() {
        #expect(WeatherSymbol.systemName(code: 0, isDay: true) == "sun.max.fill")
        #expect(
            WeatherSymbol.systemName(code: 0, isDay: false) == "moon.stars.fill"
        )
        #expect(WeatherSymbol.systemName(code: 3, isDay: true) == "cloud.fill")
        #expect(
            WeatherSymbol.systemName(code: 61, isDay: true) == "cloud.rain.fill"
        )
        #expect(
            WeatherSymbol.systemName(code: 95, isDay: true)
                == "cloud.bolt.rain.fill"
        )
    }

    @Test func isDayUsesMorningToEveningWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 12)
        )!
        let night = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 22)
        )!
        #expect(WeatherSymbol.isDay(at: day, calendar: calendar))
        #expect(!WeatherSymbol.isDay(at: night, calendar: calendar))
    }

    @Test func openMeteoParsesSnapshotAndUpcomingHours() throws {
        let json = """
            {
              "timezone": "UTC",
              "current": {
                "temperature_2m": 16.2,
                "weather_code": 61,
                "wind_speed_10m": 13.0,
                "uv_index": 3.1
              },
              "hourly": {
                "time": [
                  "2026-08-24T10:00",
                  "2026-08-24T11:00",
                  "2026-08-24T12:00",
                  "2026-08-24T13:00"
                ],
                "temperature_2m": [15.0, 15.5, 16.2, 17.0],
                "weather_code": [61, 61, 3, 2],
                "precipitation_probability": [80, 70, 20, 10],
                "precipitation": [1.2, 0.8, 0.0, 0.0]
              },
              "daily": {
                "time": ["2026-08-24", "2026-08-25", "2026-08-26"],
                "temperature_2m_max": [20.0, 21.0, 19.0],
                "temperature_2m_min": [14.0, 13.0, 12.0],
                "uv_index_max": [4.0, 5.0, 3.0],
                "weather_code": [61, 2, 0],
                "precipitation_probability_max": [80, 20, 0]
              }
            }
            """
        let now = OpenMeteo.parseDate(
            "2026-08-24T11:30",
            timeZone: TimeZone(identifier: "UTC")!
        )!
        let snap = try OpenMeteo.snapshot(
            from: Data(json.utf8),
            locality: "Vancouver",
            now: now
        )
        #expect(snap.locality == "Vancouver")
        #expect(snap.temperatureC == 16.2)
        #expect(snap.weatherCode == 61)
        #expect(snap.highC == 20)
        #expect(snap.lowC == 14)
        #expect(snap.uvIndex == 3.1)
        #expect(snap.windKmh == 13)
        #expect(snap.hours.count == 3)
        #expect(snap.hours.first?.temperatureC == 15.5)
        #expect(snap.hours.first?.precipChance == 70)
        #expect(snap.hours.first?.precipMm == 0.8)
        #expect(snap.days.count == 3)
        #expect(snap.days.first?.weatherCode == 61)
        #expect(snap.days[1].highC == 21)
    }

    @Test func forecastURLIncludesRequiredFields() {
        let url = OpenMeteo.forecastURL(latitude: 49.28, longitude: -123.12)
        let query = url.query ?? ""
        #expect(query.contains("latitude=49.28"))
        #expect(query.contains("longitude=-123.12"))
        #expect(query.contains("current="))
        #expect(query.contains("hourly="))
        #expect(query.contains("daily="))
        #expect(query.contains("timezone=auto"))
    }

    @Test func temperatureUnitPreferenceOverridesLocale() {
        #expect(
            WeatherTemperatureUnit.celsius.usesMetric(
                locale: Locale(identifier: "en_US")
            )
        )
        #expect(
            !WeatherTemperatureUnit.fahrenheit.usesMetric(
                locale: Locale(identifier: "fr_FR")
            )
        )
        #expect(
            WeatherTemperatureUnit.automatic.usesMetric(
                locale: Locale(identifier: "fr_FR")
            )
        )
        #expect(
            !WeatherTemperatureUnit.automatic.usesMetric(
                locale: Locale(identifier: "en_US")
            )
        )
    }

    @Test func hourLimitTrimsUpcomingHours() throws {
        let json = """
            {
              "timezone": "UTC",
              "current": { "temperature_2m": 16.0, "weather_code": 0 },
              "hourly": {
                "time": [
                  "2026-08-24T12:00",
                  "2026-08-24T13:00",
                  "2026-08-24T14:00",
                  "2026-08-24T15:00"
                ],
                "temperature_2m": [16, 17, 18, 19],
                "weather_code": [0, 0, 0, 0],
                "precipitation_probability": [0, 0, 0, 0]
              }
            }
            """
        let now = OpenMeteo.parseDate(
            "2026-08-24T12:00",
            timeZone: TimeZone(identifier: "UTC")!
        )!
        let snap = try OpenMeteo.snapshot(
            from: Data(json.utf8),
            locality: "Paris",
            now: now,
            hourLimit: 3
        )
        #expect(snap.hours.count == 3)
    }

    @Test func graphNormalizesAcrossRange() {
        #expect(WeatherGraph.normalized([]) == [])
        #expect(WeatherGraph.normalized([10, 10]) == [0.5, 0.5])
        #expect(WeatherGraph.normalized([0, 10]) == [0, 1])
    }
}

@Suite("Expanded page swipe")
struct ExpandedPageSwipeTests {
    @Test func verticalSwipeRequiresMoreDistance() {
        var recognizer = VerticalSwipeRecognizer()
        _ = recognizer.handle(.began(dx: 0, dy: 0))
        _ = recognizer.handle(.changed(dx: 0, dy: -50))
        #expect(recognizer.handle(.ended) == nil)
        _ = recognizer.handle(.began(dx: 0, dy: 0))
        _ = recognizer.handle(.changed(dx: 0, dy: -80))
        #expect(recognizer.handle(.ended) == 1)
    }

    @Test func weatherSlidesMoveVertically() {
        #expect(WeatherSlide.overview.neighbor(direction: 1) == .charts)
        #expect(WeatherSlide.charts.neighbor(direction: 1) == .forecast)
        #expect(WeatherSlide.forecast.neighbor(direction: 1) == nil)
        #expect(WeatherSlide.charts.neighbor(direction: -1) == .overview)
    }

    @Test func pageNeighborsAreSpatial() {
        #expect(ExpandedPage.music.neighbor(direction: 1) == .weather)
        #expect(ExpandedPage.music.neighbor(direction: -1) == nil)
        #expect(ExpandedPage.weather.neighbor(direction: -1) == .music)
        #expect(ExpandedPage.weather.neighbor(direction: 1) == nil)
    }

    @Test func storedPageRoundTrips() {
        let defaults = UserDefaults(suiteName: "loffty.weather.tests")!
        defaults.removeObject(forKey: ExpandedPage.storageKey)
        #expect(ExpandedPage.stored(in: defaults) == .music)
        defaults.set(ExpandedPage.weather.rawValue, forKey: ExpandedPage.storageKey)
        #expect(ExpandedPage.stored(in: defaults) == .weather)
        defaults.removePersistentDomain(forName: "loffty.weather.tests")
    }

    @Test func horizontalSwipeAdvancesOnLeftSwipe() {
        var recognizer = HorizontalSwipeRecognizer()
        recognizer.distanceThreshold = 20
        #expect(recognizer.handle(.began(dx: 0, dy: 0)) == nil)
        #expect(recognizer.handle(.changed(dx: -12, dy: 1)) == nil)
        #expect(recognizer.handle(.changed(dx: -12, dy: 0)) == nil)
        #expect(recognizer.handle(.ended) == 1)
    }

    @Test func horizontalSwipeIgnoresMostlyVerticalMotion() {
        var recognizer = HorizontalSwipeRecognizer()
        recognizer.distanceThreshold = 20
        _ = recognizer.handle(.began(dx: 0, dy: 0))
        _ = recognizer.handle(.changed(dx: -10, dy: -40))
        #expect(recognizer.handle(.ended) == nil)
    }

    @Test func tickGestureProducesImmediateTurn() {
        var recognizer = HorizontalSwipeRecognizer()
        #expect(recognizer.handle(.tick(dx: -20, dy: 1)) == 1)
        #expect(recognizer.handle(.tick(dx: 20, dy: 1)) == -1)
        #expect(recognizer.handle(.tick(dx: 2, dy: 20)) == nil)
    }
}
