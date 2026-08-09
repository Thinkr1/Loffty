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

    @Test func defaultCardFrameCentersAndSitsAboveBottom() {
        let screen = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let frame = LockScreenPolicy.defaultCardFrame(screenFrame: screen)
        #expect(frame.width == LockCardMetrics.width)
        #expect(frame.height == LockCardMetrics.height)
        #expect(frame.midX == screen.midX)
        #expect(frame.minY == screen.minY + screen.height * 0.19)
    }

    @Test func convertToLocalTopLeftFlipsY() {
        let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let card = CGRect(x: 100, y: 200, width: 356, height: 174)
        let local = LockScreenPolicy.convertToLocalTopLeft(
            card,
            in: window
        )
        #expect(local.minX == 100)
        #expect(local.width == 356)
        #expect(local.height == 174)
        // AppKit y=200 from bottom → SwiftUI y = 800 - 200 - 174
        #expect(local.minY == 426)
    }

    @Test func resolvedCompactRectFillsCompactWindow() {
        let size = CGSize(
            width: LockCardMetrics.width,
            height: LockCardMetrics.height
        )
        let rect = LockScreenPolicy.resolvedCompactRect(
            windowSize: size,
            placed: .zero
        )
        #expect(rect == CGRect(origin: .zero, size: size))
    }

    @Test func resolvedCompactRectUsesPlacedWhenFlying() {
        let placed = CGRect(x: 40, y: 80, width: 356, height: 174)
        let rect = LockScreenPolicy.resolvedCompactRect(
            windowSize: CGSize(width: 1512, height: 982),
            placed: placed
        )
        #expect(rect == placed)
    }

    @Test func resolvedCompactRectNeverReturnsZeroWhenPlacedMissing() {
        let window = CGSize(width: 1512, height: 982)
        let rect = LockScreenPolicy.resolvedCompactRect(
            windowSize: window,
            placed: .zero
        )
        #expect(rect.width == LockCardMetrics.width)
        #expect(rect.height == LockCardMetrics.height)
        #expect(rect.midX == window.width / 2)
        #expect(rect.midY == window.height / 2)
    }
}
