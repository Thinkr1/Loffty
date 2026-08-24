//
//  PrivacyAccess.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 11/08/2026.
//

import AppKit
import ApplicationServices
import IOBluetooth
import Network
import ServiceManagement

@MainActor
enum PrivacyAccess {
    private static var localNetworkBrowser: NWBrowser?
    private static var bluetoothProbeNote: IOBluetoothUserNotification?

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var launchAtLoginNeedsApproval: Bool {
        LaunchAtLogin.requiresApproval
    }

    static func requestAccessibilityPrompt() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func primeLocalNetworkAccess() {
        guard localNetworkBrowser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_airdrop._tcp", domain: nil),
            using: params
        )
        browser.stateUpdateHandler = { (_: NWBrowser.State) in }
        browser.browseResultsChangedHandler = {
            (_: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
        }
        browser.start(queue: .main)
        localNetworkBrowser = browser
    }

    static func stopLocalNetworkPrime() {
        localNetworkBrowser?.cancel()
        localNetworkBrowser = nil
    }

    static func requestBluetoothAccess() {
        guard bluetoothProbeNote == nil else { return }
        bluetoothProbeNote = IOBluetoothDevice.register(
            forConnectNotifications: BluetoothProbe.shared,
            selector: #selector(BluetoothProbe.connected(_:device:))
        )
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openBluetoothSettings() {
        openPrivacyPane("Privacy_Bluetooth")
    }

    static func openLocalNetworkSettings() {
        openPrivacyPane("Privacy_LocalNetwork")
    }

    static func openFullDiskAccessSettings() {
        openPrivacyPane("Privacy_AllFiles")
    }

    static func openLocationSettings() {
        openPrivacyPane("Privacy_LocationServices")
    }

    static func openAutomationSettings() {
        openPrivacyPane("Privacy_Automation")
    }

    nonisolated static func privacySettingsURLCandidates(anchor: String)
        -> [String]
    {
        [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ]
    }

    private static func openPrivacyPane(_ anchor: String) {
        for candidate in privacySettingsURLCandidates(anchor: anchor) {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private final class BluetoothProbe: NSObject {
    static let shared = BluetoothProbe()

    @objc func connected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {}
}
