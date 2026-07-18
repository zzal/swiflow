// Sources/App/Scrubber.swift
//
// The hero control. A year-long SVG track with the national demand curve
// drawn inside it, a draggable playhead (instant mode) or a two-thumb
// brush (range mode), and playback. Coordinates come from native pointer
// listeners (Swiflow events carry no clientX) — clientX minus the
// track's bounding rect, so drags stay correct under pointer capture.
import Swiflow
import JavaScriptKit
import GridCore

extension GridShell {
    @MainActor
    func intervalToX(_ t: Int) -> Double {
        Double(t) / Double(GridDataset.intervalCount - 1) * 1000
    }

    @MainActor
    func xToInterval(_ x: Double) -> Int {
        let f = min(1, max(0, x / 1000))
        return Int(f * Double(GridDataset.intervalCount - 1))
    }

    @MainActor
    func pad2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }

    @MainActor
    func formatInterval(_ t: Int) -> String {
        let d = t / GridDataset.intervalsPerDay
        var m = 11
        while GridDataset.monthStartDay[m] > d { m -= 1 }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let mins = (t % GridDataset.intervalsPerDay) * 5
        return "\(names[m]) \(d - GridDataset.monthStartDay[m] + 1), \(pad2(mins / 60)):\(pad2(mins % 60))"
    }

    @MainActor
    func scrubberView() -> VNode {
        var svgChildren: [VNode] = [
            element("path", attributes: [.attr("d", sparkPath), .class("gb-spark")])
                .memoKey("gb-spark"),
        ]
        // Month ticks.
        for (m, start) in GridDataset.monthStartDay.enumerated() {
            let x = Int(Double(start) / Double(GridDataset.dayCount) * 1000)
            svgChildren.append(element("line", attributes: [
                .attr("x1", "\(x)"), .attr("x2", "\(x)"),
                .attr("y1", "56"), .attr("y2", "62"),
                .class("gb-tick"), .attr("data-month", "\(m)"),
            ]))
        }
        if brushMode {
            let xl = intervalToX(brushLo), xh = intervalToX(brushHi)
            svgChildren.append(element("rect", attributes: [
                .attr("x", "\(Int(xl))"), .attr("y", "0"),
                .attr("width", "\(Int(max(1, xh - xl)))"), .attr("height", "56"),
                .class("gb-brush-range"),
            ]))
            for (x, cls) in [(xl, "gb-thumb gb-thumb--lo"), (xh, "gb-thumb gb-thumb--hi")] {
                svgChildren.append(element("line", attributes: [
                    .attr("x1", "\(Int(x))"), .attr("x2", "\(Int(x))"),
                    .attr("y1", "0"), .attr("y2", "56"), .class(cls),
                ]))
            }
        } else if case .instant(let t) = slice {
            let x = intervalToX(t)
            svgChildren.append(element("line", attributes: [
                .attr("x1", "\(Int(x))"), .attr("x2", "\(Int(x))"),
                .attr("y1", "0"), .attr("y2", "56"), .class("gb-playhead"),
            ]))
            svgChildren.append(element("circle", attributes: [
                .attr("cx", "\(Int(x))"), .attr("cy", "8"), .attr("r", "7"),
                .class("gb-playhead-knob"),
            ]))
        }

        let readout: String
        switch slice {
        case .instant(let t): readout = formatInterval(t)
        case .range(let a, let b): readout = "\(formatInterval(a)) → \(formatInterval(b))"
        }

        return element("div", attributes: [.class("gb-scrubber")], children: [
            element("div", attributes: [.class("gb-scrubber-bar")], children: [
                element("button", attributes: [
                    .class(playing ? "gb-btn gb-btn--on" : "gb-btn"),
                    .on(.click) { [weak self] in
                        guard let self else { return }
                        if self.brushMode { return }
                        self.playing.toggle()
                    },
                ], children: [text(playing ? "❚❚" : "▶")]),
                element("button", attributes: [
                    .class(brushMode ? "gb-btn gb-btn--on" : "gb-btn"),
                    .on(.click) { [weak self] in
                        guard let self else { return }
                        self.playing = false
                        self.brushMode.toggle()
                        self.slice = self.brushMode
                            ? .range(self.brushLo, self.brushHi)
                            : .instant((self.brushLo + self.brushHi) / 2)
                        self.runQuery()
                    },
                ], children: [text("Brush")]),
                element("span", attributes: [.class("gb-readout")], children: [text(readout)]),
            ]),
            element("svg", attributes: [
                .class("gb-track"),
                .attr("viewBox", "0 0 1000 64"),
                .attr("preserveAspectRatio", "none"),
                .ref(scrubberRef),
            ], children: svgChildren),
        ])
    }

    @MainActor
    func attachScrubberListeners() {
        guard let el = scrubberRef.wrappedValue else { return }

        func trackX(_ ev: JSValue) -> Double {
            let rect = el.getBoundingClientRect!()
            let left = rect.left.number ?? 0
            let width = rect.width.number ?? 1
            return ((ev.clientX.number ?? 0) - left) / width * 1000
        }

        retainedClosures.append(addNativeListener(el, "pointerdown") { [weak self] ev in
            guard let self else { return }
            self.playing = false
            let t = self.xToInterval(trackX(ev))
            if self.brushMode {
                let dLo = abs(t - self.brushLo), dHi = abs(t - self.brushHi)
                self.dragTarget = dLo <= dHi ? .brushLoHandle : .brushHiHandle
                self.applyDrag(t)
            } else {
                self.dragTarget = .playhead
                self.slice = .instant(t)
                self.runQuery()
            }
            if let id = ev.pointerId.number {
                _ = el.setPointerCapture!(id)
            }
        })
        retainedClosures.append(addNativeListener(el, "pointermove") { [weak self] ev in
            guard let self, self.dragTarget != nil else { return }
            self.applyDrag(self.xToInterval(trackX(ev)))
        })
        for endEvent in ["pointerup", "pointercancel"] {
            retainedClosures.append(addNativeListener(el, endEvent) { [weak self] _ in
                self?.dragTarget = nil
            })
        }
    }

    @MainActor
    private func applyDrag(_ t: Int) {
        switch dragTarget {
        case .playhead:
            slice = .instant(t)
        case .brushLoHandle:
            brushLo = min(t, brushHi)                        // clamp lo ≤ hi
            slice = .range(brushLo, brushHi)
        case .brushHiHandle:
            brushHi = max(t, brushLo)
            slice = .range(brushLo, brushHi)
        case nil:
            return
        }
        runQuery()
    }
}
