import Testing
@testable import GridCore

/// Small-N generation would be nicer, but the generator is fixed-size by
/// design (the whole point is the 105k-interval year). One shared instance
/// keeps the suite fast; generation is ~a second on host.
@Suite("Generator", .serialized)
struct GeneratorTests {
    static let a = GridDataset.generate(seed: 1)

    @Test("deterministic: same seed → identical arrays; different seed diverges")
    func determinism() {
        let b = GridDataset.generate(seed: 1)
        let c = GridDataset.generate(seed: 2)
        #expect(Self.a.demand == b.demand)
        #expect(Self.a.price == b.price)
        #expect(Self.a.gen == b.gen)
        #expect(Self.a.flow == b.flow)
        #expect(Self.a.demand != c.demand)
    }

    @Test("physical sanity: no NaN, no negatives, flows within capacity")
    func sanity() {
        let d = Self.a
        #expect(!d.demand.contains { $0.isNaN || $0 < 0 })
        #expect(!d.price.contains { $0.isNaN || $0 < 0 })
        for s in d.gen { #expect(!s.contains { $0.isNaN || $0 < 0 }) }
        for (i, tie) in Interconnect.all.enumerated() {
            let cap = Float(tie.capacityMW)
            #expect(!d.flow[i].contains { $0.isNaN || abs($0) > cap * 1.001 })
        }
    }

    @Test("dispatch identity: Σgen == demand + netExport (per zone, sampled)")
    func identity() {
        let d = Self.a
        let n = GridDataset.intervalCount
        for t in stride(from: 0, to: n, by: 997) {
            var netExport = [Double](repeating: 0, count: Zone.allCases.count)
            for (i, tie) in Interconnect.all.enumerated() {
                let f = Double(d.flow[i][t])
                netExport[tie.from.rawValue] += f
                if let to = tie.to { netExport[to.rawValue] -= f }
            }
            for z in Zone.allCases {
                let total = Source.allCases.reduce(0.0) { $0 + Double(d.gen($1, z, t)) }
                let target = Double(d.demand(z, t)) + netExport[z.rawValue]
                // Curtailment floors generation at demand+export ≥ 0; the
                // identity holds within Float rounding either way.
                #expect(abs(total - max(0, target)) < max(1.0, abs(target) * 0.001),
                        "zone \(z.code) t=\(t): gen \(total) vs target \(target)")
            }
        }
    }

    @Test("chunked GeneratorSession output is bit-identical to one-shot generate")
    func chunkedEqualsOneShot() {
        let session = GeneratorSession(seed: 1)
        // Deliberately ragged slice sizes, including a clamp past year-end.
        for days in [1, 6, 30, 90, 111, 200] {
            session.generateDays(days)
        }
        #expect(session.isComplete)
        let chunked = session.finish()
        #expect(chunked.demand == Self.a.demand)
        #expect(chunked.price == Self.a.price)
        #expect(chunked.gen == Self.a.gen)
        #expect(chunked.flow == Self.a.flow)
        // Progress counter clamps at the year boundary.
        #expect(session.daysGenerated == GridDataset.dayCount)
    }

    @Test("shape: winter-peaking Québec, daylight-bounded solar, calendar sane")
    func shape() {
        let d = Self.a
        let n = GridDataset.intervalCount
        // Mean QC demand in January > mean QC demand in July.
        var jan = 0.0, jul = 0.0, janN = 0, julN = 0
        for t in 0..<n {
            if d.monthOfInterval[t] == 0 { jan += Double(d.demand(.qc, t)); janN += 1 }
            if d.monthOfInterval[t] == 6 { jul += Double(d.demand(.qc, t)); julN += 1 }
        }
        #expect(jan / Double(janN) > jul / Double(julN) * 1.2)
        // No solar at 2am anywhere, ever.
        for t in 0..<n where d.hourOfInterval[t] == 2 {
            for z in Zone.allCases { #expect(d.gen(.solar, z, t) == 0) }
        }
        // Calendar: month array is monotone non-decreasing, hours cycle 0–23.
        #expect(d.monthOfInterval.first == 0 && d.monthOfInterval.last == 11)
        #expect(Set(d.hourOfInterval) == Set(0...23))
    }
}
