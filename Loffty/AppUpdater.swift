//
//  AppUpdater.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 18/07/2026.
//

import AppKit
import Combine
import CryptoKit
import Foundation

struct UpdateRelease: Equatable, Sendable {
    let version: String
    let tagName: String
    let notes: String
    let htmlURL: URL
    let zipURL: URL
    let sha256URL: URL
    let signatureURL: URL
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case noZipAsset
    case noChecksumAsset
    case noSignatureAsset
    case badChecksumFile
    case checksumMismatch
    case badSignature
    case invalidPublicKey
    case noAppInArchive
    case destinationNotWritable
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Could not read the releases response from GitHub."
        case .noZipAsset: "The latest release has no Loffty.zip asset."
        case .noChecksumAsset:
            "The latest release has no Loffty.zip.sha256 asset."
        case .noSignatureAsset:
            "The latest release has no Loffty.zip.sig asset."
        case .badChecksumFile: "Could not parse the SHA-256 checksum file."
        case .checksumMismatch: "Downloaded update failed the SHA-256 check."
        case .badSignature:
            "Downloaded update failed the Ed25519 signature check."
        case .invalidPublicKey: "The embedded Ed25519 public key is invalid."
        case .noAppInArchive: "The update archive did not contain Loffty.app."
        case .destinationNotWritable:
            "Cannot replace this copy of Loffty. Copy it to Applications first."
        case .installFailed(let message): message
        }
    }
}

enum UpdateVerifier {
    static func verify(
        archive: URL,
        sha256File: URL,
        signatureFile: URL
    ) throws {
        let checksumText = try String(contentsOf: sha256File, encoding: .utf8)
        guard let expected = parseSHA256(from: checksumText) else {
            throw UpdateError.badChecksumFile
        }
        let actual = try sha256Hex(of: archive)
        guard actual == expected else { throw UpdateError.checksumMismatch }

        try verifyEd25519(
            archive: archive,
            signatureFile: signatureFile,
            publicKeyBase64: AppUpdater.ed25519PublicKeyBase64
        )
    }

    static func parseSHA256(from text: String) -> String? {
        let token =
            text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
        guard let token else { return nil }
        let hex = String(token).lowercased()
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        guard hex.count == 64,
            hex.unicodeScalars.allSatisfy({ hexDigits.contains($0) })
        else { return nil }
        return hex
    }

    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifyEd25519(
        archive: URL,
        signatureFile: URL,
        publicKeyBase64: String
    ) throws {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
            keyData.count == 32
        else {
            throw UpdateError.invalidPublicKey
        }
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: keyData
        )
        let archiveData = try Data(contentsOf: archive)
        let sigData = try loadSignature(from: signatureFile)
        guard publicKey.isValidSignature(sigData, for: archiveData) else {
            throw UpdateError.badSignature
        }
    }

    private static func loadSignature(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        if data.count == 64 { return data }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = Data(base64Encoded: text), decoded.count == 64 {
            return decoded
        }
        var normalized =
            text  // b64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 { normalized.append("=") }
        if let decoded = Data(base64Encoded: normalized), decoded.count == 64 {
            return decoded
        }
        throw UpdateError.badSignature
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum UpdateReleaseParser {
    static func parse(_ data: Data) throws -> UpdateRelease {
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = AppUpdater.normalizeVersion(decoded.tagName)

        guard
            let zip = decoded.assets.first(where: {
                $0.name.lowercased() == "loffty.zip"
            })
        else { throw UpdateError.noZipAsset }
        guard
            let sha = decoded.assets.first(where: {
                $0.name.lowercased() == "loffty.zip.sha256"
            })
        else { throw UpdateError.noChecksumAsset }
        guard
            let sig = decoded.assets.first(where: {
                $0.name.lowercased() == "loffty.zip.sig"
            })
        else { throw UpdateError.noSignatureAsset }

        guard let zipURL = URL(string: zip.browserDownloadURL),
            let shaURL = URL(string: sha.browserDownloadURL),
            let sigURL = URL(string: sig.browserDownloadURL)
        else { throw UpdateError.invalidResponse }

        return UpdateRelease(
            version: version,
            tagName: decoded.tagName,
            notes: decoded.body ?? "",
            htmlURL: URL(string: decoded.htmlURL)
                ?? URL(string: "https://github.com/Thinkr1/Loffty/releases")!,
            zipURL: zipURL,
            sha256URL: shaURL,
            signatureURL: sigURL
        )
    }

    static func findAppBundle(in root: URL) throws -> URL {
        var fallback: URL?
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { throw UpdateError.noAppInArchive }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            if url.lastPathComponent == "Loffty.app" { return url }
            fallback = url
        }
        guard let fallback else { throw UpdateError.noAppInArchive }
        return fallback
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    static let ed25519PublicKeyBase64 =
        "js3DcaYcokrymhljLhxgUlWaLGDxpW46LQa5fN7MsVA="

    private static let lastCheckKey = "appUpdater.lastCheck"
    private static let automaticInterval: TimeInterval = 60 * 60 * 24

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
    }

    func checkForUpdatesIfNeeded() {
        guard AppSettings.shared.automaticUpdates else { return }
        let last =
            UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.automaticInterval {
            return
        }
        Task { await checkForUpdates(announceResult: false) }
    }

    func checkForUpdatesNow() {
        Task { await checkForUpdates(announceResult: true) }
    }

    func checkForUpdates(announceResult: Bool) async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            if !Self.isVersion(release.version, newerThan: currentVersion) {
                state = .upToDate
                if announceResult {
                    presentAlert(
                        title: "You’re up to date!",
                        message:
                            "Loffty \(currentVersion) is the latest release."
                    )
                }
                return
            }

            state = .available(release)
            presentAvailableAlert(for: release)
        } catch {
            state = .failed(error.localizedDescription)
            if announceResult {
                presentAlert(
                    title: "Update check failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func install(_ release: UpdateRelease) {
        Task { await installUpdate(release) }
    }

    private func installUpdate(_ release: UpdateRelease) async {
        guard !isBusy || state == .available(release) else { return }
        state = .downloading

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LofftyUpdate-\(UUID().uuidString)",
                isDirectory: true
            )

        do {
            try FileManager.default.createDirectory(
                at: workDir,
                withIntermediateDirectories: true
            )

            let zipURL = workDir.appendingPathComponent("Loffty.zip")
            let shaURL = workDir.appendingPathComponent("Loffty.zip.sha256")
            let sigURL = workDir.appendingPathComponent("Loffty.zip.sig")
            try await download(release.zipURL, to: zipURL)
            try await download(release.sha256URL, to: shaURL)
            try await download(release.signatureURL, to: sigURL)

            try UpdateVerifier.verify(
                archive: zipURL,
                sha256File: shaURL,
                signatureFile: sigURL
            )

            state = .installing
            let extractDir = workDir.appendingPathComponent(
                "extract",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: extractDir,
                withIntermediateDirectories: true
            )
            try extractZip(zipURL, to: extractDir)
            let newApp = try UpdateReleaseParser.findAppBundle(in: extractDir)

            let destination = Bundle.main.bundleURL
            let parent = destination.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parent.path) else {
                throw UpdateError.destinationNotWritable
            }

            try launchReplacement(
                destination: destination,
                newApp: newApp,
                cleanup: workDir
            )
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            state = .failed(error.localizedDescription)
            presentAlert(
                title: "Update failed",
                message: error.localizedDescription
            )
        }
    }

    private func fetchLatestRelease() async throws -> UpdateRelease {
        let url = URL(
            string:
                "https://api.github.com/repos/Thinkr1/Loffty/releases/latest"
        )!
        var request = URLRequest(url: url)
        request.setValue(
            "Loffty/\(currentVersion) (macOS)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            throw UpdateError.invalidResponse
        }

        return try UpdateReleaseParser.parse(data)
    }

    private func presentAvailableAlert(for release: UpdateRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Loffty \(release.version) is available!"
        alert.informativeText = """
            You have \(currentVersion). Download, verify, and replace this app?

            Because Loffty is not notarized, macOS may ask you to allow the new build once after relaunch (Open Anyway / clear quarantine).
            """
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        default:
            break
        }
    }

    private func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func download(_ remote: URL, to local: URL) async throws {
        let (tempURL, response) = try await URLSession.shared.download(
            from: remote
        )
        guard let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw UpdateError.installFailed(
                "Download failed for \(remote.lastPathComponent)."
            )
        }
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }
        try FileManager.default.moveItem(at: tempURL, to: local)
    }

    private func extractZip(_ zipURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.installFailed(
                "Could not unpack the update archive."
            )
        }
    }

    private func launchReplacement(
        destination: URL,
        newApp: URL,
        cleanup: URL
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            """
            while kill -0 "$0" 2>/dev/null; do sleep 0.1; done
            sleep 0.25
            rm -rf "$1"
            /usr/bin/ditto "$2" "$1"
            /usr/bin/xattr -cr "$1" || true
            /usr/bin/open "$1"
            rm -rf "$3"
            """,
            "\(pid)",
            destination.path,
            newApp.path,
            cleanup.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s.removeFirst()
        }
        return s
    }

    static func isVersion(_ candidate: String, newerThan current: String)
        -> Bool
    {
        compareVersions(normalizeVersion(candidate), normalizeVersion(current))
            == .orderedDescending
    }

    static func compareVersions(_ lhs: String, _ rhs: String)
        -> ComparisonResult
    {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
