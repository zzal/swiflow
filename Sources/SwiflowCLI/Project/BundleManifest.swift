// Sources/SwiflowCLI/Project/BundleManifest.swift
//
// CryptoKit ships only on Apple platforms. swift-crypto's `Crypto` module
// provides the same SHA256 API on Linux (Apple-published, API-compatible).
// Prefer CryptoKit when it's available so we don't drag a redundant copy
// of the same code into Apple builds.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

struct BundleManifest: Codable, Equatable {
    let version: String
    let wasm: Entry
    let runtime: [Entry]

    struct Entry: Codable, Equatable {
        let url: String
        let sha256: String

        static func computing(url: String, from data: Data) -> Entry {
            let hash = SHA256.hash(data: data)
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            return Entry(url: url, sha256: hex)
        }
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}
