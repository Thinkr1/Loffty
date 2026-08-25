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

    @Test @MainActor func defaultAccessoriesFrameSitsUnderClockNearTop() {
        let screen = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let settings = AppSettings.shared
        let originalWeather = settings.lockScreenWeatherAccessory
        let originalBluetooth = settings.lockScreenBluetoothAccessory
        let originalBattery = settings.lockScreenBatteryAccessory
        let originalGraph = settings.lockScreenWeatherShowGraph
        defer {
            settings.lockScreenWeatherAccessory = originalWeather
            settings.lockScreenBluetoothAccessory = originalBluetooth
            settings.lockScreenBatteryAccessory = originalBattery
            settings.lockScreenWeatherShowGraph = originalGraph
        }
        settings.lockScreenWeatherAccessory = true
        settings.lockScreenBluetoothAccessory = false
        settings.lockScreenBatteryAccessory = false
        settings.lockScreenWeatherShowGraph = false

        let frame = LockScreenPolicy.defaultAccessoriesFrame(screenFrame: screen)
        let inset = LockAccessoriesMetrics.topInset(
            screenHeight: screen.height,
            settings: settings
        )
        #expect(frame.width == LockAccessoriesMetrics.width)
        #expect(frame.height == LockAccessoriesMetrics.rowHeight)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - inset)
        #expect(inset >= LockAccessoriesMetrics.minTopInset)
        #expect(frame.minY > LockScreenPolicy.defaultCardFrame(screenFrame: screen).maxY)
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

    @Test @MainActor func accessoriesHeightGrowsWithWeatherGraph() {
        let settings = AppSettings.shared
        let originalWeather = settings.lockScreenWeatherAccessory
        let originalBluetooth = settings.lockScreenBluetoothAccessory
        let originalBattery = settings.lockScreenBatteryAccessory
        let originalGraph = settings.lockScreenWeatherShowGraph
        defer {
            settings.lockScreenWeatherAccessory = originalWeather
            settings.lockScreenBluetoothAccessory = originalBluetooth
            settings.lockScreenBatteryAccessory = originalBattery
            settings.lockScreenWeatherShowGraph = originalGraph
        }

        settings.lockScreenWeatherAccessory = false
        settings.lockScreenBluetoothAccessory = false
        settings.lockScreenBatteryAccessory = false
        #expect(LockAccessoriesMetrics.height(settings: settings) == 0)

        settings.lockScreenWeatherAccessory = true
        settings.lockScreenWeatherShowGraph = false
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
        )

        settings.lockScreenWeatherShowGraph = true
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
                + LockAccessoriesMetrics.graphExtra
        )
    }

    @Test @MainActor func accessoryOrderSwapMovesItems() {
        let settings = AppSettings.shared
        let original = settings.lockScreenAccessoryOrder
        defer { settings.lockScreenAccessoryOrder = original }
        settings.lockScreenAccessoryOrder = [.weather, .bluetooth, .battery]
        settings.moveLockScreenAccessory(.weather, offset: 1)
        #expect(settings.lockScreenAccessoryOrder == [.bluetooth, .weather, .battery])
        settings.moveLockScreenAccessory(.weather, offset: 1)
        #expect(settings.lockScreenAccessoryOrder == [.bluetooth, .battery, .weather])
        settings.moveLockScreenAccessory(.weather, offset: 1)
        #expect(settings.lockScreenAccessoryOrder == [.bluetooth, .battery, .weather])
    }

    @Test @MainActor func accessoryMoveToAndResetLayout() {
        let settings = AppSettings.shared
        let originalOrder = settings.lockScreenAccessoryOrder
        let originalInset = settings.lockScreenAccessoriesTopInsetFraction
        defer {
            settings.lockScreenAccessoryOrder = originalOrder
            settings.lockScreenAccessoriesTopInsetFraction = originalInset
        }

        settings.lockScreenAccessoryOrder = [.weather, .bluetooth, .battery]
        settings.moveLockScreenAccessory(.battery, to: 0)
        #expect(settings.lockScreenAccessoryOrder == [.battery, .weather, .bluetooth])

        settings.lockScreenAccessoriesTopInsetFraction = 0.4
        settings.resetLockScreenAccessoriesLayout()
        #expect(settings.lockScreenAccessoryOrder == Array(LockScreenAccessory.allCases))
        #expect(
            settings.lockScreenAccessoriesTopInsetFraction
                == LockAccessoriesMetrics.defaultTopInsetFraction
        )
    }
}
