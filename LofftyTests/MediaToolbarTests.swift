//
//  MediaToolbarTests.swift
//  LofftyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Loffty

@Suite("Media toolbar")
struct MediaToolbarTests {
    @Test func defaultLayoutCentresPlaybackControls() {
        let items = MediaToolbarItem.defaultLayout()
        #expect(
            items == [
                .like, .skipBack, .space, .previous, .playPause, .next, .space,
                .skipForward,
            ]
        )
        #expect(
            MediaToolbarItem.defaultLayout(includeLike: false) == [
                .skipBack, .space, .previous, .playPause, .next, .space,
                .skipForward,
            ]
        )
    }

    @Test func sanitizeDropsDuplicateButtonsAndKeepsSpaces() {
        #expect(
            MediaToolbarItem.sanitize([
                .next, .space, .next, .space, .previous,
            ]) == [.next, .space, .space, .previous]
        )
    }

    @Test func sanitizeRestoresDefaultWhenOnlySpacesRemain() {
        #expect(
            MediaToolbarItem.sanitize([.space, .space])
                == MediaToolbarItem.defaultLayout()
        )
        #expect(
            MediaToolbarItem.sanitize([]) == MediaToolbarItem.defaultLayout()
        )
    }

    @Test func decodeIgnoresUnknownIdentifiers() {
        #expect(
            MediaToolbarItem.decode(["playPause", "nope", "next"])
                == [.playPause, .next]
        )
        #expect(MediaToolbarItem.decode(nil) == nil)
        #expect(MediaToolbarItem.decode(["bogus"]) == nil)
    }

    @Test func placingMovesExistingButtonAndAppendsSpace() {
        let start: [MediaToolbarItem] = [.previous, .playPause, .next]
        #expect(
            MediaToolbarItem.placing(
                start,
                item: .next,
                from: 2,
                at: 0
            ) == [.next, .previous, .playPause]
        )
        #expect(
            MediaToolbarItem.placing(
                start,
                item: .space,
                from: nil,
                at: 1
            ) == [.previous, .space, .playPause, .next]
        )
    }

    @Test func removingAnItemCompactsTheToolbar() {
        #expect(
            MediaToolbarItem.removing(
                [.like, .skipBack, .playPause],
                at: 1
            ) == [.like, .playPause]
        )
    }

    @Test func playSymbolIsPlayNotPlayPause() {
        #expect(MediaToolbarItem.playPause.symbol == "play.fill")
        #expect(MediaToolbarItem.playPause.title == "Play")
    }

    @Test func insertionIndexUsesItemCentres() {
        let frames = [
            CGRect(x: 0, y: 0, width: 40, height: 20),
            CGRect(x: 50, y: 0, width: 40, height: 20),
            CGRect(x: 100, y: 0, width: 40, height: 20),
        ]
        #expect(
            MediaToolbarCustomizer.insertionIndex(x: 10, frames: frames) == 0
        )
        #expect(
            MediaToolbarCustomizer.insertionIndex(x: 55, frames: frames) == 1
        )
        #expect(
            MediaToolbarCustomizer.insertionIndex(x: 130, frames: frames) == 3
        )
    }

    @Test @MainActor func sanitizeSlotsKeepsSpaceIdentities() {
        let space = MediaToolbarSlot(item: .space)
        let play = MediaToolbarSlot(item: .playPause)
        let next = MediaToolbarSlot(item: .next)
        let duplicate = MediaToolbarSlot(item: .playPause)
        let result = MediaToolbarCustomizer.sanitizeSlots([
            play, space, duplicate, next,
        ])
        #expect(result.map(\.item) == [.playPause, .space, .next])
        #expect(result[0].id == play.id)
        #expect(result[1].id == space.id)
        #expect(result[2].id == next.id)
    }

    @Test func draggingOutOfTheToolbarRemovesTheItem() {
        #expect(
            MediaToolbarCustomizer.dragEndAction(
                source: .toolbar,
                overToolbar: false,
                overPalette: true
            ) == .remove
        )
        #expect(
            MediaToolbarCustomizer.dragEndAction(
                source: .toolbar,
                overToolbar: false,
                overPalette: false
            ) == .remove
        )
        #expect(
            MediaToolbarCustomizer.dragEndAction(
                source: .toolbar,
                overToolbar: true,
                overPalette: false
            ) == .insert
        )
        #expect(
            MediaToolbarCustomizer.dragEndAction(
                source: .palette,
                overToolbar: true,
                overPalette: false
            ) == .insert
        )
        #expect(
            MediaToolbarCustomizer.dragEndAction(
                source: .palette,
                overToolbar: false,
                overPalette: true
            ) == .cancel
        )
    }
}
