//
//  Settings.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import Combine
import Network
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static func isEnabled(status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    static func requiresApproval(status: SMAppService.Status) -> Bool {
        status == .requiresApproval
    }

    static var isEnabled: Bool {
        isEnabled(status: SMAppService.mainApp.status)
    }

    static var requiresApproval: Bool {
        requiresApproval(status: SMAppService.mainApp.status)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}

enum NotchEdgeStyle: String, CaseIterable, Identifiable {
    case off
    case subtle
    case accent

    static let storageKey = "notchEdgeStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .subtle: "Subtle line"
        case .accent: "Album accent"
        }
    }

    var detail: String {
        switch self {
        case .off: "No outline around the island."
        case .subtle: "A faint line around the island."
        case .accent: "Uses the accent colour of the album cover."
        }
    }

    nonisolated static func shouldDraw(
        style: NotchEdgeStyle,
        showWhenNotFullScreen: Bool,
        isFullScreen: Bool
    ) -> Bool {
        guard style != .off else { return false }
        return showWhenNotFullScreen || isFullScreen
    }

    static var current: NotchEdgeStyle {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let style = NotchEdgeStyle(rawValue: raw)
        else { return .off }
        return style
    }
}

enum SoundwaveMotion: String, CaseIterable, Identifiable {
    case live
    case decorative
    case off

    static let storageKey = "soundwaveMotion"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .decorative: "Decorative"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .live: "Bars follow what is actually playing."
        case .decorative: "Animated bars, without listening to system audio."
        case .off: "Shows a pause icon while something is playing."
        }
    }

    var usesLiveAudio: Bool { self == .live }

    var showsAnimatedBars: Bool { self != .off }

    func shouldCapture(isPlaying: Bool, idle: Bool) -> Bool {
        usesLiveAudio && isPlaying && !idle
    }

    static var current: SoundwaveMotion {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let motion = SoundwaveMotion(rawValue: raw)
        else { return .live }
        return motion
    }
}

enum SoundwaveFeel: String, CaseIterable, Identifiable {
    case calm
    case balanced
    case snappy

    static let storageKey = "soundwaveFeel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Calm"
        case .balanced: "Balanced"
        case .snappy: "Snappy"
        }
    }

    var detail: String {
        switch self {
        case .calm: "Smoother bars that ease between peaks."
        case .balanced: "Follows the music without looking frantic."
        case .snappy: "Reacts quickly to beats and transients."
        }
    }

    var attack: Float {
        switch self {
        case .calm: 0.34
        case .balanced: 0.62
        case .snappy: 0.88
        }
    }

    var release: Float {
        switch self {
        case .calm: 0.12
        case .balanced: 0.28
        case .snappy: 0.52
        }
    }

    var peakDecay: Float {
        switch self {
        case .calm: 0.93
        case .balanced: 0.86
        case .snappy: 0.74
        }
    }

    var mockSpeed: Double {
        switch self {
        case .calm: 3.4
        case .balanced: 6.0
        case .snappy: 9.2
        }
    }

    static var current: SoundwaveFeel {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let feel = SoundwaveFeel(rawValue: raw)
        else { return .balanced }
        return feel
    }
}

enum SoundwaveTone: String, CaseIterable, Identifiable {
    case warm
    case balanced
    case bright

    static let storageKey = "soundwaveTone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "Warm"
        case .balanced: "Balanced"
        case .bright: "Bright"
        }
    }

    var detail: String {
        switch self {
        case .warm: "Gives more weight to bass."
        case .balanced: "A mix of low and high frequencies."
        case .bright: "Keeps the left bars from sitting full."
        }
    }

    var minFrequency: Double {
        switch self {
        case .warm: 80
        case .balanced: 120
        case .bright: 160
        }
    }

    var tilt: Float {
        switch self {
        case .warm: 0.28
        case .balanced: 0.45
        case .bright: 0.62
        }
    }

    static var current: SoundwaveTone {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let tone = SoundwaveTone(rawValue: raw)
        else { return .bright }
        return tone
    }
}

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
    private static let brightnessHUDShownOnAutoAdjustKey =
        "brightnessHUDShownOnAuto"
    private static let batteryHUDKey = "batteryHUD"
    private static let bluetoothHUDKey = "bluetoothHUD"
    private static let focusHUDKey = "focusHUD"
    private static let airDropHUDKey = "airDropHUD"
    private static let notificationsHUDKey = "notificationsHUD"
    private static let notificationsHUDDismissDelayKey =
        "notificationsHUDDismissDelay"
    private static let notificationMessagesKey = "notificationMessages"
    private static let notificationWhatsAppKey = "notificationWhatsApp"
    private static let notificationDiscordKey = "notificationDiscord"
    private static let movableWidgetKey = "movableWidget"
    private static let lockScreenNotchKey = "lockScreenNotch"
    private static let lockScreenExpandNotchKey = "lockScreenExpandNotch"
    private static let lockScreenFullScreenArtKey = "lockScreenFullScreenArt"
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
    private static let showAirPlayButtonKey = "showAirPlayButton"
    private static let showSpotifyLikeButtonKey = "showSpotifyLikeButton"
    private static let mediaToolbarItemsKey = "mediaToolbarItems"
    private static let spotifyLibraryTokenExpirationKey =
        "spotifyLibraryTokenExpiration"
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private static let hideNotchInFullScreenKey = "hideNotchInFullScreen"
    private static let hideNotchFullScreenAppsKey = "hideNotchFullScreenApps"
    private static let notchOutlineWhenNotFullScreenKey =
        "notchOutlineWhenNotFullScreen"

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

    @Published var brightnessHUDShownOnAutoAdjust: Bool {
        didSet {
            UserDefaults.standard.set(
                brightnessHUDShownOnAutoAdjust,
                forKey: Self.brightnessHUDShownOnAutoAdjustKey
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

    @Published var notificationsHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                notificationsHUD,
                forKey: Self.notificationsHUDKey
            )
        }
    }

    @Published var notificationsHUDDismissDelay: Double {
        didSet {
            UserDefaults.standard.set(
                notificationsHUDDismissDelay,
                forKey: Self.notificationsHUDDismissDelayKey
            )
        }
    }

    @Published var notificationMessages: Bool {
        didSet {
            UserDefaults.standard.set(
                notificationMessages,
                forKey: Self.notificationMessagesKey
            )
        }
    }

    @Published var notificationWhatsApp: Bool {
        didSet {
            UserDefaults.standard.set(
                notificationWhatsApp,
                forKey: Self.notificationWhatsAppKey
            )
        }
    }

    @Published var notificationDiscord: Bool {
        didSet {
            UserDefaults.standard.set(
                notificationDiscord,
                forKey: Self.notificationDiscordKey
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

    @Published var lockScreenFullScreenArt: Bool {
        didSet {
            UserDefaults.standard.set(
                lockScreenFullScreenArt,
                forKey: Self.lockScreenFullScreenArtKey
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

    @Published var soundwaveMotion: SoundwaveMotion {
        didSet {
            UserDefaults.standard.set(
                soundwaveMotion.rawValue,
                forKey: SoundwaveMotion.storageKey
            )
        }
    }

    @Published var soundwaveFeel: SoundwaveFeel {
        didSet {
            UserDefaults.standard.set(
                soundwaveFeel.rawValue,
                forKey: SoundwaveFeel.storageKey
            )
        }
    }

    @Published var soundwaveTone: SoundwaveTone {
        didSet {
            UserDefaults.standard.set(
                soundwaveTone.rawValue,
                forKey: SoundwaveTone.storageKey
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

    @Published var showAirPlayButton: Bool {
        didSet {
            UserDefaults.standard.set(
                showAirPlayButton,
                forKey: Self.showAirPlayButtonKey
            )
        }
    }

    @Published var showSpotifyLikeButton: Bool {
        didSet {
            UserDefaults.standard.set(
                showSpotifyLikeButton,
                forKey: Self.showSpotifyLikeButtonKey
            )
        }
    }

    @Published var mediaToolbarItems: [MediaToolbarItem] {
        didSet {
            let items = MediaToolbarItem.sanitize(mediaToolbarItems)
            if items != mediaToolbarItems {
                mediaToolbarItems = items
                return
            }
            UserDefaults.standard.set(
                items.map(\.rawValue),
                forKey: Self.mediaToolbarItemsKey
            )
        }
    }

    @Published var spotifyLibraryTokenExpiration: TimeInterval {
        didSet {
            UserDefaults.standard.set(
                spotifyLibraryTokenExpiration,
                forKey: Self.spotifyLibraryTokenExpirationKey
            )
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(
                hasCompletedOnboarding,
                forKey: Self.hasCompletedOnboardingKey
            )
        }
    }

    @Published var hideNotchInFullScreen: Bool {
        didSet {
            UserDefaults.standard.set(
                hideNotchInFullScreen,
                forKey: Self.hideNotchInFullScreenKey
            )
        }
    }

    @Published var hideNotchFullScreenApps: [String] {
        didSet {
            UserDefaults.standard.set(
                hideNotchFullScreenApps,
                forKey: Self.hideNotchFullScreenAppsKey
            )
        }
    }

    @Published var notchEdgeStyle: NotchEdgeStyle {
        didSet {
            UserDefaults.standard.set(
                notchEdgeStyle.rawValue,
                forKey: NotchEdgeStyle.storageKey
            )
        }
    }

    @Published var notchOutlineWhenNotFullScreen: Bool {
        didSet {
            UserDefaults.standard.set(
                notchOutlineWhenNotFullScreen,
                forKey: Self.notchOutlineWhenNotFullScreenKey
            )
        }
    }

    var watchesFullScreenApps: Bool {
        hideNotchInFullScreen || !hideNotchFullScreenApps.isEmpty
            || (notchEdgeStyle != .off && !notchOutlineWhenNotFullScreen)
    }

    func addHideNotchFullScreenApp(_ bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !hideNotchFullScreenApps.contains(id) else { return }
        hideNotchFullScreenApps.append(id)
    }

    func removeHideNotchFullScreenApp(_ bundleID: String) {
        hideNotchFullScreenApps.removeAll { $0 == bundleID }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    @Published private(set) var launchAtLoginNeedsApproval = false

    @Published private(set) var widgetPositionResetToken: UInt = 0

    private var isApplyingLaunchAtLogin = false

    var anyHUDEnabled: Bool {
        Self.anyHUDEnabled(
            replaceSystemHUD: replaceSystemHUD,
            batteryHUD: batteryHUD,
            bluetoothHUD: bluetoothHUD,
            focusHUD: focusHUD,
            airDropHUD: airDropHUD
        )
    }

    nonisolated static func anyHUDEnabled(
        replaceSystemHUD: Bool,
        batteryHUD: Bool,
        bluetoothHUD: Bool,
        focusHUD: Bool,
        airDropHUD: Bool
    ) -> Bool {
        replaceSystemHUD || batteryHUD || bluetoothHUD || focusHUD || airDropHUD
    }

    nonisolated static func shouldPresentBrightnessHUD(
        brightnessHUD: Bool,
        replaceSystemHUD: Bool,
        showOnAutoAdjust: Bool,
        changeWasFromKeyPress: Bool
    ) -> Bool {
        guard brightnessHUD, replaceSystemHUD else { return false }
        return showOnAutoAdjust || changeWasFromKeyPress
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
        brightnessHUDShownOnAutoAdjust =
            UserDefaults.standard.object(
                forKey: Self.brightnessHUDShownOnAutoAdjustKey
            ) as? Bool ?? false
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
        notificationsHUD =
            UserDefaults.standard.object(forKey: Self.notificationsHUDKey)
            as? Bool ?? true
        notificationsHUDDismissDelay =
            UserDefaults.standard.object(
                forKey: Self.notificationsHUDDismissDelayKey
            ) as? Double ?? 2.0
        notificationMessages =
            UserDefaults.standard.object(forKey: Self.notificationMessagesKey)
            as? Bool ?? true
        notificationWhatsApp =
            UserDefaults.standard.object(forKey: Self.notificationWhatsAppKey)
            as? Bool ?? true
        notificationDiscord =
            UserDefaults.standard.object(forKey: Self.notificationDiscordKey)
            as? Bool ?? true
        movableWidget = UserDefaults.standard.bool(
            forKey: Self.movableWidgetKey
        )
        lockScreenNotch =
            UserDefaults.standard.object(forKey: Self.lockScreenNotchKey)
            as? Bool ?? true
        lockScreenExpandNotch =
            UserDefaults.standard.object(forKey: Self.lockScreenExpandNotchKey)
            as? Bool ?? true
        lockScreenFullScreenArt =
            UserDefaults.standard.object(
                forKey: Self.lockScreenFullScreenArtKey
            ) as? Bool ?? true
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
        if let raw = UserDefaults.standard.string(
            forKey: SoundwaveMotion.storageKey
        ), let motion = SoundwaveMotion(rawValue: raw) {
            soundwaveMotion = motion
        } else {
            soundwaveMotion = .live
        }
        if let raw = UserDefaults.standard.string(
            forKey: SoundwaveFeel.storageKey
        ), let feel = SoundwaveFeel(rawValue: raw) {
            soundwaveFeel = feel
        } else {
            soundwaveFeel = .balanced
        }
        if let raw = UserDefaults.standard.string(
            forKey: SoundwaveTone.storageKey
        ), let tone = SoundwaveTone(rawValue: raw) {
            soundwaveTone = tone
        } else {
            soundwaveTone = .bright
        }
        marqueeEnabled =
            UserDefaults.standard.object(forKey: Self.marqueeEnabledKey)
            as? Bool ?? true
        showAlbum =
            UserDefaults.standard.object(forKey: Self.showAlbumKey) as? Bool
            ?? false
        automaticUpdates =
            UserDefaults.standard.object(forKey: Self.automaticUpdatesKey)
            as? Bool ?? false
        showAirPlayButton =
            UserDefaults.standard.object(forKey: Self.showAirPlayButtonKey)
            as? Bool ?? true
        showSpotifyLikeButton =
            UserDefaults.standard.object(forKey: Self.showSpotifyLikeButtonKey)
            as? Bool ?? true
        if let stored = MediaToolbarItem.decode(
            UserDefaults.standard.stringArray(forKey: Self.mediaToolbarItemsKey)
        ) {
            mediaToolbarItems = stored
        } else {
            let includeLike =
                UserDefaults.standard.object(
                    forKey: Self.showSpotifyLikeButtonKey
                ) as? Bool ?? true
            mediaToolbarItems = MediaToolbarItem.defaultLayout(
                includeLike: includeLike
            )
        }
        spotifyLibraryTokenExpiration =
            UserDefaults.standard.object(
                forKey: Self.spotifyLibraryTokenExpirationKey
            ) as? Double ?? 0
        hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: Self.hasCompletedOnboardingKey
        )
        hideNotchInFullScreen = UserDefaults.standard.bool(
            forKey: Self.hideNotchInFullScreenKey
        )
        hideNotchFullScreenApps =
            UserDefaults.standard.stringArray(
                forKey: Self.hideNotchFullScreenAppsKey
            ) ?? []
        if let raw = UserDefaults.standard.string(
            forKey: ArtistEnrichmentMode.storageKey
        ), let mode = ArtistEnrichmentMode(rawValue: raw) {
            artistEnrichment = mode
        } else {
            artistEnrichment = .always
        }
        if let raw = UserDefaults.standard.string(
            forKey: NotchEdgeStyle.storageKey
        ), let style = NotchEdgeStyle(rawValue: raw) {
            notchEdgeStyle = style
        } else {
            notchEdgeStyle = .off
        }
        notchOutlineWhenNotFullScreen =
            UserDefaults.standard.object(
                forKey: Self.notchOutlineWhenNotFullScreenKey
            ) as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    }

    func resetWidgetPosition() {
        widgetPositionResetToken &+= 1
    }

    func refreshLaunchAtLogin() {
        let enabled = LaunchAtLogin.isEnabled
        let needsApproval = LaunchAtLogin.requiresApproval
        launchAtLoginNeedsApproval = needsApproval
        guard enabled != launchAtLogin else { return }
        isApplyingLaunchAtLogin = true
        launchAtLogin = enabled
        isApplyingLaunchAtLogin = false
    }

    private func applyLaunchAtLogin() {
        guard !isApplyingLaunchAtLogin else { return }
        do {
            try LaunchAtLogin.setEnabled(launchAtLogin)
        } catch {
            isApplyingLaunchAtLogin = true
            launchAtLogin = LaunchAtLogin.isEnabled
            isApplyingLaunchAtLogin = false
        }
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    }
}
