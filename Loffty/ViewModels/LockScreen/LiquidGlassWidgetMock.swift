//
//  LiquidGlassWidgetMock.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 01/09/2026.
//

import AppKit
import SwiftUI

enum LockWidgetMockLayout {
    static let height: CGFloat = 320
    static let cardScale: CGFloat = 0.7
    static let cardTop: CGFloat = 96

    static var scaledCardSize: CGSize {
        CGSize(
            width: LockCardMetrics.width * cardScale,
            height: LockCardMetrics.height * cardScale
        )
    }
}

struct LockWidgetGlassMock: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var wallpaper: NSImage?

    private let mockHeight = LockWidgetMockLayout.height
    private let cardScale = LockWidgetMockLayout.cardScale

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .top) {
                background
                chrome
                sampleCard
                    .padding(.top, LockWidgetMockLayout.cardTop)
                    .frame(width: width)
            }
            .frame(width: width, height: mockHeight)
            .clipShape(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(height: mockHeight)
        .onAppear(perform: loadWallpaper)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loadWallpaper()
        }
    }

    private var sampleCard: some View {
        let shape = RoundedRectangle(
            cornerRadius: LockCardMetrics.cornerRadius,
            style: .continuous
        )
        let tint = settings.lockScreenLiquidGlassTint
        let color = settings.lockScreenResolvedGlassColor
        let size = LockWidgetMockLayout.scaledCardSize
        return ZStack {
            cardPlate(shape: shape, tint: tint, color: color)
            sampleContent
        }
        .frame(
            width: LockCardMetrics.width,
            height: LockCardMetrics.height
        )
        .clipShape(shape)
        .scaleEffect(cardScale, anchor: .top)
        .frame(width: size.width, height: size.height, alignment: .top)
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .animation(
            .easeInOut(duration: 0.22),
            value: tint
        )
        .animation(
            .easeInOut(duration: 0.22),
            value: settings.lockScreenLiquidGlassColorTint
        )
        .animation(
            .easeInOut(duration: 0.22),
            value: LiquidGlassColorCodec.encode(
                settings.lockScreenLiquidGlassColor
            )
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cardPlate(
        shape: RoundedRectangle,
        tint: LiquidGlassTint,
        color: Color?
    ) -> some View {
        if LockGlassPlacement.showsWallpaper(tint)
            || LockGlassPlacement.showsFrostedPlate(tint)
        {
            Color.clear.lockWidgetChrome(shape, tint: tint, color: color)
        }
    }

    private var sampleContent: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                sampleArtwork
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stressed Out")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                    Text("Twenty One Pilots")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                sampleWaves
                    .frame(width: 22)
            }

            VStack(spacing: 10) {
                sampleProgress
                MediaToolbarLiveRow(
                    items: [.previous, .playPause, .next],
                    tint: .white
                )
                .frame(minHeight: 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
    }

    private var sampleArtwork: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.22, blue: 0.55),
                        Color(red: 0.18, green: 0.28, blue: 0.62),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    private var sampleWaves: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach([7, 14, 10, 16, 8], id: \.self) { height in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2.5, height: CGFloat(height))
            }
        }
        .frame(height: 16)
    }

    private var sampleProgress: some View {
        HStack(spacing: 8) {
            Text("1:24")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white.opacity(0.82))
                        .frame(width: geo.size.width * 0.38)
                }
            }
            .frame(height: 4)
            Text("3:48")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var background: some View {
        ZStack {
            fallbackBackground
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            LinearGradient(
                colors: [
                    .black.opacity(0.18),
                    .black.opacity(0.08),
                    .black.opacity(0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.22, green: 0.28, blue: 0.24),
                Color(red: 0.12, green: 0.14, blue: 0.13),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.black.opacity(0.85))
                .frame(width: 48, height: 9)
                .padding(.top, 7)

            Text(Self.sampleDate)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)

            Text("9:41")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func loadWallpaper() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        wallpaper = LockMockWallpaper.image(for: screen)
    }

    private static var sampleDate: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: Date())
    }
}
