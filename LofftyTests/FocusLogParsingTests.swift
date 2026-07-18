//
//  FocusLogParsingTests.swift
//  LofftyTests
//

import Testing

@testable import Loffty

@Suite("FocusLogParsing")
struct FocusLogParsingTests {
    @Test func clearedOnNullAssertion() {
        let line = "Active Mode Assertion: (null)"
        #expect(FocusLogParsing.event(from: line) == .cleared)
    }

    @Test func clearedOnStartingZero() {
        #expect(FocusLogParsing.event(from: "starting: 0") == .cleared)
    }

    @Test func activeWithIdentifierAndName() {
        let line =
            "Active Mode Assertion: yes; semanticModeIdentifier: com.apple.focus.work; name: Work;"
        #expect(
            FocusLogParsing.event(from: line)
                == .active(identifier: "com.apple.focus.work", name: "Work")
        )
    }

    @Test func ignoresUnrelatedLines() {
        #expect(FocusLogParsing.event(from: "heartbeat ok") == nil)
    }

    @Test func extractStopsAtDelimiter() {
        let line = "modeIdentifier: com.apple.focus.sleep; other: 1"
        #expect(
            FocusLogParsing.extract(after: "modeIdentifier:", in: line)
                == "com.apple.focus.sleep"
        )
    }

    @Test func clearedModeAssertionAndActiveModeNull() {
        #expect(
            FocusLogParsing.event(from: "cleared mode assertion") == .cleared
        )
        #expect(
            FocusLogParsing.event(from: "ActiveModeIdentifier: (null)")
                == .cleared
        )
    }

    @Test func assertedModeWithNameOnly() {
        let line = "asserted mode; name: Gaming;"
        #expect(
            FocusLogParsing.event(from: line)
                == .active(identifier: nil, name: "Gaming")
        )
    }

    @Test func looksActiveWithoutIdentityIgnored() {
        #expect(FocusLogParsing.event(from: "starting: 1") == nil)
    }
}
