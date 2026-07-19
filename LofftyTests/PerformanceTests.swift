//
//  PerformanceTests.swift
//  LofftyTests
//
//  Local XCTest performance baselines. Skipped when built with -DCI
//  (GitHub Actions) so Actions minutes stay low. Run from Xcode to
//  record/compare baselines in the Test Report navigator.
//

import AudioToolbox
import Foundation
import XCTest

@testable import Loffty

@MainActor
final class PerformanceTests: XCTestCase {
    private var measureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 12
        return options
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if CI
        throw XCTSkip("Performance tests run locally only (skipped on CI)")
        #else
        if ProcessInfo.processInfo.environment["CI"] == "true"
            || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        {
            throw XCTSkip("Performance tests run locally only (skipped on CI)")
        }
        #endif
    }

    func testOutputDeviceIconSymbolPerformance() {
        let names = [
            "PL's AirPods Pro",
            "AirPods Max",
            "Beats Studio Buds",
            "WH-1000XM5",
            "MacBook Pro Speakers",
            "Living Room",
        ]
        let transports: [UInt32] = [
            kAudioDeviceTransportTypeBluetooth,
            kAudioDeviceTransportTypeBluetoothLE,
            kAudioDeviceTransportTypeBuiltIn,
            kAudioDeviceTransportTypeAirPlay,
            kAudioDeviceTransportTypeUSB,
        ]
        let run = {
            for i in 0..<20_000 {
                _ = OutputDeviceIcon.symbol(
                    name: names[i % names.count],
                    transport: transports[i % transports.count]
                )
            }
        }
        run()  // warmup (drops cold-start samples)
        measure(options: measureOptions, block: run)
    }

    func testMediaParsingHotPathPerformance() {
        let html = #""artists":[{"name":"A"},{"name":"B"},{"name":"C"}]"#
        let info: [String: Any] = [
            "artists": ["A", "B"],
            "title": "Song",
            "bundleIdentifier": "com.spotify.client",
            "elapsedTime": 12.0,
            "timestamp": "2026-07-18T12:00:00Z",
        ]
        let elapsedOnly: [String: Any] = [
            "elapsedTime": 1.0,
            "timestamp": "2026-07-18T12:00:00Z",
        ]
        let run = {
            for _ in 0..<1_500 {
                _ = MediaParsing.parseArtistNames(from: html)
                _ = MediaParsing.parseArtist(from: info)
                _ = MediaParsing.parseIsLive(from: info)
                _ = MediaParsing.isIdlePayload(info, isDiff: false)
                _ = MediaParsing.isElapsedOnlyDiff(elapsedOnly)
                _ = MediaParsing.trackKey(
                    title: "Song",
                    bundle: "com.spotify.client",
                    currentTitle: "",
                    lastKey: nil,
                    isDiff: false
                )
                _ = MediaParsing.parseTimestamp("2026-07-18T12:00:00.5Z")
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testNotchMetricsPerformance() {
        let run = {
            for i in 0..<40_000 {
                let m = NotchMetrics(
                    notchW: 200,
                    notchH: 32,
                    expanded: i % 2 == 0,
                    idle: i % 3 == 0,
                    extended: i % 5 == 0,
                    hudActive: i % 4 == 0,
                    sideAnnouncement: i % 6 == 0,
                    airDrop: i % 7 == 0,
                    airDropTransfer: i % 8 == 0,
                    showAlbum: i % 2 == 1
                )
                _ = m.width
                _ = m.height
                _ = m.side
                _ = m.topRadius
                _ = m.bottomRadius
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testFmtTimePerformance() {
        let run = {
            for i in 0..<80_000 {
                _ = fmtTime(Double(i % 3600))
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testFocusLogParsingPerformance() {
        let lines = [
            "Active Mode Assertion: (null)",
            "starting: 0",
            "Active Mode Assertion: yes; semanticModeIdentifier: com.apple.focus.work; name: Work;",
            "asserted mode; name: Gaming;",
            "heartbeat ok",
            "cleared mode assertion",
        ]
        let run = {
            for i in 0..<25_000 {
                _ = FocusLogParsing.event(from: lines[i % lines.count])
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testAirDropLogicPerformance() {
        let run = {
            for i in 0..<60_000 {
                _ = AirDropLogic.decide(
                    state: i % 6,
                    progress: Double(i % 100) / 100,
                    sawMeaningfulProgress: i % 2 == 0,
                    isOutgoing: i % 3 == 0
                )
                _ = AirDropLogic.isOutgoing(
                    phase: i % 2 == 0 ? .picking : .idle,
                    filesNonEmpty: i % 2 == 0,
                    awaitingDelivery: i % 4 == 0
                )
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testFocusPalettePerformance() {
        let names = [
            "Work", "Sleep", "Personal", "Gaming", "Fitness", "Custom Mode",
        ]
        let run = {
            for i in 0..<40_000 {
                let name = names[i % names.count]
                _ = FocusPalette.symbol(for: name, enabled: i % 2 == 0)
                _ = FocusPalette.accent(for: name)
                _ = FocusHUDWatcher.displayName(
                    identifier: "com.apple.focus.\(name.lowercased())",
                    name: nil
                )
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }

    func testUpdateVerifierParseAndHashPerformance() throws {
        let hash = String(repeating: "ab", count: 32)
        let line = "\(hash)  Loffty.zip\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-perf-\(UUID().uuidString).bin")
        // Larger payload so hash time dominates setup noise.
        try Data(repeating: 0xA5, count: 256 * 1024).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Warm file cache + parse path.
        _ = UpdateVerifier.parseSHA256(from: line)
        _ = try UpdateVerifier.sha256Hex(of: url)

        measure(options: measureOptions) {
            for _ in 0..<80 {
                _ = UpdateVerifier.parseSHA256(from: line)
                _ = try? UpdateVerifier.sha256Hex(of: url)
            }
        }
    }

    func testVersionComparePerformance() {
        let run = {
            for i in 0..<40_000 {
                _ = AppUpdater.normalizeVersion("v1.\(i % 20).\(i % 10)")
                _ = AppUpdater.compareVersions("1.2.\(i % 5)", "1.2.0")
                _ = AppUpdater.isVersion("1.\(i % 3).0", newerThan: "1.0.0")
            }
        }
        run()
        measure(options: measureOptions, block: run)
    }
}
