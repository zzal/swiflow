// Sources/App/Charts.swift
//
// SVG path builders. Input is already ≤200 points (the engine
// downsamples) — these only turn numbers into `d` strings.
import Swiflow
import GridCore

func sourceColor(_ s: Source) -> String {
    switch s {
    case .hydro: "#3d85c8"
    case .nuclear: "#8867c9"
    case .gas: "#d98a3d"
    case .coal: "#6b5d52"
    case .wind: "#5fb88a"
    case .solar: "#e0c33f"
    case .diesel: "#a05252"
    }
}

/// Polyline path scaled into w×h, y-flipped (0 at the bottom).
func linePath(_ values: [Double], w: Double, h: Double, maxV: Double) -> String {
    guard values.count > 1, maxV > 0 else { return "" }
    var d = ""
    for (i, v) in values.enumerated() {
        let x = Double(i) / Double(values.count - 1) * w
        let y = h - min(1, max(0, v / maxV)) * h
        d += (i == 0 ? "M" : "L") + "\(x),\(y)"
    }
    return d
}

/// Stacked area bands, bottom-up in Source order. Returns one closed
/// path per source that has any generation.
func stackedAreaPaths(_ bySource: [[Double]], w: Double, h: Double) -> [(Source, String)] {
    let count = bySource.first?.count ?? 0
    guard count > 1 else { return [] }
    var cumulative = [Double](repeating: 0, count: count)
    var tops: [[Double]] = []
    for s in 0..<bySource.count {
        for i in 0..<count { cumulative[i] += bySource[s][i] }
        tops.append(cumulative)
    }
    let maxV = max(1, cumulative.max() ?? 1)
    var out: [(Source, String)] = []
    var lower = [Double](repeating: 0, count: count)
    for (s, top) in tops.enumerated() {
        let source = Source(rawValue: s)!
        if bySource[s].allSatisfy({ $0 <= 0 }) { lower = top; continue }
        func xy(_ i: Int, _ v: Double) -> String {
            "\(Double(i) / Double(count - 1) * w),\(h - v / maxV * h)"
        }
        var d = "M" + xy(0, lower[0])
        for i in 0..<count { d += "L" + xy(i, top[i]) }
        for i in stride(from: count - 1, through: 0, by: -1) { d += "L" + xy(i, lower[i]) }
        out.append((source, d + "Z"))
        lower = top
    }
    return out
}
