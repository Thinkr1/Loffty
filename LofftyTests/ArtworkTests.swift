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

    @Test func albumAccentNilFallsBack() {
        let color = AlbumColor.accent(from: nil)
        #expect(color == Color.white.opacity(0.5))
    }

    private func solidJPEG(size: Int) -> Data {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .jpeg, properties: [:])!
    }
}
