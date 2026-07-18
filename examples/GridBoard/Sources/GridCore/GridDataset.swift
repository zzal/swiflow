// Sources/GridCore/GridDataset.swift
//
// Columnar struct-of-arrays store. Zone-major layout (`z * N + t`) keeps
// each zone's year contiguous, so per-zone scans are cache-linear.
public struct GridDataset: Sendable {
    public static let intervalsPerDay = 288          // 5-minute resolution
    public static let dayCount = 365
    public static let intervalCount = 105_120        // 365 × 288

    /// Cumulative day-of-year at each month start (non-leap).
    public static let monthStartDay: [Int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

    public var demand: [Float]        // [zone × interval]
    public var price: [Float]         // [zone × interval]
    public var gen: [[Float]]         // [source][zone × interval]
    public var flow: [[Float]]        // [interconnect][interval]
    public var monthOfInterval: [UInt8]
    public var hourOfInterval: [UInt8]

    public init(demand: [Float], price: [Float], gen: [[Float]], flow: [[Float]],
                monthOfInterval: [UInt8], hourOfInterval: [UInt8]) {
        self.demand = demand
        self.price = price
        self.gen = gen
        self.flow = flow
        self.monthOfInterval = monthOfInterval
        self.hourOfInterval = hourOfInterval
    }

    /// Interval count of THIS dataset instance, derived from array length.
    /// The generator always builds `Self.intervalCount` (the full year);
    /// tests build small fixtures — the engine and helpers index with this
    /// so both work.
    @inline(__always)
    public var intervals: Int { demand.count / Zone.allCases.count }

    @inline(__always)
    public func demand(_ z: Zone, _ t: Int) -> Float {
        demand[z.rawValue * intervals + t]
    }

    @inline(__always)
    public func price(_ z: Zone, _ t: Int) -> Float {
        price[z.rawValue * intervals + t]
    }

    @inline(__always)
    public func gen(_ s: Source, _ z: Zone, _ t: Int) -> Float {
        gen[s.rawValue][z.rawValue * intervals + t]
    }

    /// Builds the two calendar arrays for a full standard year.
    public static func calendar() -> (month: [UInt8], hour: [UInt8]) {
        var month = [UInt8](repeating: 0, count: intervalCount)
        var hour = [UInt8](repeating: 0, count: intervalCount)
        var m = 0
        for d in 0..<dayCount {
            if m < 11 && d >= monthStartDay[m + 1] { m += 1 }
            for i in 0..<intervalsPerDay {
                let t = d * intervalsPerDay + i
                month[t] = UInt8(m)
                hour[t] = UInt8(i / 12)                  // 12 five-minute steps per hour
            }
        }
        return (month, hour)
    }
}
