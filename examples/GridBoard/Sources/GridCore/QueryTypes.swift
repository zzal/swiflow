// Sources/GridCore/QueryTypes.swift
//
// The engine's entire caller-facing vocabulary. The App target sees
// nothing below this interface — no raw arrays cross it.
public enum TimeSlice: Equatable, Sendable {
    case instant(Int)
    case range(Int, Int)       // inclusive lo...hi (order-normalized by the engine)
}

/// The season×hour wheel's selection. Bit m of `months` = month m
/// selected; bit h of `hours` = hour h. All-zero on a dimension means
/// "no filter" on that dimension.
public struct SeasonHourFilter: Equatable, Sendable {
    public var months: UInt16
    public var hours: UInt32

    public init(months: UInt16 = 0, hours: UInt32 = 0) {
        self.months = months
        self.hours = hours
    }

    @inline(__always)
    public func passes(month: UInt8, hour: UInt8) -> Bool {
        (months == 0 || (months >> month) & 1 == 1)
            && (hours == 0 || (hours >> hour) & 1 == 1)
    }

    public var isIdentity: Bool { months == 0 && hours == 0 }
}

public enum LensMetric: Equatable, Sendable {
    case carbonIntensity
    case sourceShare(Source)
}

public struct GridQuery: Equatable, Sendable {
    public var slice: TimeSlice
    public var wheel: SeasonHourFilter
    public var lensMetric: LensMetric
    public var focusZone: Zone?

    public init(slice: TimeSlice, wheel: SeasonHourFilter = SeasonHourFilter(),
                lensMetric: LensMetric = .carbonIntensity, focusZone: Zone? = nil) {
        self.slice = slice
        self.wheel = wheel
        self.lensMetric = lensMetric
        self.focusZone = focusZone
    }
}

public struct ZoneAggregate: Sendable {
    public let zone: Zone
    public let meanDemandMW: Double
    public let meanPriceDollars: Double
    public let genMW: [Double]          // mean MW by Source.rawValue
    public let carbonIntensity: Double  // gCO2/kWh, generation-weighted
    public let lensValue: Double        // intensity, or the share (0…1) for .sourceShare
}

public struct EdgeAggregate: Sendable {
    public let index: Int               // into Interconnect.all
    public let meanFlowMW: Double       // signed, + = from → to
    public let peakAbsMW: Double
    public let congestionShare: Double  // fraction of intervals with |flow| > 95% cap
}

public struct NationalAggregate: Sendable {
    public let totalDemandMW: Double
    public let genMW: [Double]
    public let carbonIntensity: Double
}

/// Panel series, pre-downsampled in-engine — the UI never receives more
/// than `bucketCount` points per series.
public struct ChartSeries: Sendable {
    public let bucketCount: Int
    public let demand: [Double]
    public let bySource: [[Double]]     // [source][bucket]
    public let price: [Double]
}

public struct QueryStats: Sendable {
    public let rowsTouched: Int
    /// Stamped by the caller boundary (App shell, performance.now) so the
    /// engine stays clock-free and host-testable.
    public var elapsedMs: Double
}

public struct GridSnapshot: Sendable {
    public let zones: [ZoneAggregate]
    public let edges: [EdgeAggregate]
    public let national: NationalAggregate
    public let series: ChartSeries
    public var stats: QueryStats
    public let isEmpty: Bool
}
