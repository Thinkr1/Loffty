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

    @Published var artistEnrichment: ArtistEnrichmentMode {
        didSet {
            UserDefaults.standard.set(
                artistEnrichment.rawValue,
                forKey: ArtistEnrichmentMode.storageKey
            )
        }
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
        if let raw = UserDefaults.standard.string(
            forKey: ArtistEnrichmentMode.storageKey
        ), let mode = ArtistEnrichmentMode(rawValue: raw) {
            artistEnrichment = mode
        } else {
            artistEnrichment = .always
        }
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
                Picker(
                    "Show all artists (Spotify)",
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
                    "Spotify only reports the first artist to macOS. Loffty can look up the full list from Spotify over the network."
                )
            }
            Section {
                Toggle(
                    "Hide macOS volume & brightness overlays",
                    isOn: $settings.replaceSystemHUD
                )
                Toggle("Show brightness HUD", isOn: $settings.brightnessHUD)
                HStack {
                    Text("HUD duration")
                    Slider(value: $settings.hudDuration, in: 1...3, step: 0.25)
                    Text(String(format: "%.1fs", settings.hudDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("System HUDs")
            } footer: {
                if settings.replaceSystemHUD {
                    Text(
                        "Requires Accessibility permission. Loffty only intercepts volume and brightness keys."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
