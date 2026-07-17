//
//  RootView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

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
    let gapExtended: CGFloat = 12
    let edgePad: CGFloat = 14
    let barsW: CGFloat = 18
    let hudExtra: CGFloat = 38
    var topRadius: CGFloat {
        if airDrop { return 16 }
        if expanded, idle { return 10 }
        if expanded { return 20 }
        if hudActive { return 16 }
        return 10
    }
    var bottomRadius: CGFloat {
        if airDrop { return 24 }
        if expanded, idle { return 12 }
        if expanded { return 30 }
        if hudActive { return 26 }
        return 12
    }
    var height: CGFloat {
        if airDrop { return airDropTransfer ? 128 : 112 }
        if expanded, idle { return notchH }
        if expanded { return 182 }
        if hudActive { return notchH + hudExtra }
        return notchH
    }
    var artSize: CGFloat { notchH - 11 }
    var gap: CGFloat {
        extended || sideAnnouncement || (expanded && idle) ? gapExtended : 6
    }
    var side: CGFloat {
        if expanded, idle {
            return edgePad + 22 + gap
        }
        if sideAnnouncement {
            return edgePad + 26 + gap
        }
        return extended ? edgePad + max(artSize, barsW) + gap : 50
    }
    var width: CGFloat {
        if airDrop { return max(notchW + 160, 380) }
        if expanded, idle {
            return notchW + 2 * side + 2 * topRadius
        }
        if expanded { return 380 }
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
        screen: NSScreen.main!,
        notchRect: .zero
    )
    @Published var isExpanded = false
    @Published var nowPlaying = NowPlaying()
    @Published private(set) var trackChangeToken: UInt = 0
    @Published var accentColor: Color = NotchViewModel.defaultAccent
    @Published var isLocked = false
    @Published var hud: HUDKind? = nil
    @Published var hudDisplay: HUDKind? = nil
    @Published var hudLevel: Float = 0
    @Published var hudMuted: Bool = false
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
    fileprivate static let notchExpandSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.72
    )
    fileprivate static let notchCollapseSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 1.0
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
                self?.showHUD(.volume, lvl: level, muted: muted || level == 0)
            }
        }
        volume.start()

        brightness.onChange = { [weak self] level in
            Task { @MainActor in
                guard AppSettings.shared.brightnessHUD,
                    AppSettings.shared.replaceSystemHUD
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
        if isDisplayMetadataEqual(np), pendingSeekTime == nil {
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
            || np.duration != nowPlaying.duration

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

    private func isDisplayMetadataEqual(_ np: NowPlaying) -> Bool {
        np.trackKey == nowPlaying.trackKey
            && np.title == nowPlaying.title
            && np.artist == nowPlaying.artist
            && np.album == nowPlaying.album
            && np.bundleIdentifier == nowPlaying.bundleIdentifier
            && np.artworkUnavailable == nowPlaying.artworkUnavailable
            && (np.artwork == nil) == (nowPlaying.artwork == nil)
            && np.artwork?.count == nowPlaying.artwork?.count
            && np.isPlaying == nowPlaying.isPlaying
            && np.isLive == nowPlaying.isLive
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
            incoming.artworkUnavailable = true
            incoming.artist = ""
            incoming.album = ""
            incoming.trackKey = ""
            incoming.bundleIdentifier = ""
            incoming.duration = 0
            incoming.elapsed = 0
            incoming.isLive = false
        }
        if let target = pendingSeekTime, let at = pendingSeekAt,
            Date().timeIntervalSince(at) < 4
        {
            let reported = Self.interpolatedElapsed(from: np, at: Date())
            if abs(reported - target) > 1.5 {
                incoming.elapsed = target
                incoming.elapsedTimestamp = Date()
            } else {
                pendingSeekTime = nil
                pendingSeekAt = nil
            }
        }

        let artChanged =
            (incoming.artwork == nil) != (nowPlaying.artwork == nil)
            || incoming.artwork?.count != nowPlaying.artwork?.count
        let wasIdle = isIdle
        nowPlaying = incoming
        let nowIdle = isIdle
        if nowIdle, !wasIdle {
            accentTask?.cancel()
            withAnimation(.easeOut(duration: 0.45)) {
                accentColor = Self.defaultAccent
            }
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
    }

    static func interpolatedElapsed(from np: NowPlaying, at date: Date)
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
        if !v, AirDropController.shared.phase.isActive { return }
        guard v != isExpanded else { return }
        withAnimation(v ? Self.notchExpandSpring : Self.notchCollapseSpring) {
            isExpanded = v
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

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var airDrop = AirDropController.shared
    @Namespace private var ns
    @State private var trackPulse: CGFloat = 0
    @State private var airDropPulse: CGFloat = 0

    private var hasTrack: Bool { !vm.isIdle }
    private var airDropActive: Bool { airDrop.phase.isActive }
    private var hudVisible: Bool { vm.hudDisplay != nil && !airDropActive }
    private var verticalHUD: Bool {
        !airDropActive && vm.hudDisplay?.presentsVertically == true
    }
    private var sideAnnouncement: Bool {
        !airDropActive && vm.hudDisplay?.presentsOnSides == true
            && !vm.isExpanded
    }
    private var hudIntegrated: Bool {
        verticalHUD && !vm.isExpanded && !airDropActive
    }
    private var hudBelowExpanded: Bool {
        verticalHUD && vm.isExpanded && !airDropActive
    }
    private var m: NotchMetrics {
        NotchMetrics(
            notchW: vm.notch.notchRect.width > 0
                ? vm.notch.notchRect.width : 200,
            notchH: vm.notch.notchRect.height > 0
                ? vm.notch.notchRect.height + 0.25 : 32,
            expanded: vm.isExpanded && !airDropActive,
            idle: vm.isExpanded && vm.isIdle && !airDropActive,
            extended: (settings.extendNotch && hasTrack && !verticalHUD
                && !airDropActive)
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
                }()
        )
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
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: hudBelowExpanded ? 6 : 0) {
                ZStack(alignment: .top) {
                    NotchShape(
                        topRadius: m.topRadius,
                        bottomRadius: m.bottomRadius
                    )
                    .fill(.black)
                    .frame(width: m.width, height: m.height)
                    .overlay {
                        if airDropActive {
                            NotchShape(
                                topRadius: m.topRadius,
                                bottomRadius: m.bottomRadius
                            )
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
                        NotchShape(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .stroke(
                            airDropActive
                                ? Color.white.opacity(
                                    0.08 + 0.05 * airDropPulse
                                )
                                : vm.accentColor.opacity(0.55 * trackPulse),
                            lineWidth: airDropActive ? 1 : 1.5
                        )
                        .blur(
                            radius: airDropActive
                                ? 0.8 : trackPulse * 1.5
                        )
                        .scaleEffect(
                            1
                                + (airDropActive
                                    ? airDropPulse * 0.004 : trackPulse * 0.018)
                        )
                    }
                    .background {
                        NotchShape(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .fill(
                            airDropActive
                                ? Color.white.opacity(0.045)
                                : vm.accentColor.opacity(0.22 * trackPulse)
                        )
                        .blur(radius: airDropActive ? 18 : 28)
                        .scaleEffect(x: 1.06, y: 1.1)
                        .opacity(
                            airDropActive
                                ? 0.55
                                : ((vm.isExpanded && !vm.isIdle || hudVisible
                                    ? 0.55 : 0)
                                    + trackPulse * 0.35)
                        )
                        .frame(width: m.width, height: m.height)
                    }
                    .background {
                        NotchShape(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .fill(Color.black.opacity(0.95))
                        .blur(radius: 28)
                        .scaleEffect(x: 1.12, y: 1.18)
                        .opacity(
                            airDropActive || vm.isExpanded && !vm.isIdle
                                || hudVisible ? 0.55 : 0
                        )
                        .frame(width: m.width, height: m.height)
                    }

                    if airDropActive {
                        AirDropNotchContent(airDrop: airDrop)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    } else if vm.isExpanded {
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
                .clipShape(
                    NotchShape(
                        topRadius: m.topRadius,
                        bottomRadius: m.bottomRadius
                    )
                )

                if hudBelowExpanded, let kind = vm.hudDisplay {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: hudTailMetrics.bottomRadius,
                            style: .continuous
                        )
                        .fill(.black)
                        HUDChip(kind: kind)
                            .padding(.horizontal, 20)
                            .frame(height: m.hudExtra, alignment: .center)
                    }
                    .frame(width: hudTailMetrics.width, height: m.hudExtra)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .top)
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .animation(NotchViewModel.sideHUDSpring, value: vm.hud)
        .animation(NotchViewModel.sideHUDSpring, value: vm.hudDisplay)
        .animation(NotchViewModel.airDropSpring, value: airDrop.phase)
        .animation(
            NotchViewModel.airDropSpring,
            value: airDrop.systemChooserPresented
        )
        .animation(NotchViewModel.notchExpandSpring, value: m.height)
        .animation(NotchViewModel.notchExpandSpring, value: m.width)
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
}
