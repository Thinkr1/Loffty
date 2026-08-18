//
//  SpectrumBandsTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Spectrum bands")
struct SpectrumBandsTests {
    @Test func bassTonePeaksInLowerBands() {
        let levels = bandLevels(frequency: 250, sampleRate: 44_100)
        let low = levels.prefix(2).max() ?? 0
        let high = levels.suffix(2).max() ?? 0
        #expect(low > high)
        #expect(low > 0.15)
    }

    @Test func trebleTonePeaksInUpperBands() {
        let levels = bandLevels(frequency: 6_000, sampleRate: 44_100)
        let low = levels.prefix(2).max() ?? 0
        let high = levels.suffix(2).max() ?? 0
        #expect(high > low)
        #expect(high > 0.15)
    }

    @Test func silenceIsNearZero() {
        let magnitudes = SpectrumBands.fftMagnitudes(
            samples: [Float](repeating: 0, count: SpectrumBands.fftSize)
        )
        let levels = SpectrumBands.levels(
            magnitudes: magnitudes,
            sampleRate: 44_100,
            barCount: 4
        )
        #expect(levels.allSatisfy { $0 < 0.05 })
    }

    @Test func envelopeAttacksFasterThanItReleases() {
        let previous = [Float](repeating: 0.2, count: 4)
        let rising = SpectrumBands.smoothed(
            current: [1, 1, 1, 1],
            previous: previous,
            attack: 0.5,
            release: 0.16
        )
        let falling = SpectrumBands.smoothed(
            current: [0, 0, 0, 0],
            previous: previous,
            attack: 0.5,
            release: 0.16
        )
        #expect(rising[0] > 0.2)
        #expect(falling[0] < 0.2)
        #expect(abs(rising[0] - 0.2) > abs(falling[0] - 0.2))
    }

    @Test func resamplePreservesCountAndEndpoints() {
        let source: [Float] = [0, 1]
        let five = SpectrumBands.resample(source, count: 5)
        #expect(five.count == 5)
        #expect(five.first == 0)
        #expect(five.last == 1)
        #expect(SpectrumBands.resample([], count: 3) == [0, 0, 0])
        #expect(SpectrumBands.resample([0.4], count: 1) == [0.4])
    }

    @Test func dcOffsetDoesNotFillTheFirstBar() {
        let magnitudes = SpectrumBands.fftMagnitudes(
            samples: [Float](repeating: 0.8, count: SpectrumBands.fftSize)
        )
        let levels = SpectrumBands.levels(
            magnitudes: magnitudes,
            sampleRate: 44_100,
            barCount: 4
        )
        #expect(levels.allSatisfy { $0 < 0.2 })
    }

    @Test func relativeScalePutsThePeakNearOne() {
        let scaled = SpectrumBands.relative(
            [0.1, 0.2, 0.4],
            peakHold: 0
        )
        #expect(scaled.levels.count == 3)
        #expect(abs(scaled.levels[2] - scaled.levels.max()!) < 0.001)
        #expect(scaled.levels[2] > scaled.levels[1])
        #expect(scaled.levels[1] > scaled.levels[0])
        #expect(scaled.levels[2] < 1)
        #expect(scaled.levels[0] > 0)
    }

    @Test func emphasizeBoostsHigherBins() {
        let flat = [Float](repeating: 1, count: 64)
        let tilted = SpectrumBands.emphasize(
            flat,
            sampleRate: 44_100,
            fftSize: 128
        )
        #expect(tilted[0] == 0)
        #expect(tilted[20] > tilted[2])
        #expect(tilted[40] > tilted[20])
    }

    @Test func displayLevelsKeepADecayingPeakHold() {
        let magnitudes = SpectrumBands.fftMagnitudes(
            samples: sine(frequency: 1_000, sampleRate: 44_100, count: 1024)
        )
        let first = SpectrumBands.displayLevels(
            magnitudes: magnitudes,
            sampleRate: 44_100,
            barCount: 4,
            peakHold: 0.04
        )
        #expect(first.peakHold >= 0.04)
        let silence = SpectrumBands.displayLevels(
            magnitudes: [Float](repeating: 0, count: 512),
            sampleRate: 44_100,
            barCount: 4,
            peakHold: first.peakHold
        )
        #expect(silence.peakHold < first.peakHold)
        #expect(silence.peakHold > first.peakHold * 0.8)
    }

    @Test func logBandsStayInsideAudibleRange() {
        let edges = SpectrumBands.bandEdges(barCount: 5)
        #expect(edges.count == 6)
        #expect(abs((edges.first ?? 0) - SpectrumBands.minFrequency) < 0.001)
        #expect(abs((edges.last ?? 0) - SpectrumBands.maxFrequency) < 0.001)
        for i in 1..<edges.count {
            #expect(edges[i] > edges[i - 1])
        }
    }

    @Test func pinkLikeSpectrumDoesNotPegTheFirstBars() {
        var magnitudes = [Float](repeating: 0, count: 512)
        for i in 1..<magnitudes.count {
            let freq = Double(i) * 44_100 / Double(SpectrumBands.fftSize)
            magnitudes[i] = Float(1 / sqrt(max(freq, 1)))
        }
        let shown = SpectrumBands.displayLevels(
            magnitudes: magnitudes,
            sampleRate: 44_100,
            barCount: 5,
            peakHold: 0.04
        )
        let first = shown.levels[0]
        let rest = Array(shown.levels.dropFirst())
        let restMax = rest.max() ?? 0
        #expect(first < 0.92)
        #expect(restMax > first * 0.45)
        #expect(shown.levels.allSatisfy { $0 < 0.95 })
    }

    @Test func bandEdgesHonourACustomFloor() {
        let edges = SpectrumBands.bandEdges(barCount: 4, minFrequency: 80)
        #expect(edges.count == 5)
        #expect(abs((edges.first ?? 0) - 80) < 0.001)
        #expect(
            abs((edges.last ?? 0) - SpectrumBands.maxFrequency) < 0.001
        )
    }

    @Test func higherTiltBoostsTrebleMore() {
        let flat = [Float](repeating: 1, count: 64)
        let warm = SpectrumBands.emphasize(
            flat,
            sampleRate: 44_100,
            fftSize: 128,
            tilt: 0.28
        )
        let bright = SpectrumBands.emphasize(
            flat,
            sampleRate: 44_100,
            fftSize: 128,
            tilt: 0.62
        )
        #expect(bright[40] / max(bright[8], 0.001) > warm[40] / max(warm[8], 0.001))
    }

    @Test func relativePeakDecayFollowsTheHold() {
        let decayed = SpectrumBands.relative(
            [0.5],
            peakHold: 1,
            peakDecay: 0.74
        )
        #expect(abs(decayed.peakHold - 0.74) < 0.001)
    }

    private func bandLevels(frequency: Double, sampleRate: Double) -> [Float] {
        let samples = sine(
            frequency: frequency,
            sampleRate: sampleRate,
            count: SpectrumBands.fftSize
        )
        let magnitudes = SpectrumBands.fftMagnitudes(samples: samples)
        return SpectrumBands.levels(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            barCount: 4
        )
    }

    private func sine(frequency: Double, sampleRate: Double, count: Int)
        -> [Float]
    {
        (0..<count).map { i in
            Float(
                sin(2 * Double.pi * frequency * Double(i) / sampleRate)
            )
        }
    }
}

@Suite("Wave bar motion")
struct WaveBarMotionTests {
    @Test func mockHeightStaysInRange() {
        for i in 0..<5 {
            for t in stride(from: 0.0, through: 2.0, by: 0.1) {
                let h = WaveBarMotion.mockHeight(
                    index: i,
                    time: t,
                    minHeight: 3,
                    maxHeight: 14
                )
                #expect(h >= 3)
                #expect(h <= 14)
            }
        }
    }

    @Test func liveHeightMapsZeroAndOne() {
        #expect(
            WaveBarMotion.liveHeight(level: 0, minHeight: 3, maxHeight: 14)
                == 3
        )
        #expect(
            WaveBarMotion.liveHeight(level: 1, minHeight: 3, maxHeight: 14)
                == 14
        )
        #expect(
            WaveBarMotion.liveHeight(level: -1, minHeight: 3, maxHeight: 14)
                == 3
        )
        #expect(
            WaveBarMotion.liveHeight(level: 2, minHeight: 3, maxHeight: 14)
                == 14
        )
    }

    @Test func snapshotWithoutCaptureIsNil() {
        #expect(AudioSpectrum.shared.snapshot(barCount: 4) == nil)
    }
}
