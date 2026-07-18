// Sources/App/MapView.swift
//
// The choropleth. Fill color per province comes straight from the
// snapshot's lensValue; Swiflow diffs only the changed attributes per
// query (path `d` strings are static and memo-keyed).
import Swiflow
import GridCore

/// Carbon-intensity scale, Electricity-Maps-flavored: green → brown.
func carbonColor(_ gPerKWh: Double) -> String {
    let t = min(1, max(0, gPerKWh / 700))
    let hue = 145.0 - 120.0 * t
    let sat = 55.0 - 15.0 * t
    let light = 44.0 - 16.0 * t
    return "hsl(\(Int(hue)), \(Int(sat))%, \(Int(light))%)"
}

/// Sequential single-hue scale for source-share mode (0…1).
func shareColor(_ share: Double) -> String {
    let light = 88.0 - 55.0 * min(1, max(0, share))
    return "hsl(215, 60%, \(Int(light))%)"
}

extension GridShell {
    @MainActor
    func mapView() -> VNode {
        var children: [VNode] = []
        for shape in MapGeometry.shapes {
            let agg = snapshot?.zones[shape.zone.rawValue]
            let fill: String
            switch lensMetric {
            case .carbonIntensity: fill = carbonColor(agg?.carbonIntensity ?? 0)
            case .sourceShare: fill = shareColor(agg?.lensValue ?? 0)
            }
            let zone = shape.zone
            var cls = "gb-zone"
            if focusZone == zone { cls += " gb-zone--focus" }
            children.append(
                element("path", attributes: [
                    .attr("d", MapGeometry.pathString(shape)),
                    .attr("fill", fill),
                    .class(cls),
                    .attr("data-zone", zone.code),
                    .on(.click) { [weak self] in
                        guard let self else { return }
                        self.focusZone = self.focusZone == zone ? nil : zone
                        self.inspectedEdge = nil
                        self.runQuery()
                    },
                ]).memoKey("zone-\(zone.code)-\(fill)-\(cls)")
            )
        }
        for shape in MapGeometry.shapes {
            let (cx, cy) = MapGeometry.centroid(shape.zone)
            children.append(element("text", attributes: [
                .attr("x", "\(Int(cx))"), .attr("y", "\(Int(cy))"),
                .class("gb-zone-label"),
            ], children: [text(shape.zone.code)]))
        }
        // Flow arcs land here in Task 11; canvas overlay in Task 12.
        return element("div", attributes: [.class("gb-map-wrap"), .ref(mapRef)], children: [
            element("svg", attributes: [
                .class("gb-map"),
                .attr("viewBox", "0 0 \(Int(MapGeometry.viewWidth)) \(Int(MapGeometry.viewHeight))"),
                .attr("preserveAspectRatio", "xMidYMid meet"),
            ], children: children),
            lensOverlay(),
        ])
    }
}
