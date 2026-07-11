//
//  ViewModels.swift
//  Alcoved
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
    var bundleIdentifier: String = ""
    var isPlaying: Bool = false
    var elapsed: Double = 0
    var duration: Double = 0
    var artwork: Data? = nil
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
              let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: img.extent)]),
              let out = f.outputImage else { return Color.white.opacity(0.5) }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var color = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        if let c = color.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            color = NSColor(hue: h, saturation: min(1, s * 1.7), brightness: max(b, 0.55), alpha: 1)
        }
        return Color(nsColor: color)
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var notch = NotchInfo(screen: NSScreen.main!, notchRect: .zero, hasNotch: false)
    @Published var isExpanded = false
    @Published var nowPlaying = NowPlaying()
    @Published var accentColor: Color = .white.opacity(0.5)
    @Published var waveLevels: [CGFloat] = Array(repeating: 0, count: AudioTapAnalyzer.barCount)
    private var elapsedAt = Date()
    private let media = MediaController()
    private let volume = SystemVolumeWatcher()
    private let audioAnalyzer = AudioTapAnalyzer()

    func start() {
        media.onUpdate = { [weak self] np in
            Task { @MainActor in self?.apply(np) }
        }
        audioAnalyzer.onLevels = { [weak self] levels in
            Task { @MainActor in
                self?.waveLevels = levels.map(CGFloat.init)
            }
        }
        media.start()
        volume.onChange = { _ in
            // TODO: HUD
        }
        volume.start()
    }

    private func apply(_ np: NowPlaying) {
        let artChanged = np.artwork != nowPlaying.artwork
        let bundleChanged = np.bundleIdentifier != nowPlaying.bundleIdentifier
        let playingChanged = np.isPlaying != nowPlaying.isPlaying
        nowPlaying = np
        elapsedAt = Date()
        if playingChanged || bundleChanged {
            audioAnalyzer.update(bundleID: np.bundleIdentifier, isPlaying: np.isPlaying)
        }
        if artChanged {
            let data = np.artwork
            Task.detached(priority: .utility) {
                let c = await AlbumColor.accent(from: data)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) { self.accentColor = c }
                }
            }
        }
    }

    func currentTime(at date: Date) -> Double {
        let extra = nowPlaying.isPlaying ? max(0, date.timeIntervalSince(elapsedAt)) : 0
        let t = nowPlaying.elapsed + extra
        return nowPlaying.duration > 0 ? min(t, nowPlaying.duration) : t
    }

    func setExpanded(_ v: Bool) {
        guard v != isExpanded else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            isExpanded = v
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
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tr = topRadius, br = bottomRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY)) // top left
        p.addQuadCurve(to: CGPoint(x: r.minX + tr, y: r.minY + tr), control: CGPoint(x: r.minX + tr, y: r.minY))

        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br)) // left side down

        p.addQuadCurve(to: CGPoint(x: r.minX + tr + br, y: r.maxY), control: CGPoint(x: r.minX + tr, y: r.maxY)) // bottom left

        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY)) // bottom edge

        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - br), control: CGPoint(x: r.maxX - tr, y: r.maxY)) // bottom right

        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr)) // right side up

        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - tr, y: r.minY)) // top right
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .top) {
                if vm.isExpanded {
                    ExpandedContent(ns: ns)
                        .frame(width: 380, height: 182)
                        .background(NotchShape().fill(.black))
                        .background {
                            NotchShape()
                                .fill(Color.black.opacity(0.95))
                                .blur(radius: 28)
                                .scaleEffect(x: 1.12, y: 1.18)
                                .opacity(0.55)
                        }
                        .transition(.scale(scale: 0.32, anchor: .top).combined(with: .opacity))
                } else {
                    CollapsedContent(ns: ns)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: vm.isExpanded)
    }
}

struct WaveBars: View {
    var isPlaying: Bool
    var levels: [CGFloat]
    var barCount: Int = 4
    var maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0 ..< barCount, id: \.self) { i in
                Capsule()
                    .fill(.primary)
                    .frame(width: 2.5, height: height(at: i))
                    .animation(.easeOut(duration: 0.08), value: levels)
            }
        }
        .frame(height: maxHeight)
    }

    private func height(at i: Int) -> CGFloat {
        guard isPlaying else { return minHeight }
        let level = i < levels.count ? levels[i] : 0
        return minHeight + (maxHeight - minHeight) * min(1, max(0, level))
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID
    private let side: CGFloat = 44
    private var notchW: CGFloat { vm.notch.notchRect.width > 0 ? vm.notch.notchRect.width : 200 }
    private var notchH: CGFloat { vm.notch.notchRect.height > 0 ? vm.notch.notchRect.height : 32 }
    private var hasTrack: Bool { vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            artwork(size: notchH - 8)
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(width: side, alignment: .trailing)
                .padding(.trailing, 6)
            Color.clear.frame(width: notchW, height: notchH)
            Group {
                if hasTrack {
                    WaveBars(isPlaying: vm.nowPlaying.isPlaying, levels: vm.waveLevels, barCount: 4)
                }
            }
            .frame(width: side, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: notchH)
    }

    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if hasTrack {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.4)).frame(width: size, height: size)
        }
    }
}

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID

    private var title: String { vm.nowPlaying.title.isEmpty ? "Nothing playing" : vm.nowPlaying.title }

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

                WaveBars(isPlaying: vm.nowPlaying.isPlaying, levels: vm.waveLevels, barCount: 5, maxHeight: 16)
                    .foregroundStyle(.white.opacity(0.7))
            }

            progressBar
            controls
        }
        .padding(.horizontal, 42)
        .padding(.top, 30)
        .padding(.bottom, 16)
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
                        Capsule().fill(vm.accentColor.opacity(0.9)).frame(width: max(0, geo.size.width * p))
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
        HStack(spacing: 0) {
            Spacer()
            sym("gobackward.10", 18, .white.opacity(0.8)) { vm.seek(by: -10) }.padding(.trailing, 12)
            sym("backward.fill", 20, .white) { vm.prev() }.padding(.trailing, 12)
            sym(vm.nowPlaying.isPlaying ? "pause.fill" : "play.fill", 24, .white) { vm.playPause() }.padding(.trailing, 12)
            sym("forward.fill", 20, .white) { vm.next() }.padding(.trailing, 12)
            sym("goforward.10", 18, .white.opacity(0.8)) { vm.seek(by: 10) }
            Spacer()
        }
        .padding(.horizontal, -4)
    }

    private func sym(_ name: String, _ size: CGFloat, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
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
