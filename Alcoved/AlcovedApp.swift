//
//  AlcovedApp.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import SwiftUI

@main
struct AlcovedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings {SettingsView()}
    }
}

struct SettingsView: View {
    var body: some View {Text("settings").padding().frame(width:320,height:160)}
}
