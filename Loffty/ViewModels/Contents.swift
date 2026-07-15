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

    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Nothing playing" : vm.nowPlaying.title
    }

    var body: some View {
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
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(.white).lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.18), value: title)
                    if !vm.nowPlaying.artist.isEmpty {
                        Text(vm.nowPlaying.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(
                                .smooth(duration: 0.18),
                                value: vm.nowPlaying.artist
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
            if vm.nowPlaying.artwork != nil || !vm.nowPlaying.artworkUnavailable
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
                if hasTrack {
                    WaveBars(isPlaying: vm.nowPlaying.isPlaying)
                }
            }
            .frame(width: m.side - m.gap, alignment: .leading)
            .padding(.leading, m.gap)
        }
        .frame(height: m.height)
    }
}
