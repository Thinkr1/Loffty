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
    var extended: Bool
    var hudActive: Bool
    let gapExtended: CGFloat = 12
    let edgePad: CGFloat = 14
    let barsW: CGFloat = 18
    let hudExtra: CGFloat = 38
    var topRadius: CGFloat {
        if expanded { return 20 }
        if hudActive { return 16 }
        return 10
    }
    var bottomRadius: CGFloat {
        if expanded { return 30 }
        if hudActive { return 26 }
        return 12
    }
    var height: CGFloat {
        if expanded { return 182 }
        if hudActive { return notchH + hudExtra }
        return notchH
    }
    var artSize: CGFloat { notchH - 8 }
    var gap: CGFloat { extended ? gapExtended : 6 }
    var side: CGFloat { extended ? edgePad + max(artSize, barsW) + gap : 50 }
    var width: CGFloat {
        if expanded { return 380 }
        if hudActive { return notchW + 2 * topRadius + 36 }
        return notchW + 2 * (extended ? side : 0) + 2 * topRadius
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var notch = NotchInfo(
        screen: NSScreen.main!,
        notchRect: .zero,
        hasNotch: false
    )
    @Published var isExpanded = false
    @Published var nowPlaying = NowPlaying()
    @Published private(set) var trackChangeToken: UInt = 0
    @Published var accentColor: Color = .white.opacity(0.5)
    @Published var isLocked = false
    @Published var hud: HUDKind? = nil
    @Published var hudDisplay: HUDKind? = nil
    @Published var hudLevel: Float = 0
    @Published var hudMuted: Bool = false
    private var hudHideTask: Task<Void, Never>?
    fileprivate static let hudSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.82
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
    private let media = MediaController()
    private let volume = SystemVolumeWatcher()
    private let brightness = SystemBrightnessWatcher()
    private let keyInterceptor = SystemKeyInterceptor()
    private var cancellables = Set<AnyCancellable>()

    func start() {
        media.onUpdate = { [weak self] np in
            Task { @MainActor in self?.apply(np) }
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
        if AppSettings.shared.brightnessHUD {
            brightness.start()
        }
    }

    private func apply(_ np: NowPlaying) {
        let trackChanged =
            !np.trackKey.isEmpty && np.trackKey != nowPlaying.trackKey
        if np.title != nowPlaying.title {
            pendingSeekTime = nil
            pendingSeekAt = nil
        }
        var incoming = np
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

        let artChanged = incoming.artwork != nowPlaying.artwork
        nowPlaying = incoming
        if trackChanged { trackChangeToken &+= 1 }
        if incoming.elapsedTimestamp == nil {
            elapsedAt = Date()
        }
        if artChanged {
            let data = np.artwork
            Task.detached(priority: .utility) {
                let c = await AlbumColor.accent(from: data)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
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
        guard v != isExpanded else { return }
        withAnimation(v ? Self.notchExpandSpring : Self.notchCollapseSpring) {
            isExpanded = v
        }
    }

    func showHUD(_ kind: HUDKind, lvl: Float, muted: Bool = false) {
        hudHideTask?.cancel()

        withAnimation(Self.hudSpring) {
            hud = kind
            hudDisplay = kind
            hudLevel = max(0, min(1, lvl))
            hudMuted = muted
        }

        let duration = AppSettings.shared.hudDuration
        hudHideTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(Self.hudSpring) {
                hud = nil
            }
            try? await Task.sleep(for: .seconds(0.42))
            guard !Task.isCancelled else { return }
            hudDisplay = nil
        }
    }

    func playPause() { media.command(.togglePlayPause) }
    func next() { media.command(.next) }
    func prev() { media.command(.prev) }

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
    @Namespace private var ns
    @State private var trackPulse: CGFloat = 0

    private var hasTrack: Bool {
        vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty
    }
    private var hudVisible: Bool { vm.hudDisplay != nil }
    private var hudIntegrated: Bool { hudVisible && !vm.isExpanded }
    private var hudBelowExpanded: Bool { hudVisible && vm.isExpanded }
    private var m: NotchMetrics {
        NotchMetrics(
            notchW: vm.notch.notchRect.width > 0
                ? vm.notch.notchRect.width : 200,
            notchH: vm.notch.notchRect.height > 0
                ? vm.notch.notchRect.height + 0.25 : 32,
            expanded: vm.isExpanded,
            extended: settings.extendNotch && hasTrack && !hudVisible,
            hudActive: hudIntegrated
        )
    }
    private var hudTailMetrics: NotchMetrics {
        NotchMetrics(
            notchW: vm.notch.notchRect.width > 0
                ? vm.notch.notchRect.width : 200,
            notchH: vm.notch.notchRect.height > 0
                ? vm.notch.notchRect.height + 0.25 : 32,
            expanded: false,
            extended: false,
            hudActive: true
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
                        NotchShape(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .stroke(
                            vm.accentColor.opacity(0.55 * trackPulse),
                            lineWidth: 1.5
                        )
                        .blur(radius: trackPulse * 1.5)
                        .scaleEffect(1 + trackPulse * 0.018)
                    }
                    .background {
                        NotchShape(
                            topRadius: m.topRadius,
                            bottomRadius: m.bottomRadius
                        )
                        .fill(vm.accentColor.opacity(0.22 * trackPulse))
                        .blur(radius: 28)
                        .scaleEffect(x: 1.12, y: 1.18)
                        .opacity(
                            (vm.isExpanded || hudVisible ? 0.55 : 0)
                                + trackPulse * 0.35
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
                        .opacity(vm.isExpanded || hudVisible ? 0.55 : 0)
                        .frame(width: m.width, height: m.height)
                    }

                    if vm.isExpanded {
                        ExpandedContent(ns: ns)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    } else {
                        ZStack(alignment: .top) {
                            CollapsedContent(ns: ns, m: m)
                                .opacity(vm.hudDisplay == nil ? 1 : 0)

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
            }  //.shadow(color: (!vm.isExpanded && NSScreen.screens.contains { $0.visibleFrame.equalTo($0.frame) }) ? vm.accentColor : .clear, radius: 1, y: 0)
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
        .animation(NotchViewModel.hudSpring, value: vm.hud)
        .onChange(of: vm.trackChangeToken) { _, token in
            guard token > 0 else { return }
            withAnimation(.easeOut(duration: 0.16)) { trackPulse = 1 }
            withAnimation(
                .spring(response: 0.55, dampingFraction: 0.78).delay(0.06)
            ) {
                trackPulse = 0
            }
        }
    }
}
