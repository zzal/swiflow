//
// libc, not Foundation: sin/cos/exp/pow come from the platform C library
// (WASILibc on wasm32) — GridCore's no-Foundation constraint holds.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

// Real-shaped synthetic year. Profiles are tuned for plausibility, not
// accuracy: winter-peaking demand (electric heating), latitude-aware
// solar, autocorrelated wind, nuclear baseload with outage windows,
// hydro/thermal dispatched against residual load, flows from a static
// contract shape modulated by season and hour.
//
// Replace `GridDataset.generate(seed:)` with your own loader to point
// the dashboard at real data — everything downstream only sees
// GridDataset.
struct ZoneProfile {
    let basePeakMW: Double      // reference demand scale
    let meanTempC: Double
    let tempAmpC: Double        // seasonal swing (winter = mean - amp)
    let heatShare: Double       // demand sensitivity to cold
    let coolShare: Double       // demand sensitivity to heat
    let solarSeason: Double     // latitude penalty on winter daylight (0…1, 1 = strong swing)
    let caps: [Double]          // MW by Source.rawValue order
    let merit: [Source]         // dispatch order for dispatchables
}

private let profiles: [Zone: ZoneProfile] = [
    .bc: ZoneProfile(basePeakMW: 8_000, meanTempC: 9, tempAmpC: 11, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [16_000, 0, 1_200, 0, 700, 100, 0], merit: [.hydro, .gas, .diesel]),
    .ab: ZoneProfile(basePeakMW: 10_000, meanTempC: 4, tempAmpC: 16, heatShare: 0.45, coolShare: 0.15, solarSeason: 0.60,
                     caps: [900, 0, 11_000, 1_500, 6_000, 1_800, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .sk: ZoneProfile(basePeakMW: 3_800, meanTempC: 3, tempAmpC: 17, heatShare: 0.45, coolShare: 0.15, solarSeason: 0.60,
                     caps: [900, 0, 2_800, 1_500, 800, 300, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .mb: ZoneProfile(basePeakMW: 3_500, meanTempC: 3, tempAmpC: 18, heatShare: 0.60, coolShare: 0.10, solarSeason: 0.60,
                     caps: [5_600, 0, 300, 0, 260, 50, 0], merit: [.hydro, .gas, .diesel]),
    .on: ZoneProfile(basePeakMW: 16_000, meanTempC: 8, tempAmpC: 14, heatShare: 0.35, coolShare: 0.35, solarSeason: 0.50,
                     caps: [9_000, 13_000, 10_000, 0, 5_500, 500, 0], merit: [.hydro, .gas, .diesel]),
    .qc: ZoneProfile(basePeakMW: 21_000, meanTempC: 5, tempAmpC: 16, heatShare: 0.80, coolShare: 0.15, solarSeason: 0.55,
                     caps: [37_000, 0, 0, 0, 4_000, 50, 0], merit: [.hydro, .diesel]),
    .nb: ZoneProfile(basePeakMW: 1_800, meanTempC: 6, tempAmpC: 13, heatShare: 0.60, coolShare: 0.10, solarSeason: 0.55,
                     caps: [900, 660, 400, 500, 300, 50, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .pe: ZoneProfile(basePeakMW: 150, meanTempC: 6, tempAmpC: 12, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [0, 0, 0, 0, 200, 10, 100], merit: [.diesel]),
    .ns: ZoneProfile(basePeakMW: 1_400, meanTempC: 7, tempAmpC: 12, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [400, 0, 500, 1_200, 600, 100, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .nl: ZoneProfile(basePeakMW: 1_200, meanTempC: 2, tempAmpC: 12, heatShare: 0.70, coolShare: 0.05, solarSeason: 0.60,
                     caps: [6_800, 0, 0, 0, 50, 0, 100], merit: [.hydro, .diesel]),
    .yt: ZoneProfile(basePeakMW: 60, meanTempC: -3, tempAmpC: 20, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.80,
                     caps: [95, 0, 0, 0, 5, 2, 30], merit: [.hydro, .diesel]),
    .nt: ZoneProfile(basePeakMW: 55, meanTempC: -5, tempAmpC: 22, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.85,
                     caps: [55, 0, 0, 0, 5, 2, 70], merit: [.hydro, .diesel]),
    .nu: ZoneProfile(basePeakMW: 40, meanTempC: -10, tempAmpC: 22, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.95,
                     caps: [0, 0, 0, 0, 2, 1, 200], merit: [.diesel]),
]

/// Static contract bias per interconnect (share of capacity flowing
/// from → to in an average hour). Index-aligned with `Interconnect.all`.
private let flowBias: [Double] = [
    0.15,   // BC→AB — swings with AB scarcity
    0.30,   // AB→SK
    0.25,   // SK→MB — often reverses (MB hydro pushes back)
    0.60,   // MB→ON — Manitoba hydro exports east
    0.55,   // QC→ON contract flow
    0.55,   // QC→NB
    0.55,   // NB→NS
    0.45,   // NB→PE
    0.88,   // NL→QC — Churchill Falls, near-constant
    0.45,   // BC→US
    0.60,   // MB→US
    0.40,   // ON→US
    0.70,   // QC→US
    0.35,   // NB→US
]
// Convention: bias ≈ mean of `flow / capacity`, positive = from → to.

extension GridDataset {
    public static func generate(seed: UInt64) -> GridDataset {
        let n = intervalCount
        let zoneCount = Zone.allCases.count
        var rng = SplitMix64(seed: seed)
        let cal = calendar()

        var demand = [Float](repeating: 0, count: zoneCount * n)
        var price = [Float](repeating: 0, count: zoneCount * n)
        var gen = [[Float]](repeating: [Float](repeating: 0, count: zoneCount * n),
                            count: Source.allCases.count)
        var flow = [[Float]](repeating: [Float](repeating: 0, count: n),
                             count: Interconnect.all.count)

        // Per-zone autocorrelated states (wind + cloud), advanced per interval.
        var windState = [Double](repeating: 0.35, count: zoneCount)
        var cloudState = [Double](repeating: 0.5, count: zoneCount)

        for t in 0..<n {
            let d = t / intervalsPerDay
            let hour = Double(t % intervalsPerDay) / 12.0          // 0..<24, fractional
            let dayPhase = Double(d)
            let weekend = (d % 7 == 5 || d % 7 == 6)
            // Seasonal factors shared by all zones this interval.
            let seasonCos = _cos(2 * .pi * (dayPhase - 15) / 365)  // 1 ≈ mid-January
            let sunSeason = 0.5 - 0.5 * seasonCos                  // 0 winter … 1 summer

            // --- flows first (they shape dispatch via netExport) ---
            var netExport = [Double](repeating: 0, count: zoneCount)
            for (i, tie) in Interconnect.all.enumerated() {
                let diurnal = 0.75 + 0.25 * _sin((hour - 6) * .pi / 12)
                let winterBoost = tie.from == .qc || tie.from == .mb ? (1 + 0.25 * seasonCos) : 1
                let wobble = 0.9 + 0.2 * rng.unit()
                var f = tie.capacityMW * flowBias[i] * diurnal * winterBoost * wobble
                if tie.from == .bc, tie.to == .ab {
                    // BC↔AB genuinely swings sign with Alberta's evening peak.
                    f = tie.capacityMW * (0.35 * _sin((hour - 17) * .pi / 6) + 0.1 * (rng.unit() - 0.5))
                }
                f = _clamp(f, -tie.capacityMW, tie.capacityMW)
                flow[i][t] = Float(f)
                netExport[tie.from.rawValue] += f
                if let to = tie.to { netExport[to.rawValue] -= f }
            }

            for z in Zone.allCases {
                let p = profiles[z]!
                let zi = z.rawValue
                let idx = zi * n + t

                // --- demand ---
                let temp = p.meanTempC - p.tempAmpC * seasonCos
                let heating = p.heatShare * max(0, 16 - temp) / 28
                let cooling = p.coolShare * max(0, temp - 22) / 15
                let diurnal = 0.82
                    + 0.13 * _exp(-((hour - 8) * (hour - 8)) / 8)
                    + 0.16 * _exp(-((hour - 18.5) * (hour - 18.5)) / 10)
                let dm = p.basePeakMW * diurnal * (weekend ? 0.92 : 1.0)
                    * (1 + heating + cooling) * (1 + 0.03 * (rng.unit() - 0.5))
                demand[idx] = Float(dm)

                // --- must-run: wind, solar, nuclear ---
                // Wind: mean-reverting walk, clamped capacity factor.
                windState[zi] += 0.02 * (0.35 - windState[zi]) + 0.05 * (rng.unit() - 0.5)
                windState[zi] = _clamp(windState[zi], 0.02, 0.95)
                var wind = p.caps[Source.wind.rawValue] * windState[zi]

                // Solar: daylight bell scaled by season and slow-moving cloud.
                cloudState[zi] += 0.03 * (0.5 - cloudState[zi]) + 0.06 * (rng.unit() - 0.5)
                cloudState[zi] = _clamp(cloudState[zi], 0.05, 0.95)
                let halfDay = 4.2 + 2.8 * (sunSeason * (0.4 + 0.6 * (1 - p.solarSeason)) + sunSeason * p.solarSeason)
                let elev = _cos((hour - 12.75) * .pi / (2 * halfDay))
                var solar = elev > 0
                    ? p.caps[Source.solar.rawValue] * _pow(elev, 1.4) * (0.35 + 0.65 * sunSeason) * (1 - 0.7 * cloudState[zi])
                    : 0
                // Nuclear: flat with outage windows.
                var nuclearFactor = 1.0
                if z == .on { if (110...140).contains(d) || (250...270).contains(d) { nuclearFactor = 0.85 } }
                if z == .nb { if (200...215).contains(d) { nuclearFactor = 0 } }
                var nuclear = p.caps[Source.nuclear.rawValue] * nuclearFactor

                // --- dispatch: fill demand + netExport, preserve identity ---
                var need = dm + netExport[zi] - (wind + solar + nuclear)
                if need < 0 {
                    // Curtail wind, then solar, then nuclear to maintain Σgen == demand + netExport.
                    let cut = -need
                    let windCut = min(wind, cut)
                    wind -= windCut
                    let solarCut = min(solar, cut - windCut)
                    solar -= solarCut
                    let nuclearCut = min(nuclear, cut - windCut - solarCut)
                    nuclear -= nuclearCut
                    need = 0
                }
                var dispatched: [Source: Double] = [:]
                for s in p.merit {
                    let take = min(p.caps[s.rawValue], need)
                    dispatched[s] = take
                    need -= take
                    if need <= 0 { break }
                }
                if need > 0 {
                    // Emergency peakers beyond nameplate — keeps the identity
                    // and reads as scarcity in the price.
                    dispatched[.gas, default: 0] += need
                }

                gen[Source.wind.rawValue][idx] = Float(wind)
                gen[Source.solar.rawValue][idx] = Float(solar)
                gen[Source.nuclear.rawValue][idx] = Float(nuclear)
                for (s, mw) in dispatched { gen[s.rawValue][idx] += Float(mw) }

                // --- price: quadratic in dispatch tightness ---
                let dispCap = p.merit.reduce(0.0) { $0 + p.caps[$1.rawValue] }
                let tightness = dispCap > 0 ? _clamp((dm + netExport[zi] - nuclear) / dispCap, 0, 1.4) : 1.0
                var pr = 20 + 90 * tightness * tightness + 4 * (rng.unit() - 0.5)
                if tightness > 0.9 { pr += 400 * (tightness - 0.9) }
                price[idx] = Float(max(5, pr))
            }
        }
        return GridDataset(demand: demand, price: price, gen: gen, flow: flow,
                           monthOfInterval: cal.month, hourOfInterval: cal.hour)
    }
}

@inline(__always) func _sin(_ x: Double) -> Double { sin(x) }
@inline(__always) func _cos(_ x: Double) -> Double { cos(x) }
@inline(__always) func _exp(_ x: Double) -> Double { exp(x) }
@inline(__always) func _pow(_ x: Double, _ y: Double) -> Double { pow(x, y) }
@inline(__always) func _clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
