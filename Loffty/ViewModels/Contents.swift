//
//  Contents.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    let ns: Namespace.ID
    let m: NotchMetrics

    var body: some View {
        Group {
            if vm.isIdle {
                idleContent
            } else {
                activeContent
                    .overlay(alignment: .topTrailing) {
                        if !vm.isLocked {
                            ControlButton(
                                systemName: "gearshape.fill",
                                size: 13,
                                tint: .white.opacity(0.45),
                                hitSize: 40
                            ) {
                                Task { @MainActor in
                                    SettingsOpener.shared.open()
                                }
                            }
                            .padding(.trailing, 26)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: vm.isIdle)
    }

    private var idleContent: some View {
        HStack(spacing: 0) {
            Image(systemName: "play.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: m.side - m.gap, height: m.height)
                .padding(.trailing, m.gap)

            Color.clear
                .frame(width: m.notchW, height: m.height)

            if vm.isLocked {
                Color.clear
                    .frame(width: m.side - m.gap, height: m.height)
                    .padding(.leading, m.gap)
            } else {
                ControlButton(
                    systemName: "gearshape.fill",
                    size: 12,
                    tint: .white.opacity(0.45),
                    hitSize: max(m.side - m.gap, 28)
                ) {
                    Task { @MainActor in SettingsOpener.shared.open() }
                }
                .frame(width: m.side - m.gap, height: m.height)
                .padding(.leading, m.gap)
            }
        }
        .frame(width: m.width, height: m.height)
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
                        namespace: ns,
                        bundleIdentifier: vm.nowPlaying.bundleIdentifier,
                        showPlayerBadge: settings.playerBadgeExpanded
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
                .frame(maxWidth: 310).padding(.bottom, -5)
            MediaTransportControls()
        }
        .padding(.horizontal, 42)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    let ns: Namespace.ID
    let m: NotchMetrics

    private var sideKind: HUDKind? {
        guard let kind = vm.hudDisplay, kind.presentsOnSides else { return nil }
        return kind
    }

    var body: some View {
        HStack(spacing: 0) {
            leftSlot
            Color.clear.frame(width: m.notchW, height: m.height)
            rightSlot
        }
        .frame(height: m.height)
    }

    @ViewBuilder
    private var leftSlot: some View {
        Group {
            if let kind = sideKind {
                SideHUDIcon(kind: kind)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.72))
                            .combined(with: .offset(x: 10))
                    )
            } else if !vm.isIdle,
                vm.nowPlaying.artwork != nil
                    || !vm.nowPlaying.artworkUnavailable
            {
                ArtworkThumbnail(
                    artwork: vm.nowPlaying.artwork,
                    unavailable: vm.nowPlaying.artworkUnavailable,
                    size: m.artSize,
                    cornerRadius: 4,
                    trackKey: vm.nowPlaying.trackKey,
                    namespace: ns,
                    bundleIdentifier: vm.nowPlaying.bundleIdentifier,
                    showPlayerBadge: settings.playerBadgeCollapsed,
                    showsShadow: false
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: m.side - m.gap, alignment: .trailing)
        .padding(.trailing, m.gap)
        .opacity(m.extended || sideKind != nil ? 1 : 0)
        .animation(NotchViewModel.sideHUDSpring, value: sideKind)
    }

    @ViewBuilder
    private var rightSlot: some View {
        Group {
            if let kind = sideKind {
                SideHUDLabel(kind: kind)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.72))
                            .combined(with: .offset(x: -10))
                    )
            } else if !vm.isIdle {
                WaveBars(isPlaying: vm.nowPlaying.isPlaying)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: m.side - m.gap, alignment: .leading)
        .padding(.leading, m.gap)
        .opacity(m.extended || sideKind != nil ? 1 : 0)
        .animation(NotchViewModel.sideHUDSpring, value: sideKind)
    }
}
