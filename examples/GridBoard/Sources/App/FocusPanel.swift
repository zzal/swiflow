// Sources/App/FocusPanel.swift
//
// The right-hand panel: focus-zone (or national) stats, the mix donut —
// which is ALSO the lens-metric filter — a stacked generation chart and
// a price line over the active slice. Task 11 swaps this panel for the
// interconnect inspector when an edge is selected.
import Swiflow
import GridCore

extension GridShell {
    @MainActor
    func sidePanel() -> VNode {
        if inspectedEdge != nil { return inspectorPanel() }
        guard let snap = snapshot, !snap.isEmpty else {
            return element("aside", attributes: [.class("gb-panel")], children: [
                element("p", attributes: [.class("gb-empty")],
                        children: [text(snapshot == nil ? "Crunching the year…" : "— no intervals match —")]),
            ])
        }
        let title = focusZone?.name ?? "Canada"
        let genMW: [Double]
        let demandMW: Double
        let intensity: Double
        if let z = focusZone {
            let agg = snap.zones[z.rawValue]
            genMW = agg.genMW; demandMW = agg.meanDemandMW; intensity = agg.carbonIntensity
        } else {
            genMW = snap.national.genMW
            demandMW = snap.national.totalDemandMW
            intensity = snap.national.carbonIntensity
        }

        var children: [VNode] = [
            element("h2", attributes: [.class("gb-panel-title")], children: [text(title)]),
            element("div", attributes: [.class("gb-stat-row")], children: [
                statView("\(Int(demandMW.rounded())) MW", "demand"),
                statView("\(Int(intensity.rounded())) g/kWh", "CO₂ intensity"),
            ]),
            donutView(genMW),
            legendView(genMW),
        ]
        if snap.series.bucketCount > 1 {
            var areas: [VNode] = []
            for (source, d) in stackedAreaPaths(snap.series.bySource, w: 300, h: 90) {
                areas.append(element("path", attributes: [
                    .attr("d", d), .attr("fill", sourceColor(source)), .class("gb-area"),
                ]))
            }
            children.append(chartCard("Generation mix", element("svg", attributes: [
                .attr("viewBox", "0 0 300 90"), .class("gb-chart"),
            ], children: areas)))
            children.append(chartCard("Price $/MWh", element("svg", attributes: [
                .attr("viewBox", "0 0 300 60"), .class("gb-chart"),
            ], children: [
                element("path", attributes: [
                    .attr("d", linePath(snap.series.price, w: 300, h: 60,
                                        maxV: max(1, snap.series.price.max() ?? 1))),
                    .class("gb-price-line"),
                ]),
            ])))
        }
        return element("aside", attributes: [.class("gb-panel")], children: children)
    }

    @MainActor
    func statView(_ value: String, _ label: String) -> VNode {
        element("div", attributes: [.class("gb-stat")], children: [
            element("strong", attributes: [], children: [text(value)]),
            element("small", attributes: [], children: [text(label)]),
        ])
    }

    @MainActor
    func chartCard(_ title: String, _ chart: VNode) -> VNode {
        element("section", attributes: [.class("gb-chart-card")], children: [
            element("h3", attributes: [], children: [text(title)]),
            chart,
        ])
    }

    /// The national/zone mix donut. Clicking a segment lenses the whole
    /// map by that source's share; clicking it again (or the hole)
    /// returns to carbon intensity.
    @MainActor
    func donutView(_ genMW: [Double]) -> VNode {
        let total = genMW.reduce(0, +)
        var children: [VNode] = []
        var angle = 0.0
        if total > 0 {
            for s in Source.allCases where genMW[s.rawValue] > 0 {
                let sweep = genMW[s.rawValue] / total * 2 * .pi
                let selected = lensMetric == .sourceShare(s)
                let a0 = angle, a1 = angle + max(0.02, sweep - 0.015)
                children.append(element("path", attributes: [
                    .attr("d", arcPath(cx: 80, cy: 80, r0: selected ? 44 : 48,
                                       r1: selected ? 78 : 72, a0: a0, a1: a1)),
                    .attr("fill", sourceColor(s)),
                    .class(selected ? "gb-donut-seg gb-donut-seg--on" : "gb-donut-seg"),
                    .on(.click) { [weak self] in
                        guard let self else { return }
                        self.lensMetric = selected ? .carbonIntensity : .sourceShare(s)
                        self.runQuery()
                    },
                ]))
                angle += sweep
            }
        }
        children.append(element("circle", attributes: [
            .attr("cx", "80"), .attr("cy", "80"), .attr("r", "40"), .class("gb-donut-hole"),
            .on(.click) { [weak self] in
                guard let self else { return }
                self.lensMetric = .carbonIntensity
                self.runQuery()
            },
        ]))
        let centerLabel: String
        switch lensMetric {
        case .carbonIntensity: centerLabel = "mix"
        case .sourceShare(let s): centerLabel = s.label.lowercased()
        }
        children.append(element("text", attributes: [
            .attr("x", "80"), .attr("y", "84"), .class("gb-donut-label"),
        ], children: [text(centerLabel)]))
        return element("svg", attributes: [.attr("viewBox", "0 0 160 160"), .class("gb-donut")],
                       children: children)
    }

    @MainActor
    func legendView(_ genMW: [Double]) -> VNode {
        let total = max(1, genMW.reduce(0, +))
        var items: [VNode] = []
        for s in Source.allCases where genMW[s.rawValue] > 0.5 {
            let pct = Int((genMW[s.rawValue] / total * 100).rounded())
            items.append(element("li", attributes: [.class("gb-legend-item")], children: [
                element("span", attributes: [
                    .class("gb-legend-swatch"), .style("background", sourceColor(s)),
                ], children: []),
                text("\(s.label) \(pct)%"),
            ]))
        }
        return element("ul", attributes: [.class("gb-legend")], children: items)
    }
}
