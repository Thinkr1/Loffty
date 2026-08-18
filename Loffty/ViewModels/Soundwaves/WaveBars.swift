//
//  WaveBars.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

struct WaveBars: View {
    @EnvironmentObject var vm: NotchViewModel
    @Environment(\.suppressMediaTickAnimations) private
        var suppressTickAnimations
    @ObservedObject private var settings = AppSettings.shared
    var isPlaying: Bool
    var barCount: Int = 4
    var maxHeight: CGFloat = 14
    var tint: Color? = nil
    private let minHeight: CGFloat = 3
    @State private var burst: CGFloat = 0

    private var barColor: Color {
        if let tint { return tint }
        return vm.isExpanded ? vm.accentColor : .primary
    }

    private var barBlend: BlendMode {
        if tint != nil { return .normal }
        return vm.isExpanded ? .normal : .difference
    }

    private var barsActive: Bool {
        isPlaying && settings.soundwaveMotion.showsAnimatedBars
    }

    var body: some View {
        ZStack {
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: !barsActive)
            ) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<barCount, id: \.self) { i in
                        Capsule()
                            .fill(barColor)
                            .blendMode(barBlend)
                            .frame(width: 2.5, height: height(i, t))
                    }
                }
                .frame(height: maxHeight)
                .scaleEffect(x: 1, y: 1 + burst * 0.45, anchor: .center)
            }
            .opacity(barsActive ? 1 : 0)
            .scaleEffect(barsActive ? 1 : 0.5)
            .blur(radius: barsActive ? 0 : 3)

            Image(systemName: "pause.fill")
                .font(.system(size: maxHeight * 0.8, weight: .semibold))
                .foregroundStyle(barColor)
                .blendMode(barBlend)
                .opacity(barsActive ? 0 : 1)
                .scaleEffect(barsActive ? 0.5 : 1)
                .blur(radius: barsActive ? 3 : 0)
        }
        .frame(height: maxHeight)
        .animation(
            suppressTickAnimations
                ? nil
                : .spring(response: 0.34, dampingFraction: 0.8),
            value: barsActive
        )
        .onChange(of: vm.trackChangeToken) { _, token in
            guard token > 0, !vm.isRapidSkipping else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                burst = 1
            }
            withAnimation(.easeOut(duration: 0.38).delay(0.08)) {
                burst = 0
            }
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        guard barsActive else { return minHeight }
        if settings.soundwaveMotion == .live,
            let levels = AudioSpectrum.shared.snapshot(barCount: barCount),
            i < levels.count
        {
            return WaveBarMotion.liveHeight(
                level: levels[i],
                minHeight: minHeight,
                maxHeight: maxHeight
            )
        }
        return WaveBarMotion.mockHeight(
            index: i,
            time: t,
            minHeight: minHeight,
            maxHeight: maxHeight,
            timeScale: settings.soundwaveFeel.mockSpeed
        )
    }
}
