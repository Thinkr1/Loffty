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

final class NowPlayingStream {
    var onUpdate: ((NowPlaying) -> Void)?
    private var process: Process?
    private var current = NowPlaying()
    private var buf = Data()
    private var lastEnrichedTrackID: String?
    private var lastSpotifyEnrichmentKey: String?
    private var lastSpotifyInfo: [String: Any]?
    private var enrichmentTask: Task<Void, Never>?
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
        try? p.run()
        process = p
    }

    private func ingest(_ obj: [String: Any]) {
        let info = (obj["payload"] as? [String: Any]) ?? obj
        if let t = info["title"] as? String { current.title = t }
        if let a = parseArtist(from: info) { current.artist = a }
        if let al = info["album"] as? String { current.album = al }
        if let pl = info["playing"] as? Bool { current.isPlaying = pl }
        if let e = info["elapsedTime"] as? NSNumber {
            current.elapsed = e.doubleValue
        }
        if let d = info["duration"] as? NSNumber {
            current.duration = d.doubleValue
        }
        if let b64 = info["artworkData"] as? String {
            current.artwork = Data(base64Encoded: b64)
        }
        onUpdate?(current)
        enrichSpotifyArtistsIfNeeded(from: info)
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
            await MainActor.run {
                guard self.lastEnrichedTrackID != trackID else { return }
                self.lastEnrichedTrackID = trackID
                guard self.current.artist != artists else { return }
                self.current.artist = artists
                self.onUpdate?(self.current)
            }
        }
    }

    func refreshArtistEnrichment() {
        lastSpotifyEnrichmentKey = nil
        lastEnrichedTrackID = nil
        enrichmentTask?.cancel()
        guard let info = lastSpotifyInfo else { return }
        if ArtistEnrichmentMode.current.allowsNetworkFetch {
            enrichSpotifyArtistsIfNeeded(from: info)
        } else if let artist = parseArtist(from: info),
            current.artist != artist
        {
            current.artist = artist
            onUpdate?(current)
        }
    }

    func stop() {
        enrichmentTask?.cancel()
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
