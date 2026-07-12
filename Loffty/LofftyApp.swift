//
//  LofftyApp.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import SwiftUI

@main
struct LofftyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
