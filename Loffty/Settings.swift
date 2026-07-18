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
    private static let lockScreenNotchKey = "lockScreenNotch"
    private static let lockScreenExpandNotchKey = "lockScreenExpandNotch"
    private static let lockScreenWaveformsKey = "lockScreenWaveforms"
    private static let lockScreenWaveformsAccentKey =
        "lockScreenWaveformsAccent"
    private static let playerBadgeExpandedKey = "playerBadgeExpanded.v2"
    private static let playerBadgeCollapsedKey = "playerBadgeCollapsed.v2"
    private static let playerBadgeLockScreenKey = "playerBadgeLockScreen.v2"
    private static let collapsedWaveformsAccentKey =
        "collapsedWaveformsAccent"
    private static let marqueeEnabledKey = "marqueeEnabled"
    private static let showAlbumKey = "showAlbum"
    private static let automaticUpdatesKey = "automaticUpdates"

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

    @Published var lockScreenNotch: Bool {
        didSet {
            UserDefaults.standard.set(
                lockScreenNotch,
                forKey: Self.lockScreenNotchKey
            )
        }
    }

    @Published var lockScreenExpandNotch: Bool {
        didSet {
            UserDefaults.standard.set(
                lockScreenExpandNotch,
                forKey: Self.lockScreenExpandNotchKey
            )
        }
    }

    @Published var lockScreenWaveforms: Bool {
        didSet {
            UserDefaults.standard.set(
                lockScreenWaveforms,
                forKey: Self.lockScreenWaveformsKey
            )
        }
    }

    @Published var lockScreenWaveformsAccent: Bool {
        didSet {
            UserDefaults.standard.set(
                lockScreenWaveformsAccent,
                forKey: Self.lockScreenWaveformsAccentKey
            )
        }
    }

    @Published var playerBadgeExpanded: Bool {
        didSet {
            UserDefaults.standard.set(
                playerBadgeExpanded,
                forKey: Self.playerBadgeExpandedKey
            )
        }
    }

    @Published var playerBadgeCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(
                playerBadgeCollapsed,
                forKey: Self.playerBadgeCollapsedKey
            )
        }
    }

    @Published var playerBadgeLockScreen: Bool {
        didSet {
            UserDefaults.standard.set(
                playerBadgeLockScreen,
                forKey: Self.playerBadgeLockScreenKey
            )
        }
    }

    @Published var collapsedWaveformsAccent: Bool {
        didSet {
            UserDefaults.standard.set(
                collapsedWaveformsAccent,
                forKey: Self.collapsedWaveformsAccentKey
            )
        }
    }

    @Published var marqueeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                marqueeEnabled,
                forKey: Self.marqueeEnabledKey
            )
        }
    }

    @Published var showAlbum: Bool {
        didSet {
            UserDefaults.standard.set(showAlbum, forKey: Self.showAlbumKey)
        }
    }

    @Published var automaticUpdates: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticUpdates,
                forKey: Self.automaticUpdatesKey
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
        lockScreenNotch =
            UserDefaults.standard.object(forKey: Self.lockScreenNotchKey)
            as? Bool ?? true
        lockScreenExpandNotch =
            UserDefaults.standard.object(forKey: Self.lockScreenExpandNotchKey)
            as? Bool ?? true
        lockScreenWaveforms =
            UserDefaults.standard.object(forKey: Self.lockScreenWaveformsKey)
            as? Bool ?? true
        lockScreenWaveformsAccent =
            UserDefaults.standard.object(
                forKey: Self.lockScreenWaveformsAccentKey
            ) as? Bool ?? false
        playerBadgeExpanded =
            UserDefaults.standard.object(forKey: Self.playerBadgeExpandedKey)
            as? Bool ?? true
        playerBadgeCollapsed =
            UserDefaults.standard.object(forKey: Self.playerBadgeCollapsedKey)
            as? Bool ?? true
        playerBadgeLockScreen =
            UserDefaults.standard.object(forKey: Self.playerBadgeLockScreenKey)
            as? Bool ?? true
        collapsedWaveformsAccent =
            UserDefaults.standard.object(
                forKey: Self.collapsedWaveformsAccentKey
            ) as? Bool ?? false
        marqueeEnabled =
            UserDefaults.standard.object(forKey: Self.marqueeEnabledKey)
            as? Bool ?? true
        showAlbum =
            UserDefaults.standard.object(forKey: Self.showAlbumKey) as? Bool
            ?? false
        automaticUpdates =
            UserDefaults.standard.object(forKey: Self.automaticUpdatesKey)
            as? Bool ?? false
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
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section {
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarItem)
                Toggle("Extend notch around media", isOn: $settings.extendNotch)
            }

            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: $settings.automaticUpdates
                )
                HStack {
                    Button("Check for Updates...") {
                        updater.checkForUpdatesNow()
                    }
                    .disabled(isUpdateBusy)
                    Spacer()
                    Text(updateStatusText)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(
                    "Uses GitHub Releases (zip, sha-256, ed25519). Because the app is not notarized, macOS may ask you to allow a new build once after an update."
                )
            }

            Section {
                Toggle(
                    "Show notch on lock screen",
                    isOn: $settings.lockScreenNotch
                )
                if settings.lockScreenNotch {
                    Toggle(
                        "Allow expanding notch on lock screen",
                        isOn: $settings.lockScreenExpandNotch
                    )
                }
                Toggle(
                    "Show soundwaves",
                    isOn: $settings.lockScreenWaveforms
                )
                if settings.lockScreenWaveforms {
                    Toggle(
                        "Color soundwaves with album accent",
                        isOn: $settings.lockScreenWaveformsAccent
                    )
                }
                Toggle(
                    "Allow moving lock screen widget",
                    isOn: $settings.movableWidget
                )
                Button("Reset widget position") {
                    settings.resetWidgetPosition()
                }
            } header: {
                Text("Lock Screen")
            } footer: {
                Text(
                    "The notch HUD and the lock screen widget can both appear above the lock screen. Expanding on the lock screen never steals focus from the password field."
                )
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
                Toggle(
                    "Player badge in expanded notch",
                    isOn: $settings.playerBadgeExpanded
                )
                Toggle(
                    "Player badge in collapsed notch",
                    isOn: $settings.playerBadgeCollapsed
                )
                Toggle(
                    "Player badge on lock screen",
                    isOn: $settings.playerBadgeLockScreen
                )
                Toggle(
                    "Color collapsed soundwaves with album accent",
                    isOn: $settings.collapsedWaveformsAccent
                )
                Toggle(
                    "Scroll long titles and artists",
                    isOn: $settings.marqueeEnabled
                )
                Toggle("Show album name", isOn: $settings.showAlbum)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Spotify only reports the first artist to macOS. Loffty can look up the full list over the network. The player badge shows the current app’s icon on the album cover. When scrolling is off, long titles and artists truncate with an ellipsis."
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

    private var isUpdateBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private var updateStatusText: String {
        switch updater.state {
        case .idle: "Version \(updater.currentVersion)"
        case .checking: "Checking..."
        case .upToDate: "Up to date"
        case .available(let release): "\(release.version) available"
        case .downloading: "Downloading..."
        case .installing: "Installing..."
        case .failed: "Check failed"
        }
    }
}
