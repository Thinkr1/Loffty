//
//  AirPlayPicker.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 09/08/2026.
//

import AppKit
import AudioToolbox
import SwiftUI

struct AirPlayPickerButton: View {
    var body: some View {
        ControlButton(
            systemName: "airplayaudio",
            size: 12,
            tint: .white.opacity(0.45),
            hitSize: 28
        ) {
            presentDeviceMenu()
        }
    }

    private func presentDeviceMenu() {
        let devices = AudioOutputRouter.availableDevices()
        let menu = NSMenu()
        menu.autoenablesItems = false

        if devices.isEmpty {
            let empty = NSMenuItem(
                title: "No Output Devices Found",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(AirPlayMenuTarget.selectDevice(_:)),
                    keyEquivalent: ""
                )
                item.target = AirPlayMenuTarget.shared
                item.image = NSImage(
                    systemSymbolName: device.icon,
                    accessibilityDescription: nil
                )
                item.state = device.isDefault ? .on : .off
                item.representedObject = device.id
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class AirPlayMenuTarget: NSObject {
    static let shared = AirPlayMenuTarget()

    @objc func selectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else {
            return
        }
        AudioOutputRouter.setDefaultOutput(id)
    }
}
