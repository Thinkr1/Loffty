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
    @ObservedObject private var toolbar =
        MediaToolbarCustomizer.shared
    let ns: Namespace.ID
    let m: NotchMetrics

    var body: some View {
        ZStack {
            if vm.expandedPage == .weather, !toolbar.isCustomizing,
                settings.weatherEnabled
            {
                WeatherNotchContent(m: m)
                    .transition(pageTransition)
            } else if vm.isIdle, !toolbar.isCustomizing {
                idleContent
                    .transition(pageTransition)
            } else {
                activeContent
                    .transition(pageTransition)
            }
        }
        .offset(x: vm.pageSwipeOffset)
        .scaleEffect(
            x: 1 + abs(vm.pageSwipeOffset) / 4200,
            y: 1 + abs(vm.pageSwipeOffset) / 9000,
            anchor: .center
        )
        .overlay(alignment: .top) {
            if !vm.isLocked {
                notchTopBar
            }
        }
        .overlay(alignment: .trailing) {
            if vm.expandedPage == .weather, settings.weatherEnabled,
                !toolbar.isCustomizing
            {
                VStack(spacing: 5) {
                    ForEach(WeatherSlide.allCases, id: \.rawValue) { slide in
                        Capsule()
                            .fill(
                                .white.opacity(
                                    slide == vm.weatherSlide ? 0.85 : 0.3
                                )
                            )
                            .frame(
                                width: 3,
                                height: slide == vm.weatherSlide ? 14 : 5
                            )
                    }
                }
                .frame(width: 30, height: m.height, alignment: .center)
                .padding(.trailing, 18)
                .allowsHitTesting(false)
                .opacity(1)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: vm.isIdle)
        .animation(
            NotchViewModel.notchExpandSpring,
            value: toolbar.isCustomizing
        )
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 1.015))
        )
    }

    private var notchFlankWidth: CGFloat {
        max(0, (m.width - m.notchW) / 2)
    }

    private var notchTopBar: some View {
        HStack(spacing: 0) {
            Group {
                if vm.expandedPage == .weather, settings.weatherEnabled {
                    ControlButton(
                        systemName: "music.note",
                        size: 12,
                        tint: .white.opacity(0.45),
                        hitSize: min(28, notchFlankWidth)
                    ) {
                        vm.setExpandedPage(.music)
                    }
                } else if settings.showAirPlayButton, !vm.isIdle {
                    AirPlayPickerButton()
                } else if settings.weatherEnabled {
                    ControlButton(
                        systemName: "cloud.sun.fill",
                        size: 12,
                        tint: .white.opacity(0.45),
                        hitSize: min(28, notchFlankWidth)
                    ) {
                        vm.setExpandedPage(.weather)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: notchFlankWidth, height: m.notchH)
            Color.clear
                .frame(width: m.notchW, height: m.notchH)
            ControlButton(
                systemName: "gearshape.fill",
                size: 12,
                tint: .white.opacity(0.45),
                hitSize: min(28, notchFlankWidth)
            ) {
                Task { @MainActor in
                    SettingsOpener.shared.open()
                }
            }
            .frame(width: notchFlankWidth, height: m.notchH)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
            Text("Nothing Playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Text(
                settings.weatherEnabled
                    ? "Swipe for weather" : "Waiting for media"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.34))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, m.notchH)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if settings.weatherEnabled { vm.setExpandedPage(.weather) }
        }
    }

    private var showingAlbum: Bool {
        settings.showAlbum && !vm.nowPlaying.album.isEmpty
    }

    private var activeContent: some View {
        let artSize: CGFloat = 48
        let artAspect = vm.nowPlaying.displayArtworkAspect
        let titleBlockHeight: CGFloat =
            18 + (vm.nowPlaying.artist.isEmpty ? 0 : 2 + 16)
        let textTopInset =
            showingAlbum ? max(0, (artSize - titleBlockHeight) / 2) : 0

        return VStack(spacing: 16) {
            HStack(alignment: showingAlbum ? .top : .center, spacing: 16) {
                if vm.nowPlaying.artwork != nil
                    || !vm.nowPlaying.artworkUnavailable
                {
                    ArtworkThumbnail(
                        artwork: vm.nowPlaying.artwork,
                        unavailable: vm.nowPlaying.artworkUnavailable,
                        size: artSize,
                        cornerRadius: 14,
                        trackKey: vm.nowPlaying.trackKey,
                        namespace: ns,
                        bundleIdentifier: vm.nowPlaying
                            .resolvedBundleIdentifier,
                        showPlayerBadge: settings.playerBadgeExpanded,
                        aspectRatio: artAspect,
                        websiteHost: vm.nowPlaying.websiteHost
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: vm.nowPlaying.title,
                        font: .system(size: 15),
                        color: .white,
                        height: 18,
                        scrolling: settings.marqueeEnabled
                    )
                    if showingAlbum {
                        MarqueeText(
                            text: vm.nowPlaying.album,
                            font: .system(size: 12),
                            color: .white.opacity(0.32),
                            height: 14,
                            scrolling: settings.marqueeEnabled
                        )
                        .transition(
                            .opacity.combined(with: .move(edge: .top))
                        )
                    }
                    if !vm.nowPlaying.artist.isEmpty {
                        MarqueeText(
                            text: vm.nowPlaying.artist,
                            font: .system(size: 13),
                            color: .white.opacity(0.45),
                            height: 16,
                            scrolling: settings.marqueeEnabled
                        )
                    }
                }
                .padding(.top, textTopInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(
                    .spring(response: 0.36, dampingFraction: 0.86),
                    value: showingAlbum
                )

                WaveBars(
                    isPlaying: vm.nowPlaying.isPlaying,
                    barCount: 5,
                    maxHeight: 16
                )
                .foregroundStyle(.white.opacity(0.82))
                .padding(.top, showingAlbum ? textTopInset + 1 : 0)
            }
            MediaProgressRow(accent: vm.accentColor)
                .frame(maxWidth: .infinity)
            if toolbar.isCustomizing {
                MediaToolbarCustomizeRow()
                    .padding(.top, 2)
                MediaToolbarCustomizeChrome()
                    .padding(.top, 8)
            } else {
                MediaTransportControls()
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, m.notchH + 8)
        .padding(.bottom, 24)
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
                    bundleIdentifier: vm.nowPlaying.resolvedBundleIdentifier,
                    showPlayerBadge: settings.playerBadgeCollapsed,
                    showsShadow: false,
                    aspectRatio: vm.nowPlaying.displayArtworkAspect,
                    websiteHost: vm.nowPlaying.websiteHost
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
                WaveBars(
                    isPlaying: vm.nowPlaying.isPlaying,
                    tint: settings.collapsedWaveformsAccent
                        ? vm.accentColor
                        : nil
                )
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
