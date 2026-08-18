//
//  SpectrumBands.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 18/08/2026.
//

import Accelerate
import CoreGraphics
import Foundation

enum SpectrumBands {
    nonisolated static let fftSize = 1024
    nonisolated static let defaultBarCount = 5
    nonisolated static let minFrequency: Double = 160
    nonisolated static let maxFrequency: Double = 8_000
    nonisolated static let magnitudeClip: Float = 32
    
    nonisolated static func bandEdges(
        barCount: Int,
        minFrequency: Double = Self.minFrequency,
        maxFrequency: Double = Self.maxFrequency
    ) -> [Double] {
        let count = max(1, barCount)
        let lo = log(minFrequency)
        let hi = log(maxFrequency)
        return (0...count).map { i in
            exp(lo + (hi - lo) * Double(i) / Double(count))
        }
    }
    
    nonisolated static func displayLevels(
        magnitudes: [Float],
        sampleRate: Double,
        barCount: Int,
        peakHold: Float,
        minFrequency: Double = Self.minFrequency,
        tilt: Float = 0.62,
        peakDecay: Float = 0.86
    ) -> (levels: [Float], peakHold: Float) {
        let raw = levels(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            barCount: barCount,
            minFrequency: minFrequency,
            tilt: tilt
        )
        return relative(raw, peakHold: peakHold, peakDecay: peakDecay)
    }
    
    nonisolated static func levels(
        magnitudes: [Float],
        sampleRate: Double,
        barCount: Int,
        minFrequency: Double = Self.minFrequency,
        tilt: Float = 0.62
    ) -> [Float] {
        let bins = magnitudes.count
        guard bins > 1, sampleRate > 0, barCount > 0 else {
            return Array(repeating: 0, count: max(barCount, 0))
        }
        let fftN = bins * 2
        let compensated = emphasize(
            magnitudes,
            sampleRate: sampleRate,
            fftSize: fftN,
            tilt: tilt
        )
        let edges = bandEdges(
            barCount: barCount,
            minFrequency: minFrequency
        )
        var result = [Float](repeating: 0, count: barCount)
        for band in 0..<barCount {
            let loHz = edges[band]
            let hiHz = edges[band + 1]
            let center = sqrt(loHz * hiHz)
            let ratio = pow(hiHz / loHz, 0.22)
            result[band] = peakInRange(
                compensated,
                sampleRate: sampleRate,
                fftSize: fftN,
                loHz: center / ratio,
                hiHz: center * ratio
            )
        }
        return result
    }
    
    nonisolated static func emphasize(
        _ magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int,
        tilt: Float = 0.62
    ) -> [Float] {
        var out = magnitudes
        guard !out.isEmpty, fftSize > 0, sampleRate > 0 else { return out }
        out[0] = 0
        if out.count > 1 { out[1] = 0 }
        let ref: Double = 1_000
        for i in 2..<out.count {
            let freq = Double(i) * sampleRate / Double(fftSize)
            let boost = Float(pow(max(freq, 1) / ref, Double(tilt)))
            out[i] = min(out[i], magnitudeClip) * boost
        }
        return out
    }
    
    nonisolated static func relative(
        _ values: [Float],
        peakHold: Float,
        peakDecay: Float = 0.86
    ) -> (
        levels: [Float], peakHold: Float
    ) {
        let framePeak = values.max() ?? 0
        let hold = max(max(framePeak, 0.04), peakHold * peakDecay)
        let scaled = values.map { value -> Float in
            let normalised = min(1, max(0, value / hold))
            return 1 - exp(-2.15 * normalised)
        }
        return (scaled, hold)
    }
    
    nonisolated static func peakInRange(
        _ magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int,
        loHz: Double,
        hiHz: Double
    ) -> Float {
        let bins = magnitudes.count
        guard bins > 1, fftSize > 0, sampleRate > 0 else { return 0 }
        let hzPerBin = sampleRate / Double(fftSize)
        let loBin = max(1, Int((loHz / hzPerBin).rounded(.down)))
        let hiBin = min(
            bins - 1,
            max(loBin, Int((hiHz / hzPerBin).rounded(.up)))
        )
        var peak: Float = 0
        for bin in loBin...hiBin {
            peak = max(peak, magnitudes[bin])
        }
        return peak
    }
    
    nonisolated static func smoothed(
        current: [Float],
        previous: [Float],
        attack: Float = 0.62,
        release: Float = 0.28
    ) -> [Float] {
        let count = current.count
        guard count > 0 else { return [] }
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let incoming = current[i]
            let prior = i < previous.count ? previous[i] : 0
            let coeff = incoming > prior ? attack : release
            result[i] = prior + (incoming - prior) * coeff
        }
        return result
    }
    
    nonisolated static func resample(_ levels: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if levels.isEmpty { return Array(repeating: 0, count: count) }
        if levels.count == count { return levels }
        if count == 1 { return [levels.max() ?? 0] }
        return (0..<count).map { i in
            let src = Double(i) * Double(levels.count - 1) / Double(count - 1)
            let lo = Int(src)
            let hi = min(lo + 1, levels.count - 1)
            let frac = Float(src - Double(lo))
            return levels[lo] * (1 - frac) + levels[hi] * frac
        }
    }
    
    nonisolated static func fftMagnitudes(samples: [Float]) -> [Float] {
        let n = fftSize
        var input = samples
        if input.count < n {
            input.append(contentsOf: repeatElement(0, count: n - input.count))
        } else if input.count > n {
            input = Array(input.prefix(n))
        }
        return fftMagnitudes(samples: input, count: n)
    }
    
    fileprivate nonisolated static func fftMagnitudes(
        samples: [Float],
        count n: Int
    ) -> [Float] {
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))
        
        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        windowed.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                complex in
                realp.withUnsafeMutableBufferPointer { real in
                    imagp.withUnsafeMutableBufferPointer { imag in
                        guard let r = real.baseAddress, let i = imag.baseAddress
                        else { return }
                        var split = DSPSplitComplex(realp: r, imagp: i)
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                        vDSP_fft_zrip(
                            setup,
                            &split,
                            1,
                            log2n,
                            FFTDirection(FFT_FORWARD)
                        )
                        vDSP_zvabs(
                            &split,
                            1,
                            &magnitudes,
                            1,
                            vDSP_Length(n / 2)
                        )
                    }
                }
            }
        }
        if !magnitudes.isEmpty {
            magnitudes[0] = 0
            if magnitudes.count > 1 { magnitudes[1] = 0 }
        }
        return magnitudes.map { min($0, magnitudeClip) }
    }
}

enum WaveBarMotion {
    nonisolated static let mockPhases: [Double] = [
        0.0, 0.9, 1.8, 2.7, 3.6, 4.5,
    ]
    
    nonisolated static func mockHeight(
        index: Int,
        time: Double,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        timeScale: Double = 6.0
    ) -> CGFloat {
        let phase = mockPhases[index % mockPhases.count]
        let s =
        (sin(time * timeScale + phase)
         + sin(time * timeScale * 1.617 + phase * 1.7)) / 2
        let norm = (s + 1) / 2
        return minHeight + (maxHeight - minHeight) * CGFloat(norm)
    }
    
    nonisolated static func liveHeight(
        level: Float,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        let clamped = CGFloat(min(1, max(0, level)))
        return minHeight + (maxHeight - minHeight) * clamped
    }
}
