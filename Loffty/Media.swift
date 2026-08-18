//
//  Media.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import ApplicationServices
import CoreGraphics
import SwiftUI

private struct ProcessOutput {
    let status: Int32
    let data: Data
}

private nonisolated func runProcessCollectingOutput(
    executable: URL,
    arguments: [String]
) async -> ProcessOutput? {
    await withCheckedContinuation {
        (continuation: CheckedContinuation<ProcessOutput?, Never>) in
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        proc.terminationHandler = { finished in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(
                returning: ProcessOutput(
                    status: finished.terminationStatus,
                    data: data
                )
            )
        }
        do {
            try proc.run()
        } catch {
            continuation.resume(returning: nil)
        }
    }
}

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

    static let videoAspectRatio: CGFloat = 16 / 9
    static let minVideoArtworkAspect: CGFloat = 1.3
    static let maxArtworkAspect: CGFloat = 2.4

    static func clampedArtworkAspect(_ raw: CGFloat) -> CGFloat {
        min(max(raw, 1), maxArtworkAspect)
    }

    static func displayArtworkAspect(isVideo: Bool, raw: CGFloat) -> CGFloat {
        guard isVideo else { return 1 }
        if raw >= minVideoArtworkAspect { return clampedArtworkAspect(raw) }
        return videoAspectRatio
    }

    static func parseIsVideo(
        from info: [String: Any],
        artworkAspect: CGFloat = 1,
        currentIsVideo: Bool = false,
        isDiff: Bool = false
    ) -> Bool {
        if let music = info["isMusicApp"] as? Bool, music { return false }
        if artworkAspect >= minVideoArtworkAspect { return true }
        if let mt = info["mediaType"] as? String {
            let s = mt.lowercased()
            if s.contains("video") || s.contains("movie")
                || s.contains("tvshow")
            {
                return true
            }
            if s.contains("music") || s.contains("audio") { return false }
        }
        if isDiff { return currentIsVideo }
        return false
    }

    static func host(fromPossibleURL raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates = [trimmed]
        let lower = trimmed.lowercased()
        if !lower.contains("://"),
            lower.hasPrefix("www.")
                || (trimmed.contains(".") && trimmed.contains("/"))
        {
            candidates.append("https://\(trimmed)")
        }
        for candidate in candidates {
            guard let url = URL(string: candidate), let host = url.host,
                host.contains("."), host != "localhost",
                !looksLikeBundleIdentifier(host)
            else { continue }
            return canonicalWebsiteHost(host)
        }
        return nil
    }

    static func looksLikeBundleIdentifier(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count >= 3 else { return false }
        switch parts[0] {
        case "com", "org", "net", "io", "app", "co": return true
        default: return false
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull: return nil
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let u as UInt64: return String(u)
        default: return nil
        }
    }

    static func hosts(in text: String) -> [String] {
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            )
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap { match in
                guard let url = match.url else { return nil }
                return host(fromPossibleURL: url.absoluteString)
            }
    }

    static func websiteHost(
        uniqueIdentifier: String? = nil,
        contentItemIdentifier: String? = nil,
        title: String = "",
        album: String = "",
        artist: String = ""
    ) -> String? {
        if let host = host(fromPossibleURL: uniqueIdentifier) { return host }
        if let host = host(fromPossibleURL: contentItemIdentifier) {
            return host
        }
        if let host = websiteHost(fromLabeled: title) { return host }
        if let host = knownSiteHost(from: album) { return host }
        if let host = knownSiteHost(from: artist) { return host }
        return nil
    }

    static func websiteHost(
        fromPayload info: [String: Any],
        title: String,
        album: String,
        artist: String
    ) -> String? {
        if let host = websiteHost(
            uniqueIdentifier: stringValue(info["uniqueIdentifier"]),
            contentItemIdentifier: stringValue(info["contentItemIdentifier"]),
            title: title,
            album: album,
            artist: artist
        ) {
            return host
        }
        if let genre = stringValue(info["genre"]),
            let host = knownSiteHost(from: genre)
        {
            return host
        }
        return firstHost(in: info, skipKeys: ["artworkData"])
    }

    static func firstHost(
        in object: Any,
        skipKeys: Set<String> = [],
        depth: Int = 0
    )
        -> String?
    {
        guard depth < 5 else { return nil }
        if let text = stringValue(object) {
            if let host = host(fromPossibleURL: text) { return host }
            if text.count < 4_000, let host = hosts(in: text).first {
                return host
            }
            return nil
        }
        if let dict = object as? [String: Any] {
            for (key, value) in dict where !skipKeys.contains(key) {
                if let host = firstHost(
                    in: value,
                    skipKeys: skipKeys,
                    depth: depth + 1
                ) {
                    return host
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let host = firstHost(
                    in: value,
                    skipKeys: skipKeys,
                    depth: depth + 1
                ) {
                    return host
                }
            }
        }
        return nil
    }

    static func canonicalWebsiteHost(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        if h == "youtu.be" || h.hasSuffix(".youtube.com") {
            return "youtube.com"
        }
        if h == "netflix.net" || h.hasSuffix(".netflix.com") {
            return "netflix.com"
        }
        return h
    }

    static func websiteHost(fromLabeled text: String) -> String? {
        let separators = [" - ", " – ", " — ", " | "]
        for separator in separators {
            guard let range = text.range(of: separator, options: .backwards)
            else { continue }
            let suffix = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let host = knownSiteHost(from: suffix) { return host }
        }
        return nil
    }

    static func knownSiteHost(from label: String) -> String? {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return nil }
        return Self.knownSiteHosts[key]
    }

    static let knownSiteHosts: [String: String] = [
        "youtube": "youtube.com",
        "youtube music": "music.youtube.com",
        "netflix": "netflix.com",
        "twitch": "twitch.tv",
        "vimeo": "vimeo.com",
        "prime video": "primevideo.com",
        "amazon prime video": "primevideo.com",
        "disney+": "disneyplus.com",
        "disney plus": "disneyplus.com",
        "hulu": "hulu.com",
        "crunchyroll": "crunchyroll.com",
        "ted": "ted.com",
        "plex": "plex.tv",
        "max": "max.com",
        "hbo max": "max.com",
        "paramount+": "paramountplus.com",
        "peacock": "peacocktv.com",
        "apple tv": "tv.apple.com",
        "dailymotion": "dailymotion.com",
    ]

    static let browserAppNames: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
        "com.apple.WebKit.WebContent": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.canary": "Google Chrome Canary",
        "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.operasoftware.Opera": "Opera",
        "company.thebrowser.Browser": "Arc",
        "com.kagi.kagimacOS": "Orion",
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox Developer Edition",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.OperaGX": "Opera GX",
        "com.duckduckgo.macos.browser": "DuckDuckGo",
        "app.zen-browser.zen": "Zen",
        "company.thebrowser.dia": "Dia",
    ]

    private static let browserBundlePrefixes = [
        "com.apple.Safari",
        "com.apple.WebKit",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "company.thebrowser",
        "app.zen-browser",
        "com.vivaldi.Vivaldi",
        "com.duckduckgo.macos.browser",
        "com.kagi.kagimacOS",
        "com.sigmaos",
    ]

    static func isBrowserBundle(_ id: String) -> Bool {
        if id.isEmpty { return false }
        if browserAppNames[id] != nil { return true }
        return browserBundlePrefixes.contains { id.hasPrefix($0) }
    }

    static func appleScriptApplication(forBundle id: String) -> String? {
        browserAppNames[id]
    }

    static func scriptingBundleID(for bundle: String) -> String? {
        if bundle.hasPrefix("com.apple.SafariTechnologyPreview") {
            return "com.apple.SafariTechnologyPreview"
        }
        if bundle.hasPrefix("com.apple.Safari")
            || bundle.hasPrefix("com.apple.WebKit")
        {
            return "com.apple.Safari"
        }
        if bundle.hasPrefix("com.google.Chrome.canary") {
            return "com.google.Chrome.canary"
        }
        if bundle.hasPrefix("com.google.Chrome") { return "com.google.Chrome" }
        if isBrowserBundle(bundle) { return bundle }
        return nil
    }

    static func usesSafariTabSyntax(_ bundle: String) -> Bool {
        bundle.hasPrefix("com.apple.Safari")
            || bundle.hasPrefix("com.apple.WebKit")
    }

    static func prefersAccessibilityTabs(_ bundle: String) -> Bool {
        bundle.hasPrefix("org.mozilla")
            || bundle.hasPrefix("app.zen-browser")
            || bundle.hasPrefix("com.kagi.kagimacOS")
            || bundle.hasPrefix("com.duckduckgo.macos.browser")
    }

    struct BrowserTab: Equatable {
        var title: String
        var url: String
        var isCurrent: Bool = false
    }

    private static let browserWindowSuffixes = [
        " — mozilla firefox", " - mozilla firefox", " — firefox",
        " - firefox", " — zen browser", " — zen", " — orion",
        " — duckduckgo", " - duckduckgo",
    ]

    static func strippingBrowserWindowSuffix(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        for suffix in browserWindowSuffixes where lower.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return s
    }

    static func websiteHost(fromBrowserTitle title: String) -> String? {
        websiteHost(fromLabeled: strippingBrowserWindowSuffix(title))
    }

    static func normalizedTitle(_ text: String) -> String {
        var s = strippingBrowserWindowSuffix(text).lowercased()
        let suffixes = [
            " - youtube", " | youtube", " — youtube", " – youtube",
            " - netflix", " | netflix", " - twitch", " | twitch",
            " - vimeo", " | prime video", " - disney+", " | disney+",
        ]
        for suffix in suffixes where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
        }
        s = s.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        s = s.replacingOccurrences(of: "·", with: " ")
        s = s.replacingOccurrences(of: "•", with: " ")
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        s = String(s.unicodeScalars.filter { allowed.contains($0) })
        return s.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func websiteHost(matching title: String, tabs: [BrowserTab])
        -> String?
    {
        let needle = normalizedTitle(title)
        guard needle.count >= 4 else { return nil }

        var best: (score: Int, host: String)?
        let shortNeedle =
            needle.count > 18 ? String(needle.prefix(18)) : needle
        for tab in tabs {
            let haystack = normalizedTitle(tab.title)
            var score: Int?
            if haystack == needle {
                score = 100
            } else if haystack.hasPrefix(needle) {
                score = 80
            } else if haystack.contains(needle) {
                score = 70
            } else if needle.count >= 12, haystack.count >= 12,
                needle.contains(haystack)
            {
                score = 50
            } else if shortNeedle.count >= 12, haystack.contains(shortNeedle) {
                score = 40
            }
            guard var score else { continue }
            let host =
                websiteHost(fromBrowserTitle: tab.title)
                ?? host(fromPossibleURL: tab.url)
            guard let host else { continue }
            if tab.isCurrent { score += 5 }
            if best == nil || score > best!.score {
                best = (score, host)
            }
        }
        return best?.host
    }

    static func parseTabDump(_ raw: String) -> [BrowserTab] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            let current: Bool
            let rest: String
            if text.hasPrefix("*\t") {
                current = true
                rest = String(text.dropFirst(2))
            } else {
                current = false
                rest = text
            }
            if let sep = rest.firstIndex(of: "\t") {
                let title = String(rest[..<sep])
                let url = String(rest[rest.index(after: sep)...])
                guard !title.isEmpty || !url.isEmpty else { return nil }
                return BrowserTab(title: title, url: url, isCurrent: current)
            }
            guard !rest.isEmpty else { return nil }
            return BrowserTab(title: rest, url: "", isCurrent: current)
        }
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
    static nonisolated func currentTrackID() async -> String? {
        guard
            let result = await runProcessCollectingOutput(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: [
                    "-e",
                    "tell application \"Spotify\" to get id of current track",
                ]
            ),
            result.status == 0
        else { return nil }
        guard
            let raw = String(data: result.data, encoding: .utf8)?
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

private enum BrowserMediaLookup {
    static func websiteHost(
        bundleIdentifier: String,
        title: String
    ) async -> String? {
        let needle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 4 else { return nil }

        let axTabs = await MainActor.run {
            self.axTabs(bundleIdentifier: bundleIdentifier)
        }
        if let host = MediaParsing.websiteHost(matching: needle, tabs: axTabs) {
            return host
        }

        let windowTabs = await MainActor.run {
            self.cgWindowTabs(bundleIdentifier: bundleIdentifier)
        }
        if let host = MediaParsing.websiteHost(
            matching: needle,
            tabs: windowTabs
        ) {
            return host
        }

        if !MediaParsing.prefersAccessibilityTabs(bundleIdentifier) {
            let scripted = await MainActor.run {
                self.scriptTabs(bundleIdentifier: bundleIdentifier)
            }
            if let host = MediaParsing.websiteHost(
                matching: needle,
                tabs: scripted
            ) {
                return host
            }
        }

        return await MainActor.run {
            webAppHost(bundleIdentifier: bundleIdentifier)
        }
    }

    @MainActor
    private static func scriptTabs(bundleIdentifier: String)
        -> [MediaParsing.BrowserTab]
    {
        guard
            let scriptID = MediaParsing.scriptingBundleID(
                for: bundleIdentifier
            )
        else { return [] }
        let titleProperty =
            MediaParsing.usesSafariTabSyntax(scriptID) ? "name" : "title"
        let currentTab =
            MediaParsing.usesSafariTabSyntax(scriptID)
            ? "current tab" : "active tab"
        let source = """
            tell application id "\(scriptID)"
              set output to ""
              repeat with w in windows
                try
                  set output to output & "*\t" & (\(titleProperty) of \(currentTab) of w as string) & "\t" & (URL of \(currentTab) of w as string) & linefeed
                end try
                repeat with t in tabs of w
                  try
                    set output to output & (\(titleProperty) of t as string) & "\t" & (URL of t as string) & linefeed
                  end try
                end repeat
              end repeat
              return output
            end tell
            """
        guard let raw = runAppleScript(source) else { return [] }
        return MediaParsing.parseTabDump(raw)
    }

    @MainActor
    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private static func matchingApps(bundleIdentifier: String)
        -> [NSRunningApplication]
    {
        let target =
            MediaParsing.scriptingBundleID(for: bundleIdentifier)
            ?? bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return id == target || id == bundleIdentifier
                || (target.hasPrefix("com.apple.Safari")
                    && (id.hasPrefix("com.apple.Safari")
                        || id.hasPrefix("com.apple.WebKit")))
                || (target.hasPrefix("com.google.Chrome")
                    && id.hasPrefix("com.google.Chrome"))
                || (target.hasPrefix("org.mozilla")
                    && id.hasPrefix("org.mozilla"))
        }
    }

    @MainActor
    private static func axTabs(bundleIdentifier: String) -> [MediaParsing
        .BrowserTab]
    {
        guard AXIsProcessTrusted() else { return [] }
        var tabs: [MediaParsing.BrowserTab] = []
        for app in matchingApps(bundleIdentifier: bundleIdentifier) {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard
                let windows = axElements(axApp, kAXWindowsAttribute as String)
            else { continue }
            for window in windows {
                let title =
                    axString(window, kAXTitleAttribute as String) ?? ""
                let url =
                    axString(window, kAXDocumentAttribute as String)
                    ?? axString(window, kAXURLAttribute as String)
                    ?? ""
                guard !title.isEmpty || !url.isEmpty else { continue }
                tabs.append(
                    MediaParsing.BrowserTab(
                        title: title,
                        url: url,
                        isCurrent: false
                    )
                )
            }
        }
        return tabs
    }

    @MainActor
    private static func cgWindowTabs(bundleIdentifier: String)
        -> [MediaParsing.BrowserTab]
    {
        let pids = Set(
            matchingApps(bundleIdentifier: bundleIdentifier).map(
                \.processIdentifier
            )
        )
        guard !pids.isEmpty,
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return [] }
        return info.compactMap { window in
            guard
                let pidNumber = window[kCGWindowOwnerPID as String]
                    as? NSNumber,
                pids.contains(pid_t(pidNumber.intValue)),
                (window[kCGWindowLayer as String] as? Int) == 0
            else { return nil }
            let title = window[kCGWindowName as String] as? String ?? ""
            guard !title.isEmpty else { return nil }
            return MediaParsing.BrowserTab(
                title: title,
                url: "",
                isCurrent: false
            )
        }
    }

    @MainActor
    private static func webAppHost(bundleIdentifier: String) -> String? {
        let isWebApp =
            bundleIdentifier.contains("WebApp")
            || bundleIdentifier.contains(".app.")
        guard isWebApp,
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        else { return nil }
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plistURL) as? [String: Any]
        else { return nil }
        return MediaParsing.firstHost(in: info)
    }

    private static func axString(_ element: AXUIElement, _ attribute: String)
        -> String?
    {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else { return nil }
        if let text = value as? String { return text }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }

    private static func axElements(_ element: AXUIElement, _ attribute: String)
        -> [AXUIElement]?
    {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else { return nil }
        return value as? [AXUIElement]
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
    var fullArtwork: Data? = nil
    var artworkUnavailable: Bool = true
    var bundleIdentifier: String = ""
    var parentApplicationBundleIdentifier: String = ""
    var isVideo: Bool = false
    var websiteHost: String = ""
    var artworkAspectRatio: CGFloat = 1

    var resolvedBundleIdentifier: String {
        if bundleIdentifier == "com.apple.WebKit.WebContent",
            !parentApplicationBundleIdentifier.isEmpty
        {
            return parentApplicationBundleIdentifier
        }
        return bundleIdentifier
    }

    var displayArtworkAspect: CGFloat {
        MediaParsing.displayArtworkAspect(
            isVideo: isVideo,
            raw: artworkAspectRatio
        )
    }
}

final class NowPlayingStream {
    var onUpdate: ((NowPlaying) -> Void)?
    private var process: Process?
    private var current = NowPlaying()
    private var buf = Data()
    private var lastEnrichedTrackID: String?
    private var lastSpotifyEnrichmentKey: String?
    private var lastWebsiteLookupKey: String?
    private var lastSpotifyInfo: [String: Any]?
    private var lastTrackKey: String?
    private var enrichmentTask: Task<Void, Never>?
    private var websiteLookupTask: Task<Void, Never>?
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

    private nonisolated func adapterLaunch() -> AdapterLaunch? {
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
                lastWebsiteLookupKey = nil
                enrichmentTask?.cancel()
                websiteLookupTask?.cancel()
                websiteLookupTask = nil
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
        scheduleWebsiteLookupIfNeeded()
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

    private nonisolated func fetchNowPlaying(
        now: Bool = false,
        artwork: Bool = false
    ) async -> [String: Any]? {
        guard let launch = adapterLaunch() else { return nil }
        var args = launch.baseArguments + ["get"]
        if !artwork { args.append("--no-artwork") }
        if now { args.append("--now") }
        guard
            let result = await runProcessCollectingOutput(
                executable: launch.executable,
                arguments: args
            ),
            result.status == 0
        else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: result.data)
        else { return nil }
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

        if let parent = info["parentApplicationBundleIdentifier"] as? String,
            !parent.isEmpty
        {
            current.parentApplicationBundleIdentifier = parent
        } else if info["parentApplicationBundleIdentifier"] is NSNull {
            current.parentApplicationBundleIdentifier = ""
        } else if !isDiff || trackChanged {
            current.parentApplicationBundleIdentifier = ""
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

        applyVideoAndWebsite(
            from: info,
            isDiff: isDiff,
            trackChanged: trackChanged
        )
    }

    private func applyVideoAndWebsite(
        from info: [String: Any],
        isDiff: Bool,
        trackChanged: Bool
    ) {
        if trackChanged {
            current.websiteHost = ""
            current.isVideo = false
            if current.artwork == nil { current.artworkAspectRatio = 1 }
        }

        current.isVideo = MediaParsing.parseIsVideo(
            from: info,
            artworkAspect: current.artworkAspectRatio,
            currentIsVideo: current.isVideo,
            isDiff: isDiff
        )

        if let host = MediaParsing.websiteHost(
            fromPayload: info,
            title: current.title,
            album: current.album,
            artist: current.artist
        ) {
            current.websiteHost = host
        }
    }

    private func scheduleWebsiteLookupIfNeeded() {
        guard current.websiteHost.isEmpty,
            MediaParsing.isBrowserBundle(current.resolvedBundleIdentifier),
            websiteLookupTask == nil,
            let trackKeyAtStart = lastTrackKey,
            lastWebsiteLookupKey != trackKeyAtStart
        else { return }
        lastWebsiteLookupKey = trackKeyAtStart
        let title = current.title
        let bundle = current.resolvedBundleIdentifier

        websiteLookupTask = Task { [weak self] in
            defer {
                self?.queue.async { self?.websiteLookupTask = nil }
            }
            guard
                let host = await BrowserMediaLookup.websiteHost(
                    bundleIdentifier: bundle,
                    title: title
                )
            else { return }
            guard !Task.isCancelled else { return }
            self?.queue.async {
                guard self?.lastTrackKey == trackKeyAtStart else { return }
                guard self?.current.websiteHost.isEmpty == true else { return }
                self?.current.websiteHost = host
                if let current = self?.current {
                    self?.onUpdate?(current)
                }
            }
        }
    }

    private func applyArtwork(from info: [String: Any], trackChanged: Bool) {
        if info["artworkData"] is NSNull {
            guard trackChanged else { return }
            current.artwork = nil
            current.fullArtwork = nil
            current.artworkAspectRatio = 1
            current.artworkUnavailable = false
            return
        }
        guard let b64 = info["artworkData"] as? String, !b64.isEmpty,
            let data = Data(base64Encoded: b64)
        else {
            if trackChanged {
                current.artwork = nil
                current.fullArtwork = nil
                current.artworkAspectRatio = 1
                current.artworkUnavailable = false
            }
            return
        }
        applyDecodedArtwork(data)
        cancelArtworkPolling()
    }

    private func applyDecodedArtwork(_ data: Data) {
        current.artworkAspectRatio = ArtworkProcessor.aspectRatio(from: data)
        current.artwork = ArtworkProcessor.thumbnailData(from: data)
        current.fullArtwork = ArtworkProcessor.fullResData(from: data)
        current.artworkUnavailable = false
        if current.artworkAspectRatio >= MediaParsing.minVideoArtworkAspect {
            current.isVideo = true
        }
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
            guard let trackID = await SpotifyMetadata.currentTrackID()
            else { return }
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

                let info = await self.fetchNowPlaying(artwork: true)
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
                            self.applyDecodedArtwork(data)
                            self.scheduleWebsiteLookupIfNeeded()
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
                    switch await self.probeNowPlaying() {
                    case .unavailable, .inactive:
                        continue
                    case .active:
                        guard
                            let info = await self.fetchNowPlaying(
                                artwork: true
                            )
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
            let probe = await self.probeNowPlaying()
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
            let probe = await self.probeNowPlaying()
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

    private nonisolated func probeNowPlaying() async -> NowPlayingProbe {
        guard let launch = adapterLaunch() else { return .unavailable }
        guard
            let result = await runProcessCollectingOutput(
                executable: launch.executable,
                arguments: launch.baseArguments + ["get", "--no-artwork"]
            )
        else { return .unavailable }
        guard result.status == 0 else { return .unavailable }
        if let raw = String(data: result.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            raw == "null"
        {
            return .inactive
        }
        guard let obj = try? JSONSerialization.jsonObject(with: result.data)
        else { return .unavailable }
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
            let probe = await self.probeNowPlaying()
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
        websiteLookupTask?.cancel()
        websiteLookupTask = nil
        cancelArtworkPolling()
        cancelIdleClear()
        suppressStaleStream = suppressStream
        current = NowPlaying()
        lastTrackKey = nil
        lastSpotifyInfo = nil
        lastSpotifyEnrichmentKey = nil
        lastEnrichedTrackID = nil
        lastWebsiteLookupKey = nil
        publishedElapsed = 0
        publishedElapsedTimestamp = nil
        publishedIsPlaying = false
        publishedPlaybackRate = 1
        onUpdate?(current)
    }

    func stop() {
        enrichmentTask?.cancel()
        websiteLookupTask?.cancel()
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
