import Testing
@testable import GridCore

@Suite("SplitMix64")
struct PRNGTests {
    @Test("same seed produces the same stream; different seeds diverge")
    func determinism() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42), c = SplitMix64(seed: 43)
        let streamA = (0..<64).map { _ in a.next() }
        let streamB = (0..<64).map { _ in b.next() }
        let streamC = (0..<64).map { _ in c.next() }
        #expect(streamA == streamB)
        #expect(streamA != streamC)
    }

    @Test("unit() stays in [0,1) and range() respects bounds")
    func bounds() {
        var r = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let u = r.unit()
            #expect(u >= 0 && u < 1)
            let v = r.range(-3, 5)
            #expect(v >= -3 && v < 5)
        }
    }

    @Test("universe shape: 13 zones, 7 sources, 14 interconnects")
    func universe() {
        #expect(Zone.allCases.count == 13)
        #expect(Source.allCases.count == 7)
        #expect(Interconnect.all.count == 14)
        // Every non-US tie references two distinct zones.
        for tie in Interconnect.all where tie.to != nil {
            #expect(tie.from != tie.to)
        }
    }
}
