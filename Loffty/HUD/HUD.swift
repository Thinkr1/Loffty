//
//  HUD.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 11/07/2026.
//

import AudioToolbox
import IOBluetooth
import SwiftUI

private enum NXKeyType: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

enum OutputDeviceIcon {
    static let speaker = "speaker.wave.2.fill"
    static let muted = "speaker.slash.fill"

    static func currentSymbol() -> String {
        let device = defaultOutputDevice()
        guard device != 0 else { return speaker }
        return symbolForDevice(
            name: deviceName(device) ?? "",
            transport: transportType(device)
        )
    }

    static func symbolForDevice(name: String, transport: UInt32) -> String {
        symbol(
            name: name,
            transport: transport,
            bluetoothMinorClass: bluetoothMinorClass(forDeviceNamed: name)
        )
    }

    static func symbol(
        name: String,
        transport: UInt32,
        bluetoothMinorClass: UInt32? = nil
    ) -> String {
        let key = name.lowercased()

        if key.contains("airpods max") { return "airpods.max" }
        if key.contains("airpods pro") { return "airpods.pro" }
        if key.contains("airpods") { return "airpods" }
        if key.contains("beats studio") || key.contains("studiobuds") {
            return "beats.studiobuds"
        }
        if key.contains("powerbeats") { return "beats.powerbeats" }
        if key.contains("beats fit") || key.contains("beatsx")
            || key.contains("urbeats") || key.contains("beats ear")
        {
            return "beats.earphones"
        }
        if key.contains("beats") { return "beats.headphones" }
        if key.contains("homepod") { return "homepod.fill" }
        if key.contains("apple tv") || key.contains("appletv") {
            return "appletv.fill"
        }

        switch transport {
        case kAudioDeviceTransportTypeBluetooth,
            kAudioDeviceTransportTypeBluetoothLE:
            return bluetoothSymbol(key: key, minorClass: bluetoothMinorClass)
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeBuiltIn:
            return speaker
        default:
            if isSpeakerName(key) { return "hifispeaker.fill" }
            if key.contains("headphone") || key.contains("headset") {
                return "headphones"
            }
            return speaker
        }
    }

    private static func bluetoothSymbol(key: String, minorClass: UInt32?)
        -> String
    {
        if let minorClass, let mapped = icon(forBluetoothMinorClass: minorClass)
        {
            return mapped
        }
        if isSpeakerName(key) { return "hifispeaker.fill" }
        if key.contains("headphone") || key.contains("headset")
            || key.contains("earbud") || key.contains("earphone")
        {
            return "headphones"
        }
        return "headphones"
    }

    private static func icon(forBluetoothMinorClass minor: UInt32) -> String? {
        switch minor {
        case 0x01, 0x02, 0x06:  // wearable headset, hands-free, headphones
            return "headphones"
        case 0x05, 0x07, 0x0A:  // loudspeaker, portable audio, hifi audio
            return "hifispeaker.fill"
        case 0x08:  // car audio
            return "car.fill"
        default:
            return nil
        }
    }

    private static let speakerKeywords = [
        "speaker", "soundbar", "soundlink", "soundcore", "megaboom",
        "boombox", "boom", "flip", "charge", "roam",
    ]

    private static func isSpeakerName(_ key: String) -> Bool {
        speakerKeywords.contains { key.contains($0) }
    }

    private static func bluetoothMinorClass(forDeviceNamed name: String)
        -> UInt32?
    {
        guard !name.isEmpty,
            let devices = IOBluetoothDevice.pairedDevices()
                as? [IOBluetoothDevice]
        else { return nil }
        let target = name.lowercased()
        let connected = devices.filter { $0.isConnected() }
        if let exact = connected.first(where: {
            $0.nameOrAddress?.lowercased() == target
        }) {
            return UInt32(exact.deviceClassMinor)
        }
        if let partial = connected.first(where: {
            guard let deviceName = $0.nameOrAddress?.lowercased(),
                !deviceName.isEmpty
            else { return false }
            return deviceName.contains(target) || target.contains(deviceName)
        }) {
            return UInt32(partial.deviceClassMinor)
        }
        return nil
    }

    static func defaultOutputDevice() -> AudioDeviceID {
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

    static func deviceName(_ device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(
                device,
                &addr,
                0,
                nil,
                &size,
                &transport
            ) == noErr
        else { return 0 }
        return transport
    }
}

final class SystemVolumeController {
    static let shared = SystemVolumeController()
    private var device = AudioDeviceID(0)

    private init() {
        device = defaultOutputDevice()
    }

    func readVolume() -> Float {
        refreshDevice()
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
        refreshDevice()
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
        refreshDevice()
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
        refreshDevice()
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

    private func refreshDevice() {
        device = defaultOutputDevice()
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
    private var started = false
    private var lastVol: Float = -1
    private var lastMuted = false
    private var device = AudioDeviceID(0)
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    func start() {
        guard !started else { return }
        started = true
        device = OutputDeviceIcon.defaultOutputDevice()
        registerDeviceListeners(on: device)
        listenForDefaultDeviceChanges()
        lastVol = controller.readVolume()
        lastMuted = controller.readMuted()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.armed = true
        }
    }

    private func listenForDefaultDeviceChanges() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultDeviceChange()
        }
        defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main,
            block
        )
    }

    private func handleDefaultDeviceChange() {
        let newDevice = OutputDeviceIcon.defaultOutputDevice()
        guard newDevice != device else { return }
        unregisterDeviceListeners(from: device)
        device = newDevice
        registerDeviceListeners(on: device)
        lastVol = controller.readVolume()
        lastMuted = controller.readMuted()
    }

    private func registerDeviceListeners(on device: AudioDeviceID) {
        guard device != 0 else { return }
        let volumeBlock: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            self?.emit()
        }
        volumeListenerBlock = volumeBlock
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            device,
            &volAddr,
            DispatchQueue.main,
            volumeBlock
        )

        let muteBlock: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            self?.emit()
        }
        muteListenerBlock = muteBlock
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            device,
            &muteAddr,
            DispatchQueue.main,
            muteBlock
        )
    }

    private func unregisterDeviceListeners(from device: AudioDeviceID) {
        guard device != 0 else { return }
        if let block = volumeListenerBlock {
            var volAddr = AudioObjectPropertyAddress(
                mSelector:
                    kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                device,
                &volAddr,
                DispatchQueue.main,
                block
            )
            volumeListenerBlock = nil
        }
        if let block = muteListenerBlock {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                device,
                &muteAddr,
                DispatchQueue.main,
                block
            )
            muteListenerBlock = nil
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
    enum BrightnessKeyDirection { case up, down }
    private(set) var lastBrightnessKeyPressDate: Date?
    private(set) var lastBrightnessKeyDirection: BrightnessKeyDirection?
    var brightnessKeyCorrelationWindow: TimeInterval = 0.3

    static let normalStep: Float = 1.0 / 16.0
    static let fineStep: Float = 1.0 / 64.0
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

    func brightnessChangeWasFromKeyPress(at date: Date = Date()) -> Bool {
        guard let last = lastBrightnessKeyPressDate else { return false }
        return date.timeIntervalSince(last) <= brightnessKeyCorrelationWindow
    }

    #if DEBUG
        func recordBrightnessKeyPressForTesting(
            at date: Date,
            direction: BrightnessKeyDirection = .up
        ) {
            lastBrightnessKeyPressDate = date
            lastBrightnessKeyDirection = direction
        }

        func clearBrightnessKeyPressForTesting() {
            lastBrightnessKeyPressDate = nil
            lastBrightnessKeyDirection = nil
        }
    #endif

    private func requestAccessibilityIfNeeded() {
        Task { @MainActor in
            PrivacyAccess.requestAccessibilityPrompt()
        }
    }

    private func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    static func adjustmentStep(optionAndShift: Bool) -> Float {
        optionAndShift ? fineStep : normalStep
    }

    private static func adjustmentStep(for event: CGEvent) -> Float {
        let flags = event.flags.union(CGEventSource.flagsState(.hidSystemState))
        return adjustmentStep(
            optionAndShift: flags.contains(.maskAlternate)
                && flags.contains(.maskShift)
        )
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

        switch keyCode {
        case NXKeyType.brightnessUp.rawValue:
            lastBrightnessKeyPressDate = Date()
            lastBrightnessKeyDirection = .up
        case NXKeyType.brightnessDown.rawValue:
            lastBrightnessKeyPressDate = Date()
            lastBrightnessKeyDirection = .down
        default:
            break
        }

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
