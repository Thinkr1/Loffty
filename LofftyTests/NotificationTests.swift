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
            target: "Liam",
            text: "Yeah sure"
        )
        #expect(script.contains("whose name is \"Liam\""))
        #expect(script.contains("send \"Yeah sure\""))
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
            notificationPreview: "its on my git"
        )
        let expanded = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: false,
            hudActive: false,
            notification: true,
            notificationExpanded: true
        )
        #expect(
            compact.height
                == 32
                + NotificationLayout.compactExtra(message: "its on my git")
        )
        #expect(NotificationLayout.estimatedLines("its on my git") == 1)
        #expect(
            NotificationLayout.estimatedLines(String(repeating: "a", count: 90))
                == 3
        )
        #expect(
            NotificationLayout.compactExtra(message: "its on my git")
                < NotificationLayout.compactExtra(
                    message: String(repeating: "a", count: 90)
                )
        )
        #expect(NotificationLayout.compactMessageLines == 3)
        #expect(compact.width > collapsed.width)
        #expect(expanded.width == NotificationLayout.expandedWidth)
        #expect(expanded.height == NotificationLayout.expandedHeight)
        #expect(expanded.width > compact.width || expanded.height > compact.height)
        #expect(compact.bottomRadius == 22)
        #expect(expanded.bottomRadius == 28)
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
}
