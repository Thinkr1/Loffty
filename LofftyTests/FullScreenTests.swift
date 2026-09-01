//
//  FullScreenTests.swift
//  LofftyTests
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Loffty

@Suite("Full screen hide")
struct FullScreenTests {
    @Test func shouldHideRequiresFullScreen() {
        #expect(
            !FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: true,
                selectedBundleIDs: ["org.videolan.vlc"],
                frontmostBundleID: "org.videolan.vlc",
                isFullScreen: false
            )
        )
    }

    @Test func shouldHideAnyFullScreenApp() {
        #expect(
            FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: true,
                selectedBundleIDs: [],
                frontmostBundleID: "com.apple.Safari",
                isFullScreen: true
            )
        )
    }

    @Test func shouldHideOnlySelectedAppsWhenGlobalOff() {
        #expect(
            FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: false,
                selectedBundleIDs: [
                    "com.apple.QuickTimePlayerX", "org.videolan.vlc",
                ],
                frontmostBundleID: "org.videolan.vlc",
                isFullScreen: true
            )
        )
        #expect(
            !FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: false,
                selectedBundleIDs: ["org.videolan.vlc"],
                frontmostBundleID: "com.apple.Safari",
                isFullScreen: true
            )
        )
    }

    @Test func shouldHideIgnoresMissingBundle() {
        #expect(
            !FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: true,
                selectedBundleIDs: [],
                frontmostBundleID: nil,
                isFullScreen: true
            )
        )
        #expect(
            !FullScreenPolicy.shouldHideNotch(
                hideInAnyFullScreen: true,
                selectedBundleIDs: [],
                frontmostBundleID: "",
                isFullScreen: true
            )
        )
    }

    @Test func ignoresSystemUIBundleIDs() {
        #expect(!FullScreenDetection.shouldConsider(bundleID: ""))
        #expect(!FullScreenDetection.shouldConsider(bundleID: "com.apple.dock"))
        #expect(
            !FullScreenDetection.shouldConsider(
                bundleID: "com.apple.loginwindow"
            )
        )
        #expect(
            FullScreenDetection.shouldConsider(
                bundleID: "com.apple.QuickTimePlayerX"
            )
        )
        #expect(
            FullScreenDetection.shouldConsider(bundleID: "org.videolan.vlc")
        )
    }

    @Test func fullScreenBoundsCoverTheDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(
            FullScreenDetection.isFullScreenBounds(
                screen,
                screenQuartz: screen,
                layer: 0
            )
        )
        #expect(
            FullScreenDetection.isFullScreenBounds(
                CGRect(x: 1, y: 1, width: 1510, height: 980),
                screenQuartz: screen,
                layer: 0
            )
        )
    }

    @Test func zoomedWindowBelowMenuBarIsNotFullScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let zoomed = CGRect(x: 0, y: 38, width: 1512, height: 874)
        #expect(
            !FullScreenDetection.isFullScreenBounds(
                zoomed,
                screenQuartz: screen,
                layer: 0
            )
        )
    }

    @Test func menuBarLayerIsNotFullScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(
            !FullScreenDetection.isFullScreenBounds(
                screen,
                screenQuartz: screen,
                layer: 25
            )
        )
    }

    @Test func quartzFrameMapsPrimaryDisplayToOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let quartz = FullScreenDetection.quartzFrame(
            screenFrame: primary,
            primaryFrame: primary
        )
        #expect(quartz == CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    @Test func quartzFrameFlipsSecondaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: -50, width: 1920, height: 1080)
        let quartz = FullScreenDetection.quartzFrame(
            screenFrame: external,
            primaryFrame: primary
        )
        #expect(quartz.minX == 1512)
        #expect(quartz.width == 1920)
        #expect(quartz.height == 1080)
        #expect(quartz.minY == primary.maxY - external.maxY)
    }

    @Test func bundleIdentifierReadsInfoPlist() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LofftyFullScreen-\(UUID().uuidString).app",
                isDirectory: true
            )
        let contents = dir.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let info = contents.appendingPathComponent("Info.plist")
        let plist: NSDictionary = ["CFBundleIdentifier": "org.videolan.vlc"]
        #expect(plist.write(to: info, atomically: true))
        #expect(
            FullScreenDetection.bundleIdentifier(at: dir) == "org.videolan.vlc"
        )
    }
}

@Suite("Notch edge style")
struct NotchEdgeStyleTests {
    @Test func rawValueRoundTrip() {
        for style in NotchEdgeStyle.allCases {
            #expect(NotchEdgeStyle(rawValue: style.rawValue) == style)
        }
    }

    @Test func titles() {
        #expect(NotchEdgeStyle.off.title == "Off")
        #expect(NotchEdgeStyle.subtle.title == "Subtle line")
        #expect(NotchEdgeStyle.accent.title == "Album accent")
    }

    @Test func shouldDrawFollowsFullScreenOnlyWhenSettingIsOff() {
        #expect(
            !NotchEdgeStyle.shouldDraw(
                style: .off,
                showWhenNotFullScreen: true,
                isFullScreen: true
            )
        )
        #expect(
            NotchEdgeStyle.shouldDraw(
                style: .subtle,
                showWhenNotFullScreen: true,
                isFullScreen: false
            )
        )
        #expect(
            !NotchEdgeStyle.shouldDraw(
                style: .subtle,
                showWhenNotFullScreen: false,
                isFullScreen: false
            )
        )
        #expect(
            NotchEdgeStyle.shouldDraw(
                style: .accent,
                showWhenNotFullScreen: false,
                isFullScreen: true
            )
        )
    }
}

@Suite("Liquid Glass tint")
struct LiquidGlassTintTests {
    @Test func rawValueRoundTrip() {
        for tint in LiquidGlassTint.allCases {
            #expect(LiquidGlassTint(rawValue: tint.rawValue) == tint)
        }
    }

    @Test func titles() {
        #expect(LiquidGlassTint.clear.title == "Clear")
        #expect(LiquidGlassTint.regular.title == "Regular")
        #expect(LiquidGlassTint.identity.title == "Identity")
    }

    @Test func resolvedFollowsFullScreen() {
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: false,
                windowed: .clear,
                fullScreen: .regular
            ) == .clear
        )
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: true,
                windowed: .clear,
                fullScreen: .regular
            ) == .regular
        )
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: false,
                windowed: .regular,
                fullScreen: .clear
            ) == .regular
        )
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: true,
                windowed: .regular,
                fullScreen: .clear
            ) == .clear
        )
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: true,
                windowed: .clear,
                fullScreen: .identity
            ) == .identity
        )
        #expect(
            LiquidGlassTint.resolved(
                isFullScreen: false,
                windowed: .identity,
                fullScreen: .regular
            ) == .identity
        )
    }
}

@Suite("Liquid Glass colour tint")
struct LiquidGlassColorTintTests {
    @Test func rawValueRoundTrip() {
        for tint in LiquidGlassColorTint.allCases {
            #expect(LiquidGlassColorTint(rawValue: tint.rawValue) == tint)
        }
    }

    @Test func titles() {
        #expect(LiquidGlassColorTint.none.title == "None")
        #expect(LiquidGlassColorTint.color.title == "Colour")
    }

    @Test func colorCodecRoundTripsComponents() {
        let color = Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.4)
        let encoded = LiquidGlassColorCodec.encode(color)
        let decoded = LiquidGlassColorCodec.decode(encoded)
        #expect(LiquidGlassColorCodec.encode(decoded) == encoded)
    }

    @Test func colorCodecFallsBackForInvalidRaw() {
        let decoded = LiquidGlassColorCodec.decode("not-a-color")
        #expect(
            LiquidGlassColorCodec.encode(decoded)
                == LiquidGlassColorCodec.encode(.white)
        )
    }
}
