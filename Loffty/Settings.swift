//
//  Settings.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import Combine
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let hideMenuBarItemKey = "hideMenuBarItem"
    private static let extendNotchKey = "extendNotch"
    private static let replaceSystemHUDKey = "replaceSystemHUD"
    private static let hudDurationKey = "hudDuration"
    private static let brightnessHUDKey = "brightnessHUD"

    @Published var hideMenuBarItem: Bool {
        didSet {
            UserDefaults.standard.set(
                hideMenuBarItem,
                forKey: Self.hideMenuBarItemKey
            )
        }
    }

    @Published var extendNotch: Bool {
        didSet {
            UserDefaults.standard.set(extendNotch, forKey: Self.extendNotchKey)
        }
    }

    @Published var replaceSystemHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                replaceSystemHUD,
                forKey: Self.replaceSystemHUDKey
            )
        }
    }

    @Published var hudDuration: Double {
        didSet {
            UserDefaults.standard.set(hudDuration, forKey: Self.hudDurationKey)
        }
    }

    @Published var brightnessHUD: Bool {
        didSet {
            UserDefaults.standard.set(
                brightnessHUD,
                forKey: Self.brightnessHUDKey
            )
        }
    }

    private init() {
        hideMenuBarItem = UserDefaults.standard.bool(
            forKey: Self.hideMenuBarItemKey
        )
        extendNotch = UserDefaults.standard.bool(forKey: Self.extendNotchKey)
        replaceSystemHUD =
            UserDefaults.standard.object(forKey: Self.replaceSystemHUDKey)
            as? Bool ?? true
        hudDuration =
            UserDefaults.standard.object(forKey: Self.hudDurationKey) as? Double
            ?? 1.75
        brightnessHUD =
            UserDefaults.standard.object(forKey: Self.brightnessHUDKey) as? Bool
            ?? true
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarItem)
                Toggle("Extend notch around media", isOn: $settings.extendNotch)
            }
            Section {
                Toggle(
                    "Hide macOS volume & brightness overlays",
                    isOn: $settings.replaceSystemHUD
                )
                Toggle("Show brightness HUD", isOn: $settings.brightnessHUD)
                HStack {
                    Text("HUD duration")
                    Slider(value: $settings.hudDuration, in: 1...3, step: 0.25)
                    Text(String(format: "%.1fs", settings.hudDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("System HUDs")
            } footer: {
                if settings.replaceSystemHUD {
                    Text(
                        "Requires Accessibility permission. Loffty only intercepts volume and brightness keys."
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}
