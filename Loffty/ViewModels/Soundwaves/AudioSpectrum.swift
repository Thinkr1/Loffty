//
//  AudioSpectrum.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 18/08/2026.
//

import AudioToolbox
import CoreAudio
import Foundation

nonisolated final class AudioSpectrum: @unchecked Sendable {
    static let shared = AudioSpectrum()

    private let queue = DispatchQueue(
        label: "Loffty.audioSpectrum",
        qos: .userInteractive
    )
    private let lock = NSLock()
    private var bands: [Float] = Array(
        repeating: 0,
        count: SpectrumBands.defaultBarCount
    )
    private var previous: [Float] = Array(
        repeating: 0,
        count: SpectrumBands.defaultBarCount
    )
    private var live = false
    private var hasHeardAudio = false
    private var wantCapture = false
    private var running = false
    private var startFailed = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioDeviceID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48_000
    private var pending: [Float] = []
    private var outputListenerInstalled = false
    private var peakHold: Float = 0.04
    private var attack: Float = 0.62
    private var release: Float = 0.28
    private var peakDecay: Float = 0.86
    private var minFrequency: Double = 160
    private var tilt: Float = 0.62

    private init() {}

    func setCapturing(_ capturing: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantCapture = capturing
            if capturing {
                self.startLocked()
            } else {
                self.startFailed = false
                self.stopLocked()
            }
        }
    }

    func setAnalysis(
        attack: Float,
        release: Float,
        peakDecay: Float,
        minFrequency: Double,
        tilt: Float
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.attack = attack
            self.release = release
            self.peakDecay = peakDecay
            self.minFrequency = minFrequency
            self.tilt = tilt
        }
    }

    func snapshot(barCount: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard live, hasHeardAudio else { return nil }
        return SpectrumBands.resample(bands, count: barCount)
    }

    private func startLocked() {
        guard !running, !startFailed else { return }
        installOutputListener()
        guard startTap() else {
            startFailed = true
            tearDownTap()
            setLive(false)
            return
        }
        running = true
        setLive(true)
    }

    private func stopLocked() {
        running = false
        setLive(false)
        hasHeardAudio = false
        pending.removeAll(keepingCapacity: true)
        previous = Array(repeating: 0, count: SpectrumBands.defaultBarCount)
        peakHold = 0.04
        publish(Array(repeating: 0, count: SpectrumBands.defaultBarCount))
        tearDownTap()
    }

    private func restartLocked() {
        guard wantCapture else { return }
        startFailed = false
        stopLocked()
        wantCapture = true
        startLocked()
    }

    private func setLive(_ value: Bool) {
        lock.lock()
        live = value
        if !value { hasHeardAudio = false }
        lock.unlock()
    }

    private func publish(_ values: [Float]) {
        lock.lock()
        bands = values
        lock.unlock()
    }

    private func startTap() -> Bool {
        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: []
        )
        tapDescription.uuid = UUID()
        tapDescription.name = "Loffty Soundwaves"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        let tapUID = tapDescription.uuid.uuidString

        var newTap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(tapDescription, &newTap) == noErr,
            newTap != kAudioObjectUnknown
        else { return false }
        tapID = newTap
        sampleRate = Self.tapSampleRate(tapID) ?? 48_000

        guard let outputUID = Self.defaultOutputUID() else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            return false
        }

        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Loffty Soundwave Tap",
            kAudioAggregateDeviceUIDKey:
                "com.plmls-team.Loffty.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var newAggregate = AudioDeviceID(kAudioObjectUnknown)
        guard
            AudioHardwareCreateAggregateDevice(
                aggregateDesc as CFDictionary,
                &newAggregate
            ) == noErr,
            newAggregate != kAudioObjectUnknown
        else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            return false
        }
        aggregateID = newAggregate

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            queue
        ) { [weak self] _, inputData, _, _, _ in
            self?.ingest(inputData)
        }
        guard status == noErr, let procID else {
            tearDownTap()
            return false
        }
        ioProcID = procID
        guard AudioDeviceStart(aggregateID, procID) == noErr else {
            tearDownTap()
            return false
        }
        return true
    }

    private func tearDownTap() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func ingest(_ inputData: UnsafePointer<AudioBufferList>) {
        let mono = Self.monoSamples(from: inputData)
        guard !mono.isEmpty else { return }
        if mono.contains(where: { abs($0) > 0.002 }) {
            lock.lock()
            hasHeardAudio = true
            lock.unlock()
        }
        pending.append(contentsOf: mono)
        let size = SpectrumBands.fftSize
        while pending.count >= size {
            let frame = Array(pending.prefix(size))
            pending.removeFirst(size)
            let magnitudes = SpectrumBands.fftMagnitudes(samples: frame)
            let displayed = SpectrumBands.displayLevels(
                magnitudes: magnitudes,
                sampleRate: sampleRate,
                barCount: SpectrumBands.defaultBarCount,
                peakHold: peakHold,
                minFrequency: minFrequency,
                tilt: tilt,
                peakDecay: peakDecay
            )
            peakHold = displayed.peakHold
            let next = SpectrumBands.smoothed(
                current: displayed.levels,
                previous: previous,
                attack: attack,
                release: release
            )
            previous = next
            publish(next)
        }
        if pending.count > size * 4 {
            pending.removeFirst(pending.count - size)
        }
    }

    private func installOutputListener() {
        guard !outputListenerInstalled else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            queue
        ) { [weak self] _, _ in
            self?.restartLocked()
        }
        outputListenerInstalled = status == noErr
    }

    private nonisolated static func monoSamples(
        from inputData: UnsafePointer<AudioBufferList>
    ) -> [Float] {
        let abl = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard !abl.isEmpty else { return [] }
        if abl.count >= 2,
            let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
            let right = abl[1].mData?.assumingMemoryBound(to: Float.self)
        {
            let count = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            let rightCount =
                Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size
            let n = min(count, rightCount)
            var mono = [Float](repeating: 0, count: n)
            for i in 0..<n {
                mono[i] = (left[i] + right[i]) * 0.5
            }
            return mono
        }
        guard let data = abl[0].mData else { return [] }
        let channels = max(1, Int(abl[0].mNumberChannels))
        let floats = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
        let frames = floats / channels
        let ptr = data.assumingMemoryBound(to: Float.self)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: ptr, count: frames))
        }
        var mono = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
                sum += ptr[i * channels + c]
            }
            mono[i] = sum / Float(channels)
        }
        return mono
    }

    private nonisolated static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                0,
                nil,
                &size,
                &device
            ) == noErr, device != 0
        else { return nil }

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(device, &uidAddr, 0, nil, &uidSize, ptr)
        }
        guard status == noErr else { return nil }
        return uid as String
    }

    private nonisolated static func tapSampleRate(_ tap: AudioObjectID)
        -> Double?
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard
            AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
                == noErr,
            asbd.mSampleRate > 0
        else { return nil }
        return asbd.mSampleRate
    }
}
