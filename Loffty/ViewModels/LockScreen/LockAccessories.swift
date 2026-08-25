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
    static let defaultTopInsetFraction: CGFloat = 0.30
    static let minTopInsetFraction: CGFloat = 0.18
    static let maxTopInsetFraction: CGFloat = 0.42
    static let minTopInset: CGFloat = 200
    static let maxTopInset: CGFloat = 460

    @MainActor
    static func height(settings: AppSettings = .shared) -> CGFloat {
        let accessories = settings.enabledLockScreenAccessories
        guard !accessories.isEmpty else { return 0 }
        var value = rowHeight
        if accessories.contains(.weather), settings.lockScreenWeatherShowGraph {
            value += graphExtra
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
        return min(max(screenHeight * fraction, minTopInset), maxTopInset)
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
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshBattery()
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
    @ObservedObject private var status = LockAccessoryStatus.shared

    private var accessories: [LockScreenAccessory] {
        settings.enabledLockScreenAccessories
    }

    var body: some View {
        if !accessories.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: 18) {
                    ForEach(accessories) { accessory in
                        chip(for: accessory)
                    }
                }
                .frame(maxWidth: .infinity)

                if accessories.contains(.weather),
                    settings.lockScreenWeatherShowGraph,
                    let hours = weather.snapshot?.hours, hours.count >= 3
                {
                    LockWeatherSparkline(values: hours.map(\.temperatureC))
                        .frame(height: 22)
                        .frame(maxWidth: 180)
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

    @ViewBuilder
    private func chip(for accessory: LockScreenAccessory) -> some View {
        switch accessory {
        case .weather:
            weatherChip
        case .bluetooth:
            bluetoothChip
        case .battery:
            batteryChip
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
            Image(
                systemName: status.bluetoothDevices.isEmpty
                    ? "airpodspro"
                    : "airpodspro"
            )
            .font(.system(size: 14, weight: .medium))
            Text(bluetoothLabel)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }

    private var bluetoothLabel: String {
        if let first = status.bluetoothDevices.first {
            return HUDText.shortBluetoothName(first)
        }
        return "Off"
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
}

private struct LockWeatherSparkline: View {
    var values: [Double]

    var body: some View {
        let points = WeatherGraph.normalized(values)
        Canvas { context, size in
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
                with: .color(.white.opacity(0.7)),
                style: StrokeStyle(
                    lineWidth: 1.4,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}
