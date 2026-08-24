//
//  NotchViewModelTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("NotchViewModel")
struct NotchViewModelTests {
    @Test func interpolatedElapsedRespectsPauseAndRate() {
        let ts = Date(timeIntervalSince1970: 1_000)
        var np = NowPlaying()
        np.elapsed = 10
        np.elapsedTimestamp = ts
        np.playbackRate = 1
        np.isPlaying = true
        let playing = NotchViewModel.interpolatedElapsed(
            from: np,
            at: ts.addingTimeInterval(5)
        )
        #expect(playing == 15)

        np.isPlaying = false
        let paused = NotchViewModel.interpolatedElapsed(
            from: np,
            at: ts.addingTimeInterval(5)
        )
        #expect(paused == 10)
    }

    @Test @MainActor func seekClampsToDuration() {
        let vm = NotchViewModel()
        vm.nowPlaying.duration = 100
        vm.nowPlaying.elapsed = 10
        vm.seek(to: 150)
        #expect(vm.nowPlaying.elapsed == 100)
        vm.seek(to: -5)
        #expect(vm.nowPlaying.elapsed == 0)
    }

    @Test @MainActor func isBehindLiveUsesFourSecondThreshold() {
        let vm = NotchViewModel()
        vm.nowPlaying.isLive = true
        vm.nowPlaying.duration = 100
        vm.nowPlaying.elapsed = 90
        vm.nowPlaying.elapsedTimestamp = Date()
        vm.nowPlaying.isPlaying = false
        #expect(vm.isBehindLive())
        vm.nowPlaying.elapsed = 97
        #expect(!vm.isBehindLive())
    }

    @Test @MainActor func showHUDClampsLevel() {
        let vm = NotchViewModel()
        vm.showHUD(.brightness, lvl: 1.5)
        #expect(vm.hudLevel == 1)
        vm.showHUD(.brightness, lvl: -0.2)
        #expect(vm.hudLevel == 0)
    }

    @Test @MainActor func setExpandedBlockedWhileAirDropActive() {
        let vm = NotchViewModel()
        let airDrop = AirDropController.shared
        airDrop.setPhaseForTesting(.idle)
        vm.isExpanded = true
        vm.setExpanded(false)
        #expect(!vm.isExpanded)

        vm.setExpanded(true)
        airDrop.setPhaseForTesting(.picking)
        vm.setExpanded(false)
        #expect(vm.isExpanded)
        airDrop.setPhaseForTesting(.idle)
    }

    @Test @MainActor func isIdleWhenNoTitleOrArtwork() {
        let vm = NotchViewModel()
        vm.nowPlaying = NowPlaying()
        #expect(vm.isIdle)
        vm.nowPlaying.title = "Song"
        #expect(!vm.isIdle)
    }

    @Test @MainActor func seekToLiveRequiresLiveDuration() {
        let vm = NotchViewModel()
        vm.nowPlaying.isLive = false
        vm.nowPlaying.duration = 100
        vm.nowPlaying.elapsed = 10
        vm.seekToLive()
        #expect(vm.nowPlaying.elapsed == 10)

        vm.nowPlaying.isLive = true
        vm.seekToLive()
        #expect(vm.nowPlaying.elapsed == 100)
    }

    @Test @MainActor func currentTimeUsesPendingSeekWithinWindow() {
        let vm = NotchViewModel()
        vm.nowPlaying.duration = 200
        vm.nowPlaying.isPlaying = false
        vm.seek(to: 40)
        let now = Date()
        #expect(abs(vm.currentTime(at: now) - 40) < 0.01)
    }

    @Test @MainActor func turnExpandedPageMovesSpatially() {
        let vm = NotchViewModel()
        let settings = AppSettings.shared
        let originalWeatherEnabled = settings.weatherEnabled
        let originalSwipeEnabled = settings.weatherSwipeEnabled
        let original = ExpandedPage.stored()
        defer {
            settings.weatherEnabled = originalWeatherEnabled
            settings.weatherSwipeEnabled = originalSwipeEnabled
            UserDefaults.standard.set(
                original.rawValue,
                forKey: ExpandedPage.storageKey
            )
        }
        settings.weatherEnabled = true
        settings.weatherSwipeEnabled = true
        vm.isExpanded = true
        vm.expandedPage = .music
        vm.turnExpandedPage(1)
        #expect(vm.expandedPage == .weather)
        vm.turnExpandedPage(1)
        #expect(vm.expandedPage == .weather)
        vm.turnExpandedPage(-1)
        #expect(vm.expandedPage == .music)
        #expect(
            UserDefaults.standard.string(forKey: ExpandedPage.storageKey)
                == ExpandedPage.music.rawValue
        )
    }

    @Test @MainActor func turnExpandedPageRequiresExpandedNotch() {
        let vm = NotchViewModel()
        vm.expandedPage = .music
        vm.isExpanded = false
        vm.turnExpandedPage(1)
        #expect(vm.expandedPage == .music)
    }

    @Test @MainActor func setExpandedWhileIdleOpensWeather() {
        let vm = NotchViewModel()
        let settings = AppSettings.shared
        let originalWeatherEnabled = settings.weatherEnabled
        let originalExpand = settings.weatherIdleExpand
        let original = ExpandedPage.stored()
        defer {
            settings.weatherEnabled = originalWeatherEnabled
            settings.weatherIdleExpand = originalExpand
            UserDefaults.standard.set(
                original.rawValue,
                forKey: ExpandedPage.storageKey
            )
        }
        settings.weatherEnabled = true
        settings.weatherIdleExpand = .weather
        vm.nowPlaying = NowPlaying()
        vm.expandedPage = .music
        vm.setExpanded(true)
        #expect(vm.isExpanded)
        #expect(vm.expandedPage == .weather)
        #expect(
            UserDefaults.standard.string(forKey: ExpandedPage.storageKey)
                == ExpandedPage.weather.rawValue
        )
    }

    @Test @MainActor func setExpandedWhileIdleRespectsMusicPreference() {
        let vm = NotchViewModel()
        let settings = AppSettings.shared
        let originalExpand = settings.weatherIdleExpand
        let originalPage = ExpandedPage.stored()
        defer {
            settings.weatherIdleExpand = originalExpand
            UserDefaults.standard.set(
                originalPage.rawValue,
                forKey: ExpandedPage.storageKey
            )
        }
        settings.weatherIdleExpand = .music
        vm.nowPlaying = NowPlaying()
        vm.expandedPage = .weather
        vm.setExpanded(true)
        #expect(vm.expandedPage == .music)
    }
}
