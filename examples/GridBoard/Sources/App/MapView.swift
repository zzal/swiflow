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

/// Quadratic-bezier control points for interconnect `i`: zone centroid →
/// zone centroid (bowed perpendicular), or centroid → south-of-map for
/// US exports. Shared by the SVG arcs and the canvas particles.
func arcControlPoints(_ i: Int) -> (p0: (Double, Double), c: (Double, Double), p1: (Double, Double)) {
    let tie = Interconnect.all[i]
    let p0 = MapGeometry.centroid(tie.from)
    let p1: (Double, Double)
    if let to = tie.to {
        p1 = MapGeometry.centroid(to)
    } else {
        let a = MapGeometry.usAnchor(tie.from)
        p1 = (a.0 + 18, 600)
    }
    let mx = (p0.0 + p1.0) / 2, my = (p0.1 + p1.1) / 2
    let dx = p1.0 - p0.0, dy = p1.1 - p0.1
    let len = max(1, (dx * dx + dy * dy).squareRoot())
    // Bow 12% of length to the left of travel.
    let c = (mx - dy / len * len * 0.12, my + dx / len * len * 0.12)
    return (p0, c, p1)
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
        children.append(flowArcsLayer())
        return element("div", attributes: [.class("gb-map-wrap"), .ref(mapRef)], children: [
            element("svg", attributes: [
                .class("gb-map"),
                .attr("viewBox", "0 0 \(Int(MapGeometry.viewWidth)) \(Int(MapGeometry.viewHeight))"),
                .attr("preserveAspectRatio", "xMidYMid meet"),
            ], children: children),
            element("canvas", attributes: [
                .class("gb-flow-canvas"),
                .attr("width", "1000"), .attr("height", "620"),
                .ref(canvasRef),
            ]).unmanagedChildren(),
            lensOverlay(),
        ])
    }

    @MainActor
    func flowArcsLayer() -> VNode {
        var children: [VNode] = []
        for (i, _) in Interconnect.all.enumerated() {
            let (p0, c, p1) = arcControlPoints(i)
            let d = "M\(p0.0),\(p0.1)Q\(c.0),\(c.1) \(p1.0),\(p1.1)"
            let agg = snapshot?.edges[i]
            let mean = agg?.meanFlowMW ?? 0
            let cap = Interconnect.all[i].capacityMW
            let width = 1.0 + 5.0 * min(1, abs(mean) / cap)
            var cls = "gb-arc"
            if inspectedEdge == i { cls += " gb-arc--focus" }
            if mean < 0 { cls += " gb-arc--reverse" }
            children.append(element("path", attributes: [
                .attr("d", d), .class(cls),
                .attr("stroke-width", "\(width)"),
            ]))
            // Fat invisible hit path.
            children.append(element("path", attributes: [
                .attr("d", d), .class("gb-arc-hit"),
                .on(.click) { [weak self] in
                    guard let self else { return }
                    self.inspectedEdge = self.inspectedEdge == i ? nil : i
                },
            ]))
        }
        return element("g", attributes: [.class("gb-arcs")], children: children)
    }
}
