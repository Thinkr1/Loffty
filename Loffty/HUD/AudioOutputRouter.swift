//
//  AudioOutputRouter.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 09/08/2026.
//

import AudioToolbox
import SwiftUI

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let icon: String
    let isDefault: Bool
}

enum AudioOutputRouter {
    static func availableDevices() -> [AudioOutputDevice] {
        let defaultID = OutputDeviceIcon.defaultOutputDevice()
        return allDeviceIDs()
            .filter(hasOutputStreams)
            .compactMap { id -> AudioOutputDevice? in
                guard let name = OutputDeviceIcon.deviceName(id), !name.isEmpty
                else { return nil }
                let transport = OutputDeviceIcon.transportType(id)
                return AudioOutputDevice(
                    id: id,
                    name: name,
                    icon: OutputDeviceIcon.symbolForDevice(
                        name: name,
                        transport: transport
                    ),
                    isDefault: id == defaultID
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        var value = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &value
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                0,
                nil,
                &size
            ) == noErr,
            size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                0,
                nil,
                &size,
                &ids
            ) == noErr
        else { return [] }
        return ids
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size)
                == noErr
        else { return false }
        return size > 0
    }
}
