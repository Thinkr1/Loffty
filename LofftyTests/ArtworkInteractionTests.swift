//
//  ArtworkInteractionTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Artwork interaction")
struct ArtworkInteractionTests {
    @Test func trackChangeIsForwardWithoutPreviousRequest() {
        #expect(
            NotchViewModel.trackChangeIsForward(
                previousRequestedAt: nil,
                now: Date()
            )
        )
    }

    @Test func trackChangeIsBackwardRightAfterPrevious() {
        let now = Date()
        #expect(
            !NotchViewModel.trackChangeIsForward(
                previousRequestedAt: now.addingTimeInterval(-0.5),
                now: now
            )
        )
    }

    @Test func stalePreviousRequestCountsAsForward() {
        let now = Date()
        #expect(
            NotchViewModel.trackChangeIsForward(
                previousRequestedAt: now.addingTimeInterval(-10),
                now: now
            )
        )
    }

    @Test func albumURLPrefersMatchingArtistAndUsesMusicScheme() {
        let json = """
            {"results":[
              {"collectionName":"Discovery","artistName":"Tribute Band",
               "collectionViewUrl":"https://music.apple.com/fr/album/discovery/1?uo=4"},
              {"collectionName":"Discovery","artistName":"Daft Punk",
               "collectionViewUrl":"https://music.apple.com/fr/album/discovery/2?uo=4"}
            ]}
            """
        let url = AppleMusicLibrary.albumURL(
            fromSearchResponse: Data(json.utf8),
            album: "discovery",
            artist: "Daft Punk"
        )
        #expect(
            url?.absoluteString
                == "music://music.apple.com/fr/album/discovery/2"
        )
    }

    @Test func albumURLIgnoresSingleSuffixAndDiacritics() {
        let json = """
            {"results":[
              {"collectionName":"Été - Single","artistName":"Artiste",
               "collectionViewUrl":"https://music.apple.com/fr/album/ete/3"}
            ]}
            """
        let url = AppleMusicLibrary.albumURL(
            fromSearchResponse: Data(json.utf8),
            album: "Ete",
            artist: "Artiste"
        )
        #expect(url?.absoluteString == "music://music.apple.com/fr/album/ete/3")
    }

    @Test func albumURLIsNilWithoutAlbumMatch() {
        let json = """
            {"results":[
              {"collectionName":"Other","artistName":"Artist",
               "collectionViewUrl":"https://music.apple.com/fr/album/other/4"}
            ]}
            """
        #expect(
            AppleMusicLibrary.albumURL(
                fromSearchResponse: Data(json.utf8),
                album: "Wanted",
                artist: "Artist"
            ) == nil
        )
    }
}
