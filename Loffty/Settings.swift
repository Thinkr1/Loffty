//
//  Settings.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import Combine
import Network
import SwiftUI

enum ArtistEnrichmentMode: String, CaseIterable, Identifiable {
    case never
    case wifiOnly
    case always

    static let storageKey = "artistEnrichment"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "First artist only"
        case .wifiOnly: "All artists on Wi‑Fi"
        case .always: "All artists (any network)"
        }
    }

    static var current: ArtistEnrichmentMode {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let mode = ArtistEnrichmentMode(rawValue: raw)
        else { return .always }
        return mode
    }

    var allowsNetworkFetch: Bool {
        switch self {
        case .never: false
        case .always: true
        case .wifiOnly: NetworkInterface.isOnWiFi
        }
    }
}

private enum NetworkInterface {
    static var isOnWiFi: Bool {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        let sem = DispatchSemaphore(value: 0)
        var onWiFi = false
        monitor.pathUpdateHandler = { path in
            onWiFi = path.status == .satisfied
            sem.signal()
        }
        let queue = DispatchQueue(label: "Loffty.wifiCheck")
        monitor.start(queue: queue)
        if sem.wait(timeout: .now() + 1) == .timedOut { onWiFi = false }
        monitor.cancel()
        return onWiFi
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let hideMenuBarItemKey = "hideMenuBarItem"
    private static let extendNotchKey = "extendNotch"
    private static let replaceSystemHUDKey = "replaceSystemHUD"
    private static let hudDurationKey = "hudDuration"
    private static let brightnessHUDKey = "brightnessHUD"
    private static let batteryHUDKey = "batteryHUD"
    private static let bluetoothHUDKey = "bluetoothHUD"
    private static let focusHUDKey = "focusHUD"
    private static let airDropHUDKey = "airDropHUD"
    private static let movableWidgetKey = "movableWidget"

    @Published var hideMenuBarItem: Bool {
        didSet {
            UserDefaults.standard.set(
                hideMenuBarItem,
                forKey: Self.hideMenuBarItemKey
            )
        }
    }

    @Published var extendNotch: Bool {
        didSet {
            UserDefaults.standard.set(extendNotch, forKey: Self.extendNotchKey)
        }
    }

    @Published var replaceSystemHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                replaceSystemHUD,
                forKey: Self.replaceSystemHUDKey
            )
        }
    }

    @Published var hudDuration: Double {
        didSet {
            UserDefaults.standard.set(hudDuration, forKey: Self.hudDurationKey)
        }
    }

    @Published var brightnessHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                brightnessHUD,
                forKey: Self.brightnessHUDKey
            )
        }
    }

    @Published var batteryHUD: Bool {
        didSet {
            UserDefaults.standard.set(batteryHUD, forKey: Self.batteryHUDKey)
        }
    }

    @Published var bluetoothHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                bluetoothHUD,
                forKey: Self.bluetoothHUDKey
            )
        }
    }

    @Published var focusHUD: Bool {
        didSet {
            UserDefaults.standard.set(focusHUD, forKey: Self.focusHUDKey)
        }
    }

    @Published var airDropHUD: Bool {
        didSet {
            UserDefaults.standard.set(airDropHUD, forKey: Self.airDropHUDKey)
        }
    }

    @Published var artistEnrichment: ArtistEnrichmentMode {
        didSet {
            UserDefaults.standard.set(
                artistEnrichment.rawValue,
                forKey: ArtistEnrichmentMode.storageKey
            )
        }
    }

    @Published var movableWidget: Bool {
        didSet {
            UserDefaults.standard.set(
                movableWidget,
                forKey: Self.movableWidgetKey
            )
        }
    }

    @Published private(set) var widgetPositionResetToken: UInt = 0

    var anyHUDEnabled: Bool {
        replaceSystemHUD || batteryHUD || bluetoothHUD || focusHUD || airDropHUD
    }

    private init() {
        hideMenuBarItem = UserDefaults.standard.bool(
            forKey: Self.hideMenuBarItemKey
        )
        extendNotch = UserDefaults.standard.bool(forKey: Self.extendNotchKey)
        replaceSystemHUD =
            UserDefaults.standard.object(forKey: Self.replaceSystemHUDKey)
            as? Bool ?? true
        hudDuration =
            UserDefaults.standard.object(forKey: Self.hudDurationKey) as? Double
            ?? 1.75
        brightnessHUD =
            UserDefaults.standard.object(forKey: Self.brightnessHUDKey) as? Bool
            ?? true
        batteryHUD =
            UserDefaults.standard.object(forKey: Self.batteryHUDKey) as? Bool
            ?? true
        bluetoothHUD =
            UserDefaults.standard.object(forKey: Self.bluetoothHUDKey) as? Bool
            ?? true
        focusHUD =
            UserDefaults.standard.object(forKey: Self.focusHUDKey) as? Bool
            ?? true
        airDropHUD =
            UserDefaults.standard.object(forKey: Self.airDropHUDKey) as? Bool
            ?? true
        movableWidget = UserDefaults.standard.bool(
            forKey: Self.movableWidgetKey
        )
        if let raw = UserDefaults.standard.string(
            forKey: ArtistEnrichmentMode.storageKey
        ), let mode = ArtistEnrichmentMode(rawValue: raw) {
            artistEnrichment = mode
        } else {
            artistEnrichment = .always
        }
    }

    func resetWidgetPosition() {
        widgetPositionResetToken &+= 1
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarItem)
                Toggle("Extend notch around media", isOn: $settings.extendNotch)
            }

            Section {
                Toggle(
                    "Allow moving lock screen widget",
                    isOn: $settings.movableWidget
                )
                Button("Reset widget position") {
                    settings.resetWidgetPosition()
                }
            } header: {
                Text("Lock Screen")
            }

            Section {
                Picker(
                    "Spotify artists",
                    selection: $settings.artistEnrichment
                ) {
                    ForEach(ArtistEnrichmentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Spotify only reports the first artist to macOS. Loffty can look up the full list over the network."
                )
            }

            Section {
                Toggle(
                    "Replace system volume and brightness HUDs",
                    isOn: $settings.replaceSystemHUD
                )
                if settings.replaceSystemHUD {
                    Toggle("Show brightness HUD", isOn: $settings.brightnessHUD)
                }
                Toggle("Battery status HUD", isOn: $settings.batteryHUD)
                Toggle("Bluetooth connection HUD", isOn: $settings.bluetoothHUD)
                Toggle("Focus HUD", isOn: $settings.focusHUD)
                Toggle("AirDrop in notch", isOn: $settings.airDropHUD)
                if settings.anyHUDEnabled {
                    LabeledContent("HUD duration") {
                        HStack(spacing: 8) {
                            Slider(
                                value: $settings.hudDuration,
                                in: 1...3,
                                step: 0.25
                            )
                            Text(String(format: "%.1fs", settings.hudDuration))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("System HUDs")
            } footer: {
                Text(
                    "Volume and brightness require Accessibility and replace the system HUD. Battery uses the drop-down chip; Bluetooth and Focus take over the notch sides. Drop a file on the notch to open AirDrop."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
