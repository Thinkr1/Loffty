//
//  StatusHUD.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 16/07/2026.
//

import AppKit
import IOBluetooth
import IOKit.ps
import SwiftUI

final class BatteryHUDWatcher {
    var onChange: ((Int, Bool, Bool) -> Void)?
    private var source: CFRunLoopSource?
    private var armed = false
    private var lastPercent = -1
    private var lastCharging: Bool?
    private var lastOnAC: Bool?

    func start() {
        guard source == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard
            let src = IOPSNotificationCreateRunLoopSource(
                { info in
                    guard let info else { return }
                    Unmanaged<BatteryHUDWatcher>.fromOpaque(info)
                        .takeUnretainedValue()
                        .emit()
                },
                ctx
            )?
            .takeRetainedValue()
        else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        snapshot(seed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.armed = true
        }
    }

    func stop() {
        if let src = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        source = nil
        armed = false
        lastPercent = -1
        lastCharging = nil
        lastOnAC = nil
    }

    private func emit() {
        snapshot(seed: false)
    }

    private func snapshot(seed: Bool) {
        guard let info = currentBattery() else { return }
        if seed {
            lastPercent = info.percent
            lastCharging = info.charging
            lastOnAC = info.onAC
            return
        }
        guard armed else {
            lastPercent = info.percent
            lastCharging = info.charging
            lastOnAC = info.onAC
            return
        }

        let acChanged = lastOnAC.map { $0 != info.onAC } ?? false
        let chargeChanged = lastCharging.map { $0 != info.charging } ?? false
        let crossedLow =
            crossedThreshold(from: lastPercent, to: info.percent, at: 20)
            || crossedThreshold(from: lastPercent, to: info.percent, at: 10)

        lastPercent = info.percent
        lastCharging = info.charging
        lastOnAC = info.onAC

        guard acChanged || chargeChanged || crossedLow else { return }
        onChange?(info.percent, info.charging || info.onAC, acChanged)
    }

    private func crossedThreshold(from old: Int, to new: Int, at mark: Int)
        -> Bool
    {
        old > mark && new <= mark
    }

    private func currentBattery() -> (
        percent: Int, charging: Bool, onAC: Bool
    )? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
                as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                let capacity = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }

            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let onAC = state == kIOPSACPowerValue
            return (max(0, min(100, capacity)), isCharging, onAC)
        }
        return nil
    }
}

final class BluetoothHUDWatcher: NSObject {
    var onChange: ((String, Bool) -> Void)?
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes:
        [ObjectIdentifier: IOBluetoothUserNotification] =
            [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(connected(_:device:))
        )
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
            ?? []
        {
            guard device.isConnected() else { continue }
            registerDisconnect(for: device)
        }
    }

    func stop() {
        connectNote?.unregister()
        connectNote = nil
        for note in disconnectNotes.values {
            note.unregister()
        }
        disconnectNotes.removeAll()
        started = false
    }

    @objc private func connected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let name = deviceName(device)
        onChange?(name, true)
        registerDisconnect(for: device)
    }

    @objc private func disconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let id = ObjectIdentifier(device)
        disconnectNotes.removeValue(forKey: id)?.unregister()
        onChange?(deviceName(device), false)
    }

    private func registerDisconnect(for device: IOBluetoothDevice) {
        let id = ObjectIdentifier(device)
        guard disconnectNotes[id] == nil else { return }
        disconnectNotes[id] = device.register(
            forDisconnectNotification: self,
            selector: #selector(disconnected(_:device:))
        )
    }

    private func deviceName(_ device: IOBluetoothDevice) -> String {
        if let name = device.nameOrAddress, !name.isEmpty { return name }
        if let address = device.addressString, !address.isEmpty {
            return address
        }
        return "Bluetooth"
    }
}
