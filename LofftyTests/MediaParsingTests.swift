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

    @Test func parseIsVideoUsesMediaTypeAndArtworkAspect() {
        #expect(
            MediaParsing.parseIsVideo(from: [
                "mediaType": "MRMediaRemoteMediaTypeVideo"
            ])
        )
        #expect(
            !MediaParsing.parseIsVideo(from: [
                "mediaType": "MRMediaRemoteMediaTypeMusic"
            ])
        )
        #expect(
            MediaParsing.parseIsVideo(
                from: ["mediaType": "kMRMediaRemoteNowPlayingInfoTypeAudio"],
                artworkAspect: 16 / 9
            )
        )
        #expect(
            !MediaParsing.parseIsVideo(
                from: ["isMusicApp": true],
                artworkAspect: 1.8
            )
        )
        #expect(
            MediaParsing.parseIsVideo(
                from: [:],
                currentIsVideo: true,
                isDiff: true
            )
        )
    }

    @Test func websiteHostFromURLAndLabels() {
        #expect(
            MediaParsing.websiteHost(
                uniqueIdentifier: "https://www.youtube.com/watch?v=abc"
            ) == "youtube.com"
        )
        #expect(
            MediaParsing.websiteHost(
                contentItemIdentifier: "https://youtu.be/abc"
            ) == "youtube.com"
        )
        #expect(
            MediaParsing.websiteHost(title: "SVJ At 18. - YouTube")
                == "youtube.com"
        )
        #expect(
            MediaParsing.websiteHost(album: "Netflix") == "netflix.com"
        )
        #expect(
            MediaParsing.websiteHost(artist: "Twitch") == "twitch.tv"
        )
        #expect(MediaParsing.websiteHost(title: "Just a song") == nil)
        #expect(
            MediaParsing.host(fromPossibleURL: "www.netflix.com/title/1")
                == "netflix.com"
        )
        #expect(MediaParsing.host(fromPossibleURL: "not-a-url") == nil)
        #expect(MediaParsing.host(fromPossibleURL: "com.apple.Safari") == nil)
        #expect(
            MediaParsing.looksLikeBundleIdentifier("com.google.Chrome")
        )
    }

    @Test func displayArtworkAspectUsesVideoRatio() {
        #expect(
            MediaParsing.displayArtworkAspect(isVideo: false, raw: 1.8) == 1
        )
        #expect(
            MediaParsing.displayArtworkAspect(isVideo: true, raw: 1)
                == MediaParsing.videoAspectRatio
        )
        #expect(
            MediaParsing.displayArtworkAspect(isVideo: true, raw: 1.9)
                == 1.9
        )
        #expect(
            MediaParsing.displayArtworkAspect(isVideo: true, raw: 4)
                == MediaParsing.maxArtworkAspect
        )
    }

    @Test func browserBundleDetection() {
        #expect(MediaParsing.isBrowserBundle("com.apple.Safari"))
        #expect(MediaParsing.isBrowserBundle("com.google.Chrome"))
        #expect(
            MediaParsing.isBrowserBundle(
                "com.apple.Safari.WebApp.ABC123"
            )
        )
        #expect(!MediaParsing.isBrowserBundle("com.spotify.client"))
        #expect(
            MediaParsing.appleScriptApplication(
                forBundle: "com.apple.WebKit.WebContent"
            ) == "Safari"
        )
        #expect(
            MediaParsing.scriptingBundleID(
                for: "com.apple.WebKit.WebContent"
            ) == "com.apple.Safari"
        )
        #expect(
            MediaParsing.scriptingBundleID(
                for: "com.google.Chrome.app.youtube"
            ) == "com.google.Chrome"
        )
    }

    @Test func websiteHostFromPayloadAndTabMatch() {
        #expect(
            MediaParsing.websiteHost(
                fromPayload: [
                    "uniqueIdentifier": 12_345,
                    "title": "SVJ At 18. - YouTube",
                ],
                title: "SVJ At 18. - YouTube",
                album: "",
                artist: "Josh Zitman"
            ) == "youtube.com"
        )
        #expect(
            MediaParsing.websiteHost(
                fromPayload: [
                    "uniqueIdentifier":
                        "https://www.youtube.com/watch?v=abc",
                    "artworkData": "aaaa",
                ],
                title: "SVJ At 18.",
                album: "",
                artist: ""
            ) == "youtube.com"
        )
        let tabs = MediaParsing.parseTabDump(
            """
            *\tSVJ At 18. · I Bought A Lambo - YouTube\thttps://www.youtube.com/watch?v=abc
            Inbox - Gmail\thttps://mail.google.com/mail
            """
        )
        #expect(tabs.count == 2)
        #expect(tabs[0].isCurrent)
        #expect(
            MediaParsing.websiteHost(
                matching: "SVJ At 18.",
                tabs: tabs
            ) == "youtube.com"
        )
        #expect(
            MediaParsing.stringValue(NSNumber(value: 99)) == "99"
        )
        #expect(
            MediaParsing.websiteHost(
                fromBrowserTitle:
                    "SVJ At 18. · I Bought A Lambo - YouTube — Mozilla Firefox"
            ) == "youtube.com"
        )
        #expect(
            MediaParsing.websiteHost(
                matching: "SVJ At 18.",
                tabs: [
                    .init(
                        title:
                            "SVJ At 18. · I Bought A Lambo - YouTube — Mozilla Firefox",
                        url: "",
                        isCurrent: true
                    )
                ]
            ) == "youtube.com"
        )
        #expect(MediaParsing.prefersAccessibilityTabs("org.mozilla.firefox"))
        #expect(!MediaParsing.prefersAccessibilityTabs("com.google.Chrome"))
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
