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

    @Test func defaultIdleFrameSitsJustAboveProfilePicture() {
        let screen = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let idle = LockScreenPolicy.defaultIdleFrame(screenFrame: screen)
        let card = LockScreenPolicy.defaultCardFrame(screenFrame: screen)
        #expect(idle.width == LockCardMetrics.idleWidth)
        #expect(idle.height == LockCardMetrics.idleHeight)
        #expect(idle.midX == screen.midX)
        #expect(
            idle.minY == screen.minY
                + LockCardMetrics.lockProfilePictureTopInset
                + LockCardMetrics.idleSpacingAboveProfile
        )
        #expect(idle.minY < card.midY)
        #expect(idle.maxY < card.maxY)
        #expect(idle.width < card.width)
        #expect(idle.height < card.height)
        #expect(idle.minY > screen.minY + LockCardMetrics.lockProfilePictureTopInset)
        #expect(idle.maxY < screen.maxY)
        #expect(idle.minX >= screen.minX)
        #expect(idle.maxX <= screen.maxX)
    }

    @Test func clampedTopInsetFractionUsesRaisedCeiling() {
        #expect(
            LockAccessoriesMetrics.clampedTopInsetFraction(0)
                == LockAccessoriesMetrics.minTopInsetFraction
        )
        #expect(
            LockAccessoriesMetrics.clampedTopInsetFraction(1)
                == LockAccessoriesMetrics.maxTopInsetFraction
        )
        #expect(
            LockAccessoriesMetrics.clampedTopInsetFraction(0.5) == 0.5
        )
        #expect(LockAccessoriesMetrics.maxTopInsetFraction == 0.92)
    }

    @Test func mockStripTopStaysBetweenClockAndBottomPadding() {
        #expect(
            LockMockLayout.clampedStripTop(0) == LockMockLayout.clockBottom
        )
        #expect(
            LockMockLayout.clampedStripTop(LockMockLayout.height)
                == LockMockLayout.height - LockMockLayout.bottomPadding
        )
        #expect(LockMockLayout.clampedStripTop(120) == 120)
        #expect(LockMockLayout.previewScale == 0.58)
    }

    @Test @MainActor func accessoriesHeightGrowsWithWeatherGraph() {
        let settings = AppSettings.shared
        let originalWeather = settings.lockScreenWeatherAccessory
        let originalBluetooth = settings.lockScreenBluetoothAccessory
        let originalBattery = settings.lockScreenBatteryAccessory
        let originalFocus = settings.lockScreenFocusAccessory
        let originalGraph = settings.lockScreenWeatherShowGraph
        let originalKind = settings.lockScreenWeatherGraphKind
        let originalLabels = settings.lockScreenWeatherShowGraphLabels
        defer {
            settings.lockScreenWeatherAccessory = originalWeather
            settings.lockScreenBluetoothAccessory = originalBluetooth
            settings.lockScreenBatteryAccessory = originalBattery
            settings.lockScreenFocusAccessory = originalFocus
            settings.lockScreenWeatherShowGraph = originalGraph
            settings.lockScreenWeatherGraphKind = originalKind
            settings.lockScreenWeatherShowGraphLabels = originalLabels
        }

        settings.lockScreenWeatherAccessory = false
        settings.lockScreenBluetoothAccessory = false
        settings.lockScreenBatteryAccessory = false
        settings.lockScreenFocusAccessory = false
        settings.lockScreenWeatherShowGraph = false
        settings.lockScreenWeatherShowGraphLabels = false
        settings.lockScreenWeatherGraphKind = .temperature
        #expect(LockAccessoriesMetrics.height(settings: settings) == 0)

        settings.lockScreenWeatherAccessory = true
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

        settings.lockScreenWeatherGraphKind = .both
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
                + LockAccessoriesMetrics.graphExtra
                + LockAccessoriesMetrics.graphBothExtra
        )

        settings.lockScreenWeatherShowGraphLabels = true
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
                + LockAccessoriesMetrics.graphExtra
                + LockAccessoriesMetrics.graphBothExtra
                + LockAccessoriesMetrics.graphLabelsExtra
                + LockAccessoriesMetrics.graphLabelsExtra / 2
        )

        settings.lockScreenWeatherGraphKind = .temperature
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
                + LockAccessoriesMetrics.graphExtra
                + LockAccessoriesMetrics.graphLabelsExtra
        )

        settings.lockScreenWeatherAccessory = false
        settings.lockScreenFocusAccessory = true
        #expect(
            LockAccessoriesMetrics.height(settings: settings)
                == LockAccessoriesMetrics.rowHeight
        )
    }

    @Test @MainActor func topInsetKeepsPanelAboveBottomMargin() {
        let settings = AppSettings.shared
        let originalWeather = settings.lockScreenWeatherAccessory
        let originalBluetooth = settings.lockScreenBluetoothAccessory
        let originalBattery = settings.lockScreenBatteryAccessory
        let originalFocus = settings.lockScreenFocusAccessory
        let originalGraph = settings.lockScreenWeatherShowGraph
        let originalKind = settings.lockScreenWeatherGraphKind
        let originalLabels = settings.lockScreenWeatherShowGraphLabels
        let originalFraction = settings.lockScreenAccessoriesTopInsetFraction
        defer {
            settings.lockScreenWeatherAccessory = originalWeather
            settings.lockScreenBluetoothAccessory = originalBluetooth
            settings.lockScreenBatteryAccessory = originalBattery
            settings.lockScreenFocusAccessory = originalFocus
            settings.lockScreenWeatherShowGraph = originalGraph
            settings.lockScreenWeatherGraphKind = originalKind
            settings.lockScreenWeatherShowGraphLabels = originalLabels
            settings.lockScreenAccessoriesTopInsetFraction = originalFraction
        }

        settings.lockScreenWeatherAccessory = true
        settings.lockScreenBluetoothAccessory = false
        settings.lockScreenBatteryAccessory = false
        settings.lockScreenFocusAccessory = false
        settings.lockScreenWeatherShowGraph = true
        settings.lockScreenWeatherGraphKind = .both
        settings.lockScreenWeatherShowGraphLabels = true
        settings.lockScreenAccessoriesTopInsetFraction = 0.92

        let screenHeight: CGFloat = 982
        let panelHeight = LockAccessoriesMetrics.height(settings: settings)
        let inset = LockAccessoriesMetrics.topInset(
            screenHeight: screenHeight,
            settings: settings
        )
        #expect(
            inset == screenHeight - panelHeight
                - LockAccessoriesMetrics.bottomMargin
        )
        #expect(inset > LockAccessoriesMetrics.minTopInset)

        let screen = CGRect(x: 0, y: 0, width: 1512, height: screenHeight)
        let frame = LockAccessoriesMetrics.defaultFrame(
            screenFrame: screen,
            settings: settings
        )
        #expect(frame.minY == LockAccessoriesMetrics.bottomMargin)
        #expect(frame.height == panelHeight)

        settings.lockScreenAccessoriesTopInsetFraction = 0.05
        let low = LockAccessoriesMetrics.topInset(
            screenHeight: screenHeight,
            settings: settings
        )
        #expect(low == LockAccessoriesMetrics.minTopInset)
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
