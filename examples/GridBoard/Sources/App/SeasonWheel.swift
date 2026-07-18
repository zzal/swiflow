// Sources/App/SeasonWheel.swift
//
// Radial filter: outer ring = 12 months, inner ring = 24 hours. Click
// toggles a segment; press-and-sweep paints contiguous segments on
// (mousedown starts the paint, mouseenter applies it, a window-level
// mouseup ends it). Empty selection on a ring = no filter on that
// dimension.
import Swiflow
import JavaScriptKit
import GridCore

// Local trig shims (App target also stays Foundation-free).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
@inline(__always) func _sinD(_ x: Double) -> Double { sin(x) }
@inline(__always) func _cosD(_ x: Double) -> Double { cos(x) }

/// Annular sector between radii r0<r1 from angle a0 to a1 (radians,
/// 0 = 12 o'clock, clockwise).
func arcPath(cx: Double, cy: Double, r0: Double, r1: Double, a0: Double, a1: Double) -> String {
    func pt(_ r: Double, _ a: Double) -> (Double, Double) {
        (cx + r * _sinD(a), cy - r * _cosD(a))
    }
    let large = (a1 - a0) > .pi ? 1 : 0
    let (x0, y0) = pt(r1, a0), (x1, y1) = pt(r1, a1)
    let (x2, y2) = pt(r0, a1), (x3, y3) = pt(r0, a0)
    return "M\(x0),\(y0)A\(r1),\(r1) 0 \(large) 1 \(x1),\(y1)"
        + "L\(x2),\(y2)A\(r0),\(r0) 0 \(large) 0 \(x3),\(y3)Z"
}

extension GridShell {
    @MainActor
    func wheelView() -> VNode {
        var children: [VNode] = []
        let monthNames = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        for m in 0..<12 {
            let a0 = Double(m) / 12 * 2 * .pi + 0.012
            let a1 = Double(m + 1) / 12 * 2 * .pi - 0.012
            let on = (wheel.months >> m) & 1 == 1
            children.append(element("path", attributes: [
                .attr("d", arcPath(cx: 70, cy: 70, r0: 47, r1: 65, a0: a0, a1: a1)),
                .class(on ? "gb-seg gb-seg--on" : "gb-seg"),
                .on(.mousedown) { [weak self] in self?.beginPaint { $0.months ^= 1 << m } },
                .on(.mouseenter) { [weak self] in self?.paint { $0.months |= 1 << m } },
            ]))
            let mid = (a0 + a1) / 2
            children.append(element("text", attributes: [
                .attr("x", "\(70 + 56 * _sinD(mid))"), .attr("y", "\(70 - 56 * _cosD(mid) + 3)"),
                .class("gb-seg-label"),
            ], children: [text(monthNames[m])]))
        }
        for h in 0..<24 {
            let a0 = Double(h) / 24 * 2 * .pi + 0.02
            let a1 = Double(h + 1) / 24 * 2 * .pi - 0.02
            let on = (wheel.hours >> h) & 1 == 1
            children.append(element("path", attributes: [
                .attr("d", arcPath(cx: 70, cy: 70, r0: 27, r1: 45, a0: a0, a1: a1)),
                .class(on ? "gb-seg gb-seg--on" : "gb-seg"),
                .on(.mousedown) { [weak self] in self?.beginPaint { $0.hours ^= 1 << h } },
                .on(.mouseenter) { [weak self] in self?.paint { $0.hours |= 1 << h } },
            ]))
        }
        children.append(element("circle", attributes: [
            .attr("cx", "70"), .attr("cy", "70"), .attr("r", "22"),
            .class(wheel.isIdentity ? "gb-wheel-clear gb-wheel-clear--idle" : "gb-wheel-clear"),
            .on(.click) { [weak self] in
                guard let self else { return }
                self.wheel = SeasonHourFilter()
                self.runQuery()
            },
        ]))
        children.append(element("text", attributes: [
            .attr("x", "70"), .attr("y", "74"), .class("gb-wheel-clear-label"),
        ], children: [text(wheel.isIdentity ? "all" : "clear")]))

        return element("div", attributes: [.class("gb-wheel"), .attr("title", "Filter by month (outer) and hour (inner)")], children: [
            element("svg", attributes: [.attr("viewBox", "0 0 140 140"), .class("gb-wheel-svg")],
                    children: children),
        ])
    }

    @MainActor
    func beginPaint(_ apply: (inout SeasonHourFilter) -> Void) {
        wheelPainting = true
        apply(&wheel)
        runQuery()
    }

    @MainActor
    func paint(_ apply: (inout SeasonHourFilter) -> Void) {
        guard wheelPainting else { return }
        apply(&wheel)
        runQuery()
    }

    @MainActor
    func attachWheelListeners() {
        // Paint ends wherever the pointer is released.
        let window = JSObject.global.window.object!
        retainedClosures.append(addNativeListener(window, "mouseup") { [weak self] _ in
            self?.wheelPainting = false
        })
    }
}
