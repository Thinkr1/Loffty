#!/usr/bin/env swift
import CryptoKit
import Foundation

// Signs Loffty.zip -> Loffty.zip.sig (b64 Ed25519).
// swift Scripts/sign-update.swift ~/Downloads/Loffty.zip loffty_update_private.b64

guard CommandLine.arguments.count == 3 else {
    fputs(
        "Usage: swift Scripts/sign-update.swift <Loffty.zip> <private-key.b64>\n",
        stderr
    )
    exit(1)
}

let zipPath = CommandLine.arguments[1]
let keyPath = CommandLine.arguments[2]

let keyB64 = try String(contentsOfFile: keyPath, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let keyData = Data(base64Encoded: keyB64) else {
    fputs("Invalid private key (expected base64).\n", stderr)
    exit(1)
}

let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let archiveData = try Data(contentsOf: URL(fileURLWithPath: zipPath))
let signature = try privateKey.signature(for: archiveData)
let sigURL = URL(fileURLWithPath: zipPath).appendingPathExtension("sig")
try signature.base64EncodedString()
    .write(to: sigURL, atomically: true, encoding: .utf8)
print("Wrote \(sigURL.path)")
