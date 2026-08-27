//
//  RecentPlaybackTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Recent playback")
struct RecentPlaybackTests {
    @Test func itemFromNowPlayingRequiresTitle() {
        var np = NowPlaying()
        #expect(RecentPlaybackItem.from(np) == nil)
        np.title = "Song"
        np.artist = "Artist"
        np.bundleIdentifier = AppleMusicTrack.clientBundle
        np.trackKey = "com.apple.Music|Song"
        let item = RecentPlaybackItem.from(np)
        #expect(item?.title == "Song")
        #expect(item?.artist == "Artist")
        #expect(item?.bundleIdentifier == AppleMusicTrack.clientBundle)
        #expect(item?.trackKey == "com.apple.Music|Song")
    }

    @Test func pickPrefersDifferentSourcesThenFills() {
        let music = item(
            key: "m1",
            title: "One",
            bundle: AppleMusicTrack.clientBundle
        )
        let spotify = item(
            key: "s1",
            title: "Two",
            bundle: SpotifyTrack.clientBundle
        )
        let music2 = item(
            key: "m2",
            title: "Three",
            bundle: AppleMusicTrack.clientBundle
        )
        let picked = RecentPlaybackCache.pick(
            from: [music, music2, spotify],
            limit: 3
        )
        #expect(picked.map(\.trackKey) == ["m1", "s1", "m2"])
    }

    @Test func pickStopsAtLimit() {
        let items = (0..<6).map {
            item(key: "k\($0)", title: "T\($0)", bundle: "app.\($0)")
        }
        #expect(RecentPlaybackCache.pick(from: items, limit: 3).count == 3)
        #expect(
            RecentPlaybackCache.pick(
                from: items,
                limit: IdleNotchLayout.suggestionCount
            ).count == 5
        )
        #expect(RecentPlaybackCache.pick(from: items, limit: 0).isEmpty)
    }

    @Test @MainActor func cacheRecordsNewestFirstAndDedupes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = RecentPlaybackCache(fileURL: url, maxStored: 3)

        var first = NowPlaying()
        first.title = "Alpha"
        first.bundleIdentifier = AppleMusicTrack.clientBundle
        first.trackKey = "music|Alpha"
        cache.record(first, enabled: true)

        var second = NowPlaying()
        second.title = "Beta"
        second.bundleIdentifier = SpotifyTrack.clientBundle
        second.trackKey = "spotify|Beta"
        cache.record(second, enabled: true)

        #expect(cache.items.map(\.title) == ["Beta", "Alpha"])

        first.artist = "Updated"
        cache.record(first, enabled: true)
        #expect(cache.items.map(\.title) == ["Alpha", "Beta"])
        #expect(cache.items.first?.artist == "Updated")

        cache.record(first, enabled: false)
        #expect(cache.items.count == 2)
    }

    @Test @MainActor func cacheIgnoresEmptyTitlesAndCapsLength() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-cap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = RecentPlaybackCache(fileURL: url, maxStored: 2)
        cache.record(NowPlaying(), enabled: true)
        #expect(cache.items.isEmpty)

        for name in ["A", "B", "C"] {
            var np = NowPlaying()
            np.title = name
            np.trackKey = "k|\(name)"
            np.bundleIdentifier = "app"
            cache.record(np, enabled: true)
        }
        #expect(cache.items.map(\.title) == ["C", "B"])
    }

    @Test @MainActor func cacheRoundTripsToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-disk-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecentPlaybackCache(fileURL: url, maxStored: 4)
        var np = NowPlaying()
        np.title = "Stored"
        np.artist = "Band"
        np.trackKey = "music|Stored"
        np.bundleIdentifier = AppleMusicTrack.clientBundle
        writer.record(np, enabled: true)

        let reader = RecentPlaybackCache(fileURL: url, maxStored: 4)
        #expect(reader.items.first?.title == "Stored")
        #expect(reader.items.first?.artist == "Band")
    }

    @Test func preferredBundleUsesLastSourceThenMusic() {
        let installed: (String) -> Bool = { _ in true }
        #expect(
            IdleMediaLaunch.preferredBundleID(
                app: .appleMusic,
                lastPlayedBundle: SpotifyTrack.clientBundle,
                installed: installed
            ) == AppleMusicTrack.clientBundle
        )
        #expect(
            IdleMediaLaunch.preferredBundleID(
                app: .spotify,
                lastPlayedBundle: AppleMusicTrack.clientBundle,
                installed: installed
            ) == SpotifyTrack.clientBundle
        )
        #expect(
            IdleMediaLaunch.preferredBundleID(
                app: .automatic,
                lastPlayedBundle: SpotifyTrack.clientBundle,
                installed: installed
            ) == SpotifyTrack.clientBundle
        )
        #expect(
            IdleMediaLaunch.preferredBundleID(
                app: .automatic,
                lastPlayedBundle: nil,
                installed: installed
            ) == AppleMusicTrack.clientBundle
        )
        #expect(
            IdleMediaLaunch.preferredBundleID(
                app: .automatic,
                lastPlayedBundle: nil,
                installed: { $0 == SpotifyTrack.clientBundle }
            ) == SpotifyTrack.clientBundle
        )
    }

    @Test func suggestionOpenURLUsesSpotifyTrack() {
        var item = item(
            key: "s",
            title: "Track",
            bundle: SpotifyTrack.clientBundle
        )
        item.contentItemIdentifier = "spotify:track:abc123"
        #expect(
            IdleMediaLaunch.openURL(for: item)?.absoluteString
                == "spotify:track:abc123"
        )
        item.contentItemIdentifier = "https://open.spotify.com/track/abc123"
        #expect(
            IdleMediaLaunch.openURL(for: item)?.absoluteString
                == "spotify:track:abc123"
        )
        item.contentItemIdentifier = ""
        #expect(IdleMediaLaunch.openURL(for: item) == nil)
    }

    private func item(key: String, title: String, bundle: String)
        -> RecentPlaybackItem
    {
        RecentPlaybackItem(
            trackKey: key,
            title: title,
            artist: "",
            album: "",
            bundleIdentifier: bundle,
            contentItemIdentifier: "",
            artwork: nil,
            playedAt: Date()
        )
    }
}
