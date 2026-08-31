//
//  MediaToolbarTests.swift
//  LofftyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Loffty

@Suite("Media toolbar", .serialized)
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

    @Test func dragZonePrefersTheToolbarThenThePalette() {
        let toolbar = CGRect(x: 0, y: 0, width: 200, height: 50)
        let palette = CGRect(x: 0, y: 70, width: 200, height: 120)
        #expect(
            MediaToolbarCustomizer.dragZone(
                point: CGPoint(x: 20, y: 20),
                toolbar: toolbar,
                palette: palette
            ) == .toolbar
        )
        #expect(
            MediaToolbarCustomizer.dragZone(
                point: CGPoint(x: 20, y: 90),
                toolbar: toolbar,
                palette: palette
            ) == .palette
        )
        #expect(
            MediaToolbarCustomizer.dragZone(
                point: CGPoint(x: 20, y: 240),
                toolbar: toolbar,
                palette: palette
            ) == .outside
        )
    }

    @Test func hitTargetIgnoresThePlaceholderAndFindsPaletteItems() {
        let play = UUID()
        let placeholder = MediaToolbarCustomizer.placeholderID
        let geometry = MediaToolbarEditGeometry(
            slots: [
                play: CGRect(x: 0, y: 0, width: 40, height: 40),
                placeholder: CGRect(x: 50, y: 0, width: 40, height: 40),
            ],
            paletteItems: [
                .like: CGRect(x: 0, y: 80, width: 48, height: 48)
            ]
        )
        #expect(
            MediaToolbarCustomizer.hitTarget(
                at: CGPoint(x: 18, y: 16),
                geometry: geometry
            ) == .toolbar(play)
        )
        #expect(
            MediaToolbarCustomizer.hitTarget(
                at: CGPoint(x: 70, y: 16),
                geometry: geometry
            ) == nil
        )
        #expect(
            MediaToolbarCustomizer.hitTarget(
                at: CGPoint(x: 24, y: 100),
                geometry: geometry
            ) == .palette(.like)
        )
    }

    @Test @MainActor func paletteDropOnTheToolbarAddsTheItem() {
        let settings = AppSettings.shared
        let previous = settings.mediaToolbarItems
        let customizer = MediaToolbarCustomizer.shared
        settings.mediaToolbarItems = [.previous, .playPause, .next]
        customizer.begin(reopenSettings: false)
        defer {
            customizer.end()
            settings.mediaToolbarItems = previous
        }

        let geometry = MediaToolbarEditGeometry(
            slots: Dictionary(
                uniqueKeysWithValues: customizer.slots.enumerated().map {
                    (
                        $0.element.id,
                        CGRect(
                            x: $0.offset * 50,
                            y: 0,
                            width: 40,
                            height: 40
                        )
                    )
                }
            ),
            paletteItems: [
                .like: CGRect(x: 0, y: 80, width: 40, height: 40)
            ],
            toolbarBounds: CGRect(x: 0, y: 0, width: 200, height: 50),
            paletteBounds: CGRect(x: 0, y: 70, width: 200, height: 80)
        )
        customizer.beginDrag(at: CGPoint(x: 20, y: 100), geometry: geometry)
        customizer.updateDrag(at: CGPoint(x: 10, y: 20), geometry: geometry)
        customizer.endDrag(at: CGPoint(x: 10, y: 20), geometry: geometry)
        #expect(customizer.slots.map(\.item).contains(.like))
    }

    @Test @MainActor func draggingAToolbarItemAwayRemovesIt() {
        let settings = AppSettings.shared
        let previous = settings.mediaToolbarItems
        let customizer = MediaToolbarCustomizer.shared
        settings.mediaToolbarItems = [.previous, .playPause, .next]
        customizer.begin(reopenSettings: false)
        defer {
            customizer.end()
            settings.mediaToolbarItems = previous
        }

        let geometry = MediaToolbarEditGeometry(
            slots: [
                customizer.slots[0].id: CGRect(
                    x: 0, y: 0, width: 40, height: 40
                )
            ],
            toolbarBounds: CGRect(x: 0, y: 0, width: 200, height: 50),
            paletteBounds: CGRect(x: 0, y: 70, width: 200, height: 80)
        )
        customizer.beginDrag(at: CGPoint(x: 20, y: 20), geometry: geometry)
        customizer.updateDrag(at: CGPoint(x: 20, y: 240), geometry: geometry)
        customizer.endDrag(at: CGPoint(x: 20, y: 240), geometry: geometry)
        #expect(customizer.slots.map(\.item) == [.playPause, .next])
    }

    @Test @MainActor func draggingReordersToolbarItems() {
        let settings = AppSettings.shared
        let previous = settings.mediaToolbarItems
        let customizer = MediaToolbarCustomizer.shared
        settings.mediaToolbarItems = [.previous, .playPause, .next]
        customizer.begin(reopenSettings: false)
        defer {
            customizer.end()
            settings.mediaToolbarItems = previous
        }

        let geometry = MediaToolbarEditGeometry(
            slots: Dictionary(
                uniqueKeysWithValues: customizer.slots.enumerated().map {
                    (
                        $0.element.id,
                        CGRect(
                            x: $0.offset * 50,
                            y: 0,
                            width: 40,
                            height: 40
                        )
                    )
                }
            ),
            toolbarBounds: CGRect(x: 0, y: 0, width: 200, height: 50),
            paletteBounds: CGRect(x: 0, y: 70, width: 200, height: 80)
        )
        customizer.beginDrag(at: CGPoint(x: 120, y: 20), geometry: geometry)
        customizer.updateDrag(at: CGPoint(x: 10, y: 20), geometry: geometry)
        customizer.endDrag(at: CGPoint(x: 10, y: 20), geometry: geometry)
        #expect(
            customizer.slots.map(\.item) == [.next, .previous, .playPause]
        )
    }
}
