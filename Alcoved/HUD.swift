//
//  HUD.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 11/07/2026.
//

import AudioToolbox
import CoreAudio
import SwiftUI

enum SystemHUD {
    static func suppress() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["OSDUIHelper"]
        try? p.run()
    }
}

final class SystemVolumeWatcher {
    var onChange: ((Float) -> Void)?
    private var device = AudioDeviceID(0)

    func start() {
        device = defaultOutputDevice()
        var addr = mainVolumeAddress()
        AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.emit()
        }
    }

    private func emit() {
        var addr = mainVolumeAddress()
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol) == noErr {
            onChange?(vol)
        }
    }

    private func mainVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private func defaultOutputDevice() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
}
