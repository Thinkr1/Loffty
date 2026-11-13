//
//  LyricsTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Lyrics")
struct LyricsTests {
    @Test func parsesTimestampsAndSkipsMetadata() {
        let lines = LyricsParsing.parseLRC(
            """
            [ar:Gims]
            [ti:Ciel]
            [00:12.50] Ciel
            [00:15.00]
            [01:02.25]Ciel, ciel
            """
        )
        #expect(lines.map(\.time) == [12.5, 15, 62.25])
        #expect(lines.map(\.text) == ["Ciel", "", "Ciel, ciel"])
        #expect(lines[1].isBreak)
        #expect(lines.map(\.id) == [0, 1, 2])
    }

    @Test func repeatedTimestampsExpandAndSort() {
        let lines = LyricsParsing.parseLRC(
            """
            [00:30.00][00:10.00] Chorus
            [00:20.00] Verse
            """
        )
        #expect(lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
        #expect(lines.map(\.time) == [10, 20, 30])
    }

    @Test func activeIndexFollowsPlaybackTime() {
        let lines = LyricsParsing.parseLRC(
            "[00:10.00] a\n[00:20.00] b\n[00:30.00] c"
        )
        #expect(LyricsParsing.activeIndex(in: lines, at: 5) == nil)
        #expect(LyricsParsing.activeIndex(in: lines, at: 10) == 0)
        #expect(LyricsParsing.activeIndex(in: lines, at: 19.9) == 1)
        #expect(LyricsParsing.activeIndex(in: lines, at: 45) == 2)
    }

    @Test func bestMatchPrefersSyncedWithCloseDuration() {
        let records = [
            LRCLibClient.Record(
                duration: 170,
                plainLyrics: "plain",
                syncedLyrics: nil
            ),
            LRCLibClient.Record(
                duration: 240,
                plainLyrics: "far",
                syncedLyrics: "[00:01.00] far"
            ),
            LRCLibClient.Record(
                duration: 171,
                plainLyrics: "close",
                syncedLyrics: "[00:01.00] close"
            ),
        ]
        let best = LRCLibClient.bestMatch(in: records, duration: 170)
        #expect(best?.plainLyrics == "close")
    }

    @Test func bestMatchSkipsInstrumentals() {
        let records = [
            LRCLibClient.Record(
                duration: 170,
                instrumental: true,
                plainLyrics: nil,
                syncedLyrics: nil
            )
        ]
        #expect(LRCLibClient.bestMatch(in: records, duration: 170) == nil)
    }

    @Test func recordFallsBackToPlainLyrics() {
        let lyrics = LRCLibClient.lyrics(
            from: LRCLibClient.Record(
                plainLyrics: "One\nTwo",
                syncedLyrics: nil
            )
        )
        #expect(lyrics?.isSynced == false)
        #expect(lyrics?.lines.map(\.text) == ["One", "Two"])
    }
}
