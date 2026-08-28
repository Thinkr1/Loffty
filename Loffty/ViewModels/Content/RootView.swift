//
//  RootView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import AppKit
import Combine
import SwiftUI

struct NotchMetrics {
    var notchW: CGFloat
    var notchH: CGFloat
    var expanded: Bool
    var idle: Bool
    var extended: Bool
    var hudActive: Bool
    var sideAnnouncement: Bool = false
    var airDrop: Bool = false
    var airDropTransfer: Bool = false
    var notification: Bool = false
    var notificationExpanded: Bool = false
    var notificationPreview: String = ""
    var notificationSender: String = ""
    var notificationCanReply: Bool = false
    var notificationDraft: String = ""
    var showAlbum: Bool = false
    var artAspectRatio: CGFloat = 1
    var customizingToolbar: Bool = false
    var weather: Bool = false
    var swipeExpansion: CGFloat = 0
    var idleSuggestions: Bool = false
    let gapExtended: CGFloat = 12
    let edgePad: CGFloat = 14
    let barsW: CGFloat = 18
    let hudExtra: CGFloat = 38
    var topRadius: CGFloat {
        if airDrop { return 16 }
        if notification, notificationExpanded {
            return NotificationLayout.expandedTopRadius
        }
        if notification { return NotificationLayout.compactTopRadius }
        if customizingToolbar { return 22 }
        if expanded { return 22 }
        if hudActive { return 16 }
        return 10
    }
    var bottomRadius: CGFloat {
        if airDrop { return 24 }
        if notification, notificationExpanded {
            return NotificationLayout.expandedBottomRadius
        }
        if notification { return NotificationLayout.compactBottomRadius }
        if customizingToolbar { return 30 }
        if expanded { return 30 }
        if hudActive { return 26 }
        return 12
    }
    var height: CGFloat {
        if airDrop { return airDropTransfer ? 128 : 112 }
        if notification, notificationExpanded {
            return NotificationLayout.expandedHeight(
                message: notificationPreview,
                notchH: notchH,
                canReply: notificationCanReply,
                draft: notificationDraft
            )
        }
        if notification {
            return notchH
                + NotificationLayout.compactExtra(
                    message: notificationPreview,
                    sender: notificationSender,
                    notchW: notchW,
                    canReply: notificationCanReply
                )
        }
        if customizingToolbar {
            return MediaToolbarCustomizeLayout.expandedHeight(
                showAlbum: showAlbum
            )
        }
        if expanded {
            if weather { return 168 + swipeExpansion * 24 }
            if idle, idleSuggestions {
                return notchH + IdleNotchLayout.suggestionsBody
            }
            return showAlbum ? 206 : 196
        }
        if hudActive { return notchH + hudExtra }
        return notchH
    }
    var artSize: CGFloat { notchH - 11 }
    var artWidth: CGFloat {
        artSize * MediaParsing.clampedArtworkAspect(max(artAspectRatio, 1))
    }
    var gap: CGFloat {
        extended || sideAnnouncement || notification || (expanded && idle)
            ? gapExtended : 6
    }
    var side: CGFloat {
        if notification, !notificationExpanded {
            return max(edgePad, (width - notchW) / 2)
        }
        if expanded, idle {
            return edgePad + 22 + gap
        }
        if sideAnnouncement {
            return edgePad + 26 + gap
        }
        return extended ? edgePad + max(artWidth, barsW) + gap : 50
    }
    var width: CGFloat {
        if airDrop { return max(notchW + 160, 380) }
        if notification, notificationExpanded {
            return NotificationLayout.expandedWidth
        }
        if notification {
            return NotificationLayout.compactWidth(
                notchW: notchW,
                sender: notificationSender,
                message: notificationPreview,
                canReply: notificationCanReply
            )
        }
        if customizingToolbar { return MediaToolbarCustomizeLayout.width }
        if expanded {
            return weather ? 392 + swipeExpansion * 32 : 392
        }
        if hudActive { return notchW + 2 * topRadius + 36 }
        if sideAnnouncement {
            return notchW + 2 * side + 2 * topRadius + 10
        }
        if extended {
            return notchW + 2 * side + 2 * topRadius
        }
        return notchW + 2 * topRadius
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var notch = NotchInfo(
        screen: NSScreen.main ?? NSScreen.screens[0],
        notchRect: .zero
    )
    @Published var isExpanded = false
    @Published var expandedPage: ExpandedPage = ExpandedPage.stored()
    @Published var pageTurnForward = true
    @Published var weatherSlide: WeatherSlide = .overview
    @Published var weatherSlideForward = true
    @Published var pageSwipeOffset: CGFloat = 0
    @Published var weatherSlideOffset: CGFloat = 0
    @Published var nowPlaying = NowPlaying()
    @Published private(set) var trackChangeToken: UInt = 0
    @Published var accentColor: Color = NotchViewModel.defaultAccent
    @Published var isLocked = false
    @Published var isFullScreen = false
    @Published var lockScreenArtExpanded = false
    @Published var hud: HUDKind? = nil
    @Published var hudDisplay: HUDKind? = nil
    @Published var hudLevel: Float = 0
    @Published var hudMuted: Bool = false
    @Published private(set) var isCurrentTrackLiked: Bool?
    private var hudHideTask: Task<Void, Never>?
    static let hudSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.82
    )
    static let sideHUDSpring = Animation.spring(
        response: 0.48,
        dampingFraction: 0.78,
        blendDuration: 0.05
    )
    static let airDropSpring = Animation.spring(
        response: 0.42,
        dampingFraction: 0.8,
        blendDuration: 0.04
    )
    static let notchExpandSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.72
    )
    static let notchCollapseSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 1.0
    )
    static let pageSwitchSpring = Animation.spring(
        response: 0.46,
        dampingFraction: 0.86,
        blendDuration: 0.08
    )
    private var elapsedAt = Date()
    private var pendingSeekTime: Double?
    private var pendingSeekAt: Date?
    private var pendingUpdate: NowPlaying?
    private var applyDebounceTask: Task<Void, Never>?
    private var accentTask: Task<Void, Never>?
    private var rapidSkipResetTask: Task<Void, Never>?
    private var lastTrackChangeAt = Date.distantPast
    @Published private(set) var isRapidSkipping = false
    private let media = MediaController()
    private var likeRefreshTask: Task<Void, Never>?
    private var likeToggleTask: Task<Void, Never>?
    private var likedTrackID: String?

    var isIdle: Bool {
        nowPlaying.title.isEmpty && nowPlaying.artwork == nil
    }

    static let defaultAccent = Color.white.opacity(0.5)

    private let volume = SystemVolumeWatcher()
    private let brightness = SystemBrightnessWatcher()
    private let battery = BatteryHUDWatcher()
    private let bluetooth = BluetoothHUDWatcher()
    private let focus = FocusHUDWatcher()
    private let keyInterceptor = SystemKeyInterceptor()
    private var cancellables = Set<AnyCancellable>()

    func start() {
        media.onUpdate = { [weak self] np in
            Task { @MainActor in self?.scheduleApply(np) }
        }
        media.start()

        AppSettings.shared.$artistEnrichment
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.media.refreshArtistEnrichment()
            }
            .store(in: &cancellables)

        AppSettings.shared.$showSpotifyLikeButton
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLikeState()
            }
            .store(in: &cancellables)
        AppSettings.shared.$mediaToolbarItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLikeState()
            }
            .store(in: &cancellables)
        //         SpotifyLibraryManager.shared.$isAuthenticated
        //             .receive(on: RunLoop.main)
        //             .sink { [weak self] _ in
        //                 self?.refreshLikeState()
        //             }
        //             .store(in: &cancellables)

        keyInterceptor.setEnabled(AppSettings.shared.replaceSystemHUD)
        AppSettings.shared.$replaceSystemHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.keyInterceptor.setEnabled(enabled)
                self?.syncBrightnessWatcher()
            }
            .store(in: &cancellables)

        AppSettings.shared.$brightnessHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBrightnessWatcher()
            }
            .store(in: &cancellables)

        volume.onChange = { [weak self] level, muted in
            Task { @MainActor in
                guard AppSettings.shared.replaceSystemHUD else { return }
                self?.showHUD(
                    .volume(symbol: OutputDeviceIcon.currentSymbol()),
                    lvl: level,
                    muted: muted || level == 0
                )
            }
        }
        volume.start()

        brightness.onChange = { [weak self] level in
            Task { @MainActor in
                let settings = AppSettings.shared
                guard
                    AppSettings.shouldPresentBrightnessHUD(
                        brightnessHUD: settings.brightnessHUD,
                        replaceSystemHUD: settings.replaceSystemHUD,
                        showOnAutoAdjust: settings
                            .brightnessHUDShownOnAutoAdjust,
                        changeWasFromKeyPress: self?.keyInterceptor
                            .brightnessChangeWasFromKeyPress() == true
                    )
                else { return }
                self?.showHUD(.brightness, lvl: level)
            }
        }
        syncBrightnessWatcher()

        battery.onChange = {
            [weak self] percent, charging, powerSourceChanged in
            Task { @MainActor in
                guard let self else { return }
                if powerSourceChanged {
                    self.brightness.suppress(for: 3.0)
                }
                guard AppSettings.shared.batteryHUD else { return }
                self.showHUD(
                    .battery(percent: percent, charging: charging),
                    lvl: Float(percent) / 100
                )
            }
        }
        bluetooth.onChange = { [weak self] name, connected in
            Task { @MainActor in
                guard AppSettings.shared.bluetoothHUD else { return }
                self?.showHUD(
                    .bluetooth(name: name, connected: connected),
                    lvl: connected ? 1 : 0
                )
            }
        }
        focus.onChange = { [weak self] enabled, name in
            Task { @MainActor in
                guard AppSettings.shared.focusHUD else { return }
                self?.showHUD(
                    .focus(enabled: enabled, name: name),
                    lvl: enabled ? 1 : 0
                )
            }
        }

        AppSettings.shared.$batteryHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncBatteryWatcher()
            }
            .store(in: &cancellables)
        AppSettings.shared.$bluetoothHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.bluetooth.start()
                } else {
                    self.bluetooth.stop()
                }
            }
            .store(in: &cancellables)
        AppSettings.shared.$focusHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.focus.start() } else { self.focus.stop() }
            }
            .store(in: &cancellables)

        syncBatteryWatcher()
        if AppSettings.shared.bluetoothHUD { bluetooth.start() }
        if AppSettings.shared.focusHUD { focus.start() }

        AppSettings.shared.$soundwaveMotion
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSoundwaves()
            }
            .store(in: &cancellables)
        AppSettings.shared.$soundwaveFeel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSoundwaves()
            }
            .store(in: &cancellables)
        AppSettings.shared.$soundwaveTone
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSoundwaves()
            }
            .store(in: &cancellables)
        syncSoundwaves()

        MediaToolbarCustomizer.shared.$isCustomizing
            .receive(on: RunLoop.main)
            .sink { [weak self] customizing in
                guard let self else { return }
                if customizing {
                    if self.expandedPage == .weather {
                        self.expandedPage = .music
                    }
                } else {
                    self.expandedPage = ExpandedPage.stored()
                }
            }
            .store(in: &cancellables)
    }

    private func syncSoundwaves() {
        let settings = AppSettings.shared
        let feel = settings.soundwaveFeel
        let tone = settings.soundwaveTone
        AudioSpectrum.shared.setAnalysis(
            attack: feel.attack,
            release: feel.release,
            peakDecay: feel.peakDecay,
            minFrequency: tone.minFrequency,
            tilt: tone.tilt
        )
        AudioSpectrum.shared.setCapturing(
            settings.soundwaveMotion.shouldCapture(
                isPlaying: nowPlaying.isPlaying,
                idle: isIdle
            )
        )
    }

    private func syncBrightnessWatcher() {
        let enabled =
            AppSettings.shared.replaceSystemHUD
            && AppSettings.shared.brightnessHUD
        if enabled {
            brightness.start()
        } else {
            brightness.stop()
        }
        syncBatteryWatcher()
    }

    private func syncBatteryWatcher() {
        let needPowerWatch =
            AppSettings.shared.batteryHUD
            || (AppSettings.shared.replaceSystemHUD
                && AppSettings.shared.brightnessHUD)
        if needPowerWatch {
            battery.start()
        } else {
            battery.stop()
        }
    }

    private func scheduleApply(_ np: NowPlaying) {
        let elapsedJump = hasSignificantElapsedJump(np)
        if isDisplayMetadataEqual(np), pendingSeekTime == nil, !elapsedJump {
            return
        }

        let immediate =
            np.trackKey != nowPlaying.trackKey
            || np.title != nowPlaying.title
            || np.artist != nowPlaying.artist
            || np.album != nowPlaying.album
            || np.artworkUnavailable != nowPlaying.artworkUnavailable
            || (np.artwork == nil) != (nowPlaying.artwork == nil)
            || np.isPlaying != nowPlaying.isPlaying
            || np.isLive != nowPlaying.isLive
            || np.isVideo != nowPlaying.isVideo
            || np.websiteHost != nowPlaying.websiteHost
            || abs(np.artworkAspectRatio - nowPlaying.artworkAspectRatio)
                >= 0.01
            || np.duration != nowPlaying.duration
            || elapsedJump

        applyDebounceTask?.cancel()
        if immediate {
            pendingUpdate = nil
            apply(np)
            return
        }

        pendingUpdate = np
        applyDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let pending = pendingUpdate else { return }
            pendingUpdate = nil
            apply(pending)
        }
    }

    private func hasSignificantElapsedJump(_ np: NowPlaying) -> Bool {
        let now = Date()
        let currentT = Self.interpolatedElapsed(from: nowPlaying, at: now)
        let incomingT = Self.interpolatedElapsed(from: np, at: now)
        return abs(currentT - incomingT) >= 1.35
    }

    private func isDisplayMetadataEqual(_ np: NowPlaying) -> Bool {
        np.trackKey == nowPlaying.trackKey
            && np.title == nowPlaying.title
            && np.artist == nowPlaying.artist
            && np.album == nowPlaying.album
            && np.bundleIdentifier == nowPlaying.bundleIdentifier
            && np.parentApplicationBundleIdentifier
                == nowPlaying.parentApplicationBundleIdentifier
            && np.artworkUnavailable == nowPlaying.artworkUnavailable
            && (np.artwork == nil) == (nowPlaying.artwork == nil)
            && np.artwork?.count == nowPlaying.artwork?.count
            && np.isPlaying == nowPlaying.isPlaying
            && np.isLive == nowPlaying.isLive
            && np.isVideo == nowPlaying.isVideo
            && np.websiteHost == nowPlaying.websiteHost
            && np.contentItemIdentifier == nowPlaying.contentItemIdentifier
            && abs(np.artworkAspectRatio - nowPlaying.artworkAspectRatio)
                < 0.01
            && np.duration == nowPlaying.duration
            && np.playbackRate == nowPlaying.playbackRate
    }

    private func apply(_ np: NowPlaying) {
        let trackChanged =
            !np.trackKey.isEmpty && np.trackKey != nowPlaying.trackKey
        if np.title != nowPlaying.title {
            pendingSeekTime = nil
            pendingSeekAt = nil
        }
        var incoming = np
        if incoming.title.isEmpty {
            incoming.artwork = nil
            incoming.fullArtwork = nil
            incoming.artworkUnavailable = true
            incoming.artist = ""
            incoming.album = ""
            incoming.trackKey = ""
            incoming.bundleIdentifier = ""
            incoming.duration = 0
            incoming.elapsed = 0
            incoming.isLive = false
            incoming.isVideo = false
            incoming.websiteHost = ""
            incoming.artworkAspectRatio = 1
            incoming.parentApplicationBundleIdentifier = ""
        }
        if let target = pendingSeekTime, let at = pendingSeekAt,
            Date().timeIntervalSince(at) < 4
        {
            let reported = Self.interpolatedElapsed(from: np, at: Date())
            let age = Date().timeIntervalSince(at)
            if abs(reported - target) > 1.5 {
                if age > 0.85, abs(reported - target) > 2.5 {
                    pendingSeekTime = nil
                    pendingSeekAt = nil
                } else {
                    incoming.elapsed = target
                    incoming.elapsedTimestamp = Date()
                }
            } else {
                pendingSeekTime = nil
                pendingSeekAt = nil
            }
        }

        let artChanged =
            (incoming.artwork == nil) != (nowPlaying.artwork == nil)
            || incoming.artwork?.count != nowPlaying.artwork?.count
        let wasIdle = isIdle
        let previousBundle = nowPlaying.resolvedBundleIdentifier
        let previousContentID = nowPlaying.contentItemIdentifier
        nowPlaying = incoming
        let nowIdle = isIdle
        if !nowIdle {
            RecentPlaybackCache.shared.record(
                incoming,
                enabled: AppSettings.shared.idleRecentSuggestions
            )
        }
        if nowIdle, !wasIdle {
            accentTask?.cancel()
            withAnimation(.easeOut(duration: 0.45)) {
                accentColor = Self.defaultAccent
            }
        }
        syncSoundwaves()
        if trackChanged || nowIdle != wasIdle
            || incoming.resolvedBundleIdentifier != previousBundle
            || incoming.contentItemIdentifier != previousContentID
        {
            refreshLikeState()
        }
        if trackChanged {
            let now = Date()
            isRapidSkipping = now.timeIntervalSince(lastTrackChangeAt) < 0.25
            lastTrackChangeAt = now
            trackChangeToken &+= 1
            accentTask?.cancel()
            rapidSkipResetTask?.cancel()
            rapidSkipResetTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                isRapidSkipping = false
            }
        }
        if incoming.elapsedTimestamp == nil {
            elapsedAt = Date()
        }
        if artChanged {
            let data = incoming.artwork
            let trackKey = incoming.trackKey
            accentTask?.cancel()
            accentTask = Task.detached(priority: .utility) {
                let c = await AlbumColor.accent(from: data)
                await MainActor.run {
                    guard !Task.isCancelled,
                        self.nowPlaying.trackKey == trackKey
                    else { return }
                    let animate = !self.isRapidSkipping
                    if animate {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            self.accentColor = c
                        }
                    } else {
                        self.accentColor = c
                    }
                }
            }
        }
    }

    func setLocked(_ v: Bool) {
        guard v != isLocked else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            isLocked = v
        }
        if !v { lockScreenArtExpanded = false }
    }

    func setLockScreenArtExpanded(_ v: Bool) {
        guard v != lockScreenArtExpanded else { return }
        lockScreenArtExpanded = v
    }

    nonisolated static func interpolatedElapsed(
        from np: NowPlaying,
        at date: Date
    )
        -> Double
    {
        let rate = np.isPlaying ? max(0, np.playbackRate) : 0
        if let ts = np.elapsedTimestamp {
            return np.elapsed + date.timeIntervalSince(ts) * rate
        }
        return np.elapsed
    }

    func currentTime(at date: Date) -> Double {
        let t: Double
        if let target = pendingSeekTime, let at = pendingSeekAt,
            date.timeIntervalSince(at) < 4
        {
            let rate =
                nowPlaying.isPlaying ? max(0, nowPlaying.playbackRate) : 0
            t = target + date.timeIntervalSince(at) * rate
        } else if let ts = nowPlaying.elapsedTimestamp {
            let rate =
                nowPlaying.isPlaying ? max(0, nowPlaying.playbackRate) : 0
            t = nowPlaying.elapsed + date.timeIntervalSince(ts) * rate
        } else {
            let extra =
                nowPlaying.isPlaying
                ? max(0, date.timeIntervalSince(elapsedAt)) : 0
            t = nowPlaying.elapsed + extra
        }
        guard nowPlaying.duration > 0 else { return max(0, t) }
        return min(max(0, t), nowPlaying.duration)
    }

    func setExpanded(_ v: Bool) {
        if !v, MediaToolbarCustomizer.shared.isCustomizing { return }
        if !v, AirDropController.shared.phase.isActive { return }
        if !v, NotificationController.shared.isPinned { return }
        guard v != isExpanded else { return }
        let settings = AppSettings.shared
        let idlePage: ExpandedPage? = {
            guard v, isIdle, !MediaToolbarCustomizer.shared.isCustomizing
            else { return nil }
            guard settings.weatherEnabled else { return .music }
            switch settings.weatherIdleExpand {
            case .weather: return .weather
            case .music: return .music
            case .remember: return ExpandedPage.stored()
            }
        }()
        withAnimation(v ? Self.notchExpandSpring : Self.notchCollapseSpring) {
            isExpanded = v
            if let idlePage {
                pageTurnForward = idlePage == .weather
                expandedPage = idlePage
                if idlePage == .weather { weatherSlide = .overview }
            }
        }
        if let idlePage {
            UserDefaults.standard.set(
                idlePage.rawValue,
                forKey: ExpandedPage.storageKey
            )
        }
        if v, expandedPage == .weather {
            WeatherController.shared.prepare()
        }
    }

    func setExpandedPage(_ page: ExpandedPage) {
        guard page != expandedPage else { return }
        guard !MediaToolbarCustomizer.shared.isCustomizing else { return }
        if page == .weather, !AppSettings.shared.weatherEnabled { return }
        pageTurnForward = page == .weather
        pageSwipeOffset = 0
        withAnimation(Self.pageSwitchSpring) {
            expandedPage = page
            if page == .weather { weatherSlide = .overview }
        }
        UserDefaults.standard.set(
            page.rawValue,
            forKey: ExpandedPage.storageKey
        )
        if page == .weather { WeatherController.shared.prepare() }
    }

    func turnWeatherSlide(_ direction: Int) {
        guard isExpanded, expandedPage == .weather else { return }
        guard AppSettings.shared.weatherSwipeEnabled,
            let next = weatherSlide.neighbor(direction: direction)
        else {
            cancelWeatherSlide()
            return
        }
        weatherSlideForward = direction > 0
        weatherSlideOffset = 0
        performSlideFeedback()
        withAnimation(Self.pageSwitchSpring) {
            weatherSlide = next
        }
    }

    func updatePageSwipe(_ dx: CGFloat, _ dy: CGFloat) {
        guard abs(dx) > abs(dy) * 1.35, abs(dx) >= 2 else { return }
        let resistance: CGFloat = 0.65
        let step = max(-14, min(14, dx * resistance))
        let next = max(-42, min(42, pageSwipeOffset + step))
        withTransaction(Transaction(animation: nil)) {
            pageSwipeOffset =
                pageSwipeOffset == 0 && abs(next) < 8 ? 0 : next
        }
    }

    func cancelPageSwipe() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            pageSwipeOffset = 0
        }
    }

    func turnExpandedPage(_ direction: Int) {
        guard isExpanded else { return }
        guard AppSettings.shared.weatherEnabled,
            AppSettings.shared.weatherSwipeEnabled
        else {
            cancelPageSwipe()
            return
        }
        guard let next = expandedPage.neighbor(direction: direction) else {
            cancelPageSwipe()
            return
        }
        performSlideFeedback()
        setExpandedPage(next)
    }

    private func performSlideFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    func updateWeatherSlide(_ dy: CGFloat) {
        guard abs(dy) > 2 else { return }
        let resistance: CGFloat = 0.65
        let step = max(-14, min(14, dy * resistance))
        let next = max(
            -42,
            min(42, weatherSlideOffset + step)
        )
        withTransaction(Transaction(animation: nil)) {
            weatherSlideOffset =
                weatherSlideOffset == 0 && abs(next) < 8 ? 0 : next
        }
    }

    func cancelWeatherSlide() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            weatherSlideOffset = 0
        }
    }

    func showHUD(_ kind: HUDKind, lvl: Float, muted: Bool = false) {
        hudHideTask?.cancel()

        let animation =
            kind.presentsOnSides ? Self.sideHUDSpring : Self.hudSpring

        withAnimation(animation) {
            hud = kind
            hudDisplay = kind
            hudLevel = max(0, min(1, lvl))
            hudMuted = muted
        }

        let duration =
            kind.presentsOnSides
            ? max(AppSettings.shared.hudDuration, 1.9)
            : AppSettings.shared.hudDuration
        hudHideTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                hud = nil
            }
            try? await Task.sleep(for: .seconds(0.48))
            guard !Task.isCancelled else { return }
            hudDisplay = nil
        }
    }

    func playPause() { media.command(.togglePlayPause) }
    func next() {
        applyDebounceTask?.cancel()
        pendingUpdate = nil
        media.command(.next)
    }
    func prev() {
        applyDebounceTask?.cancel()
        pendingUpdate = nil
        media.command(.prev)
    }

    func seek(by delta: Double) {
        seek(to: currentTime(at: Date()) + delta)
    }

    func seek(to time: Double) {
        var t = max(0, time)
        if nowPlaying.duration > 0 { t = min(t, nowPlaying.duration) }
        media.setElapsed(t)
        pendingSeekTime = t
        pendingSeekAt = Date()
        nowPlaying.elapsed = t
        nowPlaying.elapsedTimestamp = Date()
    }

    func seekToLive() {
        guard nowPlaying.isLive, nowPlaying.duration > 0 else { return }
        seek(to: nowPlaying.duration)
    }

    var showsLikeButton: Bool {
        Self.showsLikeButton(
            toolbarContainsLike: AppSettings.shared.mediaToolbarItems
                .contains(.like),
            bundleID: nowPlaying.resolvedBundleIdentifier,
            idle: isIdle
        )
    }

    nonisolated static func likeSource(bundleID: String) -> LikeSource? {
        switch bundleID {
        // case SpotifyTrack.clientBundle: .spotify
        case AppleMusicTrack.clientBundle: .appleMusic
        default: nil
        }
    }

    nonisolated static func showsLikeButton(
        toolbarContainsLike: Bool,
        bundleID: String,
        idle: Bool
    ) -> Bool {
        toolbarContainsLike && !idle && likeSource(bundleID: bundleID) != nil
    }

    nonisolated static func showsLikeButton(
        enabled: Bool,
        bundleID: String,
        idle: Bool
    ) -> Bool {
        showsLikeButton(
            toolbarContainsLike: enabled,
            bundleID: bundleID,
            idle: idle
        )
    }

    func toggleLike() {
        guard let liked = isCurrentTrackLiked, let id = likedTrackID,
            let source = Self.likeSource(
                bundleID: nowPlaying.resolvedBundleIdentifier
            )
        else { return }
        let next = !liked
        isCurrentTrackLiked = next
        likeToggleTask?.cancel()
        likeToggleTask = Task { [weak self] in
            guard let self else { return }
            let ok: Bool
            switch source {
            //             case .spotify:
            //                 ok = await SpotifyLibraryManager.shared.setTrackSaved(
            //                     next,
            //                     trackID: id
            //                 )
            case .appleMusic:
                ok = await AppleMusicLibrary.setCurrentTrackFavorited(
                    next,
                    trackID: id
                )
            }
            guard !Task.isCancelled else { return }
            if !ok, self.likedTrackID == id {
                self.isCurrentTrackLiked = liked
            }
        }
    }

    private func refreshLikeState() {
        likeRefreshTask?.cancel()
        likeToggleTask?.cancel()
        likedTrackID = nil
        isCurrentTrackLiked = nil
        guard showsLikeButton,
            let source = Self.likeSource(
                bundleID: nowPlaying.resolvedBundleIdentifier
            )
        else { return }
        let trackKey = nowPlaying.trackKey
        //         let contentID = nowPlaying.contentItemIdentifier
        likeRefreshTask = Task { [weak self] in
            guard let self else { return }
            switch source {
            //             case .spotify:
            //                 await self.refreshSpotifyLikeState(
            //                     trackKey: trackKey,
            //                     contentID: contentID
            //                 )
            case .appleMusic:
                await self.refreshAppleMusicLikeState(trackKey: trackKey)
            }
        }
    }

    //     private func refreshSpotifyLikeState(trackKey: String, contentID: String)
    //         async
    //     {
    //         guard SpotifyLibraryManager.shared.isAuthenticated else { return }
    //         let id: String?
    //         if let parsed = SpotifyTrack.id(from: contentID) {
    //             id = parsed
    //         } else {
    //             id = await SpotifyMetadata.currentTrackID()
    //         }
    //         guard !Task.isCancelled, nowPlaying.trackKey == trackKey else {
    //             return
    //         }
    //         guard let id else { return }
    //         likedTrackID = id
    //         let saved = await SpotifyLibraryManager.shared.isTrackSaved(
    //             trackID: id
    //         )
    //         guard !Task.isCancelled, nowPlaying.trackKey == trackKey else {
    //             return
    //         }
    //         isCurrentTrackLiked = saved
    //     }

    private func refreshAppleMusicLikeState(trackKey: String) async {
        let state = await AppleMusicLibrary.currentFavoriteState()
        guard !Task.isCancelled, nowPlaying.trackKey == trackKey else {
            return
        }
        guard let state else { return }
        likedTrackID = state.trackID
        isCurrentTrackLiked = state.favorited
    }

    func isBehindLive(at date: Date = Date()) -> Bool {
        guard nowPlaying.isLive, nowPlaying.duration > 0 else { return false }
        return currentTime(at: date) < nowPlaying.duration - 4
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat = 20
    var bottomRadius: CGFloat = 30
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let tr = topRadius
        let br = bottomRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY))  // top left
        p.addQuadCurve(
            to: CGPoint(x: r.minX + tr, y: r.minY + tr),
            control: CGPoint(x: r.minX + tr, y: r.minY)
        )

        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))  // left side down

        p.addQuadCurve(
            to: CGPoint(x: r.minX + tr + br, y: r.maxY),
            control: CGPoint(x: r.minX + tr, y: r.maxY)
        )  // bottom left

        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))  // bottom edge

        p.addQuadCurve(
            to: CGPoint(x: r.maxX - tr, y: r.maxY - br),
            control: CGPoint(x: r.maxX - tr, y: r.maxY)
        )  // bottom right

        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))  // right side up

        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY),
            control: CGPoint(x: r.maxX - tr, y: r.minY)
        )  // top right
        p.closeSubpath()
        return p
    }
}

struct NotchBottomEdge: Shape {
    var topRadius: CGFloat = 20
    var bottomRadius: CGFloat = 30
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        Self.path(in: r, topRadius: topRadius, bottomRadius: bottomRadius)
    }

    nonisolated static func path(
        in r: CGRect,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> Path {
        var p = Path()
        let tr = topRadius
        let br = bottomRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(
            to: CGPoint(x: r.minX + tr, y: r.minY + tr),
            control: CGPoint(x: r.minX + tr, y: r.minY)
        )
        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))
        p.addQuadCurve(
            to: CGPoint(x: r.minX + tr + br, y: r.maxY),
            control: CGPoint(x: r.minX + tr, y: r.maxY)
        )
        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX - tr, y: r.maxY - br),
            control: CGPoint(x: r.maxX - tr, y: r.maxY)
        )
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        p.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY),
            control: CGPoint(x: r.maxX - tr, y: r.minY)
        )
        return p
    }
}

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var airDrop = AirDropController.shared
    @ObservedObject private var notifications = NotificationController.shared
    @ObservedObject private var toolbar =
        MediaToolbarCustomizer.shared
    @ObservedObject private var recents = RecentPlaybackCache.shared
    @Namespace private var ns
    @State private var trackPulse: CGFloat = 0
    @State private var airDropPulse: CGFloat = 0

    private var hasTrack: Bool { !vm.isIdle }
    private var airDropActive: Bool { airDrop.phase.isActive }
    private var notificationActive: Bool {
        notifications.isActive && !airDropActive
    }
    private var hudVisible: Bool {
        vm.hudDisplay != nil && !airDropActive && !notificationActive
    }
    private var verticalHUD: Bool {
        !airDropActive && !notificationActive
            && vm.hudDisplay?.presentsVertically == true
    }
    private var sideAnnouncement: Bool {
        !airDropActive && !notificationActive
            && vm.hudDisplay?.presentsOnSides == true
            && !vm.isExpanded
    }
    private var swipeExpansion: CGFloat {
        let raw = min(
            1,
            max(
                abs(vm.pageSwipeOffset),
                abs(vm.weatherSlideOffset)
            ) / 42
        )
        return raw * raw * (3 - 2 * raw)
    }
    private var swipeExpansionOffset: CGFloat {
        guard vm.pageSwipeOffset != 0 else { return 0 }
        return vm.pageSwipeOffset < 0
            ? -swipeExpansion * 16
            : swipeExpansion * 16
    }
    private var hudIntegrated: Bool {
        verticalHUD && !vm.isExpanded && !airDropActive && !notificationActive
    }
    private var hudBelowExpanded: Bool {
        verticalHUD && vm.isExpanded && !airDropActive && !notificationActive
    }
    private var islandRaised: Bool {
        (vm.isExpanded && !airDropActive && !notificationActive)
            || toolbar.isCustomizing
            || (notificationActive && notifications.isExpanded)
            || airDropActive
    }
    private var m: NotchMetrics {
        NotchMetrics(
            notchW: vm.notch.notchRect.width > 0
                ? vm.notch.notchRect.width : 200,
            notchH: vm.notch.notchRect.height > 0
                ? vm.notch.notchRect.height + 0.25 : 32,
            expanded: (vm.isExpanded || toolbar.isCustomizing)
                && !airDropActive && !notificationActive,
            idle: vm.isExpanded && vm.isIdle && !toolbar.isCustomizing
                && !airDropActive && !notificationActive,
            extended: (settings.extendNotch && hasTrack && !verticalHUD
                && !airDropActive && !notificationActive)
                || sideAnnouncement,
            hudActive: hudIntegrated,
            sideAnnouncement: sideAnnouncement,
            airDrop: airDropActive,
            airDropTransfer: airDropActive
                && {
                    if case .receiving = airDrop.phase { return true }
                    if case .sent = airDrop.phase { return true }
                    if case .received = airDrop.phase { return true }
                    return false
                }(),
            notification: notificationActive,
            notificationExpanded: notificationActive
                && notifications.isExpanded,
            notificationPreview: notifications.current?.body ?? "",
            notificationSender: notifications.current?.sender ?? "",
            notificationCanReply: notifications.current?.app.supportsReply
                ?? false,
            notificationDraft: notifications.draft,
            showAlbum: settings.showAlbum
                && !vm.nowPlaying.album.isEmpty
                && !vm.isIdle,
            artAspectRatio: vm.nowPlaying.displayArtworkAspect,
            customizingToolbar: toolbar.isCustomizing,
            weather: vm.isExpanded && vm.expandedPage == .weather
                && !toolbar.isCustomizing
                && !airDropActive && !notificationActive,
            swipeExpansion: swipeExpansion,
            idleSuggestions: vm.isExpanded && vm.isIdle
                && !toolbar.isCustomizing
                && settings.idleRecentSuggestions
                && !recents.suggestions.isEmpty
                && !airDropActive && !notificationActive
        )
    }
    private var notchLiquidGlassTint: LiquidGlassTint {
        LiquidGlassTint.resolved(
            isFullScreen: vm.isFullScreen,
            windowed: settings.liquidGlassTintWhenNotFullScreen,
            fullScreen: settings.liquidGlassTintFullScreen
        )
    }

    private var persistentEdgeColor: Color? {
        guard
            NotchEdgeStyle.shouldDraw(
                style: settings.notchEdgeStyle,
                showWhenNotFullScreen: settings.notchOutlineWhenNotFullScreen,
                isFullScreen: vm.isFullScreen
            )
        else { return nil }
        switch settings.notchEdgeStyle {
        case .off:
            return nil
        case .subtle:
            return Color.white.opacity(0.16)
        case .accent:
            return vm.isIdle
                ? Color.white.opacity(0.16)
                : vm.accentColor.opacity(0.55)
        }
    }

    private var hudTailMetrics: NotchMetrics {
        NotchMetrics(
            notchW: vm.notch.notchRect.width > 0
                ? vm.notch.notchRect.width : 200,
            notchH: vm.notch.notchRect.height > 0
                ? vm.notch.notchRect.height + 0.25 : 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: true,
            sideAnnouncement: false
        )
    }

    var body: some View {
        Group {
            #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 0) {
                        rootContent
                    }
                } else {
                    rootContent
                }
            #else
                rootContent
            #endif
        }
        .animation(
            vm.isExpanded
                ? NotchViewModel.notchExpandSpring
                : NotchViewModel.notchCollapseSpring,
            value: vm.isExpanded
        )
        .animation(
            vm.isExpanded
                ? NotchViewModel.notchExpandSpring
                : NotchViewModel.notchCollapseSpring,
            value: m.extended
        )
        .animation(NotchViewModel.notchExpandSpring, value: vm.isIdle)
        .animation(NotchViewModel.notchExpandSpring, value: recents.items.count)
        .animation(NotchViewModel.notchExpandSpring, value: vm.expandedPage)
        .animation(NotchViewModel.sideHUDSpring, value: vm.hud)
        .animation(NotchViewModel.sideHUDSpring, value: vm.hudDisplay)
        .animation(NotchViewModel.airDropSpring, value: airDrop.phase)
        .animation(
            NotchViewModel.airDropSpring,
            value: airDrop.systemChooserPresented
        )
        .animation(
            NotchViewModel.notchExpandSpring,
            value: notifications.current?.id
        )
        .animation(
            NotchViewModel.notchExpandSpring,
            value: notifications.isExpanded
        )
        .animation(NotchViewModel.notchExpandSpring, value: m.height)
        .animation(
            NotchViewModel.notchExpandSpring,
            value: toolbar.isCustomizing
        )
        .animation(.easeInOut(duration: 0.35), value: settings.notchEdgeStyle)
        .animation(
            .easeInOut(duration: 0.35),
            value: settings.notchOutlineWhenNotFullScreen
        )
        .animation(
            .easeInOut(duration: 0.35),
            value: settings.liquidGlassTintWhenNotFullScreen
        )
        .animation(
            .easeInOut(duration: 0.35),
            value: settings.liquidGlassTintFullScreen
        )
        .animation(.easeInOut(duration: 0.35), value: vm.isFullScreen)
        .onChange(of: vm.trackChangeToken) { _, token in
            guard token > 0, !vm.isRapidSkipping else { return }
            withAnimation(.easeOut(duration: 0.16)) { trackPulse = 1 }
            withAnimation(
                .spring(response: 0.55, dampingFraction: 0.78).delay(0.06)
            ) {
                trackPulse = 0
            }
        }
        .onChange(of: airDropActive) { _, active in
            if active {
                withAnimation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                ) {
                    airDropPulse = 1
                }
            } else {
                withAnimation(.easeOut(duration: 0.28)) { airDropPulse = 0 }
            }
        }
    }

    private var showsNotchAmbient: Bool {
        islandRaised || hudVisible || notificationActive
    }

    private var islandShape: NotchShape {
        NotchShape(
            topRadius: m.topRadius,
            bottomRadius: m.bottomRadius
        )
    }

    private var hudTailShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: hudTailMetrics.bottomRadius,
            style: .continuous
        )
    }

    private var notchGlassVeil: LinearGradient {
        let blackUntil = min(1, m.notchH / max(m.height, 1))
        if blackUntil >= 0.85 {
            return LinearGradient(
                colors: [.black, .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: blackUntil),
                .init(
                    color: Color.black.opacity(0.42),
                    location: blackUntil + (1 - blackUntil) * 0.48
                ),
                .init(color: Color.black.opacity(0.04), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var notchAmbient: some View {
        ZStack {
            islandShape
                .fill(Color.black.opacity(0.16))
                .blur(radius: 16)
                .offset(y: 5)
                .scaleEffect(x: 1.03, y: 1.05, anchor: .top)
                .opacity(showsNotchAmbient ? 1 : 0)
            islandShape
                .fill(vm.accentColor.opacity(0.32 * trackPulse))
                .blur(radius: 20)
                .scaleEffect(x: 1.05, y: 1.08, anchor: .top)
        }
        .frame(width: m.width, height: m.height)
        .allowsHitTesting(false)
    }

    private var rootContent: some View {
        VStack(spacing: hudBelowExpanded ? 6 : 0) {
            ZStack(alignment: .top) {
                notchAmbient

                ZStack(alignment: .top) {
                    islandShape
                        .fill(notchGlassVeil)
                        .overlay {
                            if airDropActive {
                                islandShape
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(
                                                    0.05 + 0.03 * airDropPulse
                                                ),
                                                .clear,
                                            ],
                                            center: UnitPoint(x: 0.5, y: 0.12),
                                            startRadius: 1,
                                            endRadius: m.height * 0.9
                                        )
                                    )
                            }
                        }
                        .overlay {
                            islandShape
                                .stroke(
                                    airDropActive
                                        ? Color.white.opacity(
                                            0.08 + 0.05 * airDropPulse
                                        )
                                        : vm.accentColor.opacity(
                                            0.55 * trackPulse
                                        ),
                                    lineWidth: airDropActive ? 1 : 1.5
                                )
                                .blur(
                                    radius: airDropActive
                                        ? 0.8 : trackPulse * 1.5
                                )
                                .scaleEffect(
                                    1
                                        + (airDropActive
                                            ? airDropPulse * 0.004
                                            : trackPulse * 0.018)
                                )
                        }

                    if airDropActive {
                        AirDropNotchContent(airDrop: airDrop)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    } else if notificationActive {
                        NotificationNotchContent(
                            notifications: notifications,
                            m: m
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .top
                        )
                    } else if vm.isExpanded || toolbar.isCustomizing {
                        ExpandedContent(ns: ns, m: m)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    } else {
                        ZStack(alignment: .top) {
                            CollapsedContent(ns: ns, m: m)
                                .opacity(hudIntegrated ? 0 : 1)

                            if hudIntegrated, let kind = vm.hudDisplay {
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: m.notchH)
                                    HUDChip(kind: kind)
                                        .padding(.horizontal, 40)
                                        .frame(
                                            height: m.hudExtra,
                                            alignment: .center
                                        )
                                }
                                .frame(
                                    width: m.width,
                                    height: m.height,
                                    alignment: .top
                                )
                            }
                        }
                    }
                }
                .frame(width: m.width, height: m.height, alignment: .top)
                .clipShape(islandShape)
                .contentShape(islandShape)
                .notchLiquidGlass(islandShape, tint: notchLiquidGlassTint)
                .overlay {
                    if let edge = persistentEdgeColor {
                        NotchBottomEdge(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .stroke(edge, lineWidth: 1)
                    }
                }
            }
            .frame(width: m.width, height: m.height, alignment: .top)
            .offset(x: swipeExpansionOffset)

            if hudBelowExpanded, let kind = vm.hudDisplay {
                HUDChip(kind: kind)
                    .padding(.horizontal, 20)
                    .frame(
                        width: hudTailMetrics.width,
                        height: m.hudExtra,
                        alignment: .center
                    )
                    .contentShape(hudTailShape)
                    .notchLiquidGlass(hudTailShape, tint: notchLiquidGlassTint)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .top)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    @ViewBuilder
    fileprivate func notchLiquidGlass<S: Shape>(
        _ shape: S,
        tint: LiquidGlassTint
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self
                    .glassEffect(tint.interactiveGlass, in: shape)
                    .preferredColorScheme(.dark)
            } else {
                notchLiquidGlassFallback(shape, tint: tint)
            }
        #else
            notchLiquidGlassFallback(shape, tint: tint)
        #endif
    }

    @ViewBuilder
    fileprivate func notchLiquidGlassFallback<S: Shape>(
        _ shape: S,
        tint: LiquidGlassTint
    ) -> some View {
        switch tint {
        case .identity:
            self.preferredColorScheme(.dark)
        case .clear, .regular:
            self
                .background(.ultraThinMaterial, in: shape)
                .preferredColorScheme(.dark)
        }
    }
}

#if compiler(>=6.2)
    @available(macOS 26.0, *)
    extension LiquidGlassTint {
        fileprivate var interactiveGlass: Glass {
            switch self {
            case .clear: .clear.interactive()
            case .regular: .regular.interactive()
            case .identity: .identity
            }
        }
    }
#endif
