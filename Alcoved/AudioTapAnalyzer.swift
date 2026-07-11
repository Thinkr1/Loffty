//
//  AudioTapAnalyzer.swift
//  Alcoved
//

import Accelerate
import AppKit
import AudioToolbox
import Foundation

// MARK: - Core Audio helpers

private extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    var isValid: Bool { self != .unknown }

    static func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            throw TapError.coreAudio
        }
        var ids = [AudioObjectID](repeating: .unknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            throw TapError.coreAudio
        }
        return ids
    }

    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID.unknown
        var pidCopy = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pidCopy, &size, &objectID) == noErr,
              objectID.isValid else {
            throw TapError.processNotFound
        }
        return objectID
    }

    func readProcessBundleID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var raw = [CChar](repeating: 0, count: Int(size))
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &raw) == noErr else { return nil }
        let s = String(cString: raw)
        return s.isEmpty ? nil : s
    }

    func readProcessIsRunningOutput() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    func readDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &uid) == noErr else {
            throw TapError.coreAudio
        }
        return uid as String
    }

    static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID.unknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id.isValid else {
            throw TapError.coreAudio
        }
        return id
    }
}

private enum TapError: Error {
    case coreAudio, processNotFound, tapCreationFailed
}

// MARK: - Ring buffer (audio thread writes, analyzer reads)

private final class AudioRing: @unchecked Sendable {
    private let capacity: Int
    private let buffer: UnsafeMutablePointer<Float>
    private var writeIndex: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    func writeMono(from bufferList: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = abl.first,
              let data = first.mData?.assumingMemoryBound(to: Float.self),
              first.mDataByteSize > 0 else { return }

        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let channels = abl.count
        let right = channels >= 2 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil

        for i in 0 ..< frameCount {
            var sample = data[i]
            if let right { sample = (data[i] + right[i]) * 0.5 }
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    func copyRecent(into dest: inout [Float]) {
        let count = min(dest.count, capacity)
        let start = (writeIndex - count + capacity) % capacity
        dest.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            if start + count <= capacity {
                base.update(from: buffer.advanced(by: start), count: count)
            } else {
                let first = capacity - start
                base.update(from: buffer.advanced(by: start), count: first)
                base.advanced(by: first).update(from: buffer, count: count - first)
            }
        }
    }
}

// MARK: - Process tap

private final class ProcessAudioTap {
    private var processTapID = AudioObjectID.unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private let ring: AudioRing
    private let queue = DispatchQueue(label: "alcoved.process-tap", qos: .userInitiated)

    init(ring: AudioRing) { self.ring = ring }

    func start(processObjectID: AudioObjectID) throws {
        stop()

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID.unknown
        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr, tapID.isValid else {
            throw TapError.tapCreationFailed
        }
        processTapID = tapID

        let outputUID = try AudioObjectID.defaultOutputDeviceID().readDeviceUID()
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AlcovedTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]

        var aggregateID = AudioObjectID.unknown
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr, aggregateID.isValid else {
            throw TapError.tapCreationFailed
        }
        aggregateDeviceID = aggregateID

        var procID: AudioDeviceIOProcID?
        let ring = self.ring
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue) { _, inInputData, _, _, _ in
            ring.writeMono(from: inInputData)
        }
        guard err == noErr, let procID else { throw TapError.tapCreationFailed }
        deviceProcID = procID

        guard AudioDeviceStart(aggregateDeviceID, procID) == noErr else {
            throw TapError.tapCreationFailed
        }
    }

    func stop() {
        if aggregateDeviceID.isValid, let deviceProcID {
            AudioDeviceStop(aggregateDeviceID, deviceProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
        }
        deviceProcID = nil

        if aggregateDeviceID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        aggregateDeviceID = .unknown

        if processTapID.isValid {
            AudioHardwareDestroyProcessTap(processTapID)
        }
        processTapID = .unknown
    }

    deinit { stop() }
}

// MARK: - Public analyzer

final class AudioTapAnalyzer {
    static let barCount = 5

    var onLevels: (([Float]) -> Void)?

    private let ring = AudioRing(capacity: 4096)
    private var tap: ProcessAudioTap?
    private var timer: Timer?
    private var activeBundleID: String?
    private var smoothed = [Float](repeating: 0, count: barCount)

    private let gain: Float = 1.0
    private let outputScale: Float = 0.55

    private let fftSize = 512
    private let log2n = vDSP_Length(9)
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var samples: [Float]
    private let realPtr: UnsafeMutablePointer<Float>
    private let imagPtr: UnsafeMutablePointer<Float>
    private var mags: [Float]

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        samples = [Float](repeating: 0, count: fftSize)
        realPtr = .allocate(capacity: fftSize / 2)
        imagPtr = .allocate(capacity: fftSize / 2)
        realPtr.initialize(repeating: 0, count: fftSize / 2)
        imagPtr.initialize(repeating: 0, count: fftSize / 2)
        mags = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        stop()
        realPtr.deinitialize(count: fftSize / 2)
        realPtr.deallocate()
        imagPtr.deinitialize(count: fftSize / 2)
        imagPtr.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    func update(bundleID: String?, isPlaying: Bool) {
        guard isPlaying, let bundleID, !bundleID.isEmpty else {
            stop()
            publishSilence()
            return
        }

        if bundleID != activeBundleID {
            activeBundleID = bundleID
            restartTap(for: bundleID)
        }

        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func restartTap(for bundleID: String) {
        tap?.stop()
        tap = ProcessAudioTap(ring: ring)

        guard let objectID = Self.processObjectID(for: bundleID) else { return }
        try? tap?.start(processObjectID: objectID)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        tap?.stop()
        tap = nil
        activeBundleID = nil
        smoothed = [Float](repeating: 0, count: Self.barCount)
    }

    private func publishSilence() {
        onLevels?(Array(repeating: 0, count: Self.barCount))
    }

    private func tick() {
        ring.copyRecent(into: &samples)
        let raw = analyze(samples)
        for i in 0 ..< Self.barCount {
            smoothed[i] = smoothed[i] * 0.72 + raw[i] * 0.28
            smoothed[i] = min(1, smoothed[i] * outputScale)
        }
        onLevels?(smoothed)
    }

    private func analyze(_ input: [Float]) -> [Float] {
        var windowed = input
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var split = DSPSplitComplex(realp: realPtr, imagp: imagPtr)
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
            }
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        mags[0] = abs(realPtr[0])
        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(fftSize / 2 - 1))

        let edges = [2, 6, 12, 24, 48, 128]
        var out = [Float](repeating: 0, count: Self.barCount)
        for b in 0 ..< Self.barCount {
            let lo = edges[b], hi = edges[b + 1]
            var maxVal: Float = 0
            vDSP_maxv(Array(mags[lo ..< hi]), 1, &maxVal, vDSP_Length(hi - lo))
            out[b] = min(1, pow(maxVal * gain, 0.75))
        }
        return out
    }

    private static func processObjectID(for bundleID: String) -> AudioObjectID? {
        if let ids = try? AudioObjectID.readProcessList() {
            for id in ids where id.readProcessBundleID() == bundleID && id.readProcessIsRunningOutput() {
                return id
            }
        }
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let id = try? AudioObjectID.translatePIDToProcessObjectID(pid: app.processIdentifier) {
            return id
        }
        return nil
    }
}
