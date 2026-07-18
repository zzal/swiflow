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

    // Native-listener plumbing (populated in later tasks).
    let mapRef = Ref<JSObject>()
    var retainedClosures: [JSClosure] = []
    var listenersAttached = false

    /// January 20th, 18:00 — a cold winter evening, the grid at its most
    /// interesting.
    static let initialInterval = 20 * GridDataset.intervalsPerDay + 18 * 12

    init() {
        let t0 = nowMs()
        let data = GridDataset.generate(seed: 0xC0FFEE)
        engine = GridEngine(data: data)
        buildMs = nowMs() - t0
    }

    func onAppear() {
        runQuery()
        attachNativeListeners()
    }

    /// The single query funnel: every control mutation ends here.
    func runQuery() {
        let t0 = nowMs()
        var snap = engine.query(GridQuery(slice: slice, wheel: wheel,
                                          lensMetric: lensMetric, focusZone: focusZone))
        snap.stats.elapsedMs = nowMs() - t0
        snapshot = snap
    }

    /// Idempotent — later tasks append coordinate listeners here.
    func attachNativeListeners() {
        guard !listenersAttached else { return }
        listenersAttached = true
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
        element("div", attributes: [.class("gb-controls")], children: [])
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { GridShell() }
    }
}
