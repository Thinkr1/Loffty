//
//  LockMockWallpaperTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Lock screen mock wallpaper")
struct LockMockWallpaperTests {
    @Test func fallbackSystemDesktopsAreRejected() {
        #expect(
            LockMockWallpaper.isFallbackSystemDesktop(
                URL(fileURLWithPath: "/System/Library/Desktop Pictures/DefaultDesktop.heic")
            )
        )
        #expect(
            LockMockWallpaper.isFallbackSystemDesktop(
                URL(fileURLWithPath: "/Library/Desktop Pictures/.wallpapers/plain.png")
            )
        )
        #expect(
            LockMockWallpaper.isFallbackSystemDesktop(
                URL(fileURLWithPath: "/Library/Desktop Pictures/screensaver-thumb.png")
            )
        )
        #expect(
            !LockMockWallpaper.isFallbackSystemDesktop(
                URL(fileURLWithPath: "/Users/alex/Pictures/wallpaper.jpg")
            )
        )
    }

    @Test func wallpaperWindowScorePrefersCurrentSpaceThenSize() {
        #expect(
            LockMockWallpaper.wallpaperWindowScore(
                name: "Menu Bar",
                boundsSize: CGSize(width: 1512, height: 982),
                targetName: "Wallpaper-abc",
                screenSize: CGSize(width: 1512, height: 982)
            ) == nil
        )
        #expect(
            LockMockWallpaper.wallpaperWindowScore(
                name: "Wallpaper-abc",
                boundsSize: CGSize(width: 800, height: 600),
                targetName: "Wallpaper-abc",
                screenSize: CGSize(width: 1512, height: 982)
            ) == 0
        )
        #expect(
            LockMockWallpaper.wallpaperWindowScore(
                name: "Wallpaper-other",
                boundsSize: CGSize(width: 1512, height: 982),
                targetName: "Wallpaper-abc",
                screenSize: CGSize(width: 1512, height: 982)
            ) == 10
        )
        #expect(
            LockMockWallpaper.wallpaperWindowScore(
                name: "Wallpaper-other",
                boundsSize: nil,
                targetName: "Wallpaper-abc",
                screenSize: CGSize(width: 1512, height: 982)
            ) == 100
        )
    }

    @Test func imageURLSkipsScreenSaverAndMissingFiles() {
        let exists: (URL) -> Bool = { $0.path.hasSuffix("present.jpg") }
        #expect(
            LockMockWallpaper.imageURL(
                fromDesktop: [
                    "Content": [
                        "Choices": [
                            [
                                "Provider": "com.apple.wallpaper.choice.screen-saver",
                                "Files": ["/tmp/present.jpg"],
                            ]
                        ]
                    ]
                ],
                fileExists: exists
            ) == nil
        )
        #expect(
            LockMockWallpaper.imageURL(
                fromDesktop: [
                    "Content": [
                        "Choices": [
                            [
                                "Provider": "com.apple.wallpaper.choice.image",
                                "Files": ["/tmp/missing.jpg", "/tmp/present.jpg"],
                            ]
                        ]
                    ]
                ],
                fileExists: exists
            )?.path == "/tmp/present.jpg"
        )
    }

    @Test func imageURLResolvesAerialThumbnail() {
        let thumb = URL(
            fileURLWithPath:
                "/tmp/home/Library/Application Support/com.apple.wallpaper/aerials/thumbnails/asset-1.png"
        )
        let url = LockMockWallpaper.imageURL(
            fromDesktop: [
                "Content": [
                    "Choices": [
                        [
                            "Provider": "com.apple.wallpaper.choice.aerial",
                            "Configuration": ["assetID": "asset-1"],
                        ]
                    ]
                ]
            ],
            fileExists: { $0 == thumb },
            homeDirectory: "/tmp/home"
        )
        #expect(url == thumb)
    }
}
