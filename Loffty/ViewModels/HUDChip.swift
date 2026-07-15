//
//  HUDChip.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

enum HUDKind: Equatable {
    case volume, brightness
}

struct HUDChip: View {
    @EnvironmentObject var vm: NotchViewModel
    let kind: HUDKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 14)
                .contentTransition(.symbolEffect(.replace))

            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .scaleEffect(
                            x: max(CGFloat(vm.hudLevel), 0.001),
                            y: 1,
                            anchor: .leading
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 5)
                .clipShape(Capsule())
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.78),
            value: vm.hudLevel
        )
    }

    private var icon: String {
        switch kind {
        case .volume:
            vm.hudMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:
            vm.hudLevel < 0.01 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
