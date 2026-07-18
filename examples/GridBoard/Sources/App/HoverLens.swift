// Sources/App/HoverLens.swift
//
// A floating card that follows the pointer over the map: instant mix
// bar + trailing-24h demand sparkline, recomputed from the raw series
// on every pointer move (per-move compute is the point — the HUD's
// numbers include it). Uses clientX/Y minus the wrap's rect: offsetX
// would be relative to whichever <path> the pointer is over.
import Swiflow
import JavaScriptKit
import GridCore

extension GridShell {
    @MainActor
    func lensOverlay() -> VNode {
        guard let z = lensZone, let snap = snapshot else {
            return element("div", attributes: [.class("gb-lens gb-lens--hidden")], children: [])
        }
        let t: Int
        switch slice {
        case .instant(let i): t = i
        case .range(_, let hi): t = hi
        }
        let series = engine.lensSeries(zone: z, around: t)
        let total = max(1, series.mixMW.reduce(0, +))
        var mixBars: [VNode] = []
        var x = 0.0
        for s in Source.allCases where series.mixMW[s.rawValue] > 0 {
            let w = series.mixMW[s.rawValue] / total * 140
            mixBars.append(element("rect", attributes: [
                .attr("x", "\(x)"), .attr("y", "0"), .attr("width", "\(w)"), .attr("height", "8"),
                .attr("fill", sourceColor(s)),
            ]))
            x += w
        }
        let agg = snap.zones[z.rawValue]
        return element("div", attributes: [
            .class("gb-lens"),
            .style("left", "\(Int(lensPx + 14))px"),
            .style("top", "\(Int(lensPy + 14))px"),
        ], children: [
            element("strong", attributes: [], children: [text(z.name)]),
            element("div", attributes: [.class("gb-lens-stats")], children: [
                text("\(Int(agg.meanDemandMW.rounded())) MW · \(Int(agg.carbonIntensity.rounded())) g/kWh"),
            ]),
            element("svg", attributes: [.attr("viewBox", "0 0 140 8"), .class("gb-lens-mix")],
                    children: mixBars),
            element("svg", attributes: [.attr("viewBox", "0 0 140 30"), .class("gb-lens-spark")],
                    children: [
                element("path", attributes: [
                    .attr("d", linePath(series.demand24h, w: 140, h: 30,
                                        maxV: max(1, series.demand24h.max() ?? 1))),
                    .class("gb-lens-spark-line"),
                ]),
            ]),
        ])
    }

    @MainActor
    func attachLensListeners() {
        guard let wrap = mapRef.wrappedValue else { return }
        retainedClosures.append(addNativeListener(wrap, "pointermove") { [weak self] ev in
            guard let self else { return }
            let rect = wrap.getBoundingClientRect!()
            let left = rect.left.number ?? 0, top = rect.top.number ?? 0
            let width = rect.width.number ?? 1
            let px = (ev.clientX.number ?? 0) - left
            let py = (ev.clientY.number ?? 0) - top
            self.lensPx = px
            self.lensPy = py
            let scale = MapGeometry.viewWidth / width
            self.lensZone = MapGeometry.hitTest(x: px * scale, y: py * scale)
        })
        retainedClosures.append(addNativeListener(wrap, "pointerleave") { [weak self] _ in
            self?.lensZone = nil
        })
    }
}
