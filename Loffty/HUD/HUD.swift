//
//  HUD.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 11/07/2026.
//

import AudioToolbox
import SwiftUI

private enum NXKeyType: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

final class SystemVolumeController {
    static let shared = SystemVolumeController()
    private var device = AudioDeviceID(0)

    private init() {
        device = defaultOutputDevice()
    }

    func readVolume() -> Float {
        var addr = mainVolumeAddress()
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol)
                == noErr
        else { return 0 }
        return vol
    }

    func readMuted() -> Bool {
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

    func adjust(by delta: Float) {
        let vol = max(0, min(1, readVolume() + delta))
        writeVolume(vol)
        if vol > 0 { writeMuted(false) }
    }

    func toggleMute() {
        writeMuted(!readMuted())
    }

    private func writeVolume(_ vol: Float) {
        var value = vol
        var addr = mainVolumeAddress()
        AudioObjectSetPropertyData(
            device,
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
    }

    private func writeMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            device,
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
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

final class SystemVolumeWatcher {
    var onChange: ((Float, Bool) -> Void)?
    private let controller = SystemVolumeController.shared
    private var armed = false
    private var lastVol: Float = -1
    private var lastMuted = false

    func start() {
        var device = AudioDeviceID(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &device
        )
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            device,
            &volAddr,
            DispatchQueue.main
        ) {
            [weak self] _, _ in
            self?.emit()
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            device,
            &muteAddr,
            DispatchQueue.main
        ) {
            [weak self] _, _ in
            self?.emit()
        }
        lastVol = controller.readVolume()
        lastMuted = controller.readMuted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.armed = true
        }
    }

    private func emit() {
        let vol = controller.readVolume()
        let muted = controller.readMuted()
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
}

enum DisplayServicesBridge {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness =
        @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let canChange: CanChange? = load(
        "DisplayServicesCanChangeBrightness"
    )
    private static let getBrightness: GetBrightness? = load(
        "DisplayServicesGetBrightness"
    )
    private static let setBrightness: SetBrightness? = load(
        "DisplayServicesSetBrightness"
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

    static func adjustBrightness(by delta: Float) {
        guard let current = currentBrightness() else { return }
        setLevel(max(0, min(1, current + delta)))
    }

    @discardableResult
    private static func setLevel(_ value: Float) -> Bool {
        let display = CGMainDisplayID()
        guard canChange?(display) == true, let setBrightness else {
            return false
        }
        return setBrightness(display, value) == 0
    }
}

final class SystemBrightnessWatcher {
    var onChange: ((Float) -> Void)?
    private var timer: Timer?
    private var last: Float = -1
    private var armed = false
    private var suppressUntil = Date.distantPast

    func start() {
        guard timer == nil else { return }
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
    func stop() {
        timer?.invalidate()
        timer = nil
        armed = false
        last = -1
        suppressUntil = Date.distantPast
    }

    /// Ignore brightness deltas for a bit (e.g. AC plug auto-brightness).
    func suppress(for interval: TimeInterval = 2.8) {
        suppressUntil = Date().addingTimeInterval(interval)
        if let level = DisplayServicesBridge.currentBrightness() {
            last = level
        }
    }

    private func emit() {
        guard let level = DisplayServicesBridge.currentBrightness() else {
            return
        }
        if Date() < suppressUntil {
            last = level
            return
        }
        guard abs(level - last) > 0.004 else { return }
        last = level
        guard armed else { return }
        onChange?(level)
    }
}

final class SystemKeyInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private(set) var isEnabled = false

    private static let normalStep: Float = 1.0 / 16.0
    private static let fineStep: Float = 1.0 / 64.0
    private static let replaceKey = "replaceSystemHUD"
    private static let brightnessHUDKey = "brightnessHUD"

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard eventTap == nil else { return }
        requestAccessibilityIfNeeded()

        let eventMask: CGEventMask = 1 << 14  //NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, info in
                    guard let info else {
                        return Unmanaged.passRetained(event)
                    }
                    let interceptor = Unmanaged<SystemKeyInterceptor>
                        .fromOpaque(
                            info
                        ).takeUnretainedValue()
                    return interceptor.handle(type: type, event: event)
                },
                userInfo: refcon
            )
        else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        )
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reenableTap()
        }
    }

    private func stop() {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static func adjustmentStep(for event: CGEvent) -> Float {
        let flags = event.flags.union(CGEventSource.flagsState(.hidSystemState))
        if flags.contains(.maskAlternate), flags.contains(.maskShift) {
            return fineStep
        }
        return normalStep
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<
        CGEvent
    >? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableTap()
            return Unmanaged.passRetained(event)
        }

        guard type.rawValue == 14,
            let nsEvent = NSEvent(cgEvent: event),
            nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0x0A else { return Unmanaged.passRetained(event) }

        let replace =
            UserDefaults.standard.object(forKey: Self.replaceKey) as? Bool
            ?? true
        let brightnessHUD =
            UserDefaults.standard.object(forKey: Self.brightnessHUDKey) as? Bool
            ?? true

        let step = Self.adjustmentStep(for: event)

        switch keyCode {
        case NXKeyType.soundUp.rawValue where replace:
            SystemVolumeController.shared.adjust(by: step)
            return nil
        case NXKeyType.soundDown.rawValue where replace:
            SystemVolumeController.shared.adjust(by: -step)
            return nil
        case NXKeyType.mute.rawValue where replace:
            SystemVolumeController.shared.toggleMute()
            return nil
        case NXKeyType.brightnessUp.rawValue where replace && brightnessHUD:
            DisplayServicesBridge.adjustBrightness(by: step)
            return nil
        case NXKeyType.brightnessDown.rawValue where replace && brightnessHUD:
            DisplayServicesBridge.adjustBrightness(by: -step)
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }

    deinit { stop() }
}
