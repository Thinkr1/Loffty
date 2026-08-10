//
//  SystemKeyInterceptorTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("SystemKeyInterceptor")
struct SystemKeyInterceptorTests {
    @Test func adjustmentStepOptionShiftIsFine() {
        #expect(
            SystemKeyInterceptor.adjustmentStep(optionAndShift: true)
                == SystemKeyInterceptor.fineStep
        )
        #expect(
            SystemKeyInterceptor.adjustmentStep(optionAndShift: false)
                == SystemKeyInterceptor.normalStep
        )
    }

    @Test func brightnessChangeWithoutKeyPressIsNotCorrelated() {
        let interceptor = SystemKeyInterceptor()
        interceptor.clearBrightnessKeyPressForTesting()
        #expect(!interceptor.brightnessChangeWasFromKeyPress())
    }

    @Test func brightnessChangeWithinCorrelationWindowMatchesKeyPress() {
        let interceptor = SystemKeyInterceptor()
        let press = Date(timeIntervalSince1970: 1_000)
        interceptor.brightnessKeyCorrelationWindow = 0.3
        interceptor.recordBrightnessKeyPressForTesting(
            at: press,
            direction: .up
        )

        #expect(
            interceptor.brightnessChangeWasFromKeyPress(
                at: press.addingTimeInterval(0.2)
            )
        )
        #expect(interceptor.lastBrightnessKeyDirection == .up)
        #expect(
            !interceptor.brightnessChangeWasFromKeyPress(
                at: press.addingTimeInterval(0.31)
            )
        )
    }

    @Test func brightnessKeyDirectionDownIsRecorded() {
        let interceptor = SystemKeyInterceptor()
        interceptor.recordBrightnessKeyPressForTesting(
            at: Date(),
            direction: .down
        )
        #expect(interceptor.lastBrightnessKeyDirection == .down)
        #expect(interceptor.brightnessChangeWasFromKeyPress())
    }
}
