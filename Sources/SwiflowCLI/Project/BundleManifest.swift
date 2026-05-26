// Sources/SwiflowCLI/Project/BundleManifest.swift
import CryptoKit
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
