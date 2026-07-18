// Sources/GridCore/GridEngine.swift
//
// Brute-force masked scans over the columnar arrays — deliberately no
// precomputed rollups (honest per-frame compute is the demo; summaries
// could slot in behind this same interface later). Zone-major layout
// makes the inner t-loop cache-linear per zone.
public struct GridEngine: Sendable {
    public let data: GridDataset

    public init(data: GridDataset) { self.data = data }

    public func query(_ q: GridQuery) -> GridSnapshot {
        let n = data.intervals
        var lo: Int, hi: Int
        switch q.slice {
        case .instant(let t):
            lo = min(max(0, t), n - 1); hi = lo
        case .range(let a, let b):
            lo = min(max(0, min(a, b)), n - 1)
            hi = min(max(0, max(a, b)), n - 1)
        }

        // Precompute the wheel mask once for the range (identity → nil).
        var mask: [Bool]? = nil
        var visited = hi - lo + 1
        if !q.wheel.isIdentity {
            var m = [Bool](repeating: false, count: hi - lo + 1)
            var c = 0
            for t in lo...hi {
                let ok = q.wheel.passes(month: data.monthOfInterval[t], hour: data.hourOfInterval[t])
                m[t - lo] = ok
                if ok { c += 1 }
            }
            mask = m
            visited = c
        }

        let zoneCount = Zone.allCases.count
        let srcCount = Source.allCases.count
        let isEmpty = visited == 0

        // --- per-zone scan ---
        var zones: [ZoneAggregate] = []
        zones.reserveCapacity(zoneCount)
        var natDemand = 0.0
        var natGen = [Double](repeating: 0, count: srcCount)
        for z in Zone.allCases {
            var dSum = 0.0, pSum = 0.0
            var gSum = [Double](repeating: 0, count: srcCount)
            if !isEmpty {
                let base = z.rawValue * n
                for t in lo...hi {
                    if let mask, !mask[t - lo] { continue }
                    dSum += Double(data.demand[base + t])
                    pSum += Double(data.price[base + t])
                    for s in 0..<srcCount { gSum[s] += Double(data.gen[s][base + t]) }
                }
            }
            let c = Double(max(1, visited))
            let genMW = gSum.map { $0 / c }
            let totalGen = genMW.reduce(0, +)
            let intensity = totalGen > 0
                ? zip(genMW, Source.allCases).reduce(0.0) { $0 + $1.0 * $1.1.gCO2PerKWh } / totalGen
                : 0
            let lens: Double
            switch q.lensMetric {
            case .carbonIntensity: lens = intensity
            case .sourceShare(let s): lens = totalGen > 0 ? genMW[s.rawValue] / totalGen : 0
            }
            zones.append(ZoneAggregate(zone: z, meanDemandMW: dSum / c, meanPriceDollars: pSum / c,
                                       genMW: genMW, carbonIntensity: intensity, lensValue: lens))
            natDemand += dSum / c
            for s in 0..<srcCount { natGen[s] += genMW[s] }
        }
        let natTotal = natGen.reduce(0, +)
        let natIntensity = natTotal > 0
            ? zip(natGen, Source.allCases).reduce(0.0) { $0 + $1.0 * $1.1.gCO2PerKWh } / natTotal
            : 0
        let national = NationalAggregate(totalDemandMW: natDemand, genMW: natGen, carbonIntensity: natIntensity)

        // --- per-edge scan ---
        var edges: [EdgeAggregate] = []
        edges.reserveCapacity(Interconnect.all.count)
        for (i, tie) in Interconnect.all.enumerated() {
            var fSum = 0.0, peak = 0.0
            var congested = 0
            if !isEmpty {
                let limit = tie.capacityMW * 0.95
                for t in lo...hi {
                    if let mask, !mask[t - lo] { continue }
                    let f = Double(data.flow[i][t])
                    fSum += f
                    let a = abs(f)
                    if a > peak { peak = a }
                    if a > limit { congested += 1 }
                }
            }
            let c = Double(max(1, visited))
            edges.append(EdgeAggregate(index: i, meanFlowMW: fSum / c, peakAbsMW: peak,
                                       congestionShare: Double(congested) / c))
        }

        // --- chart series (focus zone, or national sum) ---
        let bucketCount = isEmpty ? 0 : min(200, hi - lo + 1)
        var sDemand = [Double](repeating: 0, count: bucketCount)
        var sPrice = [Double](repeating: 0, count: bucketCount)
        var sBySource = [[Double]](repeating: [Double](repeating: 0, count: bucketCount), count: srcCount)
        if bucketCount > 0 {
            var counts = [Int](repeating: 0, count: bucketCount)
            let span = hi - lo + 1
            let focus = q.focusZone
            for t in lo...hi {
                if let mask, !mask[t - lo] { continue }
                let b = min(bucketCount - 1, (t - lo) * bucketCount / span)
                counts[b] += 1
                if let z = focus {
                    sDemand[b] += Double(data.demand(z, t))
                    sPrice[b] += Double(data.price(z, t))
                    for s in 0..<srcCount { sBySource[s][b] += Double(data.gen[s][z.rawValue * n + t]) }
                } else {
                    for z in Zone.allCases {
                        sDemand[b] += Double(data.demand(z, t))
                        for s in 0..<srcCount { sBySource[s][b] += Double(data.gen[s][z.rawValue * n + t]) }
                    }
                    // National price: demand-agnostic simple mean across zones.
                    var p = 0.0
                    for z in Zone.allCases { p += Double(data.price(z, t)) }
                    sPrice[b] += p / Double(zoneCount)
                }
            }
            for b in 0..<bucketCount where counts[b] > 0 {
                let c = Double(counts[b])
                sDemand[b] /= c; sPrice[b] /= c
                for s in 0..<srcCount { sBySource[s][b] /= c }
            }
            // Empty buckets (wheel gaps): carry the previous bucket's value
            // so charts stay continuous.
            for b in 1..<bucketCount where counts[b] == 0 {
                sDemand[b] = sDemand[b - 1]; sPrice[b] = sPrice[b - 1]
                for s in 0..<srcCount { sBySource[s][b] = sBySource[s][b - 1] }
            }
        }
        let series = ChartSeries(bucketCount: bucketCount, demand: sDemand, bySource: sBySource, price: sPrice)

        // Rows touched: every (interval × zone) cell read across demand,
        // price, and the 7 gen arrays, plus the per-edge flow reads.
        let rows = visited * zoneCount * (2 + srcCount) + visited * Interconnect.all.count
        return GridSnapshot(zones: zones, edges: edges, national: national, series: series,
                            stats: QueryStats(rowsTouched: rows, elapsedMs: 0), isEmpty: isEmpty)
    }
}

/// Bucket-mean downsampling to at most `target` points. Empty input
/// stays empty; short input passes through unchanged.
public func downsample(_ values: [Double], to target: Int) -> [Double] {
    guard values.count > target, target > 0 else { return values }
    var out = [Double](repeating: 0, count: target)
    var counts = [Int](repeating: 0, count: target)
    for (i, v) in values.enumerated() {
        let b = min(target - 1, i * target / values.count)
        out[b] += v
        counts[b] += 1
    }
    for b in 0..<target where counts[b] > 0 { out[b] /= Double(counts[b]) }
    return out
}

public struct LensSeries: Sendable {
    public let demand24h: [Double]     // ≤ 48 points, trailing 24 h
    public let mixMW: [Double]         // instant MW by source at `around`
}

public struct DurationCurve: Sendable {
    public let points: [Double]        // |flow| sorted descending, ≤ 100 points
    public let meanMW: Double          // signed mean
    public let peakMW: Double
    public let congestionHours: Double
}

extension GridEngine {
    /// Trailing-24h demand sparkline + instant mix for the hover lens.
    public func lensSeries(zone: Zone, around t: Int) -> LensSeries {
        let n = data.intervals
        let tc = min(max(0, t), n - 1)
        let lo = max(0, tc - GridDataset.intervalsPerDay + 1)
        var raw: [Double] = []
        raw.reserveCapacity(tc - lo + 1)
        for i in lo...tc { raw.append(Double(data.demand(zone, i))) }
        let mix = Source.allCases.map { Double(data.gen($0, zone, tc)) }
        return LensSeries(demand24h: downsample(raw, to: 48), mixMW: mix)
    }

    /// Flow-duration curve for one interconnect over the active slice+wheel.
    public func durationCurve(edge: Int, slice: TimeSlice, wheel: SeasonHourFilter) -> DurationCurve {
        let n = data.intervals
        var lo: Int, hi: Int
        switch slice {
        case .instant(let t):
            // A single instant has no curve — widen to the surrounding day.
            let tc = min(max(0, t), n - 1)
            lo = max(0, tc - GridDataset.intervalsPerDay / 2)
            hi = min(n - 1, lo + GridDataset.intervalsPerDay - 1)
        case .range(let a, let b):
            lo = min(max(0, min(a, b)), n - 1)
            hi = min(max(0, max(a, b)), n - 1)
        }
        let cap = Interconnect.all[edge].capacityMW
        var absFlows: [Double] = []
        var sum = 0.0, peak = 0.0
        var congested = 0
        for t in lo...hi {
            if !wheel.isIdentity,
               !wheel.passes(month: data.monthOfInterval[t], hour: data.hourOfInterval[t]) { continue }
            let f = Double(data.flow[edge][t])
            let a = abs(f)
            absFlows.append(a)
            sum += f
            if a > peak { peak = a }
            if a > cap * 0.95 { congested += 1 }
        }
        absFlows.sort(by: >)
        let count = max(1, absFlows.count)
        return DurationCurve(points: downsample(absFlows, to: 100),
                             meanMW: sum / Double(count),
                             peakMW: peak,
                             congestionHours: Double(congested) * 5.0 / 60.0)
    }
}

