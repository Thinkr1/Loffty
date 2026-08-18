//
//  ArtworkTests.swift
//  LofftyTests
//

import AppKit
import SwiftUI
import Testing

@testable import Loffty

@Suite("Artwork")
struct ArtworkTests {
    @Test func thumbnailLeavesSmallImageUnchanged() {
        let data = solidJPEG(size: 32)
        #expect(ArtworkProcessor.thumbnailData(from: data) == data)
    }

    @Test func thumbnailDownscalesLargeImage() {
        let data = solidJPEG(size: 400)
        let out = ArtworkProcessor.thumbnailData(from: data)
        #expect(out.count <= data.count)
        #expect(out != data)
    }

    @Test func aspectRatioDetectsLandscapeArtwork() {
        let square = solidJPEG(width: 40, height: 40)
        let wide = solidJPEG(width: 160, height: 90)
        #expect(abs(ArtworkProcessor.aspectRatio(from: square) - 1) < 0.02)
        #expect(abs(ArtworkProcessor.aspectRatio(from: wide) - (16 / 9)) < 0.05)
    }

    @Test func nowPlayingResolvedBundleAndDisplayAspect() {
        var np = NowPlaying()
        np.bundleIdentifier = "com.apple.WebKit.WebContent"
        np.parentApplicationBundleIdentifier = "com.apple.Safari"
        #expect(np.resolvedBundleIdentifier == "com.apple.Safari")

        np.isVideo = true
        np.artworkAspectRatio = 1
        #expect(np.displayArtworkAspect == MediaParsing.videoAspectRatio)
        np.artworkAspectRatio = 1.77
        #expect(abs(np.displayArtworkAspect - 1.77) < 0.001)
        np.isVideo = false
        #expect(np.displayArtworkAspect == 1)
    }

    @Test func albumAccentNilFallsBack() {
        let color = AlbumColor.accent(from: nil)
        #expect(color == Color.white.opacity(0.5))
    }

    private func solidJPEG(size: Int) -> Data {
        solidJPEG(width: size, height: size)
    }

    private func solidJPEG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .jpeg, properties: [:])!
    }
}
