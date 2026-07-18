//
//  MediaParsingTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("MediaParsing")
struct MediaParsingTests {
    @Test func parseArtistNamesFromEmbedHTML() {
        let html = #""artists":[{"name":"A"},{"name":"B"}]"#
        #expect(MediaParsing.parseArtistNames(from: html) == "A, B")
    }

    @Test func parseArtistNamesMissingReturnsNil() {
        #expect(MediaParsing.parseArtistNames(from: "<html></html>") == nil)
    }

    @Test func parseArtistStringArrayAndDictForms() {
        #expect(
            MediaParsing.parseArtist(from: ["artists": ["A", "B"]]) == "A, B"
        )
        #expect(
            MediaParsing.parseArtist(from: [
                "artists": [["name": "X"], ["name": "Y"]]
            ]) == "X, Y"
        )
        #expect(MediaParsing.parseArtist(from: ["artist": "Solo"]) == "Solo")
        #expect(
            MediaParsing.parseArtist(from: ["artist": ["P", "Q"]]) == "P, Q"
        )
    }

    @Test func parseIsLiveDetectsRadioKeysAndZeroDuration() {
        #expect(
            MediaParsing.parseIsLive(from: ["radioStationIdentifier": "x"])
        )
        #expect(MediaParsing.parseIsLive(from: ["radioStationHash": 1]))
        #expect(
            MediaParsing.parseIsLive(from: ["mediaType": "MRMediaTypeRadio"])
        )
        #expect(
            MediaParsing.parseIsLive(
                from: ["duration": 0, "title": "Morning Show"]
            )
        )
        #expect(
            !MediaParsing.parseIsLive(
                from: ["duration": 200, "title": "Song"]
            )
        )
    }

    @Test func isIdlePayloadDiffAndFull() {
        #expect(MediaParsing.isIdlePayload(["title": NSNull()], isDiff: true))
        #expect(MediaParsing.isIdlePayload(["title": ""], isDiff: false))
        #expect(MediaParsing.isIdlePayload([:], isDiff: false))
        #expect(
            !MediaParsing.isIdlePayload(
                ["title": "Track", "playing": true],
                isDiff: false
            )
        )
    }

    @Test func isElapsedOnlyDiff() {
        #expect(
            MediaParsing.isElapsedOnlyDiff([
                "elapsedTime": 1.0,
                "timestamp": "2026-01-01T00:00:00Z",
            ])
        )
        #expect(
            !MediaParsing.isElapsedOnlyDiff([
                "elapsedTime": 1.0,
                "title": "Song",
            ])
        )
    }

    @Test func parseIsLiveUsesCurrentFallbackValues() {
        #expect(
            MediaParsing.parseIsLive(
                from: [:],
                currentDuration: 0,
                currentTitle: "Radio"
            )
        )
        #expect(
            !MediaParsing.parseIsLive(
                from: [:],
                currentDuration: 0,
                currentTitle: ""
            )
        )
    }

    @Test func trackKeyBuildsAndFallsBack() {
        #expect(
            MediaParsing.trackKey(
                title: "Song",
                bundle: "com.spotify.client",
                currentTitle: "",
                lastKey: nil,
                isDiff: false
            ) == "com.spotify.client|Song"
        )
        #expect(
            MediaParsing.trackKey(
                title: nil,
                bundle: "",
                currentTitle: "Old",
                lastKey: "a|b",
                isDiff: true
            ) == nil
        )
        #expect(
            MediaParsing.trackKey(
                title: nil,
                bundle: "",
                currentTitle: "Old",
                lastKey: "a|b",
                isDiff: false
            ) == "a|b"
        )
    }

    @Test func parseTimestampSupportsISO8601() {
        let withFraction = MediaParsing.parseTimestamp(
            "2026-07-18T12:00:00.5Z"
        )
        #expect(withFraction != nil)
        let plain = MediaParsing.parseTimestamp("2026-07-18T12:00:00Z")
        #expect(plain != nil)
        #expect(MediaParsing.parseTimestamp("not-a-date") == nil)
        let date = Date(timeIntervalSince1970: 42)
        #expect(MediaParsing.parseTimestamp(date) == date)
    }

    @Test func elapsedDiscontinuityThreshold() {
        let ts = Date(timeIntervalSince1970: 1000)
        let expected = MediaParsing.expectedElapsed(
            publishedElapsed: 10,
            publishedTimestamp: ts,
            publishedRate: 1,
            publishedIsPlaying: true,
            at: ts.addingTimeInterval(2)
        )
        #expect(expected == 12)
        #expect(
            !MediaParsing.hasSignificantElapsedDiscontinuity(
                expected: 12,
                actual: 12.5
            )
        )
        #expect(
            MediaParsing.hasSignificantElapsedDiscontinuity(
                expected: 12,
                actual: 14
            )
        )
    }
}
