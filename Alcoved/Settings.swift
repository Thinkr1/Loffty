//
//  Settings.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import Combine
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let hideMenuBarItemKey = "hideMenuBarItem"
    
    @Published var hideMenuBarItem: Bool {
        didSet { UserDefaults.standard.set(hideMenuBarItem, forKey: Self.hideMenuBarItemKey) }
    }
    
    private init() {
        hideMenuBarItem = UserDefaults.standard.bool(forKey: Self.hideMenuBarItemKey)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarItem)
            }
        }
        .formStyle(.grouped)
    }
}
