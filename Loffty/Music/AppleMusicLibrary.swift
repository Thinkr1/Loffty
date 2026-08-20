//
//  AppleMusicLibrary.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 20/08/2026.
//

import Foundation

enum AppleMusicTrack {
    static let clientBundle = "com.apple.Music"
}

enum LikeSource: Equatable {
    // case spotify
    case appleMusic
}

enum AppleMusicLibrary {
    struct FavoriteState: Equatable {
        var trackID: String
        var favorited: Bool
    }

    static nonisolated func currentFavoriteState() async -> FavoriteState? {
        guard
            let raw = await runAppleScript(
                """
                tell application "Music"
                  try
                    set t to current track
                    set pid to persistent ID of t
                    if pid is missing value or pid is "" then
                      set pid to (database ID of t as text)
                    end if
                    return pid & tab & (favorited of t as text)
                  on error
                    return "unavailable"
                  end try
                end tell
                """
            )
        else { return nil }
        return parseFavoriteState(raw)
    }

    static nonisolated func setCurrentTrackFavorited(
        _ favorited: Bool,
        trackID: String
    ) async -> Bool {
        let id = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        let escaped = NotificationReplyLogic.escapeAppleScript(id)
        let value = favorited ? "true" : "false"
        guard
            let raw = await runAppleScript(
                """
                tell application "Music"
                  try
                    set t to current track
                    set pid to persistent ID of t
                    if pid is missing value or pid is "" then
                      set pid to (database ID of t as text)
                    end if
                    if pid is not "\(escaped)" then return "mismatch"
                    set favorited of t to \(value)
                    return "ok"
                  on error
                    return "fail"
                  end try
                end tell
                """
            )
        else { return false }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }

    static nonisolated func parseFavoriteState(_ raw: String) -> FavoriteState? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unavailable" else { return nil }
        let parts = trimmed.split(
            separator: "\t",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 2 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        switch parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "true", "yes", "1":
            return FavoriteState(trackID: id, favorited: true)
        case "false", "no", "0":
            return FavoriteState(trackID: id, favorited: false)
        default:
            return nil
        }
    }

    private static nonisolated func runAppleScript(_ source: String) async
        -> String?
    {
        guard
            let result = await runProcessCollectingOutput(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", source]
            ),
            result.status == 0
        else { return nil }
        return String(data: result.data, encoding: .utf8)
    }
}
