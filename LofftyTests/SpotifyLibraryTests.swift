//
//  SpotifyLibraryTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("Spotify track ID")
struct SpotifyTrackIDTests {
    @Test func parsesURIAndOpenURL() {
        #expect(
            SpotifyTrack.id(from: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
                == "4uLU6hMCjMI75M1A2tKUQC"
        )
        #expect(
            SpotifyTrack.id(
                from:
                    "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=abc"
            ) == "4uLU6hMCjMI75M1A2tKUQC"
        )
        #expect(SpotifyTrack.id(from: "spotify:episode:abc") == nil)
        #expect(SpotifyTrack.id(from: "") == nil)
        #expect(SpotifyTrack.id(from: nil) == nil)
        #expect(SpotifyTrack.id(from: "  spotify:track:xyz  ") == "xyz")
    }
}

@Suite("Apple Music favourite")
struct AppleMusicFavoriteTests {
    @Test func parseFavoriteStateReadsTabSeparatedBoolean() {
        #expect(
            AppleMusicLibrary.parseFavoriteState("ABCD1234\ttrue")
                == AppleMusicLibrary.FavoriteState(
                    trackID: "ABCD1234",
                    favorited: true
                )
        )
        #expect(
            AppleMusicLibrary.parseFavoriteState("ABCD1234\tfalse")
                == AppleMusicLibrary.FavoriteState(
                    trackID: "ABCD1234",
                    favorited: false
                )
        )
        #expect(AppleMusicLibrary.parseFavoriteState("unavailable") == nil)
        #expect(AppleMusicLibrary.parseFavoriteState("") == nil)
        #expect(AppleMusicLibrary.parseFavoriteState("\ttrue") == nil)
    }
}

#if false
@Suite("Spotify config")
struct SpotifyConfigTests {
    @Test func usesCustomSchemeRedirect() {
        #expect(SpotifyConfig.redirectURI == "loffty-spotify://oauth-callback")
        #expect(SpotifyConfig.callbackScheme == "loffty-spotify")
        #expect(
            SpotifyConfig.resolvedClientID
                == SpotifyConfig.clientID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }
}
#endif

@Suite("Spotify like button")
struct SpotifyLikeButtonTests {
    @Test func visibilityRequiresMusicAndEnabledSetting() {
        #expect(
            !NotchViewModel.showsLikeButton(
                enabled: true,
                bundleID: SpotifyTrack.clientBundle,
                idle: false
            )
        )
        #expect(
            NotchViewModel.likeSource(bundleID: SpotifyTrack.clientBundle)
                == nil
        )
        #expect(
            NotchViewModel.showsLikeButton(
                enabled: true,
                bundleID: AppleMusicTrack.clientBundle,
                idle: false
            )
        )
        #expect(
            NotchViewModel.likeSource(bundleID: AppleMusicTrack.clientBundle)
                == .appleMusic
        )
        #expect(
            !NotchViewModel.showsLikeButton(
                enabled: false,
                bundleID: AppleMusicTrack.clientBundle,
                idle: false
            )
        )
        #expect(
            !NotchViewModel.showsLikeButton(
                enabled: true,
                bundleID: "com.apple.Safari",
                idle: false
            )
        )
        #expect(
            !NotchViewModel.showsLikeButton(
                enabled: true,
                bundleID: AppleMusicTrack.clientBundle,
                idle: true
            )
        )
    }
}

#if false
@Suite("Spotify library API")
struct SpotifyLibraryAPITests {
    @Test func retryDelayReadsHeaderAndRejectsLongWaits() {
        #expect(
            SpotifyLibraryAPI.retryDelay(
                from: httpResponse(status: 429, retryAfter: "2")
            ) == 2
        )
        #expect(
            SpotifyLibraryAPI.retryDelay(
                from: httpResponse(status: 429, retryAfter: "1")
            ) == 1
        )
        #expect(
            SpotifyLibraryAPI.retryDelay(
                from: httpResponse(status: 429, retryAfter: "30")
            ) == nil
        )
        #expect(
            SpotifyLibraryAPI.retryDelay(
                from: httpResponse(status: 429, retryAfter: nil)
            ) == 1
        )
    }

    @Test @MainActor func containsDecodesSavedState() async {
        let http = StubSpotifyHTTPClient(
            status: 200,
            body: Data("[true]".utf8)
        )
        let api = SpotifyLibraryAPI(
            tokenProvider: StubSpotifyTokenProvider(),
            httpClient: http
        )
        #expect(await api.isTrackSaved(trackID: "abc") == true)
    }

    @Test @MainActor func containsFailureReturnsUnknown() async {
        let http = StubSpotifyHTTPClient(status: 403, body: Data())
        let api = SpotifyLibraryAPI(
            tokenProvider: StubSpotifyTokenProvider(),
            httpClient: http
        )
        #expect(await api.isTrackSaved(trackID: "abc") == nil)
    }

    @Test @MainActor func saveUsesPutAndUnsaveUsesDelete() async {
        let http = StubSpotifyHTTPClient(status: 200, body: Data())
        let api = SpotifyLibraryAPI(
            tokenProvider: StubSpotifyTokenProvider(),
            httpClient: http
        )
        #expect(await api.setTrackSaved(true, trackID: "abc"))
        #expect(http.lastMethod == "PUT")
        #expect(await api.setTrackSaved(false, trackID: "abc"))
        #expect(http.lastMethod == "DELETE")
    }
}

private func httpResponse(status: Int, retryAfter: String?) -> HTTPURLResponse {
    var headers: [String: String] = [:]
    if let retryAfter {
        headers["Retry-After"] = retryAfter
    }
    return HTTPURLResponse(
        url: URL(string: "https://api.spotify.com/v1")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
}

@MainActor
private final class StubSpotifyTokenProvider: SpotifyTokenProviding {
    func validAccessToken(forceRefresh: Bool) async -> String? { "token" }
}

private final class StubSpotifyHTTPClient: SpotifyHTTPClient, @unchecked
    Sendable
{
    let status: Int
    let body: Data
    private let lock = NSLock()
    private var _lastMethod: String?

    var lastMethod: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastMethod
    }

    init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        _lastMethod = request.httpMethod
        lock.unlock()
        let url = request.url ?? URL(string: "https://api.spotify.com/v1")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
#endif
