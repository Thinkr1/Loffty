//
//  SettingsTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Settings")
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
        defer { settings.hideNotchFullScreenApps = original }

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
}
