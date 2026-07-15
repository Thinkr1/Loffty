//
//  WaveBars.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

struct WaveBars: View {  // TODO: actual soundwaves
    @EnvironmentObject var vm: NotchViewModel
    var isPlaying: Bool
    var barCount: Int = 4
    var maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3
    private let phases: [Double] = [0.0, 0.9, 1.8, 2.7, 3.6, 4.5]
    @State private var burst: CGFloat = 0

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)
        ) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(vm.isExpanded ? vm.accentColor : .primary)
                        .blendMode(vm.isExpanded ? .normal : .difference)
                        .frame(width: 2.5, height: height(i, t))
                }
            }
            .frame(height: maxHeight)
            .scaleEffect(x: 1, y: 1 + burst * 0.45, anchor: .center)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
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
        guard isPlaying else { return minHeight }
        let phase = phases[i % phases.count]
        let s = (sin(t * 6.0 + phase) + sin(t * 9.7 + phase * 1.7)) / 2
        let norm = (s + 1) / 2  // 0...1
        return minHeight + (maxHeight - minHeight) * CGFloat(norm)
    }
}
