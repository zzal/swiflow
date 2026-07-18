import Testing
@testable import GridCore

@Suite("GridEngine")
struct EngineTests {
    static func fixture() -> GridEngine {
        let zc = Zone.allCases.count, n = 4
        var demand = [Float](repeating: 0, count: zc * n)
        var price = [Float](repeating: 0, count: zc * n)
        var gen = [[Float]](repeating: [Float](repeating: 0, count: zc * n), count: Source.allCases.count)
        var flow = [[Float]](repeating: [Float](repeating: 0, count: n), count: Interconnect.all.count)
        let qc = Zone.qc.rawValue * n, ab = Zone.ab.rawValue * n
        for t in 0..<n {
            demand[qc + t] = Float(10 * (t + 1))
            gen[Source.hydro.rawValue][qc + t] = Float(10 * (t + 1))
            price[qc + t] = Float(t + 1)
            demand[ab + t] = 100
            gen[Source.gas.rawValue][ab + t] = 60
            gen[Source.coal.rawValue][ab + t] = 40
            price[ab + t] = 50
        }
        flow[0] = [100, -100, 200, 1200]
        let data = GridDataset(demand: demand, price: price, gen: gen, flow: flow,
                               monthOfInterval: [0, 0, 6, 6], hourOfInterval: [3, 20, 3, 20])
        return GridEngine(data: data)
    }

    @Test("instant query reads a single interval exactly")
    func instant() {
        let snap = Self.fixture().query(GridQuery(slice: .instant(2)))
        let qc = snap.zones[Zone.qc.rawValue]
        #expect(qc.meanDemandMW == 30)
        #expect(qc.genMW[Source.hydro.rawValue] == 30)
        #expect(qc.carbonIntensity == 24)                    // pure hydro
        let ab = snap.zones[Zone.ab.rawValue]
        #expect(ab.meanDemandMW == 100)
        // AB intensity: (60·490 + 40·820) / 100 = 622
        #expect(abs(ab.carbonIntensity - 622) < 0.001)
        #expect(!snap.isEmpty)
    }

    @Test("range query means; national aggregate sums zones")
    func range() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let qc = snap.zones[Zone.qc.rawValue]
        #expect(qc.meanDemandMW == 25)                       // (10+20+30+40)/4
        #expect(qc.meanPriceDollars == 2.5)
        #expect(snap.national.totalDemandMW == 125)          // 25 + 100
        #expect(abs(snap.national.genMW[Source.hydro.rawValue] - 25) < 0.001)
    }

    @Test("wheel filter: month mask selects January intervals only")
    func wheelMonths() {
        // months bit 0 = January → intervals 0 and 1.
        let wheel = SeasonHourFilter(months: 1)
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: wheel))
        #expect(snap.zones[Zone.qc.rawValue].meanDemandMW == 15)   // (10+20)/2
    }

    @Test("wheel filter: month × hour intersect; impossible combo → isEmpty")
    func wheelIntersection() {
        // January (bit 0) AND hour 20 (bit 20) → interval 1 only.
        let both = SeasonHourFilter(months: 1, hours: 1 << 20)
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: both))
        #expect(snap.zones[Zone.qc.rawValue].meanDemandMW == 20)
        // July (bit 6) AND hour 5 (unused) → nothing passes.
        let none = SeasonHourFilter(months: 1 << 6, hours: 1 << 5)
        let empty = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: none))
        #expect(empty.isEmpty)
        #expect(empty.zones[Zone.qc.rawValue].meanDemandMW == 0)
    }

    @Test("lens metric: sourceShare returns the generation share")
    func lens() {
        let q = GridQuery(slice: .instant(0), wheel: SeasonHourFilter(),
                          lensMetric: .sourceShare(.gas))
        let snap = Self.fixture().query(q)
        #expect(abs(snap.zones[Zone.ab.rawValue].lensValue - 0.6) < 0.001)
        #expect(snap.zones[Zone.qc.rawValue].lensValue == 0)
    }

    @Test("edges: mean, peak, congestion share")
    func edges() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let e = snap.edges[0]                                // BC→AB, cap 1200
        #expect(e.meanFlowMW == 350)                         // (100-100+200+1200)/4
        #expect(e.peakAbsMW == 1200)
        #expect(e.congestionShare == 0.25)                   // only 1200 > 1140
    }

    @Test("series: buckets equal the range length when short; focus zone respected")
    func series() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), focusZone: .qc))
        #expect(snap.series.bucketCount == 4)
        #expect(snap.series.demand == [10, 20, 30, 40])
        #expect(snap.series.bySource[Source.hydro.rawValue] == [10, 20, 30, 40])
    }

    @Test("rows touched scales with visited intervals")
    func stats() {
        let full = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let one = Self.fixture().query(GridQuery(slice: .instant(0)))
        #expect(full.stats.rowsTouched == 4 * 13 * 9 + 4 * 14)
        #expect(one.stats.rowsTouched == 13 * 9 + 14)
    }
}

@Suite("GridEngine extras")
struct EngineExtrasTests {
    @Test("downsample: bucket means, pass-through when short")
    func downsampleBasics() {
        #expect(downsample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
        #expect(downsample([1, 2], to: 4) == [1, 2])
        #expect(downsample([], to: 4) == [])
    }

    @Test("lensSeries: trailing window clamps at zero; mix reads the instant")
    func lens() {
        let e = EngineTests.fixture()
        let s = e.lensSeries(zone: .qc, around: 2)
        #expect(s.demand24h == [10, 20, 30])                 // 4-interval fixture, t ≤ 2
        #expect(s.mixMW[Source.hydro.rawValue] == 30)
        #expect(s.mixMW[Source.gas.rawValue] == 0)
    }

    @Test("durationCurve: sorted descending, congestion in hours")
    func duration() {
        let e = EngineTests.fixture()
        let c = e.durationCurve(edge: 0, slice: .range(0, 3), wheel: SeasonHourFilter())
        #expect(c.points == [1200, 200, 100, 100])
        #expect(c.meanMW == 350)
        #expect(c.peakMW == 1200)
        #expect(abs(c.congestionHours - 5.0 / 60.0) < 0.0001)  // one 5-min interval
    }
}
