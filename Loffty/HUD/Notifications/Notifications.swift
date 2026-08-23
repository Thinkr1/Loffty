//
//  Notifications.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 13/08/2026.
//

import AppKit
import Combine
import Contacts
import SwiftUI

enum NotificationApp: String, CaseIterable, Sendable {
    case messages
    case whatsApp
    case discord

    var displayName: String {
        switch self {
        case .messages: "Messages"
        case .whatsApp: "WhatsApp"
        case .discord: "Discord"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .messages:
            ["com.apple.MobileSMS", "com.apple.iChat", "com.apple.messages"]
        case .whatsApp:
            [
                "net.whatsapp.WhatsApp",
                "net.whatsapp.WhatsAppDesktop",
                "net.whatsapp.WhatsApp.mac",
            ]
        case .discord:
            [
                "com.hnc.Discord",
                "com.discord.Discord",
                "com.hnc.DiscordCanary",
                "com.hnc.DiscordPTB",
                "com.hnc.DiscordDevelopment",
            ]
        }
    }

    var primaryBundleID: String { bundleIDs[0] }

    var accent: Color {
        switch self {
        case .messages:
            Color(red: 0.18, green: 0.80, blue: 0.44)
        case .whatsApp:
            Color(red: 0.15, green: 0.68, blue: 0.38)
        case .discord:
            Color(red: 0.35, green: 0.40, blue: 0.93)
        }
    }

    var symbolName: String {
        switch self {
        case .messages: "message.fill"
        case .whatsApp: "phone.fill"
        case .discord: "bubble.left.and.bubble.right.fill"
        }
    }

    var supportsReply: Bool {
        switch self {
        case .messages, .whatsApp, .discord: true
        }
    }
}

enum NotificationAlertStyle: Equatable, Sendable {
    case none
    case banners
    case alerts
}

enum NotificationSettingsLink {
    nonisolated static func settingsURLCandidates(bundleID: String? = nil)
        -> [String]
    {
        var urls: [String] = []
        if let bundleID, !bundleID.isEmpty {
            urls.append(
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
            )
        }
        urls.append(
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
        urls.append(
            "x-apple.systempreferences:com.apple.preference.notifications"
        )
        return urls
    }

    @MainActor
    static func openNotificationSettings(bundleID: String? = nil) {
        for candidate in settingsURLCandidates(bundleID: bundleID) {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    @MainActor
    static func openNotificationSettings(for app: NotificationApp) {
        openNotificationSettings(bundleID: app.primaryBundleID)
    }
}

enum NotificationStyleCheck: Sendable {
    nonisolated static let bannerFlag = 1 << 3
    nonisolated static let alertFlag = 1 << 4
    nonisolated static let allowFlag = 1 << 25

    nonisolated static func synchronize() {
        CFPreferencesAppSynchronize("com.apple.ncprefs" as CFString)
    }

    nonisolated static func currentFlags(
        bundleID: String,
        apps: [[String: Any]]? = nil
    ) -> Int? {
        let key = normalizedBundleID(bundleID)
        guard !key.isEmpty else { return nil }
        for entry in apps ?? loadApps() {
            guard let raw = entry["bundle-id"] as? String else { continue }
            if normalizedBundleID(raw).caseInsensitiveCompare(key)
                == .orderedSame
            {
                return intValue(entry["flags"])
            }
        }
        return nil
    }

    nonisolated static func alertStyle(flags: Int) -> NotificationAlertStyle {
        if flags & alertFlag != 0 { return .alerts }
        if flags & bannerFlag != 0 { return .banners }
        return .none
    }

    nonisolated static func allowsNotifications(flags: Int) -> Bool {
        flags & allowFlag != 0
    }

    nonisolated static func showsOnDesktop(flags: Int) -> Bool {
        flags & bannerFlag != 0 || flags & alertFlag != 0
    }

    nonisolated static func hidesSystemBanner(flags: Int) -> Bool {
        allowsNotifications(flags: flags) && !showsOnDesktop(flags: flags)
    }

    nonisolated static func hidesSystemBanner(
        for app: NotificationApp,
        apps: [[String: Any]]? = nil
    ) -> Bool {
        let list = apps ?? loadApps()
        return app.bundleIDs.contains { id in
            guard let flags = currentFlags(bundleID: id, apps: list) else {
                return false
            }
            return hidesSystemBanner(flags: flags)
        }
    }

    nonisolated static func loadApps() -> [[String: Any]] {
        synchronize()
        guard
            let value = CFPreferencesCopyAppValue(
                "apps" as CFString,
                "com.apple.ncprefs" as CFString
            )
        else { return [] }
        return (value as? [[String: Any]]) ?? []
    }

    nonisolated static func normalizedBundleID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "_SYSTEM_CENTER_:"
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return trimmed
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Int64 {
            return Int(truncatingIfNeeded: number)
        }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

struct NotchNotification: Equatable, Identifiable, Sendable {
    let id: String
    let app: NotificationApp
    let sender: String
    let body: String
    let deliveredAt: Date
    var avatar: Data?
    var handles: [String]
    var chatID: String? = nil
    var chatName: String? = nil

    var fingerprint: String {
        NotificationBannerParser.fingerprint(
            app: app,
            sender: sender,
            body: body
        )
    }

    var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sender : trimmed
    }
}

enum NotificationLayout {
    static let compactMessageLines = 3
    static let compactAvatar: CGFloat = 34
    static let compactHorizontalPadding: CGFloat = 22
    static let compactRowSpacing: CGFloat = 10
    static let compactTopPadding: CGFloat = 6
    static let compactBottomPadding: CGFloat = 10
    static let compactTopRadius: CGFloat = 12
    static let compactBottomRadius: CGFloat = 22
    static let expandedTopRadius: CGFloat = 16
    static let expandedBottomRadius: CGFloat = 28
    static let expandedWidth: CGFloat = 360
    static let replySize: CGFloat = 24
    static let replyEdgePadding: CGFloat = 6
    private static let compactSenderHeight: CGFloat = 16
    private static let compactSenderSpacing: CGFloat = 3
    private static let compactLineHeight: CGFloat = 15
    private static let compactMessageFontSize: CGFloat = 12.5
    private static let compactMinBleed: CGFloat = 24
    static let expandedTopPadding: CGFloat = 6
    static let composerInset: CGFloat = 8
    static let expandedStackSpacing: CGFloat = 6
    static let expandedComposerHeight: CGFloat = 36
    private static let expandedAvatar: CGFloat = 36
    private static let expandedClose: CGFloat = 16
    private static let expandedHeaderSpacing: CGFloat = 10
    private static let expandedSenderHeight: CGFloat = 16
    private static let expandedSenderSpacing: CGFloat = 2
    private static let expandedComposerFontSize: CGFloat = 13

    static func compactWidth(
        notchW: CGFloat,
        sender: String,
        message: String,
        canReply: Bool
    ) -> CGFloat {
        let minW = notchW + 2 * compactTopRadius + compactMinBleed
        let chrome = horizontalChrome(canReply: canReply)
        let text = max(
            measuredWidth(sender, size: 13, weight: .semibold),
            measuredWidth(message, size: compactMessageFontSize)
        )
        return min(expandedWidth, max(minW, chrome + text))
    }

    static func compactExtra(
        message: String = "",
        sender: String = "",
        notchW: CGFloat = 200,
        canReply: Bool = false
    ) -> CGFloat {
        let width = compactWidth(
            notchW: notchW,
            sender: sender,
            message: message,
            canReply: canReply
        )
        return compactExtra(
            message: message,
            islandWidth: width,
            canReply: canReply
        )
    }

    static func expandedHeight(
        message: String,
        notchH: CGFloat,
        canReply: Bool,
        draft: String = ""
    ) -> CGFloat {
        let body =
            CGFloat(
                wrappedLineCount(message, width: expandedTextWidth)
            ) * compactLineHeight
        let header = max(
            expandedAvatar,
            expandedSenderHeight + expandedSenderSpacing + body
        )
        let composer =
            canReply
            ? expandedStackSpacing + composerHeight(draft: draft) : 0
        return notchH + expandedTopPadding + header + composer
            + composerInset
    }

    static func composerHorizontalPadding(topRadius: CGFloat) -> CGFloat {
        topRadius + composerInset
    }

    static func composerCornerRadius(
        islandBottomRadius: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        min(height / 2, max(0, islandBottomRadius - composerInset))
    }

    static func wrappedLineCount(
        _ text: String,
        width: CGFloat,
        fontSize: CGFloat = compactMessageFontSize
    ) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }
        let font = NSFont.systemFont(ofSize: fontSize)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = -1
        let storage = NSTextStorage(
            string: trimmed,
            attributes: [.font: font, .paragraphStyle: style]
        )
        let manager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(
                width: max(1, width),
                height: .greatestFiniteMagnitude
            )
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = compactMessageLines
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.glyphRange(for: container)
        var lines = 0
        let glyphCount = manager.numberOfGlyphs
        guard glyphCount > 0 else { return 1 }
        manager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: glyphCount)
        ) { _, _, _, _, _ in
            lines += 1
        }
        return min(compactMessageLines, max(1, lines))
    }

    static func replyCenter(
        in size: CGSize,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> CGPoint {
        let inset = replySize / 2 + replyEdgePadding
        let unconstrained = CGPoint(
            x: size.width - topRadius - inset,
            y: size.height - inset
        )
        let corner = CGPoint(
            x: size.width - topRadius - bottomRadius,
            y: size.height - bottomRadius
        )
        let dx = unconstrained.x - corner.x
        let dy = unconstrained.y - corner.y
        let dist = hypot(dx, dy)
        let allowed = max(0, bottomRadius - inset)
        guard dist > allowed, dist > 0, allowed > 0 else {
            return unconstrained
        }
        let scale = allowed / dist
        return CGPoint(
            x: corner.x + dx * scale,
            y: corner.y + dy * scale
        )
    }

    private static func compactExtra(
        message: String,
        islandWidth: CGFloat,
        canReply: Bool
    ) -> CGFloat {
        let textWidth = max(
            40,
            islandWidth - horizontalChrome(canReply: canReply)
        )
        let bodyHeight =
            CGFloat(wrappedLineCount(message, width: textWidth))
            * compactLineHeight
        let textColumn =
            compactSenderHeight + compactSenderSpacing + bodyHeight
        let row = max(compactAvatar, textColumn)
        return compactTopPadding + row + compactBottomPadding
    }

    private static var expandedTextWidth: CGFloat {
        expandedWidth
            - 2 * composerHorizontalPadding(topRadius: expandedTopRadius)
            - expandedAvatar
            - expandedHeaderSpacing
            - expandedClose
            - 8
    }

    private static var expandedComposerTextWidth: CGFloat {
        expandedWidth
            - 2 * composerHorizontalPadding(topRadius: expandedTopRadius)
            - 14
            - 4
            - 26
            - 6
    }

    static func composerHeight(draft: String) -> CGFloat {
        let lines = wrappedLineCount(
            draft,
            width: expandedComposerTextWidth,
            fontSize: expandedComposerFontSize
        )
        return expandedComposerHeight
            + CGFloat(max(0, lines - 1)) * compactLineHeight
    }

    private static func horizontalChrome(canReply: Bool) -> CGFloat {
        compactHorizontalPadding * 2
            + compactAvatar
            + compactRowSpacing
            + (canReply ? replySize + replyEdgePadding : 0)
    }

    private static func measuredWidth(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil(
            (trimmed as NSString).size(withAttributes: [.font: font]).width
        )
    }
}

enum NotificationBannerParser: Sendable {
    nonisolated static func app(fromBundleID id: String) -> NotificationApp? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let lower = key.lowercased()
        for app in NotificationApp.allCases {
            for known in app.bundleIDs {
                if known.caseInsensitiveCompare(key) == .orderedSame {
                    return app
                }
                if lower.hasPrefix(known.lowercased() + ".") {
                    return app
                }
            }
        }
        if lower.contains("whatsapp") { return .whatsApp }
        if lower.contains("discord") { return .discord }
        return nil
    }

    nonisolated static func app(fromName name: String) -> NotificationApp? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return nil }
        if key == "messages" || key == "imessage" || key == "message"
            || key == "apple messages"
        {
            return .messages
        }
        if key.contains("whatsapp") { return .whatsApp }
        if key == "discord" || key.hasPrefix("discord ")
            || key.contains("discord.app") || key.hasPrefix("discord canary")
            || key.hasPrefix("discord ptb")
        {
            return .discord
        }
        return nil
    }

    nonisolated static func isNotificationHost(bundleID: String) -> Bool {
        let key = bundleID.lowercased()
        return key.contains("notificationcenter")
            || key.contains("usernotification")
            || key == "com.apple.controlcenter"
    }

    nonisolated static func resolveApp(
        bundleID: String,
        appName: String,
        hints: [String] = []
    ) -> NotificationApp? {
        if let app = app(fromBundleID: bundleID) { return app }
        if !isNotificationHost(bundleID: bundleID),
            let app = app(fromName: appName)
        {
            return app
        }
        for hint in hints {
            let trimmed = hint.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty, trimmed.count <= 48 else { continue }
            if let app = app(fromBundleID: trimmed) ?? app(fromName: trimmed) {
                return app
            }
        }
        return app(fromName: appName)
    }

    nonisolated static func parse(
        title: String?,
        subtitle: String?,
        body: String?,
        bundleID: String,
        appName: String,
        hints: [String] = [],
        deliveredAt: Date = Date(),
        id: String? = nil
    ) -> NotchNotification? {
        guard
            let app = resolveApp(
                bundleID: bundleID,
                appName: appName,
                hints: hints
            )
        else { return nil }

        let tit = clean(title)
        let sub = clean(subtitle)
        let rawBody = clean(body)

        var sender: String
        var message: String

        if !tit.isEmpty, !rawBody.isEmpty {
            sender = tit
            message = rawBody
        } else if !tit.isEmpty, !sub.isEmpty {
            sender = tit
            message = sub
        } else if let split = splitCombined(tit.isEmpty ? rawBody : tit) {
            sender = split.sender
            message = split.body
        } else if !tit.isEmpty {
            sender = tit
            message = sub.isEmpty ? rawBody : sub
        } else if !rawBody.isEmpty {
            sender = app.displayName
            message = rawBody
        } else {
            return nil
        }

        if sender.caseInsensitiveCompare(app.displayName) == .orderedSame,
            let split = splitCombined(message)
        {
            sender = split.sender
            message = split.body
        }

        let resolvedMessage = message.isEmpty ? sender : message
        guard !sender.isEmpty, !resolvedMessage.isEmpty else { return nil }

        var chatName: String?
        if app == .discord {
            let channel = clean(subtitle)
            if !channel.isEmpty { chatName = channel }
        }

        return NotchNotification(
            id: id ?? UUID().uuidString,
            app: app,
            sender: sender,
            body: resolvedMessage,
            deliveredAt: deliveredAt,
            avatar: nil,
            handles: [],
            chatName: chatName
        )
    }

    nonisolated static func fingerprint(
        app: NotificationApp,
        sender: String,
        body: String
    ) -> String {
        "\(app.rawValue)|\(sender.lowercased())|\(body.lowercased())"
    }

    nonisolated static func decodeRecord(
        data: Data,
        bundleID: String,
        deliveredAt: Date,
        recID: Int
    ) -> NotchNotification? {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else { return nil }

        let req = plist["req"] as? [String: Any] ?? [:]
        let title = stringValue(req["titl"] ?? plist["titl"])
        let subtitle = stringValue(req["subt"] ?? plist["subt"])
        let body = stringValue(req["body"] ?? plist["body"])
        let appName = stringValue(plist["app"]) ?? bundleID

        guard
            var note = parse(
                title: title,
                subtitle: subtitle,
                body: body,
                bundleID: bundleID,
                appName: appName,
                hints: [appName, bundleID].compactMap { $0 },
                deliveredAt: deliveredAt,
                id: "db-\(recID)"
            )
        else { return nil }
        if note.app == .messages {
            note.chatID = MessagesChatLookup.chatID(fromPlist: plist)
        } else if note.app == .discord, note.chatName == nil {
            let channel = clean(subtitle)
            if !channel.isEmpty { note.chatName = channel }
        }
        return note
    }

    nonisolated static func relativeLabel(
        from date: Date,
        now: Date = Date()
    ) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 45 { return "Now" }
        if delta < 60 { return "1m" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        return "\(Int(delta / 86_400))d"
    }

    nonisolated static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        if letters.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return letters.joined().uppercased()
    }

    nonisolated static func shouldAccept(
        app: NotificationApp,
        messages: Bool,
        whatsApp: Bool,
        discord: Bool
    ) -> Bool {
        switch app {
        case .messages: messages
        case .whatsApp: whatsApp
        case .discord: discord
        }
    }

    nonisolated static func isDuplicate(
        incoming: NotchNotification,
        current: NotchNotification?,
        now: Date = Date()
    ) -> Bool {
        guard let current else { return false }
        guard incoming.fingerprint == current.fingerprint else { return false }
        return now.timeIntervalSince(current.deliveredAt) < 2.5
    }

    nonisolated static func splitCombined(_ text: String) -> (
        sender: String, body: String
    )? {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return nil }
        let separators = [": ", " — ", " – ", ", "]
        for sep in separators {
            guard let range = trimmed.range(of: sep) else { continue }
            let sender = String(trimmed[..<range.lowerBound])
            let body = String(trimmed[range.upperBound...])
            if sender.count >= 2, body.count >= 2 {
                return (sender, body)
            }
        }
        return nil
    }

    nonisolated static func clean(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }
}

enum NotificationReplyLogic: Sendable {
    nonisolated static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func preferredBuddyHandle(
        chatHandle: String,
        extras: [String]
    ) -> String? {
        var emails: [String] = []
        var phones: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else { return }
            if trimmed.contains("@") {
                if !emails.contains(where: {
                    $0.caseInsensitiveCompare(trimmed) == .orderedSame
                }) {
                    emails.append(trimmed)
                }
                return
            }
            guard isHandleTarget(trimmed) else { return }
            if !phones.contains(where: {
                $0.caseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                phones.append(trimmed)
            }
        }
        add(chatHandle)
        for extra in extras { add(extra) }
        return emails.first ?? phones.first
    }

    nonisolated static func isHandleTarget(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return true }
        let digits = trimmed.filter(\.isNumber)
        let letters = trimmed.filter(\.isLetter)
        return digits.count >= 8 && letters.count < 3
    }

    nonisolated static func namedChat(_ displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func isGroupChat(guid: String, identifier: String)
        -> Bool
    {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.lowercased().hasPrefix("chat") { return true }
        if guid.contains(";+;") { return true }
        if let last = guid.split(separator: ";").last,
            last.lowercased().hasPrefix("chat")
        {
            return true
        }
        return false
    }

    nonisolated static func messagesExistingChatScript(
        guid: String,
        identifier: String,
        name: String,
        text: String
    ) -> String {
        let body = escapeAppleScript(text)
        let id = escapeAppleScript(guid)
        let ident = escapeAppleScript(identifier)
        let chatName = escapeAppleScript(name)
        return """
            tell application "Messages"
              repeat with c in chats
                try
                  if (id of c as text) is "\(id)" then
                    send "\(body)" to c
                    return
                  end if
                end try
              end repeat
              repeat with c in chats
                try
                  if "\(ident)" is not "" and (id of c as text) contains "\(ident)" then
                    send "\(body)" to c
                    return
                  end if
                end try
              end repeat
              if "\(chatName)" is not "" then send "\(body)" to chat "\(chatName)"
            end tell
            """
    }

    nonisolated static func messagesChatScript(target: String, text: String)
        -> String
    {
        let name = escapeAppleScript(target)
        let body = escapeAppleScript(text)
        return
            "tell application \"Messages\" to send \"\(body)\" to chat \"\(name)\""
    }

    nonisolated static func messagesScript(target: String, text: String)
        -> String
    {
        let name = escapeAppleScript(target)
        let body = escapeAppleScript(text)
        return
            "tell application \"Messages\" to send \"\(body)\" to buddy \"\(name)\""
    }

    nonisolated static func messagesURL(handle: String, text: String) -> URL? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter(\.isNumber)
        let letters = trimmed.filter(\.isLetter)
        let isEmail = trimmed.contains("@")
        let isPhone = digits.count >= 8 && letters.count < 3
        guard isEmail || isPhone else { return nil }

        let address: String
        if isPhone {
            address =
                trimmed.hasPrefix("+")
                ? "+" + digits : digits
        } else {
            address = trimmed
        }
        let encodedAddress =
            address.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? address
        let encodedBody =
            text.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? text
        let scheme = isEmail ? "imessage" : "sms"
        return URL(string: "\(scheme):\(encodedAddress)&body=\(encodedBody)")
    }

    nonisolated static func whatsAppURL(phone: String, text: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        var components = URLComponents(string: "whatsapp://send")
        components?.queryItems = [
            URLQueryItem(name: "phone", value: digits),
            URLQueryItem(name: "text", value: text),
        ]
        return components?.url
    }

    nonisolated static func digits(from handle: String) -> String {
        handle.filter(\.isNumber)
    }

    nonisolated static func discordSearchTerm(for note: NotchNotification)
        -> String?
    {
        if let chat = note.chatName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !chat.isEmpty {
            return chat
        }
        let sender = note.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty,
            sender.caseInsensitiveCompare(NotificationApp.discord.displayName)
                != .orderedSame
        else { return nil }
        return sender
    }

    nonisolated static func discordSendScript(
        searchTerm: String?,
        message: String
    ) -> String {
        let body = escapeAppleScript(message)
        var lines = [
            "tell application \"Discord\" to activate",
            "delay 0.35",
            "tell application \"System Events\"",
            "  tell process \"Discord\"",
            "    set frontmost to true",
        ]
        if let term = searchTerm?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
            !term.isEmpty
        {
            let query = escapeAppleScript(term)
            lines += [
                "    delay 0.15",
                "    set the clipboard to \"\(query)\"",
                "    keystroke \"k\" using command down",
                "    delay 0.25",
                "    keystroke \"v\" using command down",
                "    delay 0.35",
                "    keystroke return",
                "    delay 0.25",
            ]
        }
        lines += [
            "    set the clipboard to \"\(body)\"",
            "    keystroke \"v\" using command down",
            "    delay 0.05",
            "    keystroke return",
            "  end tell",
            "end tell",
        ]
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class NotificationController: ObservableObject {
    static let shared = NotificationController()

    @Published private(set) var current: NotchNotification?
    @Published private(set) var isExpanded = false
    @Published var isReplying = false
    @Published var draft = ""
    @Published private(set) var sending = false

    var isActive: Bool { current != nil }
    var wantsInteraction: Bool { current != nil }
    var wantsKeyWindow: Bool { isReplying }
    var isPinned: Bool { isReplying || sending }

    private var dismissTask: Task<Void, Never>?
    private var watcher: NotificationBannerWatcher?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let watcher = NotificationBannerWatcher()
        watcher.onBanner = { [weak self] note in
            Task { @MainActor in
                self?.present(note)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        started = false
        dismiss(animated: false)
    }

    func present(_ note: NotchNotification) {
        guard AppSettings.shared.notificationsHUD else { return }
        guard
            NotificationBannerParser.shouldAccept(
                app: note.app,
                messages: AppSettings.shared.notificationMessages,
                whatsApp: AppSettings.shared.notificationWhatsApp,
                discord: AppSettings.shared.notificationDiscord
            )
        else { return }
        if NotificationBannerParser.isDuplicate(
            incoming: note,
            current: current
        ) {
            return
        }

        dismissTask?.cancel()
        withAnimation(NotchViewModel.notchExpandSpring) {
            current = note
            isExpanded = false
            isReplying = false
            sending = false
            draft = ""
        }
        enrich(note)
        scheduleDismiss()
    }

    func expand() {
        guard current != nil else { return }
        dismissTask?.cancel()
        withAnimation(NotchViewModel.notchExpandSpring) {
            isExpanded = true
        }
    }

    func collapse() {
        guard current != nil, !isPinned else { return }
        withAnimation(NotchViewModel.notchCollapseSpring) {
            isExpanded = false
            isReplying = false
        }
        scheduleDismiss()
    }

    func beginReply() {
        guard let note = current, note.app.supportsReply else { return }
        dismissTask?.cancel()
        withAnimation(NotchViewModel.notchExpandSpring) {
            isExpanded = true
            isReplying = true
        }
    }

    func dismiss(animated: Bool = true) {
        dismissTask?.cancel()
        let apply = {
            self.current = nil
            self.isExpanded = false
            self.isReplying = false
            self.sending = false
            self.draft = ""
        }
        if animated {
            withAnimation(NotchViewModel.notchCollapseSpring, apply)
        } else {
            apply()
        }
    }

    func openCurrent() {
        guard let note = current else { return }
        NotificationReply.open(note)
    }

    func sendReply() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note = current, !text.isEmpty, !sending else { return }
        sending = true
        Task {
            let sent = await NotificationReply.send(text, to: note)
            guard !Task.isCancelled else { return }
            if sent {
                dismiss()
            } else if note.app == .whatsApp {
                // The URL scheme opens WhatsApp with prefilled text but does
                // not send or create a quoted reply.
                sending = false
            } else if note.app != .messages {
                sending = false
                NotificationReply.open(note)
            } else {
                sending = false
            }
        }
    }

    #if DEBUG
        func presentPreview(app: NotificationApp = .whatsApp) {
            present(
                NotchNotification(
                    id: "preview-\(app.rawValue)-\(UUID().uuidString)",
                    app: app,
                    sender: "John Doe",
                    body: "helloooooo",
                    deliveredAt: Date(),
                    avatar: nil,
                    handles: []
                )
            )
        }

        func setCurrentForTesting(_ value: NotchNotification?) {
            current = value
            if value == nil {
                isExpanded = false
                isReplying = false
                draft = ""
            }
        }

        func setExpandedForTesting(_ value: Bool) {
            isExpanded = value
        }
    #endif

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard current != nil, !isPinned else { return }
        dismissTask = Task {
            try? await Task.sleep(
                for: .seconds(AppSettings.shared.notificationsHUDDismissDelay)
            )
            guard !Task.isCancelled, !isPinned else { return }
            dismiss()
        }
    }

    private func enrich(_ note: NotchNotification) {
        Task {
            let sender = note.sender
            let body = note.body
            let deliveredAt = note.deliveredAt
            let app = note.app
            let knownHandles = note.handles
            let (avatar, handles, chat) = await Task.detached(
                priority: .userInitiated
            ) {
                if app == .messages {
                    let chat = MessagesChatLookup.lookup(
                        text: body,
                        sender: sender,
                        at: deliveredAt,
                        handles: knownHandles
                    )
                    var handles = knownHandles
                    if let handle = chat?.handle, !handle.isEmpty,
                        !handles.contains(where: {
                            $0.caseInsensitiveCompare(handle) == .orderedSame
                        })
                    {
                        handles.insert(handle, at: 0)
                    }
                    return (nil as Data?, handles, chat)
                }
                return (
                    nil as Data?, knownHandles,
                    nil as MessagesChatLookup.Candidate?
                )
            }.value
            guard current?.id == note.id else { return }
            var updated = note
            updated.avatar = avatar
            updated.handles = handles
            if let chat {
                updated.chatID = chat.guid
                if !chat.displayName.isEmpty {
                    updated.chatName = chat.displayName
                }
            }
            current = updated
        }
    }
}

enum NotificationReply {
    static func open(_ note: NotchNotification) {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: note.app.primaryBundleID
        ) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        for id in note.app.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: id
            ) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: .init()
                )
                return
            }
        }
    }

    static func send(_ text: String, to note: NotchNotification) async -> Bool {
        switch note.app {
        case .messages:
            return await sendMessages(text, to: note)
        case .whatsApp:
            return await sendWhatsApp(text, to: note)
        case .discord:
            return await sendDiscord(text, to: note)
        }
    }

    private static func sendMessages(_ text: String, to note: NotchNotification)
        async -> Bool
    {
        let hit = await Task.detached(priority: .userInitiated) {
            MessagesChatLookup.lookup(
                text: note.body,
                sender: note.sender,
                at: note.deliveredAt,
                handles: note.handles
            )
        }.value

        if let hit {
            if await runAppleScript(
                NotificationReplyLogic.messagesExistingChatScript(
                    guid: hit.guid,
                    identifier: hit.chatIdentifier,
                    name: hit.displayName,
                    text: text
                )
            ) {
                return true
            }
        }

        guard
            let handle = NotificationReplyLogic.preferredBuddyHandle(
                chatHandle: hit?.handle ?? note.sender,
                extras: note.handles
            )
        else { return false }
        return await runAppleScript(
            NotificationReplyLogic.messagesScript(
                target: handle,
                text: text
            )
        )
    }

    private static func sendWhatsApp(_ text: String, to note: NotchNotification)
        async -> Bool
    {
        let handles = await NotificationContacts.whatsAppHandles(for: note)
        for handle in handles {
            if let url = NotificationReplyLogic.whatsAppURL(
                phone: handle,
                text: text
            ) {
                let ok = await MainActor.run { NSWorkspace.shared.open(url) }
                if ok { return false }
            }
        }
        open(note)
        return false
    }

    private static func sendDiscord(_ text: String, to note: NotchNotification)
        async -> Bool
    {
        let search = NotificationReplyLogic.discordSearchTerm(for: note)
        let script = NotificationReplyLogic.discordSendScript(
            searchTerm: search,
            message: text
        )
        if await runAppleScript(script) { return true }
        open(note)
        return false
    }

    private static func runAppleScript(_ source: String) async -> Bool {
        if await runUserAppleScript(source) { return true }
        return await Task.detached(priority: .userInitiated) {
            runOsascript(source)
        }.value
    }

    private static func runUserAppleScript(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            do {
                let url = try writeReplyScript(source)
                let task = try NSUserAppleScriptTask(url: url)
                task.execute(withAppleEvent: nil) { _, error in
                    withExtendedLifetime(task) {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(returning: error == nil)
                    }
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    nonisolated private static func writeReplyScript(_ source: String) throws
        -> URL
    {
        let bundleID =
            Bundle.main.bundleIdentifier ?? "com.plmls-team.Loffty"
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Scripts")
            .appendingPathComponent(bundleID)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let url = folder.appendingPathComponent(
            "reply-\(UUID().uuidString).applescript"
        )
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated private static func runOsascript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum NotificationContacts {
    struct LookupResult: Sendable {
        var handles: [String]
    }

    nonisolated static func lookup(name: String) -> LookupResult {
        var handles: [String] = []
        for term in searchTerms(from: name) {
            let hit = lookupTerm(term)
            for handle in hit.handles {
                guard
                    !handles.contains(where: {
                        $0.caseInsensitiveCompare(handle) == .orderedSame
                    })
                else { continue }
                handles.append(handle)
            }
        }
        if let phone = phoneQuery(from: name) {
            let digits = NotificationReplyLogic.digits(from: phone)
            if !handles.contains(where: {
                NotificationReplyLogic.digits(from: $0) == digits
            }) {
                handles.insert(phone, at: 0)
            }
        }
        return LookupResult(handles: handles)
    }

    static func whatsAppHandles(for note: NotchNotification) async -> [String] {
        let known = note.handles.filter {
            NotificationReplyLogic.whatsAppURL(phone: $0, text: "") != nil
        }
        if !needsContactAccess(for: note) {
            if !known.isEmpty { return known }
            if let phone = phoneQuery(from: note.sender) { return [phone] }
        }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            let store = CNContactStore()
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { return [] }
        } else if status != .authorized {
            return []
        }

        return lookup(name: note.sender).handles.filter {
            NotificationReplyLogic.whatsAppURL(phone: $0, text: "") != nil
        }
    }

    nonisolated static func needsContactAccess(for note: NotchNotification)
        -> Bool
    {
        let hasPhone = note.handles.contains {
            NotificationReplyLogic.whatsAppURL(phone: $0, text: "") != nil
        }
        return !hasPhone && phoneQuery(from: note.sender) == nil
    }

    nonisolated static func searchTerms(from sender: String) -> [String] {
        var text = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("~") {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let extras = text.range(
            of: #" and \d+ others?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[..<extras.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return [] }

        var terms: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
            guard trimmed.count >= 2 else { return }
            guard
                !terms.contains(where: {
                    $0.caseInsensitiveCompare(trimmed) == .orderedSame
                })
            else { return }
            terms.append(trimmed)
        }

        add(text)
        if let comma = text.split(separator: ",", maxSplits: 1).first {
            add(String(comma))
        }
        return terms
    }

    nonisolated static func phoneQuery(from sender: String) -> String? {
        let letters = sender.filter(\.isLetter)
        let digits = sender.filter(\.isNumber)
        guard digits.count >= 8, letters.count < 3 else { return nil }
        return digits
    }

    nonisolated private static func lookupTerm(_ term: String) -> LookupResult {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LookupResult(handles: []) }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else { return LookupResult(handles: []) }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        let contacts =
            (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))
            ?? []
        guard let contact = contacts.first else {
            return LookupResult(handles: [])
        }

        var handles: [String] = []
        handles.append(
            contentsOf: contact.phoneNumbers.map(\.value.stringValue)
        )
        handles.append(
            contentsOf: contact.emailAddresses.map { $0.value as String }
        )
        return LookupResult(handles: handles)
    }
}
