//
//  SpotifyLibrary.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 19/08/2026.
//

import Foundation

#if false
import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import Security
#endif
#if false
enum SpotifyConfig {
    static let clientID = "" // TODO: PKCE client id
    static let redirectURI = "loffty-spotify://oauth-callback"
    static let callbackScheme = "loffty-spotify"

    static var resolvedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

enum SpotifyTrack {
    static let clientBundle = "com.spotify.client"

    nonisolated static func id(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("spotify:track:") {
            let id = String(trimmed.dropFirst("spotify:track:".count))
            return id.isEmpty ? nil : id
        }
        guard let url = URL(string: trimmed),
            let host = url.host, host.contains("spotify.com")
        else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "track"),
            parts.indices.contains(index + 1)
        else { return nil }
        let id = parts[index + 1]
        return id.isEmpty ? nil : id
    }
}

#if false
enum SpotifyLibraryError: Error, Equatable {
    case missingClientID
    case secureRandomUnavailable
    case canceled
    case missingAuthorizationCode
    case authSessionFailed(String)
    case tokenExchangeFailed(String)
    case refreshTokenRevoked

    var settingsMessage: String {
        switch self {
        case .missingClientID:
            "Loffty needs its Spotify app ID before anyone can sign in."
        case .secureRandomUnavailable:
            "Could not start a secure login. Try again."
        case .canceled:
            ""
        case .missingAuthorizationCode:
            "Spotify did not return an authorisation code."
        case .authSessionFailed(let detail):
            detail
        case .tokenExchangeFailed(let detail):
            detail
        case .refreshTokenRevoked:
            "Spotify signed this app out. Sign in again."
        }
    }
}

enum SpotifyTokenAccount: String {
    case accessToken = "spotify-library-access-token"
    case refreshToken = "spotify-library-refresh-token"
}

protocol SpotifyTokenStoring: Sendable {
    func read(_ account: SpotifyTokenAccount) -> String?
    @discardableResult func write(
        _ value: String,
        account: SpotifyTokenAccount
    ) -> OSStatus
    @discardableResult func delete(_ account: SpotifyTokenAccount) -> OSStatus
}

struct KeychainSpotifyTokenStore: SpotifyTokenStoring {
    private static let service = "com.plmls-team.Loffty.SpotifyLibrary"

    private func baseQuery(for account: SpotifyTokenAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    func read(_ account: SpotifyTokenAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, account: SpotifyTokenAccount) -> OSStatus {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery(for: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecItemNotFound else { return status }
        var attributes = baseQuery(for: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    func delete(_ account: SpotifyTokenAccount) -> OSStatus {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}

final class MemorySpotifyTokenStore: SpotifyTokenStoring, @unchecked Sendable {
    private var values: [SpotifyTokenAccount: String] = [:]
    private let lock = NSLock()

    func read(_ account: SpotifyTokenAccount) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    @discardableResult
    func write(_ value: String, account: SpotifyTokenAccount) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        values[account] = value
        return errSecSuccess
    }

    @discardableResult
    func delete(_ account: SpotifyTokenAccount) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        values[account] = nil
        return errSecSuccess
    }
}

protocol SpotifyHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionSpotifyHTTPClient: SpotifyHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

@MainActor
protocol SpotifyAuthSessionPresenting {
    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL
}

@MainActor
final class WebAuthenticationSessionPresenter: NSObject,
    SpotifyAuthSessionPresenting
{
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                guard !hasResumed else { return }
                hasResumed = true
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code
                        == .canceledLogin
                    {
                        continuation.resume(
                            throwing: SpotifyLibraryError.canceled
                        )
                    } else {
                        continuation.resume(
                            throwing: SpotifyLibraryError.authSessionFailed(
                                error.localizedDescription
                            )
                        )
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(
                        throwing: SpotifyLibraryError.missingAuthorizationCode
                    )
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }
}

extension WebAuthenticationSessionPresenter:
    ASWebAuthenticationPresentationContextProviding
{
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
        -> ASPresentationAnchor
    {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
                ?? ASPresentationAnchor()
        }
    }
}

@MainActor
protocol SpotifyTokenProviding: AnyObject {
    func validAccessToken(forceRefresh: Bool) async -> String?
}

@MainActor
final class SpotifyOAuthService: SpotifyTokenProviding {
    static let redirectURI = SpotifyConfig.redirectURI
    private static let callbackScheme = SpotifyConfig.callbackScheme
    private static let scopes = "user-library-read user-library-modify"
    private static let authorizeURL = URL(
        string: "https://accounts.spotify.com/authorize"
    )!
    private static let tokenURL = URL(
        string: "https://accounts.spotify.com/api/token"
    )!
    private static let expiryLeeway: TimeInterval = 60

    var onTokenStateChange: (() -> Void)?
    var clientIDProvider: () -> String = {
        SpotifyConfig.resolvedClientID
    }
    var expirationProvider: () -> TimeInterval = {
        AppSettings.shared.spotifyLibraryTokenExpiration
    }
    var expirationSetter: (TimeInterval) -> Void = { value in
        AppSettings.shared.spotifyLibraryTokenExpiration = value
    }

    private let tokenStore: SpotifyTokenStoring
    private let httpClient: SpotifyHTTPClient
    private let authSession: SpotifyAuthSessionPresenting
    private var refreshTask: Task<String?, Never>?

    init(
        tokenStore: SpotifyTokenStoring,
        httpClient: SpotifyHTTPClient,
        authSession: SpotifyAuthSessionPresenting
    ) {
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.authSession = authSession
    }

    func authorize(clientID: String) async throws {
        guard let verifier = Self.randomURLSafeString(length: 64) else {
            throw SpotifyLibraryError.secureRandomUnavailable
        }
        let challenge = Self.codeChallenge(for: verifier)
        var components = URLComponents(
            url: Self.authorizeURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = components.url else {
            throw SpotifyLibraryError.authSessionFailed(
                "Could not build the Spotify authorisation URL."
            )
        }
        let callbackURL = try await authSession.authenticate(
            url: url,
            callbackURLScheme: Self.callbackScheme
        )
        guard
            let code = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
            )?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyLibraryError.missingAuthorizationCode
        }
        try await exchangeToken(
            body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier,
            ],
            grant: .authorizationCode
        )
    }

    func clearTokens() {
        tokenStore.delete(.accessToken)
        tokenStore.delete(.refreshToken)
        expirationSetter(0)
    }

    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh,
            let cached = tokenStore.read(.accessToken),
            !cached.isEmpty,
            expirationProvider() > Date().timeIntervalSince1970
                + Self.expiryLeeway
        {
            return cached
        }
        if let refreshTask {
            return await refreshTask.value
        }
        guard let refreshToken = tokenStore.read(.refreshToken),
            !refreshToken.isEmpty
        else { return nil }
        let clientID = clientIDProvider().trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !clientID.isEmpty else { return nil }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                try await self.exchangeToken(
                    body: [
                        "grant_type": "refresh_token",
                        "refresh_token": refreshToken,
                        "client_id": clientID,
                    ],
                    grant: .refresh
                )
                return self.tokenStore.read(.accessToken)
            } catch {
                return nil
            }
        }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        return token
    }

    private enum Grant {
        case authorizationCode
        case refresh
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct TokenErrorResponse: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func exchangeToken(body: [String: String], grant: Grant) async throws
    {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody =
            body
            .map {
                "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, http) = try await httpClient.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw tokenError(from: data, grant: grant)
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokenStore.write(token.accessToken, account: .accessToken)
        if let refresh = token.refreshToken, !refresh.isEmpty {
            tokenStore.write(refresh, account: .refreshToken)
        }
        expirationSetter(Date().timeIntervalSince1970 + token.expiresIn)
        onTokenStateChange?()
    }

    private func tokenError(from data: Data, grant: Grant) -> SpotifyLibraryError
    {
        guard
            let decoded = try? JSONDecoder().decode(
                TokenErrorResponse.self,
                from: data
            )
        else {
            return .tokenExchangeFailed(
                URLError(.userAuthenticationRequired).localizedDescription
            )
        }
        if grant == .refresh, decoded.error == "invalid_grant" {
            clearTokens()
            onTokenStateChange?()
            return .refreshTokenRevoked
        }
        return .tokenExchangeFailed(decoded.errorDescription ?? decoded.error)
    }

    private static func randomURLSafeString(length: Int) -> String? {
        let charset = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
            == errSecSuccess
        else { return nil }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class SpotifyLibraryAPI {
    private static let baseURL = "https://api.spotify.com/v1"
    private static let maxRetryAfter: TimeInterval = 5
    private static let defaultRetryAfter: TimeInterval = 1

    private let tokenProvider: SpotifyTokenProviding
    private let httpClient: SpotifyHTTPClient

    init(tokenProvider: SpotifyTokenProviding, httpClient: SpotifyHTTPClient) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

    func isTrackSaved(trackID: String) async -> Bool? {
        guard
            let data = await request(
                method: "GET",
                path: "/me/library/contains?uris=spotify%3Atrack%3A\(trackID)"
            )
        else { return nil }
        return (try? JSONDecoder().decode([Bool].self, from: data))?.first
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        await request(
            method: saved ? "PUT" : "DELETE",
            path: "/me/library?uris=spotify%3Atrack%3A\(trackID)"
        ) != nil
    }

    nonisolated static func retryDelay(from response: HTTPURLResponse)
        -> TimeInterval?
    {
        let header = response.value(forHTTPHeaderField: "Retry-After")
        let delay =
            header.flatMap(Int.init).map(TimeInterval.init)
            ?? defaultRetryAfter
        guard delay <= maxRetryAfter else { return nil }
        return max(0, delay)
    }

    private func request(
        method: String,
        path: String,
        allowUnauthorizedRetry: Bool = true,
        allowRateLimitRetry: Bool = true
    ) async -> Data? {
        guard
            let accessToken = await tokenProvider.validAccessToken(
                forceRefresh: false
            ),
            let url = URL(string: "\(Self.baseURL)\(path)")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, http) = try await httpClient.data(for: request)
            if http.statusCode == 401, allowUnauthorizedRetry {
                _ = await tokenProvider.validAccessToken(forceRefresh: true)
                return await self.request(
                    method: method,
                    path: path,
                    allowUnauthorizedRetry: false,
                    allowRateLimitRetry: allowRateLimitRetry
                )
            }
            if http.statusCode == 429, allowRateLimitRetry {
                guard let delay = Self.retryDelay(from: http) else {
                    return nil
                }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return nil
                }
                return await self.request(
                    method: method,
                    path: path,
                    allowUnauthorizedRetry: allowUnauthorizedRetry,
                    allowRateLimitRetry: false
                )
            }
            guard (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

@MainActor
final class SpotifyLibraryManager: ObservableObject {
    static let shared = SpotifyLibraryManager()
    static let redirectURI = SpotifyConfig.redirectURI

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var error: SpotifyLibraryError?

    private let tokenStore: SpotifyTokenStoring
    private let oauth: SpotifyOAuthService
    private let api: SpotifyLibraryAPI

    init(
        tokenStore: SpotifyTokenStoring = KeychainSpotifyTokenStore(),
        httpClient: SpotifyHTTPClient? = nil,
        authSession: SpotifyAuthSessionPresenting? = nil
    ) {
        self.tokenStore = tokenStore
        let client = httpClient ?? URLSessionSpotifyHTTPClient()
        self.oauth = SpotifyOAuthService(
            tokenStore: tokenStore,
            httpClient: client,
            authSession: authSession ?? WebAuthenticationSessionPresenter()
        )
        self.api = SpotifyLibraryAPI(
            tokenProvider: oauth,
            httpClient: client
        )
        oauth.onTokenStateChange = { [weak self] in
            self?.refreshAuthenticationState()
        }
        refreshAuthenticationState()
    }

    var configuredClientID: String { SpotifyConfig.resolvedClientID }

    func connect() {
        error = nil
        let clientID = configuredClientID
        guard !clientID.isEmpty else {
            error = .missingClientID
            return
        }
        isAuthorizing = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            do {
                try await oauth.authorize(clientID: clientID)
                error = nil
            } catch SpotifyLibraryError.canceled {
            } catch let authError as SpotifyLibraryError {
                error = authError
            } catch {
                self.error = .authSessionFailed(error.localizedDescription)
            }
            isAuthorizing = false
            refreshAuthenticationState()
        }
    }

    func disconnect() {
        oauth.clearTokens()
        error = nil
        refreshAuthenticationState()
    }

    func isTrackSaved(trackID: String) async -> Bool? {
        await api.isTrackSaved(trackID: trackID)
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        await api.setTrackSaved(saved, trackID: trackID)
    }

    func refreshAuthenticationState() {
        let hasRefreshToken = !(tokenStore.read(.refreshToken) ?? "").isEmpty
        isAuthenticated = hasRefreshToken && !configuredClientID.isEmpty
    }
}
#endif
