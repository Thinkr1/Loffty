//
//  OutputDeviceIconTests.swift
//  LofftyTests
//

import AudioToolbox
import Testing

@testable import Loffty

@Suite("OutputDeviceIcon")
struct OutputDeviceIconTests {
    @Test(arguments: [
        (
            "Pierre’s AirPods Max", kAudioDeviceTransportTypeBluetooth,
            "airpods.max"
        ),
        ("AirPods Pro", kAudioDeviceTransportTypeBluetooth, "airpods.pro"),
        ("AirPods", kAudioDeviceTransportTypeBluetooth, "airpods"),
        (
            "Beats Studio Buds", kAudioDeviceTransportTypeBluetooth,
            "beats.studiobuds"
        ),
        (
            "Powerbeats Pro", kAudioDeviceTransportTypeBluetooth,
            "beats.powerbeats"
        ),
        ("BeatsX", kAudioDeviceTransportTypeBluetooth, "beats.earphones"),
        ("Beats Solo", kAudioDeviceTransportTypeBluetooth, "beats.headphones"),
        ("HomePod", kAudioDeviceTransportTypeAirPlay, "homepod.fill"),
        ("Apple TV", kAudioDeviceTransportTypeAirPlay, "appletv.fill"),
        ("WH-1000XM5", kAudioDeviceTransportTypeBluetooth, "headphones"),
        ("WH-1000XM5", kAudioDeviceTransportTypeBluetoothLE, "headphones"),
        ("Living Room", kAudioDeviceTransportTypeAirPlay, "airplayaudio"),
        (
            "MacBook Pro Speakers", kAudioDeviceTransportTypeBuiltIn,
            OutputDeviceIcon.speaker
        ),
        ("USB Headset", kAudioDeviceTransportTypeUSB, "headphones"),
        (
            "Display Audio", kAudioDeviceTransportTypeDisplayPort,
            OutputDeviceIcon.speaker
        ),
    ])
    func symbol(name: String, transport: UInt32, expected: String) {
        #expect(
            OutputDeviceIcon.symbol(name: name, transport: transport)
                == expected
        )
    }
}
