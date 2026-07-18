// Sources/GridCore/Zones.swift
//
// The fixed universe: 13 Canadian provinces/territories, 7 generation
// sources, and the interconnects between zones (plus US-export ties,
// modeled as `to: nil`). Capacities are round, plausible figures — this
// is a demo dataset, not a grid model.
public enum Zone: Int, CaseIterable, Sendable, Equatable {
    case bc, ab, sk, mb, on, qc, nb, pe, ns, nl, yt, nt, nu

    public var code: String {
        switch self {
        case .bc: "BC"; case .ab: "AB"; case .sk: "SK"; case .mb: "MB"
        case .on: "ON"; case .qc: "QC"; case .nb: "NB"; case .pe: "PE"
        case .ns: "NS"; case .nl: "NL"; case .yt: "YT"; case .nt: "NT"
        case .nu: "NU"
        }
    }

    public var name: String {
        switch self {
        case .bc: "British Columbia"; case .ab: "Alberta"
        case .sk: "Saskatchewan"; case .mb: "Manitoba"
        case .on: "Ontario"; case .qc: "Québec"
        case .nb: "New Brunswick"; case .pe: "Prince Edward Island"
        case .ns: "Nova Scotia"; case .nl: "Newfoundland and Labrador"
        case .yt: "Yukon"; case .nt: "Northwest Territories"
        case .nu: "Nunavut"
        }
    }
}

public enum Source: Int, CaseIterable, Sendable, Equatable {
    case hydro, nuclear, gas, coal, wind, solar, diesel

    public var label: String {
        switch self {
        case .hydro: "Hydro"; case .nuclear: "Nuclear"; case .gas: "Gas"
        case .coal: "Coal"; case .wind: "Wind"; case .solar: "Solar"
        case .diesel: "Diesel"
        }
    }

    /// Lifecycle emission factors, gCO2eq/kWh (IPCC-style medians).
    public var gCO2PerKWh: Double {
        switch self {
        case .hydro: 24; case .nuclear: 12; case .gas: 490
        case .coal: 820; case .wind: 11; case .solar: 45; case .diesel: 650
        }
    }
}

/// A directed transmission tie. Positive flow = `from` → `to`.
/// `to == nil` models a US export interface (the US side is not a zone).
public struct Interconnect: Sendable, Equatable {
    public let from: Zone
    public let to: Zone?
    public let capacityMW: Double

    public var label: String { "\(from.code) → \(to?.code ?? "US")" }

    public init(from: Zone, to: Zone?, capacityMW: Double) {
        self.from = from
        self.to = to
        self.capacityMW = capacityMW
    }

    public static let all: [Interconnect] = [
        Interconnect(from: .bc, to: .ab, capacityMW: 1_200),
        Interconnect(from: .ab, to: .sk, capacityMW: 150),
        Interconnect(from: .sk, to: .mb, capacityMW: 300),
        Interconnect(from: .mb, to: .on, capacityMW: 250),
        Interconnect(from: .qc, to: .on, capacityMW: 2_700),
        Interconnect(from: .qc, to: .nb, capacityMW: 1_000),
        Interconnect(from: .nb, to: .ns, capacityMW: 500),
        Interconnect(from: .nb, to: .pe, capacityMW: 560),
        Interconnect(from: .nl, to: .qc, capacityMW: 5_000),   // Churchill Falls
        Interconnect(from: .bc, to: nil, capacityMW: 3_000),
        Interconnect(from: .mb, to: nil, capacityMW: 2_100),
        Interconnect(from: .on, to: nil, capacityMW: 2_500),
        Interconnect(from: .qc, to: nil, capacityMW: 4_000),
        Interconnect(from: .nb, to: nil, capacityMW: 1_000),
    ]
}
