//
//  NotificationTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Notifications")
struct NotificationTests {
    @Test func bundleIDsMapToApps() {
        #expect(
            NotificationBannerParser.app(fromBundleID: "com.apple.MobileSMS")
                == .messages
        )
        #expect(
            NotificationBannerParser.app(fromBundleID: "net.whatsapp.WhatsApp")
                == .whatsApp
        )
        #expect(
            NotificationBannerParser.app(fromBundleID: "com.hnc.Discord")
                == .discord
        )
        #expect(
            NotificationBannerParser.app(fromBundleID: "com.apple.Safari")
                == nil
        )
    }

    @Test func appNamesMapToApps() {
        #expect(NotificationBannerParser.app(fromName: "Messages") == .messages)
        #expect(NotificationBannerParser.app(fromName: "WhatsApp") == .whatsApp)
        #expect(NotificationBannerParser.app(fromName: "Discord") == .discord)
        #expect(NotificationBannerParser.app(fromName: "Mail") == nil)
    }

    @Test func messagesAndWhatsAppSupportReply() {
        #expect(NotificationApp.messages.supportsReply)
        #expect(NotificationApp.whatsApp.supportsReply)
        #expect(!NotificationApp.discord.supportsReply)
    }

    @Test func parseUsesTitleAndBody() {
        let note = NotificationBannerParser.parse(
            title: "John Doe",
            subtitle: nil,
            body: "helloooooo",
            bundleID: "net.whatsapp.WhatsApp",
            appName: "WhatsApp"
        )
        #expect(note?.app == .whatsApp)
        #expect(note?.sender == "John Doe")
        #expect(note?.body == "helloooooo")
        #expect(note?.preview == "helloooooo")
    }

    @Test func parseSplitsCombinedDescription() {
        let note = NotificationBannerParser.parse(
            title: "John Doe: helloooooo",
            subtitle: nil,
            body: nil,
            bundleID: "",
            appName: "Messages"
        )
        #expect(note?.app == .messages)
        #expect(note?.sender == "John Doe")
        #expect(note?.body == "helloooooo")
    }

    @Test func helperAndVariantBundleIDsMapToDiscord() {
        #expect(
            NotificationBannerParser.app(
                fromBundleID: "com.hnc.Discord.helper.Renderer"
            ) == .discord
        )
        #expect(
            NotificationBannerParser.app(fromBundleID: "com.hnc.DiscordCanary")
                == .discord
        )
    }

    @Test func notificationCenterBannerUsesHints() {
        let note = NotificationBannerParser.parse(
            title: "John Doe",
            subtitle: "#general",
            body: "helloooooo",
            bundleID: "com.apple.notificationcenterui",
            appName: "Notification Center",
            hints: ["Discord"]
        )
        #expect(note?.app == .discord)
        #expect(note?.sender == "John Doe")
        #expect(note?.body == "helloooooo")
    }

    @Test func notificationCenterBannerWithoutHintsIsIgnored() {
        #expect(
            NotificationBannerParser.parse(
                title: "John Doe",
                subtitle: nil,
                body: "Hey",
                bundleID: "com.apple.notificationcenterui",
                appName: "Notification Center"
            ) == nil
        )
    }

    @Test func discordTitleSplitsSenderFromBody() {
        let note = NotificationBannerParser.parse(
            title: "Discord",
            subtitle: nil,
            body: "John Doe: helloooooo",
            bundleID: "com.hnc.Discord",
            appName: "Discord"
        )
        #expect(note?.sender == "John Doe")
        #expect(note?.body == "helloooooo")
    }

    @Test func parseIgnoresUnknownApps() {
        #expect(
            NotificationBannerParser.parse(
                title: "Alert",
                subtitle: nil,
                body: "Something happened",
                bundleID: "com.apple.Safari",
                appName: "Safari"
            ) == nil
        )
    }

    @Test func relativeLabelBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            NotificationBannerParser.relativeLabel(
                from: now.addingTimeInterval(-10),
                now: now
            ) == "Now"
        )
        #expect(
            NotificationBannerParser.relativeLabel(
                from: now.addingTimeInterval(-120),
                now: now
            ) == "2m"
        )
        #expect(
            NotificationBannerParser.relativeLabel(
                from: now.addingTimeInterval(-7200),
                now: now
            ) == "2h"
        )
        #expect(
            NotificationBannerParser.relativeLabel(
                from: now.addingTimeInterval(-172_800),
                now: now
            ) == "2d"
        )
    }

    @Test func initialsUseGivenAndFamily() {
        #expect(NotificationBannerParser.initials(from: "John Doe") == "JD")
        #expect(NotificationBannerParser.initials(from: "Liam") == "L")
        #expect(NotificationBannerParser.initials(from: "") == "")
    }

    @Test func shouldAcceptHonoursPerAppFlags() {
        #expect(
            NotificationBannerParser.shouldAccept(
                app: .messages,
                messages: true,
                whatsApp: false,
                discord: false
            )
        )
        #expect(
            !NotificationBannerParser.shouldAccept(
                app: .whatsApp,
                messages: true,
                whatsApp: false,
                discord: true
            )
        )
        #expect(
            NotificationBannerParser.shouldAccept(
                app: .discord,
                messages: false,
                whatsApp: false,
                discord: true
            )
        )
    }

    @Test func duplicateFingerprintWithinWindow() {
        let first = NotificationBannerParser.parse(
            title: "John Doe",
            subtitle: nil,
            body: "Hey",
            bundleID: "com.apple.MobileSMS",
            appName: "Messages",
            deliveredAt: Date(timeIntervalSince1970: 50)
        )!
        let second = NotificationBannerParser.parse(
            title: "John Doe",
            subtitle: nil,
            body: "Hey",
            bundleID: "com.apple.MobileSMS",
            appName: "Messages",
            deliveredAt: Date(timeIntervalSince1970: 51)
        )!
        #expect(
            NotificationBannerParser.isDuplicate(
                incoming: second,
                current: first,
                now: Date(timeIntervalSince1970: 51.5)
            )
        )
        #expect(
            !NotificationBannerParser.isDuplicate(
                incoming: second,
                current: first,
                now: Date(timeIntervalSince1970: 54)
            )
        )
    }

    @Test func appleScriptEscapesQuotes() {
        #expect(
            NotificationReplyLogic.escapeAppleScript(#"He said "hi""#)
                == #"He said \"hi\""#
        )
        let script = NotificationReplyLogic.messagesScript(
            target: "pmanchuelle@icloud.com",
            text: "Yeah sure"
        )
        #expect(
            script
                == #"tell application "Messages" to send "Yeah sure" to buddy "pmanchuelle@icloud.com""#
        )
        #expect(
            NotificationReplyLogic.messagesChatScript(
                target: "Liam",
                text: "Yeah sure"
            )
                == #"tell application "Messages" to send "Yeah sure" to chat "Liam""#
        )
        #expect(
            NotificationReplyLogic.namedChat("Family") == "Family"
        )
        #expect(NotificationReplyLogic.namedChat("") == nil)
        #expect(
            NotificationReplyLogic.isGroupChat(
                guid: "iMessage;-;chat999",
                identifier: "chat999"
            )
        )
        #expect(
            !NotificationReplyLogic.isGroupChat(
                guid: "iMessage;-;+14155550100",
                identifier: "+14155550100"
            )
        )
        #expect(
            NotificationReplyLogic.isGroupChat(
                guid: "iMessage;+;chat999",
                identifier: "group"
            )
        )
        #expect(NotificationReplyLogic.namedChat("  ") == nil)
        #expect(NotificationReplyLogic.isHandleTarget("liam@icloud.com"))
        #expect(NotificationReplyLogic.isHandleTarget("+14155550100"))
        #expect(!NotificationReplyLogic.isHandleTarget("Liam"))
        #expect(NotificationReplyLogic.digits(from: "+1 (415) 555-0100") == "14155550100")
        let existing = NotificationReplyLogic.messagesExistingChatScript(
            guid: "iMessage;-;chat999",
            identifier: "chat999",
            name: "Family",
            text: "Yeah sure"
        )
        #expect(existing.contains(#"send "Yeah sure" to c"#))
        #expect(!existing.contains("buddy"))
    }

    @Test func preferredBuddyHandleUsesEmailOnce() {
        #expect(
            NotificationReplyLogic.preferredBuddyHandle(
                chatHandle: "+1 (415) 555-0100",
                extras: ["liam@icloud.com"]
            ) == "liam@icloud.com"
        )
        #expect(
            NotificationReplyLogic.preferredBuddyHandle(
                chatHandle: "pmanchuelle@icloud.com",
                extras: ["+14155550100"]
            ) == "pmanchuelle@icloud.com"
        )
        #expect(
            NotificationReplyLogic.preferredBuddyHandle(
                chatHandle: "+14155550100",
                extras: []
            ) == "+14155550100"
        )
        #expect(
            NotificationReplyLogic.preferredBuddyHandle(
                chatHandle: "Liam",
                extras: []
            ) == nil
        )
    }

    @Test func messagesURLUsesSmsOrIMessage() {
        let sms = NotificationReplyLogic.messagesURL(
            handle: "+1 (415) 555-0100",
            text: "Yeah sure"
        )
        #expect(sms?.scheme == "sms")
        #expect(sms?.absoluteString.contains("14155550100") == true)
        #expect(sms?.absoluteString.contains("body=Yeah") == true)
        let imessage = NotificationReplyLogic.messagesURL(
            handle: "liam@icloud.com",
            text: "Yeah sure"
        )
        #expect(imessage?.scheme == "imessage")
        #expect(
            NotificationReplyLogic.messagesURL(handle: "Liam", text: "x")
                == nil
        )
    }

    @Test func whatsAppURLUsesDigitsOnly() {
        let url = NotificationReplyLogic.whatsAppURL(
            phone: "+1 (415) 555-0100",
            text: "Yeah sure"
        )
        #expect(url?.scheme == "whatsapp")
        #expect(url?.absoluteString.contains("phone=14155550100") == true)
        #expect(
            NotificationReplyLogic.whatsAppURL(phone: "abc", text: "x") == nil
        )
    }

    @Test func contactSearchTermsStripWhatsAppAndGroupNoise() {
        #expect(
            NotificationContacts.searchTerms(from: "Jane Smith")
                == ["Jane Smith"]
        )
        #expect(
            NotificationContacts.searchTerms(from: "~Jane Smith")
                == ["Jane Smith"]
        )
        #expect(
            NotificationContacts.searchTerms(from: "Jane Smith and 2 others")
                == ["Jane Smith"]
        )
        #expect(
            NotificationContacts.searchTerms(from: "Jane, Bob")
                == ["Jane, Bob", "Jane"]
        )
    }

    @Test func contactPhoneQueryUsesMostlyDigits() {
        #expect(
            NotificationContacts.phoneQuery(from: "+1 (415) 555-0100")
                == "14155550100"
        )
        #expect(NotificationContacts.phoneQuery(from: "Jane Smith") == nil)
        #expect(NotificationContacts.phoneQuery(from: "123") == nil)
    }

    @Test func messagesChatLookupPrefersTheReceivingThread() {
        let now = Date()
        let oneOnOne = MessagesChatLookup.Candidate(
            guid: "iMessage;-;+14155550100",
            displayName: "Liam",
            chatIdentifier: "+14155550100",
            text: "hello",
            date: now.addingTimeInterval(-3600),
            handle: "+14155550100"
        )
        let group = MessagesChatLookup.Candidate(
            guid: "iMessage;-;chat999",
            displayName: "Family",
            chatIdentifier: "chat999",
            text: "hello",
            date: now,
            handle: "+14155550100"
        )
        let hit = MessagesChatLookup.match(
            candidates: [oneOnOne, group],
            text: "hello",
            sender: "Liam",
            at: now,
            handles: ["+14155550100"]
        )
        #expect(hit?.guid == "iMessage;-;chat999")

        let named = MessagesChatLookup.match(
            candidates: [oneOnOne, group],
            text: "hello",
            sender: "Family",
            at: now,
            handles: []
        )
        #expect(named?.guid == "iMessage;-;chat999")
        #expect(
            MessagesChatLookup.textMatches(
                notification: "Liam: hello there",
                message: "hello there"
            )
        )
        #expect(
            MessagesChatLookup.parseChatID("iMessage;-;chat999")
                == "iMessage;-;chat999"
        )
        #expect(MessagesChatLookup.parseChatID("Liam") == nil)
        #expect(
            MessagesChatLookup.date(fromAppleTime: 750_000_000)
                .timeIntervalSinceReferenceDate == 750_000_000
        )
        #expect(
            MessagesChatLookup.chatID(fromPlist: [
                "req": ["titl": "Liam", "thid": "iMessage;+;chat999"]
            ]) == "iMessage;+;chat999"
        )
        #expect(
            MessagesChatLookup.parseChatID("SMS;-;+14155550100")
                == "SMS;-;+14155550100"
        )
        #expect(MessagesChatLookup.parseChatID("iMessage;-;") == nil)
        #expect(
            MessagesChatLookup.textMatches(
                notification: "abcdefghij extra",
                message: "abcdefghij extra words"
            )
        )
        #expect(
            !MessagesChatLookup.textMatches(
                notification: "hi",
                message: "history"
            )
        )
        let emptyGuid = MessagesChatLookup.Candidate(
            guid: "",
            displayName: "Liam",
            chatIdentifier: "+14155550100",
            text: "hello",
            date: now,
            handle: "+14155550100"
        )
        #expect(
            MessagesChatLookup.match(
                candidates: [emptyGuid, oneOnOne],
                text: "hello",
                sender: "Liam",
                at: now.addingTimeInterval(-3600),
                handles: ["+14155550100"]
            )?.guid == "iMessage;-;+14155550100"
        )
        let nano = MessagesChatLookup.date(
            fromAppleTime: 1_000_000_000_000_000_000
        )
        #expect(
            abs(nano.timeIntervalSinceReferenceDate - 1_000_000_000) < 1
        )
    }

    @Test func decodeRecordFromPlist() throws {
        let plist: [String: Any] = [
            "req": [
                "titl": "John Doe",
                "body": "helloooooo",
            ]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        let note = NotificationBannerParser.decodeRecord(
            data: data,
            bundleID: "net.whatsapp.WhatsApp",
            deliveredAt: Date(timeIntervalSince1970: 1),
            recID: 9
        )
        #expect(note?.id == "db-9")
        #expect(note?.sender == "John Doe")
        #expect(note?.app == .whatsApp)
    }

    @Test func decodeRecordExtractsMessagesChatID() throws {
        let plist: [String: Any] = [
            "req": [
                "titl": "Liam",
                "body": "helloooooo",
                "thid": "iMessage;-;chat999",
            ]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        let note = NotificationBannerParser.decodeRecord(
            data: data,
            bundleID: "com.apple.MobileSMS",
            deliveredAt: Date(timeIntervalSince1970: 1),
            recID: 10
        )
        #expect(note?.app == .messages)
        #expect(note?.chatID == "iMessage;-;chat999")
    }

    @Test func alertStyleDecodesFromFlags() {
        let none = NotificationStyleCheck.allowFlag
        #expect(NotificationStyleCheck.alertStyle(flags: none) == .none)
        #expect(!NotificationStyleCheck.showsOnDesktop(flags: none))
        #expect(NotificationStyleCheck.hidesSystemBanner(flags: none))

        let banners =
            NotificationStyleCheck.allowFlag | NotificationStyleCheck.bannerFlag
        #expect(NotificationStyleCheck.alertStyle(flags: banners) == .banners)
        #expect(NotificationStyleCheck.showsOnDesktop(flags: banners))
        #expect(!NotificationStyleCheck.hidesSystemBanner(flags: banners))

        let alerts =
            NotificationStyleCheck.allowFlag | NotificationStyleCheck.alertFlag
        #expect(NotificationStyleCheck.alertStyle(flags: alerts) == .alerts)
        #expect(NotificationStyleCheck.showsOnDesktop(flags: alerts))
        #expect(!NotificationStyleCheck.hidesSystemBanner(flags: alerts))
    }

    @Test func hidesSystemBannerRequiresAllowNotifications() {
        #expect(NotificationStyleCheck.alertStyle(flags: 0) == .none)
        #expect(!NotificationStyleCheck.hidesSystemBanner(flags: 0))
        #expect(!NotificationStyleCheck.allowsNotifications(flags: 0))
        #expect(
            NotificationStyleCheck.allowsNotifications(
                flags: NotificationStyleCheck.allowFlag
            )
        )
    }

    @Test func currentFlagsFindsBundleAndIgnoresOthers() {
        let apps: [[String: Any]] = [
            ["bundle-id": "com.apple.Safari", "flags": 8],
            [
                "bundle-id": "com.apple.MobileSMS",
                "flags": NotificationStyleCheck.allowFlag,
            ],
        ]
        #expect(
            NotificationStyleCheck.currentFlags(
                bundleID: "com.apple.MobileSMS",
                apps: apps
            ) == NotificationStyleCheck.allowFlag
        )
        #expect(
            NotificationStyleCheck.currentFlags(
                bundleID: "net.whatsapp.WhatsApp",
                apps: apps
            ) == nil
        )
    }

    @Test func systemCenterPrefixIsStrippedFromBundleIDs() {
        #expect(
            NotificationStyleCheck.normalizedBundleID(
                "_SYSTEM_CENTER_:com.apple.MobileSMS"
            ) == "com.apple.MobileSMS"
        )
        let apps: [[String: Any]] = [
            [
                "bundle-id": "_SYSTEM_CENTER_:net.whatsapp.WhatsApp",
                "flags": NotificationStyleCheck.allowFlag,
            ]
        ]
        #expect(
            NotificationStyleCheck.hidesSystemBanner(
                for: .whatsApp,
                apps: apps
            )
        )
        #expect(
            !NotificationStyleCheck.hidesSystemBanner(
                for: .messages,
                apps: apps
            )
        )
    }

    @Test func hidesSystemBannerChecksAlternateBundleIDs() {
        let apps: [[String: Any]] = [
            [
                "bundle-id": "net.whatsapp.WhatsAppDesktop",
                "flags": NotificationStyleCheck.allowFlag,
            ]
        ]
        #expect(
            NotificationStyleCheck.hidesSystemBanner(
                for: .whatsApp,
                apps: apps
            )
        )
    }
}

@Suite("Notification metrics")
struct NotificationMetricsTests {
    @Test func compactIsTallerThanCollapsedAndNarrowerThanExpanded() {
        let collapsed = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false
        )
        let compact = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            notification: true,
            notificationPreview: "its on my git",
            notificationSender: "John Doe",
            notificationCanReply: true
        )
        let expanded = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            notification: true,
            notificationExpanded: true,
            notificationPreview: "its on my git",
            notificationSender: "John Doe",
            notificationCanReply: true
        )
        #expect(
            compact.height
                == 32
                + NotificationLayout.compactExtra(
                    message: "its on my git",
                    sender: "John Doe",
                    notchW: 200,
                    canReply: true
                )
        )
        #expect(
            NotificationLayout.wrappedLineCount(
                "its on my git",
                width: 220
            ) == 1
        )
        #expect(
            NotificationLayout.wrappedLineCount(
                String(repeating: "a", count: 90),
                width: 160
            ) == 3
        )
        #expect(
            NotificationLayout.compactExtra(
                message: "its on my git",
                sender: "John Doe",
                canReply: true
            )
                < NotificationLayout.compactExtra(
                    message: String(repeating: "a", count: 90),
                    sender: "John Doe",
                    canReply: true
                )
        )
        #expect(NotificationLayout.compactMessageLines == 3)
        #expect(compact.width > collapsed.width)
        #expect(compact.width <= NotificationLayout.expandedWidth)
        #expect(expanded.width == NotificationLayout.expandedWidth)
        #expect(
            expanded.height
                == NotificationLayout.expandedHeight(
                    message: "its on my git",
                    notchH: 32,
                    canReply: true
                )
        )
        #expect(
            expanded.width > compact.width || expanded.height > compact.height
        )
        #expect(
            expanded.height
                >= compact.height
                + NotificationLayout.expandedComposerHeight
        )
        #expect(compact.bottomRadius == NotificationLayout.compactBottomRadius)
        #expect(expanded.bottomRadius == NotificationLayout.expandedBottomRadius)
    }

    @Test func compactWidthGrowsWithContentThenCaps() {
        let short = NotificationLayout.compactWidth(
            notchW: 200,
            sender: "Jo",
            message: "hi",
            canReply: false
        )
        let long = NotificationLayout.compactWidth(
            notchW: 200,
            sender: "A very long contact name",
            message: String(repeating: "hello ", count: 20),
            canReply: true
        )
        #expect(short >= 200 + 2 * NotificationLayout.compactTopRadius)
        #expect(long > short)
        #expect(long == NotificationLayout.expandedWidth)
    }

    @Test func expandedHeightGrowsWithMessageAndReply() {
        let short = NotificationLayout.expandedHeight(
            message: "hi",
            notchH: 32,
            canReply: false
        )
        let shortReply = NotificationLayout.expandedHeight(
            message: "hi",
            notchH: 32,
            canReply: true
        )
        let longReply = NotificationLayout.expandedHeight(
            message: String(repeating: "hello ", count: 24),
            notchH: 32,
            canReply: true
        )
        let longDraft = NotificationLayout.expandedHeight(
            message: "hi",
            notchH: 32,
            canReply: true,
            draft: String(repeating: "hello ", count: 24)
        )
        #expect(shortReply > short)
        #expect(longReply > shortReply)
        #expect(longDraft > shortReply)
        #expect(
            shortReply - short
                >= NotificationLayout.expandedStackSpacing
                + NotificationLayout.expandedComposerHeight
        )
        #expect(
            NotificationLayout.composerHeight(draft: "")
                == NotificationLayout.expandedComposerHeight
        )
        #expect(
            NotificationLayout.composerHeight(
                draft: String(repeating: "hello ", count: 24)
            ) > NotificationLayout.expandedComposerHeight
        )
    }

    @Test func composerFollowsIslandCornersWithUniformInset() {
        let pad = NotificationLayout.composerHorizontalPadding(
            topRadius: NotificationLayout.expandedTopRadius
        )
        #expect(
            pad
                == NotificationLayout.expandedTopRadius
                + NotificationLayout.composerInset
        )
        let height = NotificationLayout.expandedComposerHeight
        let inner = NotificationLayout.composerCornerRadius(
            islandBottomRadius: NotificationLayout.expandedBottomRadius,
            height: height
        )
        #expect(inner <= height / 2)
        #expect(inner == min(
            height / 2,
            NotificationLayout.expandedBottomRadius
                - NotificationLayout.composerInset
        ))
    }

    @Test func replyCenterTracksBottomRightCorner() {
        let compact = CGSize(width: 280, height: 86)
        let expanded = CGSize(width: 360, height: 140)
        let a = NotificationLayout.replyCenter(
            in: compact,
            topRadius: NotificationLayout.compactTopRadius,
            bottomRadius: NotificationLayout.compactBottomRadius
        )
        let b = NotificationLayout.replyCenter(
            in: expanded,
            topRadius: NotificationLayout.expandedTopRadius,
            bottomRadius: NotificationLayout.expandedBottomRadius
        )
        let radius = NotificationLayout.replySize / 2
        #expect(a.x > compact.width * 0.6)
        #expect(a.y > compact.height * 0.5)
        #expect(b.x > a.x)
        #expect(b.y > a.y)
        #expect(a.x + radius <= compact.width - NotificationLayout.compactTopRadius + 0.6)
        #expect(a.y + radius <= compact.height + 0.6)
        #expect(
            b.x + radius
                <= expanded.width - NotificationLayout.expandedTopRadius + 0.6
        )
        #expect(b.y + radius <= expanded.height + 0.6)

        let corner = CGPoint(
            x: compact.width
                - NotificationLayout.compactTopRadius
                - NotificationLayout.compactBottomRadius,
            y: compact.height - NotificationLayout.compactBottomRadius
        )
        let dist = hypot(a.x - corner.x, a.y - corner.y)
        #expect(
            dist
                <= NotificationLayout.compactBottomRadius
                - NotificationLayout.replyEdgePadding + 0.6
        )
    }

    @Test func airDropWinsOverNotification() {
        let m = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            airDrop: true,
            notification: true,
            notificationExpanded: true
        )
        #expect(m.height == 112)
        #expect(m.width == 380)
    }

    @Test func expandedNotificationHeightUsesDraft() {
        let short = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            notification: true,
            notificationExpanded: true,
            notificationPreview: "hi",
            notificationSender: "John Doe",
            notificationCanReply: true,
            notificationDraft: ""
        )
        let long = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            notification: true,
            notificationExpanded: true,
            notificationPreview: "hi",
            notificationSender: "John Doe",
            notificationCanReply: true,
            notificationDraft: String(repeating: "hello ", count: 24)
        )
        #expect(long.height > short.height)
        #expect(short.topRadius == NotificationLayout.expandedTopRadius)
    }
}

@Suite("Notification controller")
struct NotificationControllerTests {
    private func sampleNote(app: NotificationApp = .messages)
        -> NotchNotification
    {
        NotchNotification(
            id: "test-\(UUID().uuidString)",
            app: app,
            sender: "John Doe",
            body: "helloooooo",
            deliveredAt: Date(),
            avatar: nil,
            handles: []
        )
    }

    @Test @MainActor func presentHonoursMasterAndPerAppToggles() {
        let controller = NotificationController.shared
        let settings = AppSettings.shared
        let originalHUD = settings.notificationsHUD
        let originalMessages = settings.notificationMessages
        defer {
            settings.notificationsHUD = originalHUD
            settings.notificationMessages = originalMessages
            controller.dismiss(animated: false)
        }

        settings.notificationsHUD = false
        controller.present(sampleNote())
        #expect(controller.current == nil)

        settings.notificationsHUD = true
        settings.notificationMessages = false
        controller.present(sampleNote())
        #expect(controller.current == nil)

        settings.notificationMessages = true
        controller.present(sampleNote())
        #expect(controller.current?.sender == "John Doe")
        #expect(controller.current?.app == .messages)
    }

    @Test @MainActor func beginReplyPinsUntilDismiss() {
        let controller = NotificationController.shared
        let settings = AppSettings.shared
        let originalHUD = settings.notificationsHUD
        defer {
            settings.notificationsHUD = originalHUD
            controller.dismiss(animated: false)
        }

        settings.notificationsHUD = true
        controller.present(sampleNote())
        controller.beginReply()
        #expect(controller.isReplying)
        #expect(controller.isExpanded)
        #expect(controller.isPinned)
        #expect(controller.wantsKeyWindow)

        controller.collapse()
        #expect(controller.isReplying)
        #expect(controller.isExpanded)

        controller.dismiss(animated: false)
        #expect(controller.current == nil)
        #expect(!controller.isReplying)
        #expect(!controller.isPinned)
    }
}
