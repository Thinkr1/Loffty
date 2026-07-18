//
//  BatteryThresholdTests.swift
//  LofftyTests
//

import Testing

@testable import Loffty

@Suite("BatteryThreshold")
struct BatteryThresholdTests {
    @Test func crossesDownThroughMark() {
        #expect(BatteryThreshold.crossed(from: 21, to: 20, at: 20))
        #expect(BatteryThreshold.crossed(from: 11, to: 10, at: 10))
        #expect(!BatteryThreshold.crossed(from: 20, to: 19, at: 20))
        #expect(!BatteryThreshold.crossed(from: 25, to: 22, at: 20))
        #expect(!BatteryThreshold.crossed(from: 15, to: 25, at: 20))
    }
}
