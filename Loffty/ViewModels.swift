//
//  ViewModels.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import Combine
import CoreImage
import SwiftUI

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var elapsed: Double = 0
    var duration: Double = 0
    var artwork: Data? = nil
}

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

enum HUDKind: Equatable {
    case volume, brightness
}

func fmtTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

enum AlbumColor {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    static func accent(from data: Data?) -> Color {
        guard let data, let img = CIImage(data: data), img.extent.width > 0,
            let f = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: img,
                    kCIInputExtentKey: CIVector(cgRect: img.extent),
                ]
            ),
            let out = f.outputImage
        else { return Color.white.opacity(0.5) }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(
            out,
            toBitmap: &px,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var color = NSColor(
            red: CGFloat(px[0]) / 255,
            green: CGFloat(px[1]) / 255,
            blue: CGFloat(px[2]) / 255,
            alpha: 1
        )
        if let c = color.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0
            var s: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            color = NSColor(
                hue: h,
                saturation: min(1, s * 1.7),
                brightness: max(b, 0.55),
                alpha: 1
            )
        }
        return Color(nsColor: color)
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
        let artChanged = np.artwork != nowPlaying.artwork
        nowPlaying = np
        elapsedAt = Date()
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

    func currentTime(at date: Date) -> Double {
        let extra =
            nowPlaying.isPlaying ? max(0, date.timeIntervalSince(elapsedAt)) : 0
        let t = nowPlaying.elapsed + extra
        return nowPlaying.duration > 0 ? min(t, nowPlaying.duration) : t
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
        var t = max(0, currentTime(at: Date()) + delta)
        if nowPlaying.duration > 0 { t = min(t, nowPlaying.duration) }
        media.setElapsed(t)
        nowPlaying.elapsed = t
        elapsedAt = Date()
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
        .animation(NotchViewModel.hudSpring, value: vm.hud)
    }
}

struct WaveBars: View {  // TODO: actual soundwaves
    @EnvironmentObject var vm: NotchViewModel
    var isPlaying: Bool
    var barCount: Int = 4
    var maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3
    private let phases: [Double] = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5]

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)
        ) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(vm.isExpanded ? vm.accentColor : .primary)
                        .blendMode(vm.isExpanded ? .normal : .difference)
                        .frame(width: 2.5, height: height(i, t))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        guard isPlaying else { return minHeight }
        let phase = phases[i % phases.count]
        let s = (sin(t * 6.0 + phase) + sin(t * 9.7 + phase * 1.7)) / 2
        let norm = (s + 1) / 2  // 0...1
        return minHeight + (maxHeight - minHeight) * CGFloat(norm)
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID
    let m: NotchMetrics
    private var hasTrack: Bool {
        vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            artwork(size: m.artSize)
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(width: m.side - m.gap, alignment: .trailing)
                .padding(.trailing, m.gap)
            Color.clear.frame(width: m.notchW, height: m.height)
            Group {
                if hasTrack {
                    WaveBars(isPlaying: vm.nowPlaying.isPlaying)
                }
            }
            .frame(width: m.side - m.gap, alignment: .leading)
            .padding(.leading, m.gap)
        }
        .frame(height: m.height)
    }

    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if hasTrack {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.4)).frame(
                width: size,
                height: size
            )
        }
    }
}

struct NotchControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 1.0),
                value: configuration.isPressed
            )
    }
}

struct ControlButton: View {
    let systemName: String
    let size: CGFloat
    let tint: Color
    var hitSize: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace.offUp))
        }
        .buttonStyle(NotchControlButtonStyle())
    }
}

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID

    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Nothing playing" : vm.nowPlaying.title
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                artwork(size: 52)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(.white).lineLimit(1)
                        .id(title).transition(.blurReplace)
                    Text(vm.nowPlaying.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        .id(vm.nowPlaying.artist).transition(.blurReplace)
                }
                .animation(.smooth(duration: 0.4), value: title)
                .frame(maxWidth: .infinity, alignment: .leading)

                WaveBars(
                    isPlaying: vm.nowPlaying.isPlaying,
                    barCount: 5,
                    maxHeight: 16
                )
                .foregroundStyle(.white.opacity(0.7))
            }
            progressBar
            controls
        }
        .padding(.horizontal, 42)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .overlay(alignment: .topTrailing) {
            ControlButton(
                systemName: "gearshape.fill",
                size: 13,
                tint: .white.opacity(0.45),
                hitSize: 40
            ) {
                Task { @MainActor in SettingsOpener.shared.open() }
            }
            .padding(.trailing, 24)
            .padding(.top, 0)
        }
    }

    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let cur = vm.currentTime(at: ctx.date)
            let dur = vm.nowPlaying.duration
            let p = dur > 0 ? min(1, max(0, cur / dur)) : 0
            let remaining = max(0, dur - cur)
            HStack(spacing: 10) {
                Text(fmtTime(cur))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(vm.accentColor.opacity(0.9)).frame(
                            width: max(0, geo.size.width * p)
                        )
                    }
                }
                .frame(height: 6)
                Text(dur > 0 ? "-\(fmtTime(remaining))" : fmtTime(cur))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            ControlButton(
                systemName: "gobackward.10",
                size: 18,
                tint: .white.opacity(0.8)
            ) { vm.seek(by: -10) }
            ControlButton(
                systemName: "backward.fill",
                size: 20,
                tint: .white
            ) { vm.prev() }
            ControlButton(
                systemName: vm.nowPlaying.isPlaying
                    ? "pause.fill" : "play.fill",
                size: 24,
                tint: .white
            ) { vm.playPause() }
            ControlButton(
                systemName: "forward.fill",
                size: 20,
                tint: .white
            ) { vm.next() }
            ControlButton(
                systemName: "goforward.10",
                size: 18,
                tint: .white.opacity(0.8)
            ) { vm.seek(by: 10) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.35))
                .frame(width: size, height: size)
        }
    }
}

struct HUDChip: View {
    @EnvironmentObject var vm: NotchViewModel
    let kind: HUDKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 14)
                .contentTransition(.symbolEffect(.replace))

            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .scaleEffect(
                            x: max(CGFloat(vm.hudLevel), 0.001),
                            y: 1,
                            anchor: .leading
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 5)
                .clipShape(Capsule())
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.78),
            value: vm.hudLevel
        )
    }

    private var icon: String {
        switch kind {
        case .volume:
            vm.hudMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:
            vm.hudLevel < 0.01 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
