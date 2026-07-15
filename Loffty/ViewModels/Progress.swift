//
//  Progress.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

func fmtTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct ControlButton: View {
    let systemName: String
    let size: CGFloat
    let tint: Color
    var hitSize: CGFloat = 34
    var enabled: Bool = true
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
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.22)
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

struct Progress: View {
    @EnvironmentObject var vm: NotchViewModel
    let accent: Color

    @State private var hovering = false
    @State private var dragging = false
    @State private var scrubFraction: CGFloat?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let cur = vm.currentTime(at: ctx.date)
            let dur = vm.nowPlaying.duration
            let liveFraction =
                dur > 0 ? min(1, max(0, CGFloat(cur / dur))) : 0
            let displayFraction = scrubFraction ?? liveFraction
            let displayTime = Double(displayFraction) * dur
            let remaining = max(0, dur - displayTime)
            let active = hovering || dragging

            HStack(spacing: 10) {
                Text(fmtTime(displayTime))
                    .contentTransition(.numericText())
                seekTrack(
                    fraction: displayFraction,
                    enabled: dur > 0 && !vm.nowPlaying.isLive,
                    active: active
                )
                Text(dur > 0 ? "-\(fmtTime(remaining))" : fmtTime(displayTime))
                    .contentTransition(.numericText())
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
            .animation(.smooth(duration: 0.18), value: displayTime)
        }
        .animation(
            .spring(response: 0.45, dampingFraction: 0.86),
            value: vm.nowPlaying.trackKey
        )
    }

    private func seekTrack(
        fraction: CGFloat,
        enabled: Bool,
        active: Bool
    ) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barH: CGFloat = active ? 8 : 5
            let knobSize: CGFloat = active ? 11 : 8
            let clamped = min(1, max(0, fraction))
            let fillW = max(0, width * clamped)
            let knobX = fillW

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(active ? 0.22 : 0.16))
                    .frame(height: barH)

                Capsule()
                    .fill(accent.opacity(0.92))
                    .frame(width: fillW, height: barH)
                    .shadow(
                        color: accent.opacity(active ? 0.45 : 0.2),
                        radius: active ? 6 : 2
                    )

                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .overlay {
                        Circle()
                            .fill(accent.opacity(0.85))
                            .frame(width: knobSize - 4, height: knobSize - 4)
                    }
                    .offset(x: knobX - knobSize / 2)
                    .opacity(active ? 1 : 0)
                    .scaleEffect(active ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = enabled && $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        dragging = true
                        scrubFraction = min(
                            1,
                            max(0, value.location.x / max(width, 1))
                        )
                    }
                    .onEnded { value in
                        guard enabled, vm.nowPlaying.duration > 0 else {
                            dragging = false
                            scrubFraction = nil
                            return
                        }
                        let fraction = min(
                            1,
                            max(0, value.location.x / max(width, 1))
                        )
                        let time = Double(fraction) * vm.nowPlaying.duration
                        withAnimation(
                            .spring(response: 0.32, dampingFraction: 0.78)
                        ) {
                            vm.seek(to: time)
                        }
                        scrubFraction = nil
                        dragging = false
                    }
            )
            .animation(
                .spring(response: 0.28, dampingFraction: 0.76),
                value: active
            )
            .animation(
                dragging ? nil : .spring(response: 0.32, dampingFraction: 0.82),
                value: fraction
            )
        }
        .frame(height: 22)
    }
}

struct MediaProgressRow: View {
    @EnvironmentObject var vm: NotchViewModel
    let accent: Color

    var body: some View {
        if vm.nowPlaying.isLive {
            LiveProgressIndicator(accent: accent)
        } else {
            Progress(accent: accent)
        }
    }
}

struct LiveProgressIndicator: View {
    @EnvironmentObject var vm: NotchViewModel
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let behindLive = vm.isBehindLive(at: ctx.date)
            if behindLive, vm.nowPlaying.duration > 0 {
                let cur = vm.currentTime(at: ctx.date)
                let dur = vm.nowPlaying.duration
                let p = min(1, max(0, cur / dur))
                HStack(spacing: 10) {
                    Text(fmtTime(cur))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(accent.opacity(0.75))
                            .frame(width: max(0, 200 * p))
                    }
                    .frame(height: 5)
                    liveBadge(active: true)
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    liveBadge(active: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .monospacedDigit()
        .frame(height: 22)
    }

    private func liveBadge(active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .opacity(active ? 1 : 0.45)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white.opacity(active ? 0.85 : 0.45))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

struct LiveEdgeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("Live")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(NotchControlButtonStyle())
    }
}

struct MediaTransportControls: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        Group {
            if vm.nowPlaying.isLive {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    transportControls(behindLive: vm.isBehindLive(at: ctx.date))
                }
            } else {
                transportControls(behindLive: false)
            }
        }
    }

    private func transportControls(behindLive: Bool) -> some View {
        HStack(spacing: 12) {
            ControlButton(
                systemName: "gobackward.10",
                size: 18,
                tint: .white.opacity(0.8),
                enabled: !vm.nowPlaying.isLive
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
            if behindLive {
                LiveEdgeButton { vm.seekToLive() }
            } else {
                ControlButton(
                    systemName: "goforward.10",
                    size: 18,
                    tint: .white.opacity(0.8),
                    enabled: !vm.nowPlaying.isLive
                ) { vm.seek(by: 10) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.2), value: behindLive)
    }
}
