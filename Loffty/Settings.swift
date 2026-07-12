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

    private init() {
        hideMenuBarItem = UserDefaults.standard.bool(
            forKey: Self.hideMenuBarItemKey
        )
        extendNotch = UserDefaults.standard.bool(forKey: Self.extendNotchKey)
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
        }
        .formStyle(.grouped)
    }
}
