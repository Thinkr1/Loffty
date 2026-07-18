//
//  LockScreenPolicyTests.swift
//  LofftyTests
//

import CoreGraphics
import Testing

@testable import Loffty

@Suite("Lock screen + notch geometry")
struct LockScreenPolicyTests {
    @Test func expandAllowedRequiresBothToggles() {
        #expect(
            LockScreenPolicy.expandAllowed(
                lockScreenNotch: true,
                lockScreenExpandNotch: true
            )
        )
        #expect(
            !LockScreenPolicy.expandAllowed(
                lockScreenNotch: false,
                lockScreenExpandNotch: true
            )
        )
        #expect(
            !LockScreenPolicy.expandAllowed(
                lockScreenNotch: true,
                lockScreenExpandNotch: false
            )
        )
    }

    @Test func notchRectUsesAuxiliaryAreasWhenPresent() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rect = notchRect(
            screenFrame: frame,
            topInset: 37,
            leftAuxWidth: 300,
            rightAuxWidth: 300
        )
        #expect(rect.width == 912)
        #expect(rect.height == 37)
        #expect(rect.minX == 300)
        #expect(rect.maxY == frame.maxY)
    }

    @Test func notchRectFallsBackWithoutAuxAreas() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = notchRect(
            screenFrame: frame,
            topInset: 0,
            leftAuxWidth: nil,
            rightAuxWidth: nil
        )
        #expect(rect.width == 220)
        #expect(rect.height == 32)
        #expect(rect.midX == frame.midX)
    }
}
