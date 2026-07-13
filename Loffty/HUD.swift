//
//  HUD.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 11/07/2026.
//

import AudioToolbox
import CoreAudio
import CoreGraphics
import SwiftUI

enum SystemHUD {
    static func suppress() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["OSDUIHelper"]
        try? p.run()
        //        DispatchQueue.main.asyncAfter(deadline: .now()+0.05){
        //            try? p.run()
        //        }
    }
}

final class SystemVolumeWatcher {
    var onChange: ((Float, Bool) -> Void)?
    private var device = AudioDeviceID(0)
    private var armed = false
    private var lastVol: Float = -1
    private var lastMuted = false

    func start() {
        device = defaultOutputDevice()
        var addr = mainVolumeAddress()
        AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main) {
            [weak self] _, _ in
            self?.emit()
        }
        lastVol = readVolume()
        lastMuted = readMuted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.armed = true
        }
    }

    private func emit() {
        let vol = readVolume()
        let muted = readMuted()
        guard armed else {
            lastVol = vol
            lastMuted = muted
            return
        }
        guard vol != lastVol || muted != lastMuted else { return }
        lastVol = vol
        lastMuted = muted
        onChange?(vol, muted)
    }

    private func readVolume() -> Float {
        var addr = mainVolumeAddress()
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol)
                == noErr
        else { return 0 }
        return vol
    }

    private func readMuted() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted)
                == noErr
        else { return false }
        return muted != 0
    }

    private func mainVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultOutputDevice() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &id
        )
        return id
    }
}

enum DisplayServicesBridge {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let canChange: CanChange? = load(
        "DisplayServicesCanChangeBrightness"
    )
    private static let getBrightness: GetBrightness? = load(
        "DisplayServicesGetBrightness"
    )
    private static func load<T>(_ name: String) -> T? {
        let path =
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
            let sym = dlsym(handle, name)
        else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
    static func currentBrightness() -> Float? {
        let display = CGMainDisplayID()
        guard canChange?(display) == true, let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return max(0, min(1, value))
    }
}

final class SystemBrightnessWatcher {
    var onChange: ((Float) -> Void)?
    private var timer: Timer?
    private var last: Float = -1
    private var armed = false

    func start() {
        if let level = DisplayServicesBridge.currentBrightness() {
            last = level
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self] _ in
            self?.emit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.armed = true
        }
    }
    func stop() { timer?.invalidate() }
    private func emit() {
        guard let level = DisplayServicesBridge.currentBrightness() else {
            return
        }
        guard abs(level - last) > 0.004 else { return }
        last = level
        guard armed else { return }
        onChange?(level)
    }
}
