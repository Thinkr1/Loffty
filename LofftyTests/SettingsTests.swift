//
//  SettingsTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Settings", .serialized)
struct SettingsTests {
    @Test func anyHUDEnabledOrLogic() {
        #expect(
            AppSettings.anyHUDEnabled(
                replaceSystemHUD: false,
                batteryHUD: false,
                bluetoothHUD: false,
                focusHUD: false,
                airDropHUD: false
            ) == false
        )
        #expect(
            AppSettings.anyHUDEnabled(
                replaceSystemHUD: true,
                batteryHUD: false,
                bluetoothHUD: false,
                focusHUD: false,
                airDropHUD: false
            )
        )
        #expect(
            AppSettings.anyHUDEnabled(
                replaceSystemHUD: false,
                batteryHUD: false,
                bluetoothHUD: false,
                focusHUD: false,
                airDropHUD: true
            )
        )
    }

    @Test func shouldPresentBrightnessHUDRequiresEnabledAndReplace() {
        #expect(
            !AppSettings.shouldPresentBrightnessHUD(
                brightnessHUD: false,
                replaceSystemHUD: true,
                showOnAutoAdjust: true,
                changeWasFromKeyPress: true
            )
        )
        #expect(
            !AppSettings.shouldPresentBrightnessHUD(
                brightnessHUD: true,
                replaceSystemHUD: false,
                showOnAutoAdjust: true,
                changeWasFromKeyPress: true
            )
        )
    }

    @Test func shouldPresentBrightnessHUDAutoAdjustGate() {
        #expect(
            AppSettings.shouldPresentBrightnessHUD(
                brightnessHUD: true,
                replaceSystemHUD: true,
                showOnAutoAdjust: true,
                changeWasFromKeyPress: false
            )
        )
        #expect(
            !AppSettings.shouldPresentBrightnessHUD(
                brightnessHUD: true,
                replaceSystemHUD: true,
                showOnAutoAdjust: false,
                changeWasFromKeyPress: false
            )
        )
        #expect(
            AppSettings.shouldPresentBrightnessHUD(
                brightnessHUD: true,
                replaceSystemHUD: true,
                showOnAutoAdjust: false,
                changeWasFromKeyPress: true
            )
        )
    }

    @Test @MainActor func brightnessHUDShownOnAutoAdjustPersists() {
        let settings = AppSettings.shared
        let original = settings.brightnessHUDShownOnAutoAdjust
        defer { settings.brightnessHUDShownOnAutoAdjust = original }

        settings.brightnessHUDShownOnAutoAdjust = true
        #expect(
            UserDefaults.standard.object(forKey: "brightnessHUDShownOnAuto")
                as? Bool == true
        )

        settings.brightnessHUDShownOnAutoAdjust = false
        #expect(
            UserDefaults.standard.object(forKey: "brightnessHUDShownOnAuto")
                as? Bool == false
        )
        #expect(!settings.brightnessHUDShownOnAutoAdjust)
    }

    @Test func artistEnrichmentModeNetworkFetch() {
        #expect(!ArtistEnrichmentMode.never.allowsNetworkFetch)
        #expect(ArtistEnrichmentMode.always.allowsNetworkFetch)
    }

    @Test func artistEnrichmentRawValueRoundTrip() {
        for mode in ArtistEnrichmentMode.allCases {
            #expect(ArtistEnrichmentMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test func artistEnrichmentTitles() {
        #expect(ArtistEnrichmentMode.never.title == "First artist only")
        #expect(ArtistEnrichmentMode.wifiOnly.title == "All artists on Wi‑Fi")
        #expect(
            ArtistEnrichmentMode.always.title == "All artists (any network)"
        )
    }

    @Test @MainActor func resetWidgetPositionTokenIncrements() {
        let before = AppSettings.shared.widgetPositionResetToken
        AppSettings.shared.resetWidgetPosition()
        #expect(AppSettings.shared.widgetPositionResetToken == before + 1)
    }

    @Test @MainActor func launchAtLoginPublishedStateMatchesService() {
        let settings = AppSettings.shared
        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLogin == LaunchAtLogin.isEnabled)
        #expect(
            settings.launchAtLoginNeedsApproval
                == LaunchAtLogin.requiresApproval
        )
    }

    @Test @MainActor func notificationsHUDPersists() {
        let settings = AppSettings.shared
        let original = settings.notificationsHUD
        defer { settings.notificationsHUD = original }

        settings.notificationsHUD = false
        #expect(
            UserDefaults.standard.object(forKey: "notificationsHUD") as? Bool
                == false
        )
        settings.notificationsHUD = true
        #expect(settings.notificationsHUD)
    }

    @Test @MainActor func notificationsHUDDismissDelayPersists() {
        let settings = AppSettings.shared
        let original = settings.notificationsHUDDismissDelay
        defer { settings.notificationsHUDDismissDelay = original }

        settings.notificationsHUDDismissDelay = 3.25
        #expect(
            UserDefaults.standard.double(forKey: "notificationsHUDDismissDelay")
                == 3.25
        )
        #expect(settings.notificationsHUDDismissDelay == 3.25)
    }

    @Test @MainActor func notificationAppTogglesPersist() {
        let settings = AppSettings.shared
        let original = (
            settings.notificationMessages,
            settings.notificationWhatsApp,
            settings.notificationDiscord
        )
        defer {
            settings.notificationMessages = original.0
            settings.notificationWhatsApp = original.1
            settings.notificationDiscord = original.2
        }

        settings.notificationMessages = false
        settings.notificationWhatsApp = false
        settings.notificationDiscord = false
        #expect(
            UserDefaults.standard.object(forKey: "notificationMessages")
                as? Bool == false
        )
        #expect(
            UserDefaults.standard.object(forKey: "notificationWhatsApp")
                as? Bool == false
        )
        #expect(
            UserDefaults.standard.object(forKey: "notificationDiscord")
                as? Bool == false
        )

        settings.notificationMessages = true
        settings.notificationWhatsApp = true
        settings.notificationDiscord = true
        #expect(settings.notificationMessages)
        #expect(settings.notificationWhatsApp)
        #expect(settings.notificationDiscord)
    }

    @Test @MainActor func hasCompletedOnboardingPersists() {
        let settings = AppSettings.shared
        let original = settings.hasCompletedOnboarding
        defer { settings.hasCompletedOnboarding = original }

        settings.hasCompletedOnboarding = true
        #expect(
            UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        )
        #expect(settings.hasCompletedOnboarding)

        settings.hasCompletedOnboarding = false
        #expect(
            !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        )
        #expect(!settings.hasCompletedOnboarding)
    }

    @Test @MainActor func hideNotchInFullScreenPersists() {
        let settings = AppSettings.shared
        let original = settings.hideNotchInFullScreen
        defer { settings.hideNotchInFullScreen = original }

        settings.hideNotchInFullScreen = true
        #expect(
            UserDefaults.standard.bool(forKey: "hideNotchInFullScreen")
        )
        #expect(settings.hideNotchInFullScreen)
        #expect(settings.watchesFullScreenApps)

        settings.hideNotchInFullScreen = false
        #expect(
            !UserDefaults.standard.bool(forKey: "hideNotchInFullScreen")
        )
        #expect(!settings.hideNotchInFullScreen)
    }

    @Test @MainActor func hideNotchFullScreenAppsPersistAndDedupe() {
        let settings = AppSettings.shared
        let original = settings.hideNotchFullScreenApps
        let originalHide = settings.hideNotchInFullScreen
        let originalStyle = settings.notchEdgeStyle
        let originalOutline = settings.notchOutlineWhenNotFullScreen
        defer {
            settings.hideNotchFullScreenApps = original
            settings.hideNotchInFullScreen = originalHide
            settings.notchEdgeStyle = originalStyle
            settings.notchOutlineWhenNotFullScreen = originalOutline
        }

        settings.hideNotchInFullScreen = false
        settings.notchEdgeStyle = .off
        settings.notchOutlineWhenNotFullScreen = true
        settings.hideNotchFullScreenApps = []
        settings.addHideNotchFullScreenApp("org.videolan.vlc")
        settings.addHideNotchFullScreenApp(" org.videolan.vlc ")
        settings.addHideNotchFullScreenApp("")
        settings.addHideNotchFullScreenApp("com.apple.QuickTimePlayerX")
        #expect(
            settings.hideNotchFullScreenApps == [
                "org.videolan.vlc", "com.apple.QuickTimePlayerX",
            ]
        )
        #expect(
            UserDefaults.standard.stringArray(forKey: "hideNotchFullScreenApps")
                == ["org.videolan.vlc", "com.apple.QuickTimePlayerX"]
        )
        #expect(settings.watchesFullScreenApps)

        settings.removeHideNotchFullScreenApp("org.videolan.vlc")
        #expect(
            settings.hideNotchFullScreenApps == ["com.apple.QuickTimePlayerX"]
        )
        settings.removeHideNotchFullScreenApp("com.apple.QuickTimePlayerX")
        #expect(settings.hideNotchFullScreenApps.isEmpty)
        #expect(!settings.watchesFullScreenApps)
    }

    @Test @MainActor func notchEdgeStylePersists() {
        let settings = AppSettings.shared
        let original = settings.notchEdgeStyle
        defer { settings.notchEdgeStyle = original }

        settings.notchEdgeStyle = .accent
        #expect(
            UserDefaults.standard.string(forKey: "notchEdgeStyle") == "accent"
        )
        #expect(settings.notchEdgeStyle == .accent)

        settings.notchEdgeStyle = .subtle
        #expect(
            UserDefaults.standard.string(forKey: "notchEdgeStyle") == "subtle"
        )
        #expect(settings.notchEdgeStyle == .subtle)

        settings.notchEdgeStyle = .off
        #expect(UserDefaults.standard.string(forKey: "notchEdgeStyle") == "off")
        #expect(settings.notchEdgeStyle == .off)
    }

    @Test @MainActor func showSpotifyLikeButtonPersists() {
        let settings = AppSettings.shared
        let original = settings.showSpotifyLikeButton
        defer { settings.showSpotifyLikeButton = original }

        settings.showSpotifyLikeButton = false
        #expect(
            UserDefaults.standard.object(forKey: "showSpotifyLikeButton")
                as? Bool == false
        )
        #expect(!settings.showSpotifyLikeButton)

        settings.showSpotifyLikeButton = true
        #expect(UserDefaults.standard.bool(forKey: "showSpotifyLikeButton"))
        #expect(settings.showSpotifyLikeButton)
    }

    @Test @MainActor func mediaToolbarItemsPersistAndSanitize() {
        let settings = AppSettings.shared
        let original = settings.mediaToolbarItems
        defer { settings.mediaToolbarItems = original }

        settings.mediaToolbarItems = [.playPause, .playPause, .next]
        #expect(settings.mediaToolbarItems == [.playPause, .next])
        #expect(
            UserDefaults.standard.stringArray(forKey: "mediaToolbarItems")
                == ["playPause", "next"]
        )

        settings.mediaToolbarItems = MediaToolbarItem.defaultLayout()
        #expect(
            settings.mediaToolbarItems
                == MediaToolbarItem.defaultLayout()
        )
    }

    @Test @MainActor func notchOutlineWhenNotFullScreenPersists() {
        let settings = AppSettings.shared
        let original = settings.notchOutlineWhenNotFullScreen
        defer { settings.notchOutlineWhenNotFullScreen = original }

        settings.notchOutlineWhenNotFullScreen = false
        #expect(
            UserDefaults.standard.object(forKey: "notchOutlineWhenNotFullScreen")
                as? Bool == false
        )
        #expect(!settings.notchOutlineWhenNotFullScreen)

        settings.notchOutlineWhenNotFullScreen = true
        #expect(
            UserDefaults.standard.bool(forKey: "notchOutlineWhenNotFullScreen")
        )
        #expect(settings.notchOutlineWhenNotFullScreen)
    }

    @Test @MainActor func liquidGlassTintsPersistIndependently() {
        let settings = AppSettings.shared
        let originalWindowed = settings.liquidGlassTintWhenNotFullScreen
        let originalFullScreen = settings.liquidGlassTintFullScreen
        defer {
            settings.liquidGlassTintWhenNotFullScreen = originalWindowed
            settings.liquidGlassTintFullScreen = originalFullScreen
        }

        settings.liquidGlassTintWhenNotFullScreen = .regular
        settings.liquidGlassTintFullScreen = .clear
        #expect(
            UserDefaults.standard.string(
                forKey: "liquidGlassTintWhenNotFullScreen"
            ) == "regular"
        )
        #expect(
            UserDefaults.standard.string(forKey: "liquidGlassTintFullScreen")
                == "clear"
        )
        #expect(settings.liquidGlassTintWhenNotFullScreen == .regular)
        #expect(settings.liquidGlassTintFullScreen == .clear)

        settings.liquidGlassTintWhenNotFullScreen = .clear
        settings.liquidGlassTintFullScreen = .regular
        #expect(
            UserDefaults.standard.string(
                forKey: "liquidGlassTintWhenNotFullScreen"
            ) == "clear"
        )
        #expect(
            UserDefaults.standard.string(forKey: "liquidGlassTintFullScreen")
                == "regular"
        )
        #expect(settings.liquidGlassTintWhenNotFullScreen == .clear)
        #expect(settings.liquidGlassTintFullScreen == .regular)
    }

    @Test @MainActor func lockScreenLiquidGlassTintPersists() {
        let settings = AppSettings.shared
        let original = settings.lockScreenLiquidGlassTint
        defer { settings.lockScreenLiquidGlassTint = original }

        settings.lockScreenLiquidGlassTint = .regular
        #expect(
            UserDefaults.standard.string(forKey: "lockScreenLiquidGlassTint")
                == "regular"
        )
        #expect(settings.lockScreenLiquidGlassTint == .regular)

        settings.lockScreenLiquidGlassTint = .identity
        #expect(
            UserDefaults.standard.string(forKey: "lockScreenLiquidGlassTint")
                == "identity"
        )
        #expect(settings.lockScreenLiquidGlassTint == .identity)

        settings.lockScreenLiquidGlassTint = .clear
        #expect(
            UserDefaults.standard.string(forKey: "lockScreenLiquidGlassTint")
                == "clear"
        )
        #expect(settings.lockScreenLiquidGlassTint == .clear)
    }

    @Test @MainActor func watchesFullScreenAppsForOutlineWhenNotFullScreen() {
        let settings = AppSettings.shared
        let originalStyle = settings.notchEdgeStyle
        let originalOutline = settings.notchOutlineWhenNotFullScreen
        let originalHide = settings.hideNotchInFullScreen
        let originalApps = settings.hideNotchFullScreenApps
        defer {
            settings.notchEdgeStyle = originalStyle
            settings.notchOutlineWhenNotFullScreen = originalOutline
            settings.hideNotchInFullScreen = originalHide
            settings.hideNotchFullScreenApps = originalApps
        }

        settings.hideNotchInFullScreen = false
        settings.hideNotchFullScreenApps = []
        settings.notchEdgeStyle = .off
        settings.notchOutlineWhenNotFullScreen = false
        #expect(!settings.watchesFullScreenApps)

        settings.notchEdgeStyle = .subtle
        #expect(settings.watchesFullScreenApps)

        settings.notchOutlineWhenNotFullScreen = true
        #expect(!settings.watchesFullScreenApps)
    }

    @Test func soundwaveMotionCaptureAndTitles() {
        for motion in SoundwaveMotion.allCases {
            #expect(SoundwaveMotion(rawValue: motion.rawValue) == motion)
        }
        #expect(SoundwaveMotion.live.title == "Live")
        #expect(SoundwaveMotion.decorative.title == "Decorative")
        #expect(SoundwaveMotion.off.title == "Off")
        #expect(SoundwaveMotion.live.usesLiveAudio)
        #expect(!SoundwaveMotion.decorative.usesLiveAudio)
        #expect(SoundwaveMotion.live.showsAnimatedBars)
        #expect(!SoundwaveMotion.off.showsAnimatedBars)
        #expect(
            SoundwaveMotion.live.shouldCapture(isPlaying: true, idle: false)
        )
        #expect(
            !SoundwaveMotion.live.shouldCapture(isPlaying: true, idle: true)
        )
        #expect(
            !SoundwaveMotion.decorative.shouldCapture(
                isPlaying: true,
                idle: false
            )
        )
        #expect(
            !SoundwaveMotion.off.shouldCapture(isPlaying: true, idle: false)
        )
    }

    @Test func soundwaveFeelPresetsGetSnappier() {
        #expect(SoundwaveFeel.snappy.attack > SoundwaveFeel.balanced.attack)
        #expect(SoundwaveFeel.balanced.attack > SoundwaveFeel.calm.attack)
        #expect(SoundwaveFeel.snappy.release > SoundwaveFeel.balanced.release)
        #expect(SoundwaveFeel.balanced.release > SoundwaveFeel.calm.release)
        #expect(SoundwaveFeel.snappy.peakDecay < SoundwaveFeel.balanced.peakDecay)
        #expect(SoundwaveFeel.balanced.peakDecay < SoundwaveFeel.calm.peakDecay)
        #expect(SoundwaveFeel.snappy.mockSpeed > SoundwaveFeel.balanced.mockSpeed)
        #expect(SoundwaveFeel.calm.title == "Calm")
        #expect(SoundwaveFeel.balanced.title == "Balanced")
        #expect(SoundwaveFeel.snappy.title == "Snappy")
    }

    @Test func soundwaveTonePresetsGetBrighter() {
        #expect(SoundwaveTone.bright.tilt > SoundwaveTone.balanced.tilt)
        #expect(SoundwaveTone.balanced.tilt > SoundwaveTone.warm.tilt)
        #expect(
            SoundwaveTone.bright.minFrequency
                > SoundwaveTone.balanced.minFrequency
        )
        #expect(
            SoundwaveTone.balanced.minFrequency > SoundwaveTone.warm.minFrequency
        )
        #expect(SoundwaveTone.warm.title == "Warm")
        #expect(SoundwaveTone.balanced.title == "Balanced")
        #expect(SoundwaveTone.bright.title == "Bright")
    }

    @Test @MainActor func soundwaveSettingsPersist() {
        let settings = AppSettings.shared
        let original = (
            settings.soundwaveMotion,
            settings.soundwaveFeel,
            settings.soundwaveTone,
            settings.collapsedWaveformsAccent
        )
        defer {
            settings.soundwaveMotion = original.0
            settings.soundwaveFeel = original.1
            settings.soundwaveTone = original.2
            settings.collapsedWaveformsAccent = original.3
        }

        settings.soundwaveMotion = .decorative
        settings.soundwaveFeel = .snappy
        settings.soundwaveTone = .warm
        settings.collapsedWaveformsAccent = true
        #expect(
            UserDefaults.standard.string(forKey: "soundwaveMotion")
                == "decorative"
        )
        #expect(
            UserDefaults.standard.string(forKey: "soundwaveFeel") == "snappy"
        )
        #expect(UserDefaults.standard.string(forKey: "soundwaveTone") == "warm")
        #expect(
            UserDefaults.standard.object(forKey: "collapsedWaveformsAccent")
                as? Bool == true
        )
        #expect(settings.soundwaveMotion == .decorative)
        #expect(settings.soundwaveFeel == .snappy)
        #expect(settings.soundwaveTone == .warm)
        #expect(settings.collapsedWaveformsAccent)

        settings.soundwaveMotion = .live
        settings.soundwaveFeel = .balanced
        settings.soundwaveTone = .bright
        settings.collapsedWaveformsAccent = false
        #expect(settings.soundwaveMotion == .live)
    }

    @Test func lockScreenAccessoryCatalogIncludesFocus() {
        #expect(
            LockScreenAccessory.allCases == [
                .weather, .bluetooth, .battery, .focus,
            ]
        )
        #expect(LockScreenAccessory.focus.title == "Focus")
        #expect(LockScreenAccessory.focus.id == "focus")
    }

    @Test func lockScreenWeatherGraphKindsHaveTitles() {
        #expect(
            LockScreenWeatherGraphKind.allCases == [
                .temperature, .precipitation, .both,
            ]
        )
        #expect(LockScreenWeatherGraphKind.temperature.title == "Temperature")
        #expect(LockScreenWeatherGraphKind.precipitation.title == "Precipitation")
        #expect(LockScreenWeatherGraphKind.both.title == "Temperature + rain")
        #expect(LockScreenWeatherGraphKind(rawValue: "both") == .both)
        #expect(LockScreenWeatherGraphKind(rawValue: "nope") == nil)
    }

    @Test @MainActor func enabledLockScreenAccessoriesHonorsFocusToggle() {
        let settings = AppSettings.shared
        let originalOrder = settings.lockScreenAccessoryOrder
        let originalWeather = settings.lockScreenWeatherAccessory
        let originalBluetooth = settings.lockScreenBluetoothAccessory
        let originalBattery = settings.lockScreenBatteryAccessory
        let originalFocus = settings.lockScreenFocusAccessory
        defer {
            settings.lockScreenAccessoryOrder = originalOrder
            settings.lockScreenWeatherAccessory = originalWeather
            settings.lockScreenBluetoothAccessory = originalBluetooth
            settings.lockScreenBatteryAccessory = originalBattery
            settings.lockScreenFocusAccessory = originalFocus
        }

        settings.lockScreenAccessoryOrder = [
            .weather, .focus, .bluetooth, .battery,
        ]
        settings.lockScreenWeatherAccessory = false
        settings.lockScreenBluetoothAccessory = false
        settings.lockScreenBatteryAccessory = false
        settings.lockScreenFocusAccessory = true
        #expect(settings.enabledLockScreenAccessories == [.focus])
        #expect(settings.isLockScreenAccessoryEnabled(.focus))
        #expect(!settings.isLockScreenAccessoryEnabled(.weather))

        settings.lockScreenFocusAccessory = false
        #expect(settings.enabledLockScreenAccessories.isEmpty)
        #expect(
            UserDefaults.standard.object(forKey: "lockScreenFocusAccessory")
                as? Bool == false
        )
    }

    @Test @MainActor func lockScreenWeatherGraphKindPersists() {
        let settings = AppSettings.shared
        let original = settings.lockScreenWeatherGraphKind
        defer { settings.lockScreenWeatherGraphKind = original }

        settings.lockScreenWeatherGraphKind = .precipitation
        #expect(
            UserDefaults.standard.string(forKey: "lockScreenWeatherGraphKind")
                == "precipitation"
        )
        settings.lockScreenWeatherGraphKind = .both
        #expect(
            UserDefaults.standard.string(forKey: "lockScreenWeatherGraphKind")
                == "both"
        )
    }

    @Test @MainActor func idlePlaySettingsPersist() {
        let settings = AppSettings.shared
        let originalButton = settings.idlePlayButton
        let originalApp = settings.idlePlayApp
        let originalRecents = settings.idleRecentSuggestions
        defer {
            settings.idlePlayButton = originalButton
            settings.idlePlayApp = originalApp
            settings.idleRecentSuggestions = originalRecents
        }

        settings.idlePlayButton = true
        settings.idlePlayApp = .spotify
        settings.idleRecentSuggestions = true
        #expect(UserDefaults.standard.bool(forKey: "idlePlayButton"))
        #expect(UserDefaults.standard.string(forKey: "idlePlayApp") == "spotify")
        #expect(UserDefaults.standard.bool(forKey: "idleRecentSuggestions"))
        #expect(settings.idlePlayApp.title == "Spotify")
        #expect(IdlePlayApp.automatic.title == "Automatic")

        settings.idlePlayButton = false
        settings.idleRecentSuggestions = false
        #expect(
            UserDefaults.standard.object(forKey: "idlePlayButton") as? Bool
                == false
        )
        #expect(
            UserDefaults.standard.object(forKey: "idleRecentSuggestions")
                as? Bool == false
        )
    }
}
