#!/usr/bin/env swift
import CryptoKit
import Foundation

// Rotate the Ed25519 update key pair (only if the current private key is lost/compromised).
// After rotating: replace AppUpdater.ed25519PublicKeyBase64 and ship a new build.

let privateKey = Curve25519.Signing.PrivateKey()
let publicB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
let privateB64 = privateKey.rawRepresentation.base64EncodedString()

let privateURL = URL(fileURLWithPath: "loffty_update_private.b64")
try privateB64.write(to: privateURL, atomically: true, encoding: .utf8)

print("Public key -> AppUpdater.ed25519PublicKeyBase64:")
print(publicB64)
print("")
print("Private key -> \(privateURL.path) (gitignored, never commit)")
