//
//  Media.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

// INSTALL ungive/media-control (homebrew)

import SwiftUI

private enum SpotifyMetadata {
    static func currentTrackID() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [
            "-e", "tell application \"Spotify\" to get id of current track",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            raw.hasPrefix("spotify:track:")
        else { return nil }
        return String(raw.dropFirst("spotify:track:".count))
    }

    static func fetchArtists(trackID: String) async -> String? {
        guard
            let url = URL(
                string: "https://open.spotify.com/embed/track/\(trackID)"
            )
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard
            let (data, response) = try? await URLSession.shared.data(
                for: request
            ),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let html = String(data: data, encoding: .utf8)
        else { return nil }
        return parseArtistNames(from: html)
    }

    private static func parseArtistNames(from html: String) -> String? {
        guard let start = html.range(of: "\"artists\":[") else { return nil }
        var slice = html[start.upperBound...]
        guard let end = slice.firstIndex(of: "]") else { return nil }
        slice = slice[..<end]
        var names: [String] = []
        var rest = Substring(slice)
        while let marker = rest.range(of: "\"name\":\"") {
            let after = rest[marker.upperBound...]
            guard let endQuote = after.firstIndex(of: "\"") else { break }
            let name = String(after[..<endQuote])
            if !name.isEmpty { names.append(name) }
            rest = after[endQuote...].dropFirst()
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var elapsed: Double = 0
    var elapsedTimestamp: Date? = nil
    var playbackRate: Double = 1
    var duration: Double = 0
    var isLive: Bool = false
    var trackKey: String = ""
    var artwork: Data? = nil
    var artworkUnavailable: Bool = true
}

final class NowPlayingStream {
    var onUpdate: ((NowPlaying) -> Void)?
    private var process: Process?
    private var current = NowPlaying()
    private var buf = Data()
    private var lastEnrichedTrackID: String?
    private var lastSpotifyEnrichmentKey: String?
    private var lastSpotifyInfo: [String: Any]?
    private var lastTrackKey: String?
    private var enrichmentTask: Task<Void, Never>?
    private var artworkPollTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "Loffty.NowPlayingStream")
    private static let elapsedOnlyKeys: Set<String> = [
        "elapsedTime", "timestamp", "playbackRate", "elapsedTimeNow",
    ]
    private let tsFormatter = ISO8601DateFormatter()
    private let pth = "/opt/homebrew/bin/media-control"
    func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pth)
        p.arguments = ["stream"]
        let pipe = Pipe()
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            self.queue.async {
                self.buf.append(data)
                while let nl = self.buf.firstIndex(of: 0x0A) {
                    let line = self.buf[self.buf.startIndex..<nl]
                    self.buf.removeSubrange(self.buf.startIndex...nl)
                    guard !line.isEmpty,
                        let obj = try? JSONSerialization.jsonObject(with: line)
                            as? [String: Any]
                    else { continue }
                    self.ingest(obj)
                }
            }
        }
        try? p.run()
        process = p
    }

    private func ingest(_ obj: [String: Any]) {
        let isDiff = obj["diff"] as? Bool ?? false
        let info = (obj["payload"] as? [String: Any]) ?? obj
        var trackChanged = false

        if let incomingKey = trackKey(from: info, isDiff: isDiff) {
            trackChanged = incomingKey != lastTrackKey
            if trackChanged {
                lastTrackKey = incomingKey
                lastSpotifyEnrichmentKey = nil
                lastEnrichedTrackID = nil
                enrichmentTask?.cancel()
                cancelArtworkPolling()
                if info["bundleIdentifier"] as? String != "com.spotify.client" {
                    lastSpotifyInfo = nil
                }
            }
            applyTrackFields(
                from: info,
                isDiff: isDiff,
                trackChanged: trackChanged
            )
        } else {
            applyTrackFields(from: info, isDiff: isDiff, trackChanged: false)
        }

        var playStateChanged = false
        if let pl = info["playing"] as? Bool {
            playStateChanged = pl != current.isPlaying
            current.isPlaying = pl
        }
        applyElapsed(from: info)
        if let d = info["duration"] as? NSNumber {
            current.duration = d.doubleValue
        }
        applyLiveState(from: info, isDiff: isDiff, trackChanged: trackChanged)
        current.trackKey = lastTrackKey ?? ""
        if shouldPublish(
            info: info,
            isDiff: isDiff,
            trackChanged: trackChanged,
            playStateChanged: playStateChanged
        ) {
            onUpdate?(current)
        }
        enrichSpotifyArtistsIfNeeded(from: info)
        scheduleArtworkPollingIfNeeded()
    }

    private func shouldPublish(
        info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool,
        playStateChanged: Bool
    ) -> Bool {
        if trackChanged || playStateChanged { return true }
        if !isDiff { return true }
        let keys = Set(info.keys.map { String($0) })
        if keys.isSubset(of: Self.elapsedOnlyKeys), current.isPlaying {
            return false
        }
        return true
    }

    private func applyLiveState(
        from info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool
    ) {
        let liveKeys = [
            "duration", "mediaType", "radioStationIdentifier",
            "radioStationHash", "title",
        ]
        if isDiff, !trackChanged,
            !liveKeys.contains(where: { info.keys.contains($0) })
        {
            return
        }
        current.isLive = parseIsLive(from: info)
    }

    private func parseIsLive(from info: [String: Any]) -> Bool {
        if let station = info["radioStationIdentifier"], !(station is NSNull) {
            return true
        }
        if let hash = info["radioStationHash"], !(hash is NSNull) {
            return true
        }
        if let mt = info["mediaType"] as? String,
            mt.localizedCaseInsensitiveContains("radio")
        {
            return true
        }
        let duration =
            (info["duration"] as? NSNumber)?.doubleValue ?? current.duration
        let title = (info["title"] as? String) ?? current.title
        if duration <= 0, !title.isEmpty {
            return true
        }
        return false
    }

    private func applyElapsed(from info: [String: Any]) {
        if let rate = info["playbackRate"] as? NSNumber {
            current.playbackRate = max(0, rate.doubleValue)
        }
        if let e = info["elapsedTime"] as? NSNumber {
            current.elapsed = e.doubleValue
            if let ts = parseTimestamp(info["timestamp"]) {
                current.elapsedTimestamp = ts
            } else if info.keys.contains("elapsedTime") {
                current.elapsedTimestamp = Date()
            }
        }
    }

    private func parseTimestamp(_ value: Any?) -> Date? {
        if let d = value as? Date { return d }
        guard let raw = value as? String else { return nil }
        tsFormatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let d = tsFormatter.date(from: raw) { return d }
        tsFormatter.formatOptions = [.withInternetDateTime]
        return tsFormatter.date(from: raw)
    }

    private func trackKey(from info: [String: Any], isDiff: Bool) -> String? {
        let title = info["title"] as? String
        let bundle = info["bundleIdentifier"] as? String ?? ""
        guard title != nil || !bundle.isEmpty else {
            return isDiff ? nil : lastTrackKey
        }
        let resolvedTitle = title ?? current.title
        guard !resolvedTitle.isEmpty || !bundle.isEmpty else {
            return isDiff ? nil : lastTrackKey
        }
        return "\(bundle)|\(resolvedTitle)"
    }

    private func applyTrackFields(
        from info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool
    ) {
        if let t = info["title"] as? String { current.title = t }

        if isDiff {
            if info["artist"] is NSNull || info["artists"] is NSNull {
                current.artist = ""
            } else if info.keys.contains("artist")
                || info.keys.contains("artists")
            {
                current.artist = parseArtist(from: info) ?? ""
            } else if trackChanged {
                current.artist = ""
            }
        } else {
            current.artist = parseArtist(from: info) ?? ""
        }

        if trackChanged {
            current.artworkUnavailable = false
        }
        applyArtwork(from: info, trackChanged: trackChanged)

        if isDiff {
            if info["album"] is NSNull {
                current.album = ""
            } else if let al = info["album"] as? String {
                current.album = al
            } else if trackChanged {
                current.album = ""
            }
        } else if let al = info["album"] as? String {
            current.album = al
        } else {
            current.album = ""
        }
    }

    private func parseArtist(from info: [String: Any]) -> String? {
        if let artists = info["artists"] as? [String], !artists.isEmpty {
            return artists.joined(separator: ", ")
        }
        if let artists = info["artists"] as? [[String: Any]] {
            let names = artists.compactMap { $0["name"] as? String }
                .filter { !$0.isEmpty }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        if let artist = info["artist"] as? String, !artist.isEmpty {
            return artist
        }
        if let artists = info["artist"] as? [String], !artists.isEmpty {
            return artists.joined(separator: ", ")
        }
        return nil
    }

    private func applyArtwork(from info: [String: Any], trackChanged: Bool) {
        if info["artworkData"] is NSNull {
            guard trackChanged else { return }
            current.artwork = nil
            current.artworkUnavailable = true
            cancelArtworkPolling()
            return
        }
        guard let b64 = info["artworkData"] as? String, !b64.isEmpty,
            let data = Data(base64Encoded: b64)
        else {
            if trackChanged { current.artwork = nil }
            return
        }
        current.artwork = ArtworkProcessor.thumbnailData(from: data)
        current.artworkUnavailable = false
        cancelArtworkPolling()
    }

    private func enrichSpotifyArtistsIfNeeded(from info: [String: Any]) {
        guard info["bundleIdentifier"] as? String == "com.spotify.client" else {
            return
        }
        lastSpotifyInfo = info
        guard ArtistEnrichmentMode.current.allowsNetworkFetch else {
            enrichmentTask?.cancel()
            return
        }
        let key =
            "\(info["title"] as? String ?? "")|\(info["contentItemIdentifier"] as? String ?? "")"
        guard key != lastSpotifyEnrichmentKey else { return }
        lastSpotifyEnrichmentKey = key

        enrichmentTask?.cancel()
        enrichmentTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard ArtistEnrichmentMode.current.allowsNetworkFetch else {
                return
            }
            guard let trackID = SpotifyMetadata.currentTrackID() else { return }
            guard !Task.isCancelled else { return }
            guard
                let artists = await SpotifyMetadata.fetchArtists(
                    trackID: trackID
                )
            else { return }
            guard !Task.isCancelled else { return }
            guard ArtistEnrichmentMode.current.allowsNetworkFetch else {
                return
            }
            self.queue.async {
                guard !Task.isCancelled else { return }
                guard self.lastEnrichedTrackID != trackID else { return }
                self.lastEnrichedTrackID = trackID
                guard self.current.artist != artists else { return }
                self.current.artist = artists
                self.onUpdate?(self.current)
            }
        }
    }

    func refreshArtistEnrichment() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastSpotifyEnrichmentKey = nil
            self.lastEnrichedTrackID = nil
            self.enrichmentTask?.cancel()
            guard let info = self.lastSpotifyInfo else { return }
            if ArtistEnrichmentMode.current.allowsNetworkFetch {
                self.enrichSpotifyArtistsIfNeeded(from: info)
            } else {
                let artist = self.parseArtist(from: info) ?? ""
                if self.current.artist != artist {
                    self.current.artist = artist
                    self.onUpdate?(self.current)
                }
            }
        }
    }

    private func scheduleArtworkPollingIfNeeded() {
        guard current.artwork == nil, !current.artworkUnavailable else {
            cancelArtworkPolling()
            return
        }
        guard artworkPollTask == nil, let trackKeyAtStart = lastTrackKey else {
            return
        }

        artworkPollTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.queue.async { self.artworkPollTask = nil }
            }
            var delay: Duration = .milliseconds(500)
            var attempts = 0
            let maxAttempts = 6
            while !Task.isCancelled, attempts < maxAttempts {
                if attempts > 0 {
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, .seconds(4))
                }
                attempts += 1
                guard !Task.isCancelled else { return }

                let info = self.fetchNowPlaying()
                let applied: Bool = await withCheckedContinuation { cont in
                    self.queue.async {
                        guard self.lastTrackKey == trackKeyAtStart,
                            self.current.artwork == nil,
                            !self.current.artworkUnavailable
                        else {
                            cont.resume(returning: true)
                            return
                        }
                        guard let info,
                            self.trackKey(from: info, isDiff: false)
                                == trackKeyAtStart
                        else {
                            cont.resume(returning: true)
                            return
                        }
                        if info["artworkData"] is NSNull {
                            cont.resume(returning: false)
                            return
                        }
                        if let b64 = info["artworkData"] as? String,
                            !b64.isEmpty,
                            let data = Data(base64Encoded: b64)
                        {
                            self.current.artwork =
                                ArtworkProcessor.thumbnailData(
                                    from: data
                                )
                            self.current.artworkUnavailable = false
                            self.onUpdate?(self.current)
                            cont.resume(returning: true)
                            return
                        }
                        cont.resume(returning: false)
                    }
                }
                if applied { return }
            }
        }
    }

    private func fetchNowPlaying(now: Bool = false) -> [String: Any]? {
        var args = ["get", "--no-artwork"]
        if now { args.append("--now") }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pth)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if obj is NSNull { return nil }
        return obj as? [String: Any]
    }

    private func cancelArtworkPolling() {
        artworkPollTask?.cancel()
        artworkPollTask = nil
    }

    func stop() {
        enrichmentTask?.cancel()
        cancelArtworkPolling()
        process?.terminate()
    }
}

final class MediaCommands {
    private typealias SendCmd = @convention(c) (Int, [String: Any]?) -> Bool
    private typealias SetTime = @convention(c) (Double) -> Void
    private let send: SendCmd?
    private let setTime: SetTime?

    init() {
        let pth = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: pth)
            ),
            let ptr = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSendCommand" as CFString
            )
        else {
            send = nil
            setTime = nil
            return
        }
        send = unsafeBitCast(ptr, to: SendCmd.self)
        if let tptr = CFBundleGetFunctionPointerForName(
            bundle,
            "MRMediaRemoteSetElapsedTime" as CFString
        ) {
            setTime = unsafeBitCast(tptr, to: SetTime.self)
        } else {
            setTime = nil
        }
    }

    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case next = 4
        case prev = 5
    }

    @discardableResult
    func perform(_ c: Command) -> Bool { send?(c.rawValue, nil) ?? false }
    func setElapsed(_ t: Double) { setTime?(t) }
}

final class MediaController {
    var onUpdate: ((NowPlaying) -> Void)?
    private let reader = NowPlayingStream()
    private let commands = MediaCommands()

    func start() {
        reader.onUpdate = { [weak self] in self?.onUpdate?($0) }
        reader.start()
    }

    func command(_ c: MediaCommands.Command) { commands.perform(c) }
    func setElapsed(_ t: Double) { commands.setElapsed(t) }
    func refreshArtistEnrichment() { reader.refreshArtistEnrichment() }
}
