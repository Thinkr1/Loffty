//
//  Media.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import SwiftUI

enum MediaParsing {
    static func parseArtistNames(from html: String) -> String? {
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

    static func parseArtist(from info: [String: Any]) -> String? {
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

    static func parseIsLive(
        from info: [String: Any],
        currentDuration: Double = 0,
        currentTitle: String = ""
    ) -> Bool {
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
            (info["duration"] as? NSNumber)?.doubleValue ?? currentDuration
        let title = (info["title"] as? String) ?? currentTitle
        if duration <= 0, !title.isEmpty {
            return true
        }
        return false
    }

    static func isIdlePayload(_ info: [String: Any], isDiff: Bool) -> Bool {
        if isDiff {
            return info["title"] is NSNull
        }
        if let title = info["title"] as? String { return title.isEmpty }
        if info.isEmpty { return true }
        if info["artworkData"] != nil || info["bundleIdentifier"] != nil
            || info["playing"] != nil
        {
            return false
        }
        return true
    }

    static let elapsedOnlyKeys: Set<String> = [
        "elapsedTime", "timestamp", "playbackRate", "elapsedTimeNow",
    ]

    static func isElapsedOnlyDiff(_ info: [String: Any]) -> Bool {
        Set(info.keys.map { String($0) }).isSubset(of: elapsedOnlyKeys)
    }

    static let seekJumpThreshold: Double = 1.35

    static func trackKey(
        title: String?,
        bundle: String,
        currentTitle: String,
        lastKey: String?,
        isDiff: Bool
    ) -> String? {
        guard title != nil || !bundle.isEmpty else {
            return isDiff ? nil : lastKey
        }
        let resolvedTitle = title ?? currentTitle
        guard !resolvedTitle.isEmpty || !bundle.isEmpty else {
            return isDiff ? nil : lastKey
        }
        return "\(bundle)|\(resolvedTitle)"
    }

    static func parseTimestamp(_ value: Any?) -> Date? {
        if let d = value as? Date { return d }
        guard let raw = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let d = formatter.date(from: raw) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func expectedElapsed(
        publishedElapsed: Double,
        publishedTimestamp: Date?,
        publishedRate: Double,
        publishedIsPlaying: Bool,
        at date: Date
    ) -> Double {
        let rate = publishedIsPlaying ? max(0, publishedRate) : 0
        if let ts = publishedTimestamp {
            return publishedElapsed + date.timeIntervalSince(ts) * rate
        }
        return publishedElapsed
    }

    static func hasSignificantElapsedDiscontinuity(
        expected: Double,
        actual: Double,
        threshold: Double = seekJumpThreshold
    ) -> Bool {
        abs(actual - expected) >= threshold
    }
}

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
        return MediaParsing.parseArtistNames(from: html)
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
    var bundleIdentifier: String = ""
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
    private var idlePollTask: Task<Void, Never>?
    private var idleClearTask: Task<Void, Never>?
    private var idleClearGeneration: UInt = 0
    private var suppressStaleStream = false
    private let queue = DispatchQueue(label: "Loffty.NowPlayingStream")
    private var publishedElapsed: Double = 0
    private var publishedElapsedTimestamp: Date?
    private var publishedPlaybackRate: Double = 1
    private var publishedIsPlaying = false
    private static let pausedIdlePollInterval: Duration = .seconds(2)

    private struct AdapterLaunch {
        let executable: URL
        let baseArguments: [String]
    }

    private func adapterLaunch() -> AdapterLaunch? {
        let bundle = Bundle.main
        if let script = bundle.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl"
        ),
            let framework = bundle.url(
                forResource: "MediaRemoteAdapter",
                withExtension: "framework"
            )
        {
            return AdapterLaunch(
                executable: URL(fileURLWithPath: "/usr/bin/perl"),
                baseArguments: [script.path, framework.path]
            )
        }

        let brew = URL(fileURLWithPath: "/opt/homebrew/bin/media-control")  //fallback if bundle resources missing
        if FileManager.default.isExecutableFile(atPath: brew.path) {
            return AdapterLaunch(executable: brew, baseArguments: [])
        }
        return nil
    }

    private var hasDisplayableMedia: Bool {
        !current.title.isEmpty || current.artwork != nil
    }

    func start() {
        guard let launch = adapterLaunch() else { return }
        let p = Process()
        p.executableURL = launch.executable
        p.arguments = launch.baseArguments + ["stream"]
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
        startIdlePolling()
    }

    private func ingest(_ obj: [String: Any]) {
        let isDiff = obj["diff"] as? Bool ?? false
        let info = (obj["payload"] as? [String: Any]) ?? obj

        if MediaParsing.isIdlePayload(info, isDiff: isDiff) {
            if !suppressStaleStream { scheduleIdleClear() }
            return
        }

        if suppressStaleStream {
            if !MediaParsing.isIdlePayload(info, isDiff: isDiff) {
                confirmSuppressionLift(with: obj)
            }
            return
        }

        cancelIdleClear()

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
            rememberPublishedPlaybackClock()
            onUpdate?(current)
        }
        enrichSpotifyArtistsIfNeeded(from: info)
        scheduleArtworkPollingIfNeeded()

        if playStateChanged, !current.isPlaying, hasDisplayableMedia {
            verifyPausedStillPresent()
        }
    }

    private func fetchNowPlaying(
        now: Bool = false,
        artwork: Bool = false
    ) -> [String: Any]? {
        guard let launch = adapterLaunch() else { return nil }
        var args = launch.baseArguments + ["get"]
        if !artwork { args.append("--no-artwork") }
        if now { args.append("--now") }
        let proc = Process()
        proc.executableURL = launch.executable
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

    private func rememberPublishedPlaybackClock() {
        publishedElapsed = current.elapsed
        publishedElapsedTimestamp = current.elapsedTimestamp
        publishedPlaybackRate = current.playbackRate
        publishedIsPlaying = current.isPlaying
    }

    private func shouldPublish(
        info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool,
        playStateChanged: Bool
    ) -> Bool {
        if trackChanged || playStateChanged { return true }
        if !isDiff { return true }
        if MediaParsing.isElapsedOnlyDiff(info) {
            if info.keys.contains("playbackRate"),
                abs(current.playbackRate - publishedPlaybackRate) > 0.01
            {
                return true
            }
            if current.isPlaying {
                return hasSignificantElapsedDiscontinuity()
            }
        }
        return true
    }

    private func hasSignificantElapsedDiscontinuity() -> Bool {
        let now = Date()
        let expected = MediaParsing.expectedElapsed(
            publishedElapsed: publishedElapsed,
            publishedTimestamp: publishedElapsedTimestamp,
            publishedRate: publishedPlaybackRate,
            publishedIsPlaying: publishedIsPlaying,
            at: now
        )
        let actual = MediaParsing.expectedElapsed(
            publishedElapsed: current.elapsed,
            publishedTimestamp: current.elapsedTimestamp,
            publishedRate: current.playbackRate,
            publishedIsPlaying: current.isPlaying,
            at: now
        )
        return MediaParsing.hasSignificantElapsedDiscontinuity(
            expected: expected,
            actual: actual
        )
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
        current.isLive = MediaParsing.parseIsLive(
            from: info,
            currentDuration: current.duration,
            currentTitle: current.title
        )
    }

    private func applyElapsed(from info: [String: Any]) {
        if let rate = info["playbackRate"] as? NSNumber {
            current.playbackRate = max(0, rate.doubleValue)
        }
        if let e = info["elapsedTime"] as? NSNumber {
            current.elapsed = e.doubleValue
            if let ts = MediaParsing.parseTimestamp(info["timestamp"]) {
                current.elapsedTimestamp = ts
            } else if info.keys.contains("elapsedTime") {
                current.elapsedTimestamp = Date()
            }
        }
    }

    private func trackKey(from info: [String: Any], isDiff: Bool) -> String? {
        MediaParsing.trackKey(
            title: info["title"] as? String,
            bundle: info["bundleIdentifier"] as? String ?? "",
            currentTitle: current.title,
            lastKey: lastTrackKey,
            isDiff: isDiff
        )
    }

    private func applyTrackFields(
        from info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool
    ) {
        if let t = info["title"] as? String { current.title = t }

        if let bundle = info["bundleIdentifier"] as? String, !bundle.isEmpty {
            current.bundleIdentifier = bundle
        } else if info["bundleIdentifier"] is NSNull {
            current.bundleIdentifier = ""
        } else if !isDiff {
            current.bundleIdentifier = ""
        }

        if current.bundleIdentifier.isEmpty,
            let key = lastTrackKey,
            let pipe = key.firstIndex(of: "|")
        {
            let fromKey = String(key[..<pipe])
            if !fromKey.isEmpty { current.bundleIdentifier = fromKey }
        }

        if isDiff {
            if info["artist"] is NSNull || info["artists"] is NSNull {
                current.artist = ""
            } else if info.keys.contains("artist")
                || info.keys.contains("artists")
            {
                current.artist = MediaParsing.parseArtist(from: info) ?? ""
            } else if trackChanged {
                current.artist = ""
            }
        } else {
            current.artist = MediaParsing.parseArtist(from: info) ?? ""
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

    private func applyArtwork(from info: [String: Any], trackChanged: Bool) {
        if info["artworkData"] is NSNull {
            guard trackChanged else { return }
            current.artwork = nil
            current.artworkUnavailable = false
            return
        }
        guard let b64 = info["artworkData"] as? String, !b64.isEmpty,
            let data = Data(base64Encoded: b64)
        else {
            if trackChanged {
                current.artwork = nil
                current.artworkUnavailable = false
            }
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
                let artist = MediaParsing.parseArtist(from: info) ?? ""
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

                let info = self.fetchNowPlaying(artwork: true)
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

    private func cancelArtworkPolling() {
        artworkPollTask?.cancel()
        artworkPollTask = nil
    }

    private enum NowPlayingProbe {
        case active(info: [String: Any])
        case inactive
        case unavailable
    }

    private enum IdlePollMode {
        case skip
        case checkStillPresent
        case liftSuppressionIfActive
    }

    private func startIdlePolling() {
        idlePollTask?.cancel()
        idlePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pausedIdlePollInterval)
                guard let self, !Task.isCancelled else { return }

                let mode = await withCheckedContinuation {
                    (cont: CheckedContinuation<IdlePollMode, Never>) in
                    self.queue.async {
                        if self.suppressStaleStream {
                            cont.resume(returning: .liftSuppressionIfActive)
                        } else if self.hasDisplayableMedia,
                            !self.current.isPlaying
                        {
                            cont.resume(returning: .checkStillPresent)
                        } else {
                            cont.resume(returning: .skip)
                        }
                    }
                }

                switch mode {
                case .skip:
                    continue
                case .checkStillPresent:
                    self.verifyPausedStillPresent()
                case .liftSuppressionIfActive:
                    switch self.probeNowPlaying() {
                    case .unavailable, .inactive:
                        continue
                    case .active:
                        guard let info = self.fetchNowPlaying(artwork: true)
                        else { continue }
                        self.queue.async {
                            self.applySuppressionLift(payload: info)
                        }
                    }
                }
            }
        }
    }

    private func confirmSuppressionLift(with obj: [String: Any]) {
        Task { [weak self] in
            guard let self else { return }
            let probe = self.probeNowPlaying()
            self.queue.async {
                guard self.suppressStaleStream else { return }
                switch probe {
                case .unavailable, .inactive:
                    return
                case .active:
                    self.suppressStaleStream = false
                    self.ingest(obj)
                }
            }
        }
    }

    private func applySuppressionLift(payload info: [String: Any]) {
        guard suppressStaleStream else { return }
        suppressStaleStream = false
        ingest([
            "type": "data",
            "diff": false,
            "payload": info,
        ])
    }

    private func verifyPausedStillPresent() {
        Task { [weak self] in
            guard let self else { return }
            let probe = self.probeNowPlaying()
            self.queue.async {
                guard self.hasDisplayableMedia, !self.current.isPlaying else {
                    return
                }
                switch probe {
                case .unavailable:
                    return
                case .inactive:
                    self.clearNowPlaying(suppressStream: true)
                case .active(let info):
                    let key = self.trackKey(from: info, isDiff: false)
                    if let key, key != self.current.trackKey {
                        self.ingest([
                            "type": "data",
                            "diff": false,
                            "payload": info,
                        ])
                    }
                }
            }
        }
    }

    private func probeNowPlaying() -> NowPlayingProbe {
        guard let launch = adapterLaunch() else { return .unavailable }
        let proc = Process()
        proc.executableURL = launch.executable
        proc.arguments = launch.baseArguments + ["get", "--no-artwork"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return .unavailable
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return .unavailable }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            raw == "null"
        {
            return .inactive
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return .unavailable
        }
        if obj is NSNull { return .inactive }
        guard let info = obj as? [String: Any] else { return .unavailable }
        if let title = info["title"] as? String, !title.isEmpty {
            return .active(info: info)
        }
        return .inactive
    }

    private func scheduleIdleClear() {
        guard hasDisplayableMedia, !suppressStaleStream else { return }
        idleClearGeneration &+= 1
        let generation = idleClearGeneration
        idleClearTask?.cancel()
        idleClearTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            let probe = self.probeNowPlaying()
            self.queue.async {
                guard generation == self.idleClearGeneration else { return }
                self.idleClearTask = nil
                guard self.hasDisplayableMedia else { return }
                if case .inactive = probe {
                    self.clearNowPlaying(suppressStream: true)
                }
            }
        }
    }

    private func cancelIdleClear() {
        idleClearGeneration &+= 1
        idleClearTask?.cancel()
        idleClearTask = nil
    }

    private func clearNowPlaying(suppressStream: Bool) {
        enrichmentTask?.cancel()
        cancelArtworkPolling()
        cancelIdleClear()
        suppressStaleStream = suppressStream
        current = NowPlaying()
        lastTrackKey = nil
        lastSpotifyInfo = nil
        lastSpotifyEnrichmentKey = nil
        lastEnrichedTrackID = nil
        publishedElapsed = 0
        publishedElapsedTimestamp = nil
        publishedIsPlaying = false
        publishedPlaybackRate = 1
        onUpdate?(current)
    }

    func stop() {
        enrichmentTask?.cancel()
        cancelArtworkPolling()
        idlePollTask?.cancel()
        idlePollTask = nil
        cancelIdleClear()
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
