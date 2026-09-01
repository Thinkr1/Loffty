//
//  Weather.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 23/08/2026.
//

import AppKit
import Combine
import CoreLocation
import Foundation

struct WeatherHour: Codable, Equatable, Sendable {
    var date: Date
    var temperatureC: Double
    var weatherCode: Int
    var precipChance: Int
    var precipMm: Double
}

struct WeatherDay: Codable, Equatable, Sendable {
    var date: Date
    var highC: Double
    var lowC: Double
    var weatherCode: Int
    var precipChance: Int
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    var locality: String
    var temperatureC: Double
    var weatherCode: Int
    var highC: Double
    var lowC: Double
    var uvIndex: Double
    var windKmh: Double
    var hours: [WeatherHour]
    var days: [WeatherDay]
    var fetchedAt: Date
    var isDay: Bool
}

enum WeatherGraph {
    nonisolated static func normalized(_ values: [Double]) -> [CGFloat] {
        guard let min = values.min(), let max = values.max() else { return [] }
        let span = max - min
        if span < 0.01 {
            return values.map { _ in 0.5 }
        }
        return values.map { CGFloat(($0 - min) / span) }
    }

    nonisolated static func currentIndex(
        in hours: [WeatherHour],
        now: Date = Date()
    ) -> Int {
        var index = 0
        for (offset, hour) in hours.enumerated() where hour.date <= now {
            index = offset
        }
        return index
    }
}

enum WeatherHourList {
    nonisolated static func upcoming(
        _ hours: [WeatherHour],
        now: Date = Date(),
        limit: Int
    ) -> [WeatherHour] {
        let future = hours.filter { $0.date > now }
        let source = future.isEmpty ? hours : future
        return Array(source.prefix(max(0, limit)))
    }
}

enum WeatherCache {
    static let storageKey = "weather.cachedSnapshot.v1"

    struct Record: Codable, Equatable, Sendable {
        var snapshot: WeatherSnapshot
        var latitude: Double
        var longitude: Double
        var locationMode: String
        var manualQuery: String
    }

    nonisolated static func isFresh(
        fetchedAt: Date,
        now: Date = Date(),
        interval: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(fetchedAt) < interval
    }

    nonisolated static func isNearby(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
        meters: Double = 2500
    ) -> Bool {
        let a = CLLocation(latitude: lat1, longitude: lon1)
        let b = CLLocation(latitude: lat2, longitude: lon2)
        return a.distance(from: b) <= meters
    }

    nonisolated static func matches(
        _ record: Record,
        mode: WeatherLocationMode,
        manualQuery: String
    ) -> Bool {
        guard record.locationMode == mode.rawValue else { return false }
        if mode == .manual {
            return record.manualQuery == manualQuery
        }
        return true
    }

    static func load(from defaults: UserDefaults = .standard) -> Record? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Record.self, from: data)
    }

    static func save(_ record: Record, to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

enum WeatherStatus: Equatable, Sendable {
    case idle
    case locating
    case needsPermission
    case ready
    case denied
    case failed
}

enum WeatherFormatting {
    nonisolated static func usesMetric(_ locale: Locale = .current) -> Bool {
        locale.measurementSystem == .metric
    }

    nonisolated static func usesMetricTemperature(
        _ preference: WeatherTemperatureUnit,
        locale: Locale = .current
    ) -> Bool {
        preference.usesMetric(locale: locale)
    }

    nonisolated static func usesMetricWind(
        _ preference: WeatherWindUnit,
        locale: Locale = .current
    ) -> Bool {
        preference.usesMetric(locale: locale)
    }

    nonisolated static func temperature(
        _ celsius: Double,
        metric: Bool
    ) -> Int {
        let value = metric ? celsius : celsius * 9 / 5 + 32
        return Int(value.rounded())
    }

    nonisolated static func temperatureLabel(
        _ celsius: Double,
        metric: Bool
    ) -> String {
        "\(temperature(celsius, metric: metric))°"
    }

    nonisolated static func highLowLabel(
        highC: Double,
        lowC: Double,
        metric: Bool
    ) -> String {
        "H:\(temperatureLabel(highC, metric: metric)) L:\(temperatureLabel(lowC, metric: metric))"
    }

    nonisolated static func windLabel(
        _ kmh: Double,
        metric: Bool
    ) -> String {
        if metric {
            return "\(Int(kmh.rounded())) km/h"
        }
        let mph = kmh / 1.609_344
        return "\(Int(mph.rounded())) mph"
    }

    nonisolated static func uvLabel(_ uv: Double) -> String {
        "UV \(Int(uv.rounded()))"
    }

    nonisolated static func precipChanceLabel(_ percent: Int) -> String {
        "\(max(0, min(100, percent)))%"
    }

    nonisolated static func conditionLabel(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunder"
        default: "Cloudy"
        }
    }

    nonisolated static func hourLabel(
        _ date: Date,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    nonisolated static func weekdayLabel(
        _ date: Date,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

enum WeatherSymbol {
    nonisolated static func systemName(code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1:
            return isDay ? "sun.min.fill" : "moon.fill"
        case 2:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67:
            return "cloud.rain.fill"
        case 71, 73, 75, 77:
            return "cloud.snow.fill"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        }
    }

    nonisolated static func isDay(at date: Date, calendar: Calendar = .current)
        -> Bool
    {
        let hour = calendar.component(.hour, from: date)
        return hour >= 6 && hour < 19
    }
}

enum OpenMeteo {
    nonisolated struct Forecast: Decodable, Sendable {
        var timezone: String?
        var current: Current?
        var hourly: Hourly?
        var daily: Daily?

        nonisolated struct Current: Decodable, Sendable {
            var temperature2m: Double?
            var weatherCode: Int?
            var windSpeed10m: Double?
            var uvIndex: Double?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case uvIndex = "uv_index"
            }
        }

        nonisolated struct Hourly: Decodable, Sendable {
            var time: [String]
            var temperature2m: [Double]?
            var weatherCode: [Int]?
            var precipitationProbability: [Int]?
            var precipitation: [Double]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability"
                case precipitation
            }
        }

        nonisolated struct Daily: Decodable, Sendable {
            var time: [String]?
            var temperature2mMax: [Double]?
            var temperature2mMin: [Double]?
            var uvIndexMax: [Double]?
            var weatherCode: [Int]?
            var precipitationProbabilityMax: [Int]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case uvIndexMax = "uv_index_max"
                case weatherCode = "weather_code"
                case precipitationProbabilityMax =
                    "precipitation_probability_max"
            }
        }
    }

    nonisolated static func parseDate(
        _ raw: String,
        timeZone: TimeZone
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = formatter.date(from: raw) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    nonisolated static func upcomingHours(
        from forecast: Forecast,
        now: Date,
        limit: Int = 6
    ) -> [WeatherHour] {
        guard let hourly = forecast.hourly else { return [] }
        let zone =
            forecast.timezone.flatMap { TimeZone(identifier: $0) }
            ?? .current
        let temps = hourly.temperature2m ?? []
        let codes = hourly.weatherCode ?? []
        let precip = hourly.precipitationProbability ?? []
        let mm = hourly.precipitation ?? []
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: now)?.start ?? now

        var hours: [WeatherHour] = []
        hours.reserveCapacity(limit)
        for (index, raw) in hourly.time.enumerated() {
            guard hours.count < limit,
                let date = parseDate(raw, timeZone: zone),
                date >= start
            else { continue }
            hours.append(
                WeatherHour(
                    date: date,
                    temperatureC: index < temps.count
                        ? temps[index] : 0,
                    weatherCode: index < codes.count ? codes[index] : 0,
                    precipChance: index < precip.count ? precip[index] : 0,
                    precipMm: index < mm.count ? mm[index] : 0
                )
            )
        }
        return hours
    }

    nonisolated static func upcomingDays(
        from forecast: Forecast,
        now: Date,
        limit: Int = 5
    ) -> [WeatherDay] {
        guard let daily = forecast.daily, let times = daily.time else {
            return []
        }
        let zone =
            forecast.timezone.flatMap { TimeZone(identifier: $0) }
            ?? .current
        let highs = daily.temperature2mMax ?? []
        let lows = daily.temperature2mMin ?? []
        let codes = daily.weatherCode ?? []
        let precip = daily.precipitationProbabilityMax ?? []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        var days: [WeatherDay] = []
        days.reserveCapacity(limit)
        for (index, raw) in times.enumerated() {
            guard days.count < limit else { break }
            let date =
                parseDate(raw + "T00:00", timeZone: zone)
                ?? parseDate(raw, timeZone: zone)
            guard let date, calendar.startOfDay(for: date) >= today else {
                continue
            }
            days.append(
                WeatherDay(
                    date: date,
                    highC: index < highs.count ? highs[index] : 0,
                    lowC: index < lows.count ? lows[index] : 0,
                    weatherCode: index < codes.count ? codes[index] : 0,
                    precipChance: index < precip.count ? precip[index] : 0
                )
            )
        }
        return days
    }

    nonisolated static func snapshot(
        from data: Data,
        locality: String,
        now: Date = Date(),
        hourLimit: Int = 24
    ) throws -> WeatherSnapshot {
        let forecast = try JSONDecoder().decode(Forecast.self, from: data)
        let current = forecast.current
        let hours = upcomingHours(from: forecast, now: now, limit: hourLimit)
        let days = upcomingDays(from: forecast, now: now)
        let temp = current?.temperature2m ?? hours.first?.temperatureC ?? 0
        let code = current?.weatherCode ?? hours.first?.weatherCode ?? 0
        return WeatherSnapshot(
            locality: locality,
            temperatureC: temp,
            weatherCode: code,
            highC: forecast.daily?.temperature2mMax?.first ?? temp,
            lowC: forecast.daily?.temperature2mMin?.first ?? temp,
            uvIndex: current?.uvIndex
                ?? forecast.daily?.uvIndexMax?.first ?? 0,
            windKmh: current?.windSpeed10m ?? 0,
            hours: hours,
            days: days,
            fetchedAt: now,
            isDay: WeatherSymbol.isDay(at: now)
        )
    }

    nonisolated static func forecastURL(
        latitude: Double,
        longitude: Double
    ) -> URL {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast"
        )!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value:
                    "temperature_2m,weather_code,wind_speed_10m,uv_index"
            ),
            URLQueryItem(
                name: "hourly",
                value:
                    "temperature_2m,weather_code,precipitation_probability,precipitation"
            ),
            URLQueryItem(
                name: "daily",
                value:
                    "weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_probability_max"
            ),
            URLQueryItem(name: "forecast_hours", value: "24"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components.url!
    }
}

@MainActor
final class WeatherController: NSObject, ObservableObject {
    static let shared = WeatherController()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: WeatherStatus = .idle

    var refreshInterval: TimeInterval {
        AppSettings.shared.weatherRefreshMinutes * 60
    }
    var fetch: (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
            !(200..<300).contains(http.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private var location = CLLocationManager()
    private var lastCoordinate: CLLocationCoordinate2D?
    private var fetchTask: Task<Void, Never>?
    private var manualLocationTask: Task<Void, Never>?
    private var locationRetryTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var locationAttempts = 0
    private var accessWindow: NSWindow?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var cacheRecord: WeatherCache.Record?

    override init() {
        super.init()
        configureLocationManager()
        restoreCache()
    }

    private func configureLocationManager() {
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private var hasFreshSnapshot: Bool {
        guard let snapshot,
            WeatherCache.isFresh(
                fetchedAt: snapshot.fetchedAt,
                interval: refreshInterval
            )
        else { return false }
        guard let cacheRecord else { return true }
        return WeatherCache.matches(
            cacheRecord,
            mode: AppSettings.shared.weatherLocationMode,
            manualQuery: AppSettings.shared.weatherManualLocation
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func restoreCache() {
        guard snapshot == nil,
            let record = WeatherCache.load(),
            WeatherCache.matches(
                record,
                mode: AppSettings.shared.weatherLocationMode,
                manualQuery: AppSettings.shared.weatherManualLocation
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        else { return }
        cacheRecord = record
        snapshot = record.snapshot
        lastCoordinate = CLLocationCoordinate2D(
            latitude: record.latitude,
            longitude: record.longitude
        )
        status = .ready
    }

    private func persistCache(for location: CLLocation) {
        guard let snapshot else { return }
        let record = WeatherCache.Record(
            snapshot: snapshot,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            locationMode: AppSettings.shared.weatherLocationMode.rawValue,
            manualQuery: AppSettings.shared.weatherManualLocation
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cacheRecord = record
        WeatherCache.save(record)
    }

    func prepare(forcePrompt: Bool = false) {
        guard AppSettings.shared.weatherEnabled else { return }
        restoreCache()
        if hasFreshSnapshot { return }
        if AppSettings.shared.weatherLocationMode == .manual,
            !AppSettings.shared.weatherManualLocation
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            loadManualLocation()
            return
        }
        applyAuthorizationStatus(promptIfNeeded: forcePrompt)
    }

    func refreshManualLocation() {
        manualLocationTask?.cancel()
        fetchTask?.cancel()
        snapshot = nil
        cacheRecord = nil
        lastCoordinate = nil
        WeatherCache.clear()
        status = .locating
        loadManualLocation()
    }

    private func loadManualLocation() {
        if hasFreshSnapshot { return }
        guard status != .locating || manualLocationTask == nil else { return }
        let query = AppSettings.shared.weatherManualLocation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            status = .failed
            return
        }
        status = .locating
        manualLocationTask = Task { [weak self] in
            guard let self else { return }
            let geocoder = CLGeocoder()
            let result = await withCheckedContinuation { continuation in
                geocoder.geocodeAddressString(query) { marks, _ in
                    continuation.resume(returning: marks?.first?.location)
                }
            }
            guard !Task.isCancelled else { return }
            guard let result else {
                self.status = .failed
                return
            }
            self.manualLocationTask = nil
            self.loadForecast(for: result)
        }
    }

    func requestAccessFromUser() {
        guard AppSettings.shared.weatherEnabled else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = .denied
            PrivacyAccess.openLocationSettings()
            return
        }
        switch location.authorizationStatus {
        case .denied, .restricted:
            status = .denied
            PrivacyAccess.openLocationSettings()
        case .authorizedAlways, .authorized:
            dismissAccessWindow()
            startUpdating()
        case .notDetermined:
            status = .needsPermission
            presentAccessWindow()
        @unknown default:
            status = .failed
        }
    }

    private func applyAuthorizationStatus(promptIfNeeded: Bool) {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .denied
            return
        }
        switch location.authorizationStatus {
        case .notDetermined:
            if snapshot == nil { status = .needsPermission }
            if promptIfNeeded { presentAccessWindow() }
        case .denied, .restricted:
            status = .denied
            dismissAccessWindow()
        case .authorizedAlways, .authorized:
            dismissAccessWindow()
            startUpdating()
        @unknown default:
            status = .failed
        }
    }

    private func presentAccessWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.activationPolicy() == .accessory {
            previousActivationPolicy = .accessory
            NSApp.setActivationPolicy(.regular)
        }
        let window = accessWindow ?? makeAccessWindow()
        accessWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func allowLocationClicked(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        accessWindow?.makeKeyAndOrderFront(nil)
        location.requestWhenInUseAuthorization()
    }

    @objc private func openLocationSettingsClicked(_ sender: Any?) {
        PrivacyAccess.openLocationSettings()
    }

    private func makeAccessWindow() -> NSWindow {
        let window = LocationKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 148),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Weather"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self

        let message = NSTextField(
            wrappingLabelWithString:
                "macOS will ask for Location so Loffty can show a local forecast."
        )
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false

        let allow = NSButton(
            title: "Allow Location",
            target: self,
            action: #selector(allowLocationClicked(_:))
        )
        allow.bezelStyle = .rounded
        allow.keyEquivalent = "\r"
        allow.translatesAutoresizingMaskIntoConstraints = false

        let settings = NSButton(
            title: "Open Settings",
            target: self,
            action: #selector(openLocationSettingsClicked(_:))
        )
        settings.bezelStyle = .rounded
        settings.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(message)
        content.addSubview(settings)
        content.addSubview(allow)
        window.contentView = content

        NSLayoutConstraint.activate([
            message.topAnchor.constraint(
                equalTo: content.topAnchor,
                constant: 18
            ),
            message.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: 20
            ),
            message.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -20
            ),
            settings.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: 20
            ),
            settings.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: -16
            ),
            allow.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -20
            ),
            allow.centerYAnchor.constraint(equalTo: settings.centerYAnchor),
            allow.topAnchor.constraint(
                greaterThanOrEqualTo: message.bottomAnchor,
                constant: 16
            ),
        ])
        window.setContentSize(NSSize(width: 380, height: 148))
        return window
    }

    private func dismissAccessWindow() {
        if let window = accessWindow {
            accessWindow = nil
            window.delegate = nil
            window.orderOut(nil)
        }
        if previousActivationPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
            previousActivationPolicy = nil
        }
    }

    func refreshIfStale() {
        guard status != .denied else { return }
        restoreCache()
        if hasFreshSnapshot { return }
        prepare()
    }

    private func startUpdating() {
        if hasFreshSnapshot { return }
        guard status != .locating else { return }
        if status != .ready { status = .locating }
        locationAttempts = 0
        requestLocationAttempt()
    }

    private func requestLocationAttempt() {
        locationAttempts += 1
        let attempt = locationAttempts
        location.requestLocation()
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            guard self.status == .locating,
                self.locationAttempts == attempt
            else { return }
            self.handleLocationUnavailable()
        }
    }

    private func handleLocationUnavailable() {
        guard locationAttempts < 3 else {
            if snapshot == nil { status = .failed }
            return
        }
        locationRetryTask?.cancel()
        locationRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.requestLocationAttempt()
        }
    }

    private func loadForecast(for location: CLLocation) {
        if let last = lastCoordinate,
            hasFreshSnapshot,
            WeatherCache.isNearby(
                lat1: last.latitude,
                lon1: last.longitude,
                lat2: location.coordinate.latitude,
                lon2: location.coordinate.longitude
            )
        {
            return
        }
        fetchTask?.cancel()
        lastCoordinate = location.coordinate
        let url = OpenMeteo.forecastURL(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let locality = await self.reverseGeocode(location)
            do {
                let data = try await self.fetch(url)
                let snap = try OpenMeteo.snapshot(
                    from: data,
                    locality: locality,
                    hourLimit: 24
                )
                guard !Task.isCancelled else { return }
                self.snapshot = snap
                self.status = .ready
                self.persistCache(for: location)
            } catch {
                guard !Task.isCancelled else { return }
                if self.snapshot == nil { self.status = .failed }
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                let name =
                    marks?.first?.locality
                    ?? marks?.first?.subAdministrativeArea
                    ?? marks?.first?.administrativeArea
                    ?? "Local"
                continuation.resume(returning: name)
            }
        }
    }
}

extension WeatherController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        accessWindow = nil
        if previousActivationPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
            previousActivationPolicy = nil
        }
    }
}

private final class LocationKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension WeatherController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            applyAuthorizationStatus(promptIfNeeded: false)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.locationRetryTask?.cancel()
            self.locationRetryTask = nil
            self.locationTimeoutTask?.cancel()
            self.locationTimeoutTask = nil
            self.locationAttempts = 0
            loadForecast(for: location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            if let clError = error as? CLError, clError.code == .denied {
                status = .denied
                return
            }
            if let clError = error as? CLError,
                clError.code == .locationUnknown
            {
                locationTimeoutTask?.cancel()
                locationTimeoutTask = nil
                handleLocationUnavailable()
                return
            }
            if snapshot == nil { status = .failed }
        }
    }
}
