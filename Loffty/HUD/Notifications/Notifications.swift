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
        case .messages, .whatsApp: true
        case .discord: false
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

        return NotchNotification(
            id: id ?? UUID().uuidString,
            app: app,
            sender: sender,
            body: resolvedMessage,
            deliveredAt: deliveredAt,
            avatar: nil,
            handles: []
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

        return parse(
            title: title,
            subtitle: subtitle,
            body: body,
            bundleID: bundleID,
            appName: appName,
            hints: [appName, bundleID].compactMap { $0 },
            deliveredAt: deliveredAt,
            id: "db-\(recID)"
        )
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

    nonisolated static func messagesScript(target: String, text: String)
        -> String
    {
        let name = escapeAppleScript(target)
        let body = escapeAppleScript(text)
        return """
            tell application "Messages"
                try
                    set targetBuddy to first participant whose name is "\(name)"
                    send "\(body)" to targetBuddy
                on error
                    try
                        set targetChat to first chat whose name is "\(name)"
                        send "\(body)" to targetChat
                    end try
                end try
            end tell
            """
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
    private let contacts = CNContactStore()

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
        requestContactsIfNeeded()
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
        guard current != nil else { return }
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
            } else {
                sending = false
                NotificationReply.open(note)
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
            let (avatar, handles) = await Task.detached(
                priority: .userInitiated
            ) {
                NotificationContacts.lookup(name: sender)
            }.value
            guard current?.id == note.id else { return }
            var updated = note
            updated.avatar = avatar
            updated.handles = handles
            current = updated
        }
    }

    private func requestContactsIfNeeded() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined else { return }
        contacts.requestAccess(for: .contacts) { _, _ in }
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
            return false
        }
    }

    private static func sendMessages(_ text: String, to note: NotchNotification)
        async -> Bool
    {
        let targets = ([note.sender] + note.handles).filter { !$0.isEmpty }
        for target in targets {
            let script = NotificationReplyLogic.messagesScript(
                target: target,
                text: text
            )
            if await runAppleScript(script) { return true }
        }
        open(note)
        return false
    }

    private static func sendWhatsApp(_ text: String, to note: NotchNotification)
        async -> Bool
    {
        for handle in note.handles {
            if let url = NotificationReplyLogic.whatsAppURL(
                phone: handle,
                text: text
            ) {
                let ok = await MainActor.run { NSWorkspace.shared.open(url) }
                if ok { return true }
            }
        }
        open(note)
        return false
    }

    private static func runAppleScript(_ source: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&error)
            return error == nil
        }.value
    }
}

enum NotificationContacts {
    nonisolated static func lookup(name: String) -> (Data?, [String]) {
        guard canReadContacts else { return (nil, []) }
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        var matches: [CNContact] = []
        if let phone = phoneQuery(from: name) {
            let number = CNPhoneNumber(stringValue: phone)
            let found =
                (try? store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matching: number),
                    keysToFetch: keys
                )) ?? []
            matches.append(contentsOf: found)
        }
        if matches.isEmpty {
            for term in searchTerms(from: name) {
                let found =
                    (try? store.unifiedContacts(
                        matching: CNContact.predicateForContacts(
                            matchingName: term
                        ),
                        keysToFetch: keys
                    )) ?? []
                if !found.isEmpty {
                    matches = found
                    break
                }
            }
        }
        guard let contact = preferred(matches) else { return (nil, []) }
        return (imageData(from: contact), handles(from: contact))
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

    nonisolated private static var canReadContacts: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    nonisolated private static func preferred(_ contacts: [CNContact])
        -> CNContact?
    {
        contacts.first { imageData(from: $0) != nil } ?? contacts.first
    }

    nonisolated private static func imageData(from contact: CNContact) -> Data?
    {
        if contact.isKeyAvailable(CNContactThumbnailImageDataKey) {
            if let data = contact.thumbnailImageData { return data }
        }
        if contact.isKeyAvailable(CNContactImageDataKey) {
            return contact.imageData
        }
        return nil
    }

    nonisolated private static func handles(from contact: CNContact) -> [String]
    {
        var values: [String] = []
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            values.append(
                contentsOf: contact.emailAddresses.map { $0.value as String }
            )
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            values.append(
                contentsOf: contact.phoneNumbers.map(\.value.stringValue)
            )
        }
        return values
    }
}
