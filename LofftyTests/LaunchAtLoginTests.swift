//
//  LaunchAtLoginTests.swift
//  LofftyTests
//

import ServiceManagement
import Testing

@testable import Loffty

@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test @MainActor func enabledStatusTreatsApprovalAsOn() {
        #expect(LaunchAtLogin.isEnabled(status: .enabled))
        #expect(LaunchAtLogin.isEnabled(status: .requiresApproval))
        #expect(!LaunchAtLogin.isEnabled(status: .notRegistered))
        #expect(!LaunchAtLogin.isEnabled(status: .notFound))
    }

    @Test @MainActor func requiresApprovalOnlyForPendingStatus() {
        #expect(LaunchAtLogin.requiresApproval(status: .requiresApproval))
        #expect(!LaunchAtLogin.requiresApproval(status: .enabled))
        #expect(!LaunchAtLogin.requiresApproval(status: .notRegistered))
        #expect(!LaunchAtLogin.requiresApproval(status: .notFound))
    }

    @Test @MainActor func refreshLaunchAtLoginSyncsPublishedFlags() {
        let settings = AppSettings.shared
        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLogin == LaunchAtLogin.isEnabled)
        #expect(
            settings.launchAtLoginNeedsApproval == LaunchAtLogin.requiresApproval
        )
    }
}
