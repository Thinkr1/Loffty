//
//  LockMorphCardView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 09/08/2026.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class LockCardPlacement: ObservableObject {
    @Published var compactRect: CGRect
    @Published var isFlying: Bool
    @Published var expandNonce: UInt = 0
    @Published var wallpaper: NSImage?
    @Published var wallpaperScreenFrame: CGRect = .zero
    @Published var cardScreenFrame: CGRect = .zero

    init(compactRect: CGRect = .zero, isFlying: Bool = false) {
        self.compactRect = compactRect
        self.isFlying = isFlying
    }

    func requestExpand() {
        expandNonce &+= 1
    }
}

struct LockMorphCardView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var placement: LockCardPlacement
    @ObservedObject private var settings = AppSettings.shared

    var onHitRegionChange: (CGRect, Bool) -> Void

    @State private var progress: CGFloat = 0
    @State private var canCollapse = false
    @State private var compactChromeVisible = true

    private let expandAnimation = Animation.smooth(duration: 0.62)
    private let collapseAnimation = Animation.smooth(duration: 0.52)
    private let chromeRevealAnimation = Animation.easeOut(duration: 0.14)

    private let compactArtSize: CGFloat = 58
    private let compactArtCorner: CGFloat = 14
    private let compactPadX: CGFloat = 18
    private let compactPadTop: CGFloat = 16
    private let compactRowGap: CGFloat = 14
    private let compactStackGap: CGFloat = 14

    private let expandedCornerRadius: CGFloat = 0
    private let expandedArtMaxSide: CGFloat = 460
    private let expandedArtCorner: CGFloat = 12
    private let expandedVerticalPad: CGFloat = 72
    private let artTextGap: CGFloat = 22
    private let textControlsGap: CGFloat = 16
    private let controlsBlockHeight: CGFloat = 70

    private var showsLyrics: Bool { settings.lockScreenLyrics }
    private var playerChromeOpacity: Double {
        let x = Double(min(max((t - 0.4) / 0.6, 0), 1))
        return x * x * (3 - 2 * x)
    }

    private var t: CGFloat { min(max(progress, 0), 1) }
    private var isExpanded: Bool { t > 0.5 }
    private var isCompactRest: Bool { t < 0.05 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let card = cardRect(in: size)
            let art = artRect(in: size)
            let text = textRect(in: size)
            let controls = controlsRect(in: size)
            let artCorner =
                compactArtCorner
                + (expandedArtCorner - compactArtCorner) * t

            ZStack {
                if t > 0.02 {
                    Color.black.opacity(0.001)
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .allowsHitTesting(canCollapse)
                }

                cardChrome(rect: card)

                if t > 0.01 {
                    LockPlayerBackdrop(
                        artwork: vm.nowPlaying.fullArtwork
                            ?? vm.nowPlaying.artwork,
                        accent: vm.accentColor
                    )
                    .frame(width: card.width, height: card.height)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cardCornerRadius,
                            style: .continuous
                        )
                    )
                    .position(x: card.midX, y: card.midY)
                    .opacity(Double(t))
                    .allowsHitTesting(false)
                }

                if showsLyrics, t > 0.01 {
                    let lyrics = lyricsRect(in: size)
                    LockLyricsView(vm: vm, isActive: isExpanded)
                        .frame(width: lyrics.width, height: lyrics.height)
                        .position(x: lyrics.midX, y: lyrics.midY)
                        .offset(x: (1 - t) * 40)
                        .opacity(playerChromeOpacity)
                        .allowsHitTesting(canCollapse && isExpanded)
                }

                if t > 0.01 {
                    closeButton
                        .position(x: 56, y: 56)
                        .offset(y: (1 - t) * -12)
                        .opacity(playerChromeOpacity)
                        .allowsHitTesting(canCollapse && isExpanded)
                }

                flyingText(rect: text)
                flyingControls(rect: controls)

                if settings.lockScreenWaveforms {
                    flyingWaveform(in: size)
                }

                ArtworkThumbnail(
                    artwork: vm.nowPlaying.fullArtwork ?? vm.nowPlaying.artwork,
                    unavailable: vm.nowPlaying.artworkUnavailable,
                    size: art.height,
                    cornerRadius: artCorner,
                    trackKey: vm.nowPlaying.trackKey,
                    bundleIdentifier: vm.nowPlaying.resolvedBundleIdentifier,
                    showPlayerBadge: settings.playerBadgeLockScreen,
                    aspectRatio: art.height > 0 ? art.width / art.height : 1,
                    websiteHost: vm.nowPlaying.websiteHost
                )
                .environmentObject(vm)
                .frame(width: art.width, height: art.height)
                .shadow(
                    color: .black.opacity(0.28 + 0.12 * t),
                    radius: 10 + 16 * t,
                    y: 4 + 10 * t
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: handleArtworkTap)
                .position(x: art.midX, y: art.midY)
                .allowsHitTesting(isCompactRest || canCollapse)
            }
            .environmentObject(vm)
            .environment(
                \.suppressMediaTickAnimations,
                t > 0.02 && t < 0.98
            )
            .onAppear {
                onHitRegionChange(card, isExpanded)
            }
            .onChange(of: placement.compactRect) { _, _ in
                onHitRegionChange(cardRect(in: size), isExpanded)
            }
            .onChange(of: progress) { _, _ in
                onHitRegionChange(cardRect(in: size), isExpanded)
            }
            .onChange(of: placement.expandNonce) { _, _ in
                expand()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasAlbumLine: Bool {
        settings.showAlbum && !vm.nowPlaying.album.isEmpty
    }

    private var hasArtistLine: Bool { !vm.nowPlaying.artist.isEmpty }

    private var textBlockHeight: CGFloat {
        var h: CGFloat = 18
        if hasAlbumLine { h += 3 + 14 }
        if hasArtistLine { h += 3 + 16 }
        return h
    }

    private var waveformReserve: CGFloat {
        settings.lockScreenWaveforms ? 36 : 0
    }

    private func resolvedCompactRect(in size: CGSize) -> CGRect {
        LockScreenPolicy.resolvedCompactRect(
            windowSize: size,
            placed: placement.compactRect
        )
    }

    private func expandedCardRect(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size)
    }

    private var cardCornerRadius: CGFloat {
        LockCardMetrics.cornerRadius
            + (expandedCornerRadius - LockCardMetrics.cornerRadius) * t
    }

    private var columnStackHeight: CGFloat {
        artTextGap + textBlockHeight + textControlsGap + controlsBlockHeight
    }

    private func expandedArtSide(in size: CGSize) -> CGFloat {
        let widthLimit = size.width * (showsLyrics ? 0.3 : 0.4)
        let heightLimit =
            size.height - expandedVerticalPad * 2 - columnStackHeight
        return max(160, min(expandedArtMaxSide, widthLimit, heightLimit))
    }

    private func expandedColumnCenterX(in size: CGSize) -> CGFloat {
        showsLyrics ? size.width * 0.28 : size.width / 2
    }

    private func lyricsRect(in size: CGSize) -> CGRect {
        let x = size.width * 0.5
        let width = min(size.width * 0.42, 680)
        return CGRect(
            x: x,
            y: expandedVerticalPad * 0.5,
            width: width,
            height: size.height - expandedVerticalPad
        )
    }

    private var closeButton: some View {
        Button(action: collapse) {
            Image(systemName: "multiply")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .lockPlayerButtonGlass()
        }
        .buttonStyle(NotchControlButtonStyle())
        .help("Close player")
        .accessibilityLabel("Close player")
    }

    private func cardRect(in size: CGSize) -> CGRect {
        lerp(resolvedCompactRect(in: size), expandedCardRect(in: size), t)
    }

    private var artworkAspect: CGFloat {
        vm.nowPlaying.displayArtworkAspect
    }

    private func compactArtRect(in size: CGSize) -> CGRect {
        let c = resolvedCompactRect(in: size)
        return CGRect(
            x: c.minX + compactPadX,
            y: c.minY + compactPadTop,
            width: compactArtSize * artworkAspect,
            height: compactArtSize
        )
    }

    private func expandedArtRect(in size: CGSize) -> CGRect {
        let side = expandedArtSide(in: size)
        let height = side / max(artworkAspect, 1)
        let groupHeight = height + columnStackHeight
        return CGRect(
            x: expandedColumnCenterX(in: size) - side / 2,
            y: (size.height - groupHeight) / 2,
            width: side,
            height: height
        )
    }

    private func artRect(in size: CGSize) -> CGRect {
        lerp(compactArtRect(in: size), expandedArtRect(in: size), t)
    }

    private func compactTextRect(in size: CGSize) -> CGRect {
        let c = resolvedCompactRect(in: size)
        let art = compactArtRect(in: size)
        let x = art.maxX + compactRowGap
        let width = max(
            0,
            c.maxX - compactPadX - x - waveformReserve
        )
        let height = textBlockHeight
        let y = art.minY + (art.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func expandedTextRect(in size: CGSize) -> CGRect {
        let art = expandedArtRect(in: size)
        return CGRect(
            x: art.minX,
            y: art.maxY + artTextGap,
            width: art.width,
            height: textBlockHeight
        )
    }

    private func textRect(in size: CGSize) -> CGRect {
        lerp(compactTextRect(in: size), expandedTextRect(in: size), t)
    }

    private func compactControlsRect(in size: CGSize) -> CGRect {
        let c = resolvedCompactRect(in: size)
        let art = compactArtRect(in: size)
        let y = art.maxY + compactStackGap
        return CGRect(
            x: c.minX + compactPadX,
            y: y,
            width: c.width - compactPadX * 2,
            height: controlsBlockHeight
        )
    }

    private func expandedControlsRect(in size: CGSize) -> CGRect {
        let text = expandedTextRect(in: size)
        return CGRect(
            x: text.minX,
            y: text.maxY + textControlsGap,
            width: text.width,
            height: controlsBlockHeight
        )
    }

    private func controlsRect(in size: CGSize) -> CGRect {
        lerp(compactControlsRect(in: size), expandedControlsRect(in: size), t)
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    private func cardChrome(rect: CGRect) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cardCornerRadius,
            style: .continuous
        )
        let tint = settings.lockScreenLiquidGlassTint
        let color = settings.lockScreenResolvedGlassColor
        let plate = LockGlassPlacement.screenPlate(
            fromLocalTopLeft: rect,
            windowFrame: placement.cardScreenFrame
        )
        return lockFlyingPlate(
            shape: shape,
            tint: tint,
            color: color,
            plate: plate
        )
        .frame(width: rect.width, height: rect.height)
        .clipShape(shape)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func lockFlyingPlate(
        shape: RoundedRectangle,
        tint: LiquidGlassTint,
        color: Color?,
        plate: CGRect
    ) -> some View {
        if LockGlassPlacement.showsWallpaper(tint) {
            LockCardWallpaperBackdrop(
                image: placement.wallpaper,
                screenFrame: placement.wallpaperScreenFrame,
                plate: plate
            )
            .lockWidgetChrome(shape, tint: tint, color: color)
        } else if LockGlassPlacement.showsFrostedPlate(tint) {
            Color.clear.lockWidgetChrome(shape, tint: tint, color: color)
        }
    }

    private func flyingText(rect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MarqueeText(
                text: vm.nowPlaying.title.isEmpty
                    ? "Not playing" : vm.nowPlaying.title,
                font: .system(size: 15, weight: .semibold),
                color: .white.opacity(0.96),
                height: 18,
                scrolling: settings.marqueeEnabled
            )
            if hasAlbumLine {
                MarqueeText(
                    text: vm.nowPlaying.album,
                    font: .system(size: 12, weight: .medium),
                    color: .white.opacity(0.38),
                    height: 14,
                    scrolling: settings.marqueeEnabled
                )
            }
            if hasArtistLine {
                MarqueeText(
                    text: vm.nowPlaying.artist,
                    font: .system(size: 13, weight: .medium),
                    color: .white.opacity(0.52),
                    height: 16,
                    scrolling: settings.marqueeEnabled
                )
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }

    private func flyingControls(rect: CGRect) -> some View {
        VStack(spacing: 14) {
            MediaProgressRow(
                accent: vm.accentColor.mix(with: .white, by: Double(t))
            )
            .frame(maxWidth: isExpanded ? rect.width : 310)
            .padding(.bottom, -5)
            MediaTransportControls()
        }
        .frame(width: rect.width, height: rect.height, alignment: .top)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(isCompactRest || (canCollapse && isExpanded))
    }

    private func flyingWaveform(in size: CGSize) -> some View {
        let art = compactArtRect(in: size)
        let c = resolvedCompactRect(in: size)
        let width: CGFloat = 22
        let x = c.maxX - compactPadX - 14 - width / 2
        return WaveBars(
            isPlaying: vm.nowPlaying.isPlaying,
            barCount: 5,
            maxHeight: 16,
            tint: settings.lockScreenWaveformsAccent
                ? vm.accentColor
                : .white
        )
        .frame(width: width)
        .position(x: x, y: art.midY)
        .opacity(compactChromeVisible ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func handleArtworkTap() {
        if isExpanded {
            collapse()
        } else if isCompactRest {
            guard AppSettings.shared.lockScreenFullScreenArt else { return }
            vm.setLockScreenArtExpanded(true)
        }
    }

    private func hideCompactChrome() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { compactChromeVisible = false }
    }

    private func expand() {
        guard progress < 0.5 else { return }
        canCollapse = false
        hideCompactChrome()
        withAnimation(expandAnimation) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            canCollapse = true
        }
    }

    private func collapse() {
        guard canCollapse, isExpanded else { return }
        canCollapse = false
        hideCompactChrome()
        withAnimation(collapseAnimation) {
            progress = 0
        } completion: {
            withAnimation(chromeRevealAnimation) {
                compactChromeVisible = true
            }
            vm.setLockScreenArtExpanded(false)
        }
    }
}
