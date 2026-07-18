//
//  FocusPaletteTests.swift
//  LofftyTests
//

import SwiftUI
import Testing

@testable import Loffty

@Suite("FocusPalette")
struct FocusPaletteTests {
    @Test func disabledUsesMoon() {
        #expect(FocusPalette.symbol(for: "Work", enabled: false) == "moon")
    }

    @Test(arguments: [
        ("Work", "briefcase.fill"),
        ("Personal", "person.fill"),
        ("Sleep", "bed.double.fill"),
        ("Driving", "car.fill"),
        ("Fitness", "figure.run"),
        ("Gaming", "gamecontroller.fill"),
        ("Mindfulness", "brain.head.profile"),
        ("Reading", "book.fill"),
        ("Custom Mode", "moon.fill"),
    ])
    func symbolForKnownModes(name: String, expected: String) {
        #expect(FocusPalette.symbol(for: name, enabled: true) == expected)
    }

    @Test func accentDiffersByMode() {
        #expect(
            FocusPalette.accent(for: "Work")
                != FocusPalette.accent(for: "Sleep")
        )
        #expect(
            FocusPalette.accent(for: nil) != FocusPalette.accent(for: "Work")
        )
    }

    @Test(arguments: [
        ("com.apple.focus.work", nil as String?, "Work"),
        ("com.apple.donotdisturb", nil as String?, "Do Not Disturb"),
        ("com.apple.focus.reduce-interruptions", nil as String?, "Focus"),
        (nil as String?, "My Mode" as String?, "My Mode"),
        ("com.apple.focus.sleep", "com.apple.focus.sleep" as String?, "Sleep"),
        ("com.apple.focus.personal", nil as String?, "Personal"),
        ("com.apple.focus.driving", nil as String?, "Driving"),
        ("com.apple.focus.fitness", nil as String?, "Fitness"),
        ("com.apple.focus.gaming", nil as String?, "Gaming"),
        ("com.apple.focus.mindfulness", nil as String?, "Mindfulness"),
        ("com.apple.focus.reading", nil as String?, "Reading"),
        ("com.apple.focus.unknown-mode", nil as String?, "Focus"),
    ])
    func displayName(identifier: String?, name: String?, expected: String) {
        #expect(
            FocusHUDWatcher.displayName(identifier: identifier, name: name)
                == expected
        )
    }
}
