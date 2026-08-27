//
//  LockAccessories.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 25/08/2026.
//

import AppKit
import Combine
import IOBluetooth
import IOKit.ps
import SwiftUI

enum LockCardMetrics {
    static let width: CGFloat = 356
    static let height: CGFloat = 174
    static let cornerRadius: CGFloat = 38
}

enum LockAccessoriesMetrics {
    static let width: CGFloat = 340
    static let rowHeight: CGFloat = 44
    static let graphExtra: CGFloat = 30
    static let graphBothExtra: CGFloat = 18
    static let graphLabelsExtra: CGFloat = 14
    static let defaultTopInsetFraction: CGFloat = 0.30
    static let minTopInsetFraction: CGFloat = 0.18
    static let maxTopInsetFraction: CGFloat = 0.92
    static let minTopInset: CGFloat = 200
    static let bottomMargin: CGFloat = 16

    @MainActor
    static func height(settings: AppSettings = .shared) -> CGFloat {
        let accessories = settings.enabledLockScreenAccessories
        guard !accessories.isEmpty else { return 0 }
        var value = rowHeight
        if accessories.contains(.weather), settings.lockScreenWeatherShowGraph {
            value += graphExtra
            if settings.lockScreenWeatherGraphKind == .both {
                value += graphBothExtra
            }
            if settings.lockScreenWeatherShowGraphLabels {
                value += graphLabelsExtra
                if settings.lockScreenWeatherGraphKind == .both {
                    value += graphLabelsExtra / 2
                }
            }
        }
        return value
    }

    static func clampedTopInsetFraction(_ value: CGFloat) -> CGFloat {
        min(max(value, minTopInsetFraction), maxTopInsetFraction)
    }

    @MainActor
    static func topInset(
        screenHeight: CGFloat,
        settings: AppSettings = .shared
    ) -> CGFloat {
        let fraction = clampedTopInsetFraction(
            settings.lockScreenAccessoriesTopInsetFraction
        )
        let panelHeight = height(settings: settings)
        let maxInset = max(
            minTopInset,
            screenHeight - panelHeight - bottomMargin
        )
        return min(max(screenHeight * fraction, minTopInset), maxInset)
    }

    @MainActor
    static func defaultFrame(
        screenFrame: CGRect,
        settings: AppSettings = .shared
    ) -> CGRect {
        let sizeHeight = height(settings: settings)
        guard sizeHeight > 0 else { return .zero }
        let inset = topInset(
            screenHeight: screenFrame.height,
            settings: settings
        )
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - inset - sizeHeight,
            width: width,
            height: sizeHeight
        )
    }
}

@MainActor
final class LockAccessoryStatus: ObservableObject {
    static let shared = LockAccessoryStatus()

    @Published private(set) var bluetoothDevices: [String] = []
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var batteryCharging = false
    @Published private(set) var batteryOnAC = false
    @Published private(set) var focusActive = false
    @Published private(set) var focusName: String?

    private let bluetooth = BluetoothHUDWatcher()
    private var timer: Timer?

    private init() {
        bluetooth.onChange = { [weak self] name, connected in
            Task { @MainActor in
                self?.applyBluetooth(name: name, connected: connected)
            }
        }
    }

    func start() {
        bluetooth.start()
        refreshBluetoothSnapshot()
        refreshBattery()
        refreshFocus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshBattery()
                self?.refreshFocus()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        bluetooth.stop()
    }

    private func applyBluetooth(name: String, connected: Bool) {
        if connected {
            if !bluetoothDevices.contains(name) {
                bluetoothDevices.append(name)
            }
        } else {
            bluetoothDevices.removeAll { $0 == name }
        }
    }

    private func refreshBluetoothSnapshot() {
        let connected =
            (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .compactMap { device -> String? in
                if let name = device.nameOrAddress, !name.isEmpty {
                    return name
                }
                if let address = device.addressString, !address.isEmpty {
                    return address
                }
                return nil
            }
        bluetoothDevices = connected
    }

    func refreshBattery() {
        guard let info = Self.readBattery() else {
            batteryPercent = nil
            return
        }
        batteryPercent = info.percent
        batteryCharging = info.charging
        batteryOnAC = info.onAC
    }

    func refreshFocus() {
        let bridge = FocusFilterBridge.shared
        focusActive = bridge.isFocused
        focusName = bridge.modeName
    }

    private static func readBattery() -> (
        percent: Int, charging: Bool, onAC: Bool
    )? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
                as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                let capacity = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }

            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let onAC =
                (desc[kIOPSPowerSourceStateKey] as? String)
                == kIOPSACPowerValue
            return (capacity, isCharging, onAC)
        }
        return nil
    }
}

struct LockAccessoriesRootView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        LockAccessoriesView()
            .frame(
                width: LockAccessoriesMetrics.width,
                height: LockAccessoriesMetrics.height(settings: settings),
                alignment: .top
            )
    }
}

struct LockAccessoriesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherController.shared

    private var accessories: [LockScreenAccessory] {
        settings.enabledLockScreenAccessories
    }

    var body: some View {
        if !accessories.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: 18) {
                    ForEach(accessories) { accessory in
                        LockAccessoryChip(accessory: accessory)
                    }
                }
                .frame(maxWidth: .infinity)

                if accessories.contains(.weather) {
                    LockWeatherSparklinePane()
                        .frame(maxWidth: 220)
                }
            }
            .padding(.horizontal, 8)
            .onAppear {
                LockAccessoryStatus.shared.start()
                if settings.lockScreenWeatherAccessory {
                    weather.refreshIfStale()
                }
            }
        }
    }
}

struct LockAccessoryChip: View {
    var accessory: LockScreenAccessory

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherController.shared
    @ObservedObject private var status = LockAccessoryStatus.shared

    var body: some View {
        Group {
            switch accessory {
            case .weather: weatherChip
            case .bluetooth: bluetoothChip
            case .battery: batteryChip
            case .focus: focusChip
            }
        }
    }

    private var weatherChip: some View {
        let metricTemp = WeatherFormatting.usesMetricTemperature(
            settings.weatherTemperatureUnit
        )
        let metricWind = WeatherFormatting.usesMetricWind(
            settings.weatherWindUnit
        )
        return Group {
            if let snap = weather.snapshot, weather.status == .ready {
                HStack(spacing: 5) {
                    Image(
                        systemName: WeatherSymbol.systemName(
                            code: snap.weatherCode,
                            isDay: snap.isDay
                        )
                    )
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    Text(
                        WeatherFormatting.temperatureLabel(
                            snap.temperatureC,
                            metric: metricTemp
                        )
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    if settings.lockScreenWeatherShowCondition {
                        Text(
                            WeatherFormatting.conditionLabel(
                                code: snap.weatherCode
                            )
                        )
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.72)
                        .lineLimit(1)
                    }
                    if settings.lockScreenWeatherShowLocation {
                        Text(snap.locality)
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.72)
                            .lineLimit(1)
                    }
                    if settings.lockScreenWeatherShowHighLow {
                        Text(
                            "H\(WeatherFormatting.temperatureLabel(snap.highC, metric: metricTemp)) L\(WeatherFormatting.temperatureLabel(snap.lowC, metric: metricTemp))"
                        )
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.55)
                        .monospacedDigit()
                    }
                    if settings.lockScreenWeatherShowUV {
                        Text(WeatherFormatting.uvLabel(snap.uvIndex))
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.55)
                    }
                    if settings.lockScreenWeatherShowWind {
                        Text(
                            WeatherFormatting.windLabel(
                                snap.windKmh,
                                metric: metricWind
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.55)
                    }
                    if settings.lockScreenWeatherShowPrecip,
                        let chance = snap.hours.first?.precipChance
                    {
                        HStack(spacing: 2) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(WeatherFormatting.precipChanceLabel(chance))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                        }
                        .opacity(0.55)
                    }
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "cloud.fill")
                    Text(weatherPlaceholder)
                }
                .font(.system(size: 13, weight: .medium))
                .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
    }

    private var weatherPlaceholder: String {
        switch weather.status {
        case .locating: "…"
        case .needsPermission, .denied: "—"
        case .failed: "—"
        default: "—"
        }
    }

    private var bluetoothChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "airpodspro")
                .font(.system(size: 14, weight: .medium))
            Text(bluetoothLabel)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }

    private var bluetoothLabel: String {
        let devices = status.bluetoothDevices
        guard let first = devices.first else { return "Off" }
        let name = HUDText.shortBluetoothName(first)
        if settings.lockScreenBluetoothShowCount, devices.count > 1 {
            return "\(name) +\(devices.count - 1)"
        }
        return name
    }

    private var batteryChip: some View {
        HStack(spacing: 5) {
            Image(systemName: batterySymbol)
                .font(.system(size: 14, weight: .medium))
            if let percent = status.batteryPercent {
                Text("\(percent)%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .medium))
            }
            if settings.lockScreenBatteryShowCharging,
                status.batteryPercent != nil
            {
                if status.batteryCharging {
                    Text("Charging")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.55)
                } else if status.batteryOnAC {
                    Text("Power Adapter")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.55)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var batterySymbol: String {
        guard let percent = status.batteryPercent else {
            return "battery.100"
        }
        if status.batteryCharging || status.batteryOnAC {
            return "battery.100.bolt"
        }
        switch percent {
        case 0..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<70: return "battery.50"
        case 70..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var focusChip: some View {
        HStack(spacing: 5) {
            Image(
                systemName: status.focusActive
                    ? "moon.fill" : "moon"
            )
            .font(.system(size: 14, weight: .medium))
            Text(focusLabel)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .opacity(status.focusActive ? 1 : 0.55)
    }

    private var focusLabel: String {
        if status.focusActive {
            return status.focusName ?? "Focus"
        }
        return "Off"
    }
}

struct LockWeatherSparklinePane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherController.shared

    var body: some View {
        if settings.lockScreenWeatherShowGraph,
            let hours = weather.snapshot?.hours, hours.count >= 3
        {
            LockWeatherSparkline(
                hours: hours,
                kind: settings.lockScreenWeatherGraphKind,
                showLabels: settings.lockScreenWeatherShowGraphLabels,
                metricTemperature: WeatherFormatting.usesMetricTemperature(
                    settings.weatherTemperatureUnit
                )
            )
        }
    }
}

struct LockWeatherSparkline: View {
    var hours: [WeatherHour]
    var kind: LockScreenWeatherGraphKind
    var showLabels: Bool
    var metricTemperature: Bool

    var body: some View {
        switch kind {
        case .temperature:
            temperatureBlock(includeHours: showLabels)
        case .precipitation:
            precipBlock(includeHours: showLabels)
        case .both:
            VStack(spacing: 6) {
                temperatureBlock(includeHours: false)
                precipBlock(includeHours: showLabels)
            }
        }
    }

    private func temperatureBlock(includeHours: Bool) -> some View {
        VStack(spacing: 3) {
            if showLabels {
                graphHeader(
                    title: "Temp",
                    detail: temperatureRangeLabel
                )
            }
            temperatureLine(values: hours.map(\.temperatureC))
                .frame(height: 16)
            if includeHours {
                hourFooter
            }
        }
    }

    private func precipBlock(includeHours: Bool) -> some View {
        VStack(spacing: 3) {
            if showLabels {
                graphHeader(
                    title: "Rain",
                    detail: precipRangeLabel
                )
            }
            precipBars(values: hours.map { Double($0.precipChance) })
                .frame(height: 14)
            if includeHours {
                hourFooter
            }
        }
    }

    private var temperatureRangeLabel: String {
        guard let min = hours.map(\.temperatureC).min(),
            let max = hours.map(\.temperatureC).max()
        else { return "" }
        return
            "\(WeatherFormatting.temperatureLabel(min, metric: metricTemperature))–\(WeatherFormatting.temperatureLabel(max, metric: metricTemperature))"
    }

    private var precipRangeLabel: String {
        guard let max = hours.map(\.precipChance).max() else { return "" }
        return "up to \(WeatherFormatting.precipChanceLabel(max))"
    }

    private var hourFooter: some View {
        HStack {
            Text(hourLabel(hours.first?.date))
            Spacer(minLength: 0)
            Text(hourLabel(hours.last?.date))
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
        .monospacedDigit()
    }

    private func graphHeader(title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.3)
            Spacer(minLength: 0)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
            }
        }
    }

    private func hourLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        return WeatherFormatting.hourLabel(date)
    }

    private func temperatureLine(values: [Double]) -> some View {
        let points = WeatherGraph.normalized(values)
        return Canvas { context, size in
            guard points.count > 1 else { return }
            var line = Path()
            for (index, y) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let py = size.height - (2 + y * (size.height - 4))
                let point = CGPoint(x: x, y: py)
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            context.stroke(
                line,
                with: .color(.white.opacity(0.75)),
                style: StrokeStyle(
                    lineWidth: 1.4,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func precipBars(values: [Double]) -> some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let count = CGFloat(values.count)
            let gap: CGFloat = 1.5
            let barWidth = max(
                1.5,
                (size.width - gap * (count - 1)) / count
            )
            for (index, value) in values.enumerated() {
                let normalized = CGFloat(min(max(value / 100, 0), 1))
                let height = max(1.5, normalized * (size.height - 1))
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(
                    x: x,
                    y: size.height - height,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(.white.opacity(0.45 + 0.35 * normalized))
                )
            }
        }
    }
}
