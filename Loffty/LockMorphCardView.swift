//
//  LockMorphCardView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 09/08/2026.
//

import Combine
import SwiftUI

@MainActor
final class LockCardPlacement: ObservableObject {
    @Published var compactRect: CGRect
    @Published var isFlying: Bool

    init(compactRect: CGRect = .zero, isFlying: Bool = false) {
        self.compactRect = compactRect
        self.isFlying = isFlying
    }
}

struct LockMorphCardView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var placement: LockCardPlacement
    @ObservedObject private var settings = AppSettings.shared

    var onHitRegionChange: (CGRect, Bool) -> Void

    @State private var expanded = false
    @State private var canCollapse = false

    private let flightAnimation = Animation.smooth(
        duration: 0.46,
        extraBounce: 0.04
    )

    private let compactCornerRadius: CGFloat = 38
    private let expandedCornerRadius: CGFloat = 34
    private let compactArtSize: CGFloat = 58
    private let compactArtCornerRadius: CGFloat = 14
    private let expandedArtCornerRadius: CGFloat = 26
    private let expandedArtSide: CGFloat = 300
    private let expandedHorizontalPad: CGFloat = 32
    private let expandedVerticalPad: CGFloat = 32
    private let expandedArtGap: CGFloat = 34
    private let expandedSideColumnWidth: CGFloat = 250
    private let textControlsGap: CGFloat = 16
    private let controlsBlockHeight: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rect = cardRect(in: size)
            ZStack {
                if expanded {
                    Color.black.opacity(0.001)
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { collapse() }
                }

                cardChrome(rect: rect)
                bottomControls(rect: rect)
                textBlock(rect: rect)
                if settings.lockScreenWaveforms {
                    waveform(rect: rect)
                }
                artwork(rect: rect)
            }
            .environmentObject(vm)
            .onAppear {
                onHitRegionChange(rect, expanded)
                DispatchQueue.main.async { expand() }
            }
            .onChange(of: placement.compactRect) { _, _ in
                onHitRegionChange(cardRect(in: size), expanded)
            }
            .onChange(of: expanded) { _, _ in
                onHitRegionChange(cardRect(in: size), expanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func expandedCardSize(in size: CGSize) -> CGSize {
        let contentWidth =
            expandedHorizontalPad * 2 + expandedArtSide + expandedArtGap
            + expandedSideColumnWidth
        let contentHeight = expandedVerticalPad * 2 + expandedArtSide
        return CGSize(
            width: min(contentWidth, size.width * 0.55),
            height: min(contentHeight, size.height * 0.62)
        )
    }

    private func cardRect(in size: CGSize) -> CGRect {
        guard expanded else { return placement.compactRect }
        let s = expandedCardSize(in: size)
        return CGRect(
            x: (size.width - s.width) / 2,
            y: (size.height - s.height) / 2,
            width: s.width,
            height: s.height
        )
    }

    private var cornerRadius: CGFloat {
        expanded ? expandedCornerRadius : compactCornerRadius
    }

    private func cardChrome(rect: CGRect) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        return Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .lockWidgetChrome(shape)
                }
            } else {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .lockWidgetChrome(shape)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func artSide(in rect: CGRect) -> CGFloat {
        guard expanded else { return compactArtSize }
        return min(
            expandedArtSide,
            rect.height - expandedVerticalPad * 2,
            rect.width - expandedHorizontalPad * 2
        )
    }

    private func artRect(in rect: CGRect) -> CGRect {
        let side = artSide(in: rect)
        if expanded {
            return CGRect(
                x: rect.minX + expandedHorizontalPad,
                y: rect.minY + (rect.height - side) / 2,
                width: side,
                height: side
            )
        }
        return CGRect(
            x: rect.minX + 18,
            y: rect.minY + 16,
            width: side,
            height: side
        )
    }

    private func artwork(rect: CGRect) -> some View {
        let r = artRect(in: rect)
        let data =
            expanded
            ? (vm.nowPlaying.fullArtwork ?? vm.nowPlaying.artwork)
            : vm.nowPlaying.artwork
        return ArtworkThumbnail(
            artwork: data,
            unavailable: vm.nowPlaying.artworkUnavailable,
            size: r.width,
            cornerRadius: expanded
                ? expandedArtCornerRadius : compactArtCornerRadius,
            trackKey: vm.nowPlaying.trackKey,
            bundleIdentifier: vm.nowPlaying.bundleIdentifier,
            showPlayerBadge: settings.playerBadgeLockScreen
        )
        .frame(width: r.width, height: r.height)
        .shadow(
            color: .black.opacity(expanded ? 0.4 : 0.28),
            radius: expanded ? 26 : 10,
            y: expanded ? 14 : 4
        )
        .contentShape(Rectangle())
        .onTapGesture { collapse() }
        .position(x: r.midX, y: r.midY)
    }

    private func sideColumnRect(in rect: CGRect) -> CGRect {
        let art = artRect(in: rect)
        let x = art.maxX + expandedArtGap
        return CGRect(
            x: x,
            y: art.minY,
            width: max(0, rect.maxX - expandedHorizontalPad - x),
            height: art.height
        )
    }

    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Not playing" : vm.nowPlaying.title
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

    private func waveformReserve() -> CGFloat {
        guard !expanded, settings.lockScreenWaveforms else { return 0 }
        return 36
    }

    private var expandedGroupHeight: CGFloat {
        textBlockHeight + textControlsGap + controlsBlockHeight
    }

    private func expandedGroupTop(in rect: CGRect) -> CGFloat {
        let col = sideColumnRect(in: rect)
        return col.minY + (col.height - expandedGroupHeight) / 2
    }

    private func textWidth(in rect: CGRect) -> CGFloat {
        if expanded { return sideColumnRect(in: rect).width }
        let art = artRect(in: rect)
        return max(
            0,
            rect.maxX - 18 - (art.maxX + 14) - waveformReserve()
        )
    }

    private func textCenter(in rect: CGRect) -> CGPoint {
        let width = textWidth(in: rect)
        if expanded {
            let col = sideColumnRect(in: rect)
            return CGPoint(
                x: col.minX + width / 2,
                y: expandedGroupTop(in: rect) + textBlockHeight / 2
            )
        }
        let art = artRect(in: rect)
        return CGPoint(x: art.maxX + 14 + width / 2, y: art.midY)
    }

    private func textBlock(rect: CGRect) -> some View {
        let width = textWidth(in: rect)
        let center = textCenter(in: rect)
        return VStack(alignment: .leading, spacing: 3) {
            MarqueeText(
                text: title,
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
        .frame(width: width, alignment: .leading)
        .position(x: center.x, y: center.y)
        .allowsHitTesting(false)
    }

    private func waveform(rect: CGRect) -> some View {
        let art = artRect(in: rect)
        let width: CGFloat = 22
        let x = rect.maxX - 18 - 14 - width / 2
        return WaveBars(
            isPlaying: vm.nowPlaying.isPlaying,
            barCount: 5,
            maxHeight: 16,
            tint: settings.lockScreenWaveformsAccent
                ? vm.accentColor
                : .white.opacity(0.72)
        )
        .frame(width: width)
        .position(x: x, y: art.midY)
        .opacity(expanded ? 0 : 1)
        .allowsHitTesting(false)
    }

    private func controlsRegion(in rect: CGRect) -> CGRect {
        if expanded {
            let col = sideColumnRect(in: rect)
            let y =
                expandedGroupTop(in: rect) + textBlockHeight + textControlsGap
            return CGRect(
                x: col.minX,
                y: y,
                width: col.width,
                height: controlsBlockHeight
            )
        }
        return CGRect(
            x: rect.minX + 18,
            y: rect.minY,
            width: rect.width - 36,
            height: rect.height
        )
    }

    private func bottomControls(rect: CGRect) -> some View {
        let region = controlsRegion(in: rect)
        return VStack(spacing: 14) {
            MediaProgressRow(accent: vm.accentColor)
                .frame(maxWidth: expanded ? .infinity : 310)
                .padding(.bottom, expanded ? 0 : -5)
            MediaTransportControls()
        }
        .frame(
            width: region.width,
            height: region.height,
            alignment: expanded ? .top : .bottom
        )
        .padding(.bottom, expanded ? 0 : 14)
        .position(x: region.midX, y: region.midY)
    }

    private func expand() {
        canCollapse = false
        withAnimation(flightAnimation) { expanded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            canCollapse = true
        }
    }

    private func collapse() {
        guard canCollapse, expanded else { return }
        canCollapse = false
        withAnimation(flightAnimation) {
            expanded = false
        } completion: {
            vm.setLockScreenArtExpanded(false)
        }
    }
}
