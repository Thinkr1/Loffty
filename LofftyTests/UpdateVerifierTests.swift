//
//  UpdateVerifierTests.swift
//  LofftyTests
//

import CryptoKit
import Foundation
import Testing

@testable import Loffty

@Suite("UpdateVerifier")
struct UpdateVerifierTests {
    @Test func parseSHA256AcceptsBareHash() {
        let hash = String(repeating: "ab", count: 32)
        #expect(UpdateVerifier.parseSHA256(from: hash) == hash)
    }

    @Test func parseSHA256AcceptsHashAndFilenameLine() {
        let hash = String(repeating: "cd", count: 32)
        let text = "\(hash)  Loffty.zip\n"
        #expect(UpdateVerifier.parseSHA256(from: text) == hash)
    }

    @Test func parseSHA256RejectsWrongLength() {
        #expect(UpdateVerifier.parseSHA256(from: "abcd") == nil)
    }

    @Test func parseSHA256RejectsNonHex() {
        let bad = String(repeating: "zz", count: 32)
        #expect(UpdateVerifier.parseSHA256(from: bad) == nil)
    }

    @Test func sha256HexMatchesKnownFixture() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-sha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = Data("loffty".utf8)
        try payload.write(to: url)
        let hex = try UpdateVerifier.sha256Hex(of: url)
        #expect(hex == expectedSHA256(of: payload))
    }

    @Test func ed25519AcceptsValidSignatureBase64() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let archive = try writeTempData(Data("archive-bytes".utf8), ext: "zip")
        let sig = try privateKey.signature(for: Data(contentsOf: archive))
        let sigURL = try writeTempData(
            Data(sig.base64EncodedString().utf8),
            ext: "sig"
        )
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: sigURL)
        }

        try UpdateVerifier.verifyEd25519(
            archive: archive,
            signatureFile: sigURL,
            publicKeyBase64: publicKey.rawRepresentation.base64EncodedString()
        )
    }

    @Test func ed25519AcceptsRawAndBase64URLSignatures() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicB64 = privateKey.publicKey.rawRepresentation
            .base64EncodedString()
        let archive = try writeTempData(Data("raw-sig".utf8), ext: "zip")
        let sig = try privateKey.signature(for: Data(contentsOf: archive))

        let rawURL = try writeTempData(Data(sig), ext: "sig")
        try UpdateVerifier.verifyEd25519(
            archive: archive,
            signatureFile: rawURL,
            publicKeyBase64: publicB64
        )

        let b64url = Data(sig).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let urlSig = try writeTempData(Data(b64url.utf8), ext: "sig")
        try UpdateVerifier.verifyEd25519(
            archive: archive,
            signatureFile: urlSig,
            publicKeyBase64: publicB64
        )

        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: urlSig)
        }
    }

    @Test func ed25519RejectsTamperedArchive() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let archive = try writeTempData(Data("good".utf8), ext: "zip")
        let sig = try privateKey.signature(for: Data(contentsOf: archive))
        let sigURL = try writeTempData(
            Data(sig.base64EncodedString().utf8),
            ext: "sig"
        )
        try Data("evil".utf8).write(to: archive)
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: sigURL)
        }

        var threw = false
        do {
            try UpdateVerifier.verifyEd25519(
                archive: archive,
                signatureFile: sigURL,
                publicKeyBase64: privateKey.publicKey.rawRepresentation
                    .base64EncodedString()
            )
        } catch UpdateError.badSignature {
            threw = true
        }
        #expect(threw)
    }

    private func expectedSHA256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeTempData(_ data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}
