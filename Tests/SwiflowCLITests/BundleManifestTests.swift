// Tests/SwiflowCLITests/BundleManifestTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("BundleManifest")
struct BundleManifestTests {
    @Test("encodes wasm + runtime entries with their sha256s")
    func encodesEntries() throws {
        let manifest = BundleManifest(
            version: "1",
            wasm: .init(url: "App.wasm", sha256: String(repeating: "a", count: 64)),
            runtime: [
                .init(url: "index.js",   sha256: String(repeating: "b", count: 64)),
                .init(url: "runtime.js", sha256: String(repeating: "c", count: 64)),
            ]
        )
        let json = try manifest.encoded()
        let parsed = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        #expect(parsed["version"] as? String == "1")
        let wasm = parsed["wasm"] as! [String: String]
        #expect(wasm["url"] == "App.wasm")
        #expect(wasm["sha256"] == String(repeating: "a", count: 64))
        let runtime = parsed["runtime"] as! [[String: String]]
        #expect(runtime.count == 2)
        #expect(runtime[0]["url"] == "index.js")
    }

    @Test("entry init computes SHA256 of the given bytes")
    func computesSHA() {
        let entry = BundleManifest.Entry.computing(url: "x", from: Data("hello".utf8))
        // Known SHA256 of "hello":
        #expect(entry.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
