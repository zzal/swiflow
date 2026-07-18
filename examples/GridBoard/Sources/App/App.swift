// Sources/App/App.swift
//
// GridBoard — the Canadian grid, live, with no server.
//
// Single-component architecture: GridShell owns ALL dashboard state and
// every view is an extension method on it. One state hub, one query
// funnel (runQuery), no embed/prop plumbing — the whole dashboard
// re-renders from one snapshot, and Swiflow's diff keeps the DOM work
// proportional to what changed.
import Swiflow
import SwiflowDOM
import JavaScriptKit
import GridCore

@Component
final class GridShell {
    let engine: GridEngine
    let buildMs: Double

    @State var slice: TimeSlice = .instant(GridShell.initialInterval)
    @State var wheel: SeasonHourFilter = SeasonHourFilter()
    @State var lensMetric: LensMetric = .carbonIntensity
    @State var focusZone: Zone? = nil
    @State var inspectedEdge: Int? = nil
    @State var snapshot: GridSnapshot? = nil

    @State var brushMode: Bool = false
    @State var playing: Bool = false
    @State var brushLo: Int = GridShell.initialInterval - 4 * GridDataset.intervalsPerDay
    @State var brushHi: Int = GridShell.initialInterval + 3 * GridDataset.intervalsPerDay

    // Native-listener plumbing (populated in later tasks).
    let mapRef = Ref<JSObject>()
    let scrubberRef = Ref<JSObject>()
    let raf = RAFLoop()
    var retainedClosures: [JSClosure] = []
    var listenersAttached = false
    var sparkPath = ""
    enum DragTarget { case playhead, brushLoHandle, brushHiHandle }
    var dragTarget: DragTarget? = nil

    /// January 20th, 18:00 — a cold winter evening, the grid at its most
    /// interesting.
    static let initialInterval = 20 * GridDataset.intervalsPerDay + 18 * 12

    init() {
        let t0 = nowMs()
        let data = GridDataset.generate(seed: 0xC0FFEE)
        engine = GridEngine(data: data)
        buildMs = nowMs() - t0

        // National daily mean demand → the sparkline drawn INSIDE the
        // scrubber track. 365 points, built once.
        var daily = [Double](repeating: 0, count: GridDataset.dayCount)
        for d in 0..<GridDataset.dayCount {
            var sum = 0.0
            let t0d = d * GridDataset.intervalsPerDay
            for z in Zone.allCases {
                for i in stride(from: t0d, to: t0d + GridDataset.intervalsPerDay, by: 24) {
                    sum += Double(data.demand(z, i))
                }
            }
            daily[d] = sum
        }
        let maxD = daily.max() ?? 1
        var path = "M0,56"
        for (d, v) in daily.enumerated() {
            let x = Double(d) / Double(GridDataset.dayCount - 1) * 1000
            let y = 56 - 50 * (v / maxD)
            path += "L\(Int(x)),\(Int(y))"
        }
        sparkPath = path + "L1000,56Z"
    }

    func onAppear() {
        runQuery()
        attachNativeListeners()
        raf.onFrame = { [weak self] ts in self?.tick(ts) }
        raf.start()
    }

    /// The single query funnel: every control mutation ends here.
    func runQuery() {
        let t0 = nowMs()
        var snap = engine.query(GridQuery(slice: slice, wheel: wheel,
                                          lensMetric: lensMetric, focusZone: focusZone))
        snap.stats.elapsedMs = nowMs() - t0
        snapshot = snap
    }

    /// Per-frame driver. Task 12 appends the canvas flow pass.
    func tick(_ ts: Double) {
        if playing, case .instant(let t) = slice {
            slice = .instant((t + 6) % GridDataset.intervalCount)
            runQuery()
        }
    }

    /// Idempotent — later tasks append coordinate listeners here.
    func attachNativeListeners() {
        guard !listenersAttached else { return }
        listenersAttached = true
        attachScrubberListeners()
    }

    var body: VNode {
        element("main", attributes: [.class("gb-shell")], children: [
            headerView(),
            element("div", attributes: [.class("gb-main")], children: [
                mapView(),
                sidePanel(),
            ]),
            controlsRow(),
        ])
    }

    // MARK: placeholder slots — replaced by later tasks

    func headerView() -> VNode {
        element("header", attributes: [.class("gb-header")], children: [
            element("h1", attributes: [], children: [text("Canada Grid — live")]),
            element("p", attributes: [.class("gb-tagline")],
                    children: [text("A year of 5-minute grid data, queried in your browser. No server.")]),
        ])
    }

    func sidePanel() -> VNode {
        element("aside", attributes: [.class("gb-panel")], children: [
            text(focusZone.map { $0.name } ?? "Canada"),
        ])
    }

    func controlsRow() -> VNode {
        element("div", attributes: [.class("gb-controls")], children: [
            scrubberView(),
            wheelSlot(),
        ])
    }

    /// Replaced by the season×hour wheel in Task 8.
    func wheelSlot() -> VNode {
        element("div", attributes: [.class("gb-wheel")], children: [])
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { GridShell() }
    }
}
