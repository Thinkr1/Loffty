//
//  HUDKindTests.swift
//  LofftyTests
//

import Testing

@testable import Loffty

@Suite("HUDKind")
struct HUDKindTests {
    @Test func presentsVerticallyForLevelHUDsOnly() {
        #expect(
            HUDKind.volume(symbol: OutputDeviceIcon.speaker).presentsVertically
        )
        #expect(HUDKind.brightness.presentsVertically)
        #expect(
            HUDKind.battery(percent: 50, charging: false).presentsVertically
        )
        #expect(
            !HUDKind.bluetooth(name: "AirPods", connected: true)
                .presentsVertically
        )
        #expect(!HUDKind.focus(enabled: true, name: "Work").presentsVertically)
        #expect(HUDKind.bluetooth(name: "x", connected: true).presentsOnSides)
    }

    @Test func isLevelFlags() {
        #expect(HUDKind.volume(symbol: "speaker.wave.2.fill").isLevel)
        #expect(HUDKind.brightness.isLevel)
        #expect(HUDKind.battery(percent: 10, charging: false).isLevel)
        #expect(!HUDKind.focus(enabled: false).isLevel)
    }

    @Test(arguments: [
        (100, false, "battery.100"),
        (90, false, "battery.100"),
        (70, false, "battery.75"),
        (50, false, "battery.50"),
        (20, false, "battery.25"),
        (5, false, "battery.0"),
        (40, true, "battery.100.bolt"),
    ])
    func batterySymbol(percent: Int, charging: Bool, expected: String) {
        #expect(
            BatteryIcon.symbol(percent: percent, charging: charging) == expected
        )
    }

    @Test func shortBluetoothNameTruncatesAt12() {
        #expect(HUDText.shortBluetoothName("AirPods Pro") == "AirPods Pro")
        #expect(
            HUDText.shortBluetoothName("Very Long Device Name")
                == "Very Long D..."
        )
    }

    @Test func accents() {
        let focusOn = HUDKind.focus(enabled: true, name: "Work").accent
        let focusOff = HUDKind.focus(enabled: false, name: "Work").accent
        #expect(focusOn == FocusPalette.accent(for: "Work"))
        #expect(focusOff != focusOn)

        let btOn = HUDKind.bluetooth(name: "x", connected: true).accent
        let btOff = HUDKind.bluetooth(name: "x", connected: false).accent
        #expect(btOn != btOff)
    }
}
