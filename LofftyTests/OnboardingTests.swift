//
//  OnboardingTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Onboarding")
struct OnboardingTests {
    @Test func presentsUntilCompleted() {
        #expect(
            OnboardingFlow.shouldPresentOnboarding(
                hasCompletedOnboarding: false
            )
        )
        #expect(
            !OnboardingFlow.shouldPresentOnboarding(
                hasCompletedOnboarding: true
            )
        )
    }

    @Test func stepOrderAdvancesAndRetreats() {
        #expect(OnboardingFlow.next(.welcome) == .setup)
        #expect(OnboardingFlow.next(.setup) == .ready)
        #expect(OnboardingFlow.next(.ready) == nil)

        #expect(OnboardingFlow.previous(.ready) == .setup)
        #expect(OnboardingFlow.previous(.setup) == .welcome)
        #expect(OnboardingFlow.previous(.welcome) == nil)
    }

    @Test func transitionGroupsStayStablePerScreen() {
        #expect(OnboardingFlow.transitionGroup(for: .welcome) == "welcome")
        #expect(OnboardingFlow.transitionGroup(for: .setup) == "setup")
        #expect(OnboardingFlow.transitionGroup(for: .ready) == "ready")
        #expect(
            OnboardingFlow.transitionGroup(for: .setup)
                != OnboardingFlow.transitionGroup(for: .welcome)
        )
    }

    @Test func primaryTitlesMatchFlow() {
        #expect(OnboardingFlow.primaryTitle(for: .welcome) == "Get Started")
        #expect(OnboardingFlow.primaryTitle(for: .setup) == "Continue")
        #expect(OnboardingFlow.primaryTitle(for: .ready) == "Start Loffty")
    }

    @Test func onlyReadyFinishesOnPrimaryAction() {
        #expect(!OnboardingFlow.finishesOnPrimaryAction(.welcome))
        #expect(!OnboardingFlow.finishesOnPrimaryAction(.setup))
        #expect(OnboardingFlow.finishesOnPrimaryAction(.ready))
    }

    @Test func menuBarIconBindingInvertsHideFlag() {
        #expect(OnboardingFlow.showMenuBarIcon(hidingMenuBarItem: false))
        #expect(!OnboardingFlow.showMenuBarIcon(hidingMenuBarItem: true))
        #expect(OnboardingFlow.hideMenuBarItem(showingMenuBarIcon: false))
        #expect(!OnboardingFlow.hideMenuBarItem(showingMenuBarIcon: true))
    }

    @Test @MainActor func markCompletedSetsPersistedFlag() {
        let settings = AppSettings.shared
        let original = settings.hasCompletedOnboarding
        defer { settings.hasCompletedOnboarding = original }

        settings.hasCompletedOnboarding = false
        OnboardingFlow.markCompleted(settings: settings)
        #expect(settings.hasCompletedOnboarding)
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
    }

    @Test func privacySettingsURLCandidatesIncludeModernAndLegacyAnchors() {
        let urls = PrivacyAccess.privacySettingsURLCandidates(
            anchor: "Privacy_Accessibility"
        )
        #expect(urls.count == 2)
        #expect(
            urls[0]
                == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        )
        #expect(
            urls[1]
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        for url in urls {
            #expect(URL(string: url) != nil)
        }
    }

    @Test func privacySettingsURLCandidatesCoverBluetoothAndLocalNetwork() {
        #expect(
            PrivacyAccess.privacySettingsURLCandidates(
                anchor: "Privacy_Bluetooth"
            ).contains {
                $0.hasSuffix("Privacy_Bluetooth")
            }
        )
        #expect(
            PrivacyAccess.privacySettingsURLCandidates(
                anchor: "Privacy_LocalNetwork"
            ).contains {
                $0.hasSuffix("Privacy_LocalNetwork")
            }
        )
        #expect(
            PrivacyAccess.privacySettingsURLCandidates(
                anchor: "Privacy_AllFiles"
            ).contains {
                $0.hasSuffix("Privacy_AllFiles")
            }
        )
    }
}
