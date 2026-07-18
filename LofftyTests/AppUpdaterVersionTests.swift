//
//  AppUpdaterVersionTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("AppUpdater versions")
struct AppUpdaterVersionTests {
    @Test func normalizeVersionStripsVPrefix() {
        #expect(AppUpdater.normalizeVersion("v1.2.3") == "1.2.3")
        #expect(AppUpdater.normalizeVersion("V2.0") == "2.0")
        #expect(AppUpdater.normalizeVersion(" 1.0 ") == "1.0")
    }

    @Test func compareVersionsPadsMissingComponents() {
        #expect(AppUpdater.compareVersions("1.2", "1.2.0") == .orderedSame)
        #expect(
            AppUpdater.compareVersions("1.2.1", "1.2") == .orderedDescending
        )
        #expect(AppUpdater.compareVersions("1.1.9", "1.2") == .orderedAscending)
    }

    @Test func isVersionNewerThan() {
        #expect(AppUpdater.isVersion("1.1.4", newerThan: "1.1.3"))
        #expect(!AppUpdater.isVersion("1.1.3", newerThan: "1.1.3"))
        #expect(!AppUpdater.isVersion("1.1.2", newerThan: "1.1.3"))
        #expect(AppUpdater.isVersion("v2.0.0", newerThan: "1.9.9"))
    }

    @Test func compareVersionsTreatsNonNumericAsZero() {
        #expect(AppUpdater.compareVersions("1.2.a", "1.2.0") == .orderedSame)
        #expect(AppUpdater.compareVersions("", "1") == .orderedAscending)
    }
}
