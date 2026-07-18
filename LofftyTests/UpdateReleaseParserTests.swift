//
//  UpdateReleaseParserTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("UpdateReleaseParser")
struct UpdateReleaseParserTests {
    @Test func parsesCompleteReleaseJSON() throws {
        let json = """
            {
              "tag_name": "v1.2.3",
              "html_url": "https://github.com/Thinkr1/Loffty/releases/tag/v1.2.3",
              "body": "Notes",
              "assets": [
                {"name": "Loffty.zip", "browser_download_url": "https://example.com/Loffty.zip"},
                {"name": "Loffty.zip.sha256", "browser_download_url": "https://example.com/Loffty.zip.sha256"},
                {"name": "Loffty.zip.sig", "browser_download_url": "https://example.com/Loffty.zip.sig"}
              ]
            }
            """
        let release = try UpdateReleaseParser.parse(Data(json.utf8))
        #expect(release.version == "1.2.3")
        #expect(release.tagName == "v1.2.3")
        #expect(release.notes == "Notes")
        #expect(release.zipURL.lastPathComponent == "Loffty.zip")
    }

    @Test func missingZipThrows() throws {
        let json = """
            {
              "tag_name": "v1.0.0",
              "html_url": "https://example.com",
              "assets": [
                {"name": "Loffty.zip.sha256", "browser_download_url": "https://example.com/a"},
                {"name": "Loffty.zip.sig", "browser_download_url": "https://example.com/b"}
              ]
            }
            """
        var threw = false
        do {
            _ = try UpdateReleaseParser.parse(Data(json.utf8))
        } catch UpdateError.noZipAsset {
            threw = true
        }
        #expect(threw)
    }

    @Test func missingChecksumThrows() throws {
        let json = """
            {
              "tag_name": "v1.0.0",
              "html_url": "https://example.com",
              "assets": [
                {"name": "Loffty.zip", "browser_download_url": "https://example.com/a"},
                {"name": "Loffty.zip.sig", "browser_download_url": "https://example.com/b"}
              ]
            }
            """
        var threw = false
        do {
            _ = try UpdateReleaseParser.parse(Data(json.utf8))
        } catch UpdateError.noChecksumAsset {
            threw = true
        }
        #expect(threw)
    }

    @Test func missingSignatureThrows() throws {
        let json = """
            {
              "tag_name": "v1.0.0",
              "html_url": "https://example.com",
              "assets": [
                {"name": "Loffty.zip", "browser_download_url": "https://example.com/a"},
                {"name": "Loffty.zip.sha256", "browser_download_url": "https://example.com/b"}
              ]
            }
            """
        var threw = false
        do {
            _ = try UpdateReleaseParser.parse(Data(json.utf8))
        } catch UpdateError.noSignatureAsset {
            threw = true
        }
        #expect(threw)
    }

    @Test func findAppBundlePrefersLofftyApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-find-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Payload/Other.app")
        let preferred = root.appendingPathComponent("Payload/Loffty.app")
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: preferred,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let found = try UpdateReleaseParser.findAppBundle(in: root)
        #expect(found.lastPathComponent == "Loffty.app")
    }

    @Test func findAppBundleFallsBackThenFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-find2-\(UUID().uuidString)")
        let other = root.appendingPathComponent("Helper.app")
        try FileManager.default.createDirectory(
            at: other,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let found = try UpdateReleaseParser.findAppBundle(in: root)
        #expect(found.lastPathComponent == "Helper.app")

        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(
            at: empty,
            withIntermediateDirectories: true
        )
        var threw = false
        do {
            _ = try UpdateReleaseParser.findAppBundle(in: empty)
        } catch UpdateError.noAppInArchive {
            threw = true
        }
        #expect(threw)
    }

    @Test func updateErrorDescriptions() {
        #expect(
            UpdateError.noZipAsset.errorDescription?.contains("Loffty.zip")
                == true
        )
        #expect(UpdateError.checksumMismatch.errorDescription != nil)
        #expect(
            UpdateError.installFailed("boom").errorDescription == "boom"
        )
    }
}
