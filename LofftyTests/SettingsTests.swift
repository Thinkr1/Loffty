//
//  SettingsTests.swift
//  LofftyTests
//

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
}
