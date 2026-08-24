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
            "PL's AirPods Max", kAudioDeviceTransportTypeBluetooth,
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
        ("JBL Flip 6", kAudioDeviceTransportTypeBluetooth, "hifispeaker.fill"),
        (
            "Bose SoundLink Mini", kAudioDeviceTransportTypeBluetooth,
            "hifispeaker.fill"
        ),
        (
            "Generic Soundbar", kAudioDeviceTransportTypeUSB,
            "hifispeaker.fill"
        ),
    ])
    func symbol(name: String, transport: UInt32, expected: String) {
        #expect(
            OutputDeviceIcon.symbol(name: name, transport: transport)
                == expected
        )
    }

    @Test(arguments: [
        (
            "Unnamed BT Speaker", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x05), "hifispeaker.fill"
        ),
        (
            "Unnamed BT Headset", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x06), "headphones"
        ),
        (
            "Unnamed BT Hands-Free", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x02), "headphones"
        ),
        (
            "Unnamed Car Kit", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x08), "car.fill"
        ),
        (
            "Unnamed HiFi Device", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x0A), "hifispeaker.fill"
        ),
        (
            "Unnamed Gadget", kAudioDeviceTransportTypeBluetooth,
            UInt32(0x12), "headphones"
        ),
    ])
    func symbolWithBluetoothClass(
        name: String,
        transport: UInt32,
        minorClass: UInt32,
        expected: String
    ) {
        #expect(
            OutputDeviceIcon.symbol(
                name: name,
                transport: transport,
                bluetoothMinorClass: minorClass
            ) == expected
        )
    }
}
