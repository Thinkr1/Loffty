//
//  UpdateSignRoundTripTests.swift
//  LofftyTests
//

import CryptoKit
import Foundation
import Testing

@testable import Loffty

@Suite("Update sign round-trip")
struct UpdateSignRoundTripTests {
    @Test func keygenSignVerifyRoundTrip() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicB64 = privateKey.publicKey.rawRepresentation
            .base64EncodedString()

        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("Loffty-\(UUID().uuidString).zip")
        try Data("loffty-update-payload".utf8).write(to: archive)

        let signature = try privateKey.signature(for: Data(contentsOf: archive))
        let sigURL = archive.appendingPathExtension("sig")
        try signature.base64EncodedString()
            .write(to: sigURL, atomically: true, encoding: .utf8)

        let shaURL = archive.appendingPathExtension("sha256")
        let hex = try UpdateVerifier.sha256Hex(of: archive)
        try "\(hex)  Loffty.zip\n"
            .write(to: shaURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: sigURL)
            try? FileManager.default.removeItem(at: shaURL)
        }

        try UpdateVerifier.verifyEd25519(
            archive: archive,
            signatureFile: sigURL,
            publicKeyBase64: publicB64
        )
        #expect(UpdateVerifier.parseSHA256(from: hex) == hex)
    }
}
