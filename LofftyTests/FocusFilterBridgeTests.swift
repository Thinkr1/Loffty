//
//  FocusFilterBridgeTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("FocusFilterBridge")
struct FocusFilterBridgeTests {
    @Test @MainActor func announcesActivationAndIgnoresDuplicate() {
        let bridge = FocusFilterBridge.shared
        bridge.resetForTesting()
        var events: [(Bool, String?)] = []
        bridge.onChange = { events.append(($0, $1)) }

        bridge.handle(active: true, name: "Work", forceAnnounce: true)
        #expect(events.count == 1)
        #expect(events[0].0)
        #expect(events[0].1 == "Work")

        bridge.handle(active: true, name: "Work")
        #expect(events.count == 1)
    }

    @Test @MainActor func announcesNameChangeWhileActive() {
        let bridge = FocusFilterBridge.shared
        bridge.resetForTesting()
        var names: [String?] = []
        bridge.onChange = { _, name in names.append(name) }

        bridge.handle(active: true, name: "Work", forceAnnounce: true)
        bridge.handle(active: true, name: "Sleep")
        #expect(names == ["Work", "Sleep"])
    }

    @Test @MainActor func ignoresLogActivateDuringDebounceWindow() {
        let bridge = FocusFilterBridge.shared
        bridge.resetForTesting()
        var count = 0
        bridge.onChange = { _, _ in count += 1 }

        let t0 = Date(timeIntervalSince1970: 1_000)
        bridge.handle(active: false, forceAnnounce: true, now: t0)
        #expect(count == 1)

        bridge.handle(
            active: true,
            name: "Work",
            source: .log,
            now: t0.addingTimeInterval(0.5)
        )
        #expect(count == 1)
        #expect(!bridge.isFocused)

        bridge.handle(
            active: true,
            name: "Work",
            source: .log,
            now: t0.addingTimeInterval(1.3)
        )
        #expect(count == 2)
        #expect(bridge.isFocused)
    }
}
