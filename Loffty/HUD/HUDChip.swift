//
//  HUDChip.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

enum HUDKind: Equatable {
    case volume
    case brightness
    case bluetooth(name: String, connected: Bool)
    case battery(percent: Int, charging: Bool)
    case focus(enabled: Bool, name: String? = nil)

    var presentsVertically: Bool {
        switch self {
        case .volume, .brightness, .battery: true
        case .bluetooth, .focus: false
        }
    }

    var presentsOnSides: Bool { !presentsVertically }

    var isLevel: Bool {
        switch self {
        case .volume, .brightness, .battery: true
        case .bluetooth, .focus: false
        }
    }

    var accent: Color {
        switch self {
        case .focus(let enabled, let name):
            guard enabled else { return .white.opacity(0.55) }
            return FocusPalette.accent(for: name)
        case .bluetooth(_, let connected):
            return connected
                ? Color(red: 0.25, green: 0.55, blue: 1.0)
                : .white.opacity(0.55)
        default:
            return Color.white.opacity(0.9)
        }
    }
}

enum FocusPalette {
    static func accent(for name: String?) -> Color {
        let key = (name ?? "").lowercased()
        if key.contains("work") {
            return Color(red: 0.35, green: 0.72, blue: 0.86)
        }
        if key.contains("personal") {
            return Color(red: 0.75, green: 0.35, blue: 0.95)
        }
        if key.contains("sleep") {
            return Color(red: 0.34, green: 0.38, blue: 0.98)
        }
        if key.contains("driving") {
            return Color(red: 0.99, green: 0.56, blue: 0.15)
        }
        if key.contains("fitness") {
            return Color(red: 0.18, green: 0.80, blue: 0.46)
        }
        if key.contains("gaming") {
            return Color(red: 0.05, green: 0.52, blue: 1.0)
        }
        if key.contains("mindfulness") {
            return Color(red: 0.36, green: 0.90, blue: 0.88)
        }
        if key.contains("reading") {
            return Color(red: 1.0, green: 0.62, blue: 0.05)
        }
        return Color(red: 0.56, green: 0.42, blue: 0.98)
    }

    static func symbol(for name: String?, enabled: Bool) -> String {
        guard enabled else { return "moon" }
        let key = (name ?? "").lowercased()
        if key.contains("work") { return "briefcase.fill" }
        if key.contains("personal") { return "person.fill" }
        if key.contains("sleep") { return "bed.double.fill" }
        if key.contains("driving") { return "car.fill" }
        if key.contains("fitness") { return "figure.run" }
        if key.contains("gaming") { return "gamecontroller.fill" }
        if key.contains("mindfulness") { return "brain.head.profile" }
        if key.contains("reading") { return "book.fill" }
        return "moon.fill"
    }
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

            if kind.isLevel {
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
        case .bluetooth(_, let connected):
            connected
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash"
        case .battery(_, let charging):
            charging ? "battery.100.bolt" : batterySymbol
        case .focus(let enabled, let name):
            FocusPalette.symbol(for: name, enabled: enabled)
        }
    }

    private var batterySymbol: String {
        switch kind {
        case .battery(let percent, _) where percent >= 90:
            "battery.100"
        case .battery(let percent, _) where percent >= 65:
            "battery.75"
        case .battery(let percent, _) where percent >= 40:
            "battery.50"
        case .battery(let percent, _) where percent >= 15:
            "battery.25"
        case .battery:
            "battery.0"
        default:
            "battery.100"
        }
    }
}

struct SideHUDIcon: View {
    let kind: HUDKind

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind.accent)
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
            .shadow(color: kind.accent.opacity(0.45), radius: 6, y: 0)
    }

    private var icon: String {
        switch kind {
        case .bluetooth(_, let connected):
            connected
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash"
        case .focus(let enabled, let name):
            FocusPalette.symbol(for: name, enabled: enabled)
        default:
            "circle"
        }
    }
}

struct SideHUDLabel: View {
    let kind: HUDKind

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(kind.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
    }

    private var title: String {
        switch kind {
        case .bluetooth(let name, let connected):
            connected ? shortBluetoothName(name) : "Off"
        case .focus(let enabled, _):
            enabled ? "On" : "Off"
        default:
            ""
        }
    }

    private func shortBluetoothName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 12 { return trimmed }
        return String(trimmed.prefix(11)) + "…"
    }
}
