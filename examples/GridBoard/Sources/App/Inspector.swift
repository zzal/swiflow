// Sources/App/Inspector.swift
//
// Interconnect detail: flow-duration curve + congestion stats for the
// active slice+wheel. Replaces the focus panel while an edge is
// selected.
import Swiflow
import GridCore

extension GridShell {
    @MainActor
    func inspectorPanel() -> VNode {
        guard let i = inspectedEdge, let engine else {
            return element("aside", attributes: [.class("gb-panel")], children: [])
        }
        let tie = Interconnect.all[i]
        let curve = engine.durationCurve(edge: i, slice: slice, wheel: wheel)
        let capLine = tie.capacityMW
        return element("aside", attributes: [.class("gb-panel")], children: [
            element("div", attributes: [.class("gb-inspector-head")], children: [
                element("h2", attributes: [.class("gb-panel-title")], children: [text(tie.label)]),
                element("button", attributes: [.class("gb-btn"), .on(.click) { [weak self] in
                    self?.inspectedEdge = nil
                }], children: [text("✕")]),
            ]),
            element("div", attributes: [.class("gb-stat-row")], children: [
                statView("\(Int(curve.meanMW.rounded())) MW", "mean flow"),
                statView("\(Int(curve.peakMW.rounded())) MW", "peak"),
                statView("\(Int(curve.congestionHours.rounded())) h", "congested"),
            ]),
            chartCard("Flow duration (|MW|, sorted)", element("svg", attributes: [
                .attr("viewBox", "0 0 300 90"), .class("gb-chart"),
            ], children: [
                element("line", attributes: [
                    .attr("x1", "0"), .attr("x2", "300"),
                    .attr("y1", "\(90 - min(1, capLine / max(1, max(curve.peakMW, capLine))) * 90)"),
                    .attr("y2", "\(90 - min(1, capLine / max(1, max(curve.peakMW, capLine))) * 90)"),
                    .class("gb-cap-line"),
                ]),
                element("path", attributes: [
                    .attr("d", linePath(curve.points, w: 300, h: 90,
                                        maxV: max(1, max(curve.peakMW, capLine)))),
                    .class("gb-duration-line"),
                ]),
            ])),
            element("p", attributes: [.class("gb-inspector-note")], children: [
                text("Capacity \(Int(tie.capacityMW)) MW. Positive = \(tie.from.code) exports."),
            ]),
        ])
    }
}
