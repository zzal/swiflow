// Tests/SwiflowTests/Regions/RegionDecoderTests.swift
import Testing
@testable import Swiflow

private struct Ping: Decodable, Equatable { let n: Int }

/// A stub decoder that records what it was asked to decode and returns a fixed value.
private struct StubDecoding: RegionEventDecoding {
    let result: Any
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let typed = result as? E else { throw RegionError(code: "stub", message: json) }
        return typed
    }
}

@MainActor
@Suite("RegionDecoder seam")
struct RegionDecoderTests {
    @Test("current is nil by default and installs/uninstalls")
    func installs() {
        #expect(RegionDecoder.current == nil)
        RegionDecoder.current = StubDecoding(result: Ping(n: 1))
        defer { RegionDecoder.current = nil }
        let decoded = try? RegionDecoder.current?.decode(Ping.self, from: "{}")
        #expect(decoded == Ping(n: 1))
    }
}
