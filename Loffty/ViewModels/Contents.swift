//
//  Contents.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID
    let m: NotchMetrics

    var body: some View {
        Group {
            if vm.isIdle {
                idleContent
            } else {
                activeContent
            }
        }
        .overlay(alignment: .topTrailing) {
            if !vm.isIdle {
                ControlButton(
                    systemName: "gearshape.fill",
                    size: 13,
                    tint: .white.opacity(0.45),
                    hitSize: 40
                ) {
                    Task { @MainActor in SettingsOpener.shared.open() }
                }
                .padding(.trailing, 26)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: vm.isIdle)
    }

    private var idleContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: m.notchH)
            Label("Nothing playing", systemImage: "play.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity)
                .frame(height: m.idleLipHeight)
        }
    }

    private var activeContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                if vm.nowPlaying.artwork != nil
                    || !vm.nowPlaying.artworkUnavailable
                {
                    ArtworkThumbnail(
                        artwork: vm.nowPlaying.artwork,
                        unavailable: vm.nowPlaying.artworkUnavailable,
                        size: 52,
                        cornerRadius: 12,
                        trackKey: vm.nowPlaying.trackKey,
                        namespace: ns
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: vm.nowPlaying.title,
                        font: .system(size: 15),
                        color: .white,
                        height: 18
                    )
                    if !vm.nowPlaying.artist.isEmpty {
                        MarqueeText(
                            text: vm.nowPlaying.artist,
                            font: .system(size: 13),
                            color: .white.opacity(0.45),
                            height: 16
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WaveBars(
                    isPlaying: vm.nowPlaying.isPlaying,
                    barCount: 5,
                    maxHeight: 16
                )
                .foregroundStyle(.white.opacity(0.7))
            }
            MediaProgressRow(accent: vm.accentColor)
            MediaTransportControls()
        }
        .padding(.horizontal, 42)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    let ns: Namespace.ID
    let m: NotchMetrics

    var body: some View {
        HStack(spacing: 0) {
            if !vm.isIdle,
                vm.nowPlaying.artwork != nil
                    || !vm.nowPlaying.artworkUnavailable
            {
                ArtworkThumbnail(
                    artwork: vm.nowPlaying.artwork,
                    unavailable: vm.nowPlaying.artworkUnavailable,
                    size: m.artSize,
                    cornerRadius: 4,
                    trackKey: vm.nowPlaying.trackKey,
                    namespace: ns
                )
                .frame(width: m.side - m.gap, alignment: .trailing)
                .padding(.trailing, m.gap)
            }
            Color.clear.frame(width: m.notchW, height: m.height)
            Group {
                if !vm.isIdle {
                    WaveBars(isPlaying: vm.nowPlaying.isPlaying)
                }
            }
            .frame(width: m.side - m.gap, alignment: .leading)
            .padding(.leading, m.gap)
        }
        .frame(height: m.height)
    }
}
