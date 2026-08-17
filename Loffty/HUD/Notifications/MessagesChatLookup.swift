//
//  MessagesChatLookup.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 17/08/2026.
//

import Foundation
import SQLite3

enum MessagesChatLookup: Sendable {
    struct Candidate: Equatable, Sendable {
        var guid: String
        var displayName: String
        var chatIdentifier: String
        var text: String
        var date: Date
        var handle: String
    }

    nonisolated static func lookup(
        text: String,
        sender: String,
        at date: Date,
        handles: [String]
    ) -> Candidate? {
        match(
            candidates: recentIncoming(),
            text: text,
            sender: sender,
            at: date,
            handles: handles
        )
    }

    nonisolated static func match(
        candidates: [Candidate],
        text: String,
        sender: String,
        at date: Date,
        handles: [String]
    ) -> Candidate? {
        var best: (Candidate, Int)?
        for candidate in candidates {
            guard !candidate.guid.isEmpty else { continue }
            guard
                let score = score(
                    candidate,
                    text: text,
                    sender: sender,
                    at: date,
                    handles: handles
                )
            else { continue }
            if let current = best {
                if score > current.1 {
                    best = (candidate, score)
                }
            } else {
                best = (candidate, score)
            }
        }
        return best?.0
    }

    nonisolated static func parseChatID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(
            separator: ";",
            omittingEmptySubsequences: false
        )
        guard parts.count >= 3 else { return nil }
        let service = String(parts[0])
        let marker = String(parts[1])
        let identifier = parts.dropFirst(2).joined(separator: ";")
        guard
            ["iMessage", "SMS", "RCS", "Jabber"].contains(service),
            marker == "-" || marker == "+",
            !identifier.isEmpty
        else { return nil }
        return trimmed
    }

    nonisolated static func chatID(fromPlist plist: [String: Any]) -> String? {
        var found: String?
        func walk(_ value: Any) {
            guard found == nil else { return }
            if let text = value as? String {
                found = parseChatID(text)
                return
            }
            if let dict = value as? [String: Any] {
                for key in [
                    "thid", "thread-id", "threadId", "chatGUID", "guid",
                ] {
                    if let text = dict[key] as? String {
                        found = parseChatID(text)
                        if found != nil { return }
                    }
                }
                for nested in dict.values { walk(nested) }
                return
            }
            if let items = value as? [Any] {
                for nested in items { walk(nested) }
            }
        }
        walk(plist)
        return found
    }

    nonisolated static func date(fromAppleTime value: Int64) -> Date {
        let magnitude = abs(Double(value))
        let seconds: Double
        if magnitude > 1e16 {
            seconds = Double(value) / 1_000_000_000
        } else if magnitude > 1e13 {
            seconds = Double(value) / 1_000_000
        } else if magnitude > 1e10 {
            seconds = Double(value) / 1_000
        } else {
            seconds = Double(value)
        }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    nonisolated static func textMatches(notification: String, message: String)
        -> Bool
    {
        let expected = normalize(notification)
        let actual = normalize(message)
        if expected.isEmpty || actual.isEmpty { return false }
        if expected == actual { return true }
        if let split = NotificationBannerParser.splitCombined(expected) {
            let body = normalize(split.body)
            if body == actual { return true }
            if body.count >= 8, actual.hasPrefix(body) || body.hasPrefix(actual)
            {
                return true
            }
        }
        guard expected.count >= 8, actual.count >= 8 else { return false }
        return actual.hasPrefix(expected) || expected.hasPrefix(actual)
    }

    nonisolated private static func score(
        _ candidate: Candidate,
        text: String,
        sender: String,
        at date: Date,
        handles: [String]
    ) -> Int? {
        let matchedText = textMatches(
            notification: text,
            message: candidate.text
        )
        let matchedSender = senderMatches(
            candidate,
            sender: sender,
            handles: handles
        )
        let delta = abs(candidate.date.timeIntervalSince(date))
        if !matchedText {
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            guard matchedSender, delta <= 180 else { return nil }
            return 10 + max(0, 120 - Int(delta))
        }

        var value = 20
        if normalize(text) == normalize(candidate.text) { value += 50 }
        value += max(0, 120 - Int(delta))
        if matchedSender { value += 25 }
        return value
    }

    nonisolated private static func senderMatches(
        _ candidate: Candidate,
        sender: String,
        handles: [String]
    ) -> Bool {
        let names = [
            candidate.displayName, candidate.handle, candidate.chatIdentifier,
        ]
        if names.contains(where: {
            !$0.isEmpty && $0.caseInsensitiveCompare(sender) == .orderedSame
        }) {
            return true
        }
        let senderDigits = NotificationReplyLogic.digits(from: sender)
        for handle in handles + names {
            if handle.caseInsensitiveCompare(sender) == .orderedSame {
                return true
            }
            let handleDigits = NotificationReplyLogic.digits(from: handle)
            if senderDigits.count >= 8, senderDigits == handleDigits {
                return true
            }
            for known in handles {
                let knownDigits = NotificationReplyLogic.digits(from: known)
                if known.contains("@"),
                    handle.caseInsensitiveCompare(known) == .orderedSame
                {
                    return true
                }
                if knownDigits.count >= 8, knownDigits == handleDigits {
                    return true
                }
            }
        }
        return false
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func recentIncoming(limit: Int = 100)
        -> [Candidate]
    {
        guard let db = openDatabase() else { return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 800)

        let sql = """
            SELECT
                IFNULL(chat.guid, ''),
                IFNULL(chat.display_name, ''),
                IFNULL(chat.chat_identifier, ''),
                IFNULL(message.text, ''),
                message.date,
                IFNULL(handle.id, '')
            FROM message
            JOIN chat_message_join
                ON chat_message_join.message_id = message.ROWID
            JOIN chat ON chat.ROWID = chat_message_join.chat_id
            LEFT JOIN handle ON handle.ROWID = message.handle_id
            WHERE message.is_from_me = 0
            ORDER BY message.date DESC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [Candidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let guid = columnText(stmt, 0)
            guard !guid.isEmpty else { continue }
            out.append(
                Candidate(
                    guid: guid,
                    displayName: columnText(stmt, 1),
                    chatIdentifier: columnText(stmt, 2),
                    text: columnText(stmt, 3),
                    date: date(fromAppleTime: sqlite3_column_int64(stmt, 4)),
                    handle: columnText(stmt, 5)
                )
            )
        }
        return out
    }

    nonisolated private static func openDatabase() -> OpaquePointer? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    nonisolated private static func columnText(
        _ stmt: OpaquePointer?,
        _ index: Int32
    ) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }
}
