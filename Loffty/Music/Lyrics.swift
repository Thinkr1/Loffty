//
//  Lyrics.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 08/11/2026.
//

import Combine
import Foundation

struct LyricLine: Equatable, Identifiable, Sendable {
    let id: Int
    let time: Double
    let text: String

    var isBreak: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct Lyrics: Equatable, Sendable {
    var lines: [LyricLine]
    var isSynced: Bool
}

enum LyricsParsing {
    nonisolated static func parseLRC(_ raw: String) -> [LyricLine] {
        var timed: [(Double, String)] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            var rest = Substring(rawLine)
            var stamps: [Double] = []
            while rest.hasPrefix("["),
                let close = rest.firstIndex(of: "]")
            {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let seconds = timestamp(tag) else { break }
                stamps.append(seconds)
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for stamp in stamps { timed.append((stamp, text)) }
        }
        return
            timed
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map {
                LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1)
            }
    }

    nonisolated static func parsePlain(_ raw: String) -> [LyricLine] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: 0, text: $0.element) }
    }

    nonisolated static func activeIndex(
        in lines: [LyricLine],
        at time: Double,
        lead: Double = 0.2
    ) -> Int? {
        let target = time + lead
        var result: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= target {
                result = index
            } else {
                break
            }
        }
        return result
    }

    nonisolated private static func timestamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
            let minutes = Double(parts[0]),
            let seconds = Double(
                parts[1].replacingOccurrences(of: ",", with: ".")
            )
        else { return nil }
        return minutes * 60 + seconds
    }
}

enum LRCLibClient {
    struct Record: Decodable, Equatable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    private static let base = "https://lrclib.net/api"

    nonisolated static func lyrics(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) async -> Lyrics? {
        if duration > 0, !album.isEmpty,
            let record = await get(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            ),
            let lyrics = lyrics(from: record)
        {
            return lyrics
        }
        let results = await search(title: title, artist: artist)
        guard let best = bestMatch(in: results, duration: duration) else {
            return nil
        }
        return lyrics(from: best)
    }

    nonisolated static func lyrics(from record: Record) -> Lyrics? {
        if let synced = record.syncedLyrics {
            let lines = LyricsParsing.parseLRC(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, isSynced: true) }
        }
        if let plain = record.plainLyrics,
            !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return Lyrics(
                lines: LyricsParsing.parsePlain(plain),
                isSynced: false
            )
        }
        return nil
    }

    nonisolated static func bestMatch(in records: [Record], duration: Double)
        -> Record?
    {
        let usable = records.filter {
            $0.instrumental != true
                && ($0.syncedLyrics != nil || $0.plainLyrics != nil)
        }
        func distance(_ record: Record) -> Double {
            guard duration > 0, let d = record.duration else { return 0 }
            return abs(d - duration)
        }
        let close = usable.filter { duration <= 0 || distance($0) <= 4 }
        let pool = close.isEmpty ? usable : close
        return pool.min { lhs, rhs in
            let lhsSynced = lhs.syncedLyrics != nil
            let rhsSynced = rhs.syncedLyrics != nil
            if lhsSynced != rhsSynced { return lhsSynced }
            return distance(lhs) < distance(rhs)
        }
    }

    nonisolated private static func get(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) async -> Record? {
        var components = URLComponents(string: "\(base)/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(
                name: "duration",
                value: String(Int(duration.rounded()))
            ),
        ]
        guard let data = await fetch(components?.url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    nonisolated private static func search(title: String, artist: String) async
        -> [Record]
    {
        var components = URLComponents(string: "\(base)/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let data = await fetch(components?.url) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    nonisolated private static func fetch(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            )
            as? String ?? "1.0"
        request.setValue(
            "Loffty/\(version) (macOS)",
            forHTTPHeaderField: "User-Agent"
        )
        guard
            let (data, response) = try? await URLSession.shared.data(
                for: request
            ),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else { return nil }
        return data
    }
}

@MainActor
final class LyricsStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case unavailable
    }

    static let shared = LyricsStore()

    @Published private(set) var state: State = .idle

    private var cache: [String: Lyrics?] = [:]
    private var cacheOrder: [String] = []
    private var currentKey = ""
    private var task: Task<Void, Never>?

    func load(for np: NowPlaying) {
        let key = Self.key(for: np)
        guard !np.title.isEmpty else {
            currentKey = ""
            task?.cancel()
            state = .idle
            return
        }
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        if let cached = cache[key] {
            state = cached.map(State.loaded) ?? .unavailable
            return
        }
        state = .loading
        let title = np.title
        let artist = np.artist
        let album = np.album
        let duration = np.duration
        let isMusic =
            np.resolvedBundleIdentifier == AppleMusicTrack.clientBundle
        task = Task { [weak self] in
            var lyrics = await LRCLibClient.lyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            if lyrics == nil, isMusic,
                let plain = await AppleMusicLibrary.currentTrackLyrics()
            {
                lyrics = Lyrics(
                    lines: LyricsParsing.parsePlain(plain),
                    isSynced: false
                )
            }
            guard !Task.isCancelled, let self, self.currentKey == key else {
                return
            }
            self.remember(lyrics, for: key)
            self.state = lyrics.map(State.loaded) ?? .unavailable
        }
    }

    private func remember(_ lyrics: Lyrics?, for key: String) {
        cache[key] = lyrics
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > 20 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func key(for np: NowPlaying) -> String {
        "\(np.artist)|\(np.title)|\(np.album)"
    }
}
