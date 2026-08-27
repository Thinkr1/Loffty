//
//  RecentPlayback.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 27/08/2026.
//

import AppKit
import Combine
import Foundation

enum IdlePlayApp: String, CaseIterable, Identifiable {
    case automatic
    case appleMusic
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .automatic: nil
        case .appleMusic: AppleMusicTrack.clientBundle
        case .spotify: SpotifyTrack.clientBundle
        }
    }
}

enum IdleNotchLayout {
    static let suggestionCount = 5
    static let suggestionArt: CGFloat = 48
    static let suggestionSpacing: CGFloat = 6
    static let playWidth: CGFloat = 56
    static let playHeight: CGFloat = 34
    static let playCornerRadius: CGFloat = 12
    static let suggestionsBody: CGFloat = 186
}

struct RecentPlaybackItem: Equatable, Codable, Identifiable {
    var trackKey: String
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String
    var contentItemIdentifier: String
    var artwork: Data?
    var playedAt: Date

    var id: String { trackKey }

    static func from(_ np: NowPlaying) -> RecentPlaybackItem? {
        guard !np.title.isEmpty else { return nil }
        let bundle = np.resolvedBundleIdentifier
        let key =
            np.trackKey.isEmpty ? "\(bundle)|\(np.title)" : np.trackKey
        return RecentPlaybackItem(
            trackKey: key,
            title: np.title,
            artist: np.artist,
            album: np.album,
            bundleIdentifier: bundle,
            contentItemIdentifier: np.contentItemIdentifier,
            artwork: np.artwork,
            playedAt: Date()
        )
    }
}

enum IdleMediaLaunch {
    static func preferredBundleID(
        app: IdlePlayApp,
        lastPlayedBundle: String?,
        installed: (String) -> Bool = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                != nil
        }
    ) -> String {
        if let exact = app.bundleIdentifier { return exact }
        let music = AppleMusicTrack.clientBundle
        let spotify = SpotifyTrack.clientBundle
        if lastPlayedBundle == spotify, installed(spotify) { return spotify }
        if lastPlayedBundle == music, installed(music) { return music }
        if installed(music) { return music }
        if installed(spotify) { return spotify }
        return lastPlayedBundle?.isEmpty == false
            ? lastPlayedBundle!
            : music
    }

    static func openURL(for item: RecentPlaybackItem) -> URL? {
        if let id = SpotifyTrack.id(from: item.contentItemIdentifier) {
            return URL(string: "spotify:track:\(id)")
        }
        guard let url = URL(string: item.contentItemIdentifier),
            let scheme = url.scheme, !scheme.isEmpty,
            scheme != "http", scheme != "https"
        else { return nil }
        return url
    }

    @discardableResult
    static func open(bundleID: String) -> Bool {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            )
        else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    static func openPreferred(
        app: IdlePlayApp,
        lastPlayedBundle: String?
    ) {
        open(
            bundleID: preferredBundleID(
                app: app,
                lastPlayedBundle: lastPlayedBundle
            )
        )
    }

    static func open(_ item: RecentPlaybackItem) {
        if let url = openURL(for: item) {
            NSWorkspace.shared.open(url)
            return
        }
        if !item.bundleIdentifier.isEmpty {
            open(bundleID: item.bundleIdentifier)
        }
    }
}

@MainActor
final class RecentPlaybackCache: ObservableObject {
    static let shared = RecentPlaybackCache()

    @Published private(set) var items: [RecentPlaybackItem] = []

    private let fileURL: URL
    private let maxStored: Int

    init(fileURL: URL? = nil, maxStored: Int = 12) {
        self.maxStored = max(1, maxStored)
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
        load()
    }

    var suggestions: [RecentPlaybackItem] {
        Self.pick(from: items, limit: IdleNotchLayout.suggestionCount)
    }

    func record(_ np: NowPlaying, enabled: Bool) {
        guard enabled, let item = RecentPlaybackItem.from(np) else { return }
        if let index = items.firstIndex(where: { $0.trackKey == item.trackKey })
        {
            var updated = items[index]
            let artworkChanged =
                item.artwork != nil && item.artwork != updated.artwork
            let metaChanged =
                updated.title != item.title
                || updated.artist != item.artist
                || updated.album != item.album
                || updated.bundleIdentifier != item.bundleIdentifier
                || updated.contentItemIdentifier != item.contentItemIdentifier
            if index == 0, !artworkChanged, !metaChanged { return }
            updated.title = item.title
            updated.artist = item.artist
            updated.album = item.album
            updated.bundleIdentifier = item.bundleIdentifier
            updated.contentItemIdentifier = item.contentItemIdentifier
            updated.playedAt = item.playedAt
            if artworkChanged { updated.artwork = item.artwork }
            items.remove(at: index)
            items.insert(updated, at: 0)
        } else {
            items.insert(item, at: 0)
            if items.count > maxStored {
                items = Array(items.prefix(maxStored))
            }
        }
        persist()
    }

    nonisolated static func pick(from items: [RecentPlaybackItem], limit: Int)
        -> [RecentPlaybackItem]
    {
        guard limit > 0 else { return [] }
        var picked: [RecentPlaybackItem] = []
        var seenBundles = Set<String>()
        for item in items {
            if picked.count >= limit { break }
            let bundle = item.bundleIdentifier
            if !bundle.isEmpty, seenBundles.contains(bundle) { continue }
            picked.append(item)
            if !bundle.isEmpty { seenBundles.insert(bundle) }
        }
        for item in items {
            if picked.count >= limit { break }
            if picked.contains(where: { $0.trackKey == item.trackKey }) {
                continue
            }
            picked.append(item)
        }
        return picked
    }

    static func defaultFileURL() -> URL {
        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("Loffty", isDirectory: true)
        return folder.appendingPathComponent(
            "recent-playback.json",
            isDirectory: false
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(
                [RecentPlaybackItem].self,
                from: data
            )
        else { return }
        items = decoded
    }

    private func persist() {
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
