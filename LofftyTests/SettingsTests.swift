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
}
