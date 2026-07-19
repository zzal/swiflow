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
    /// nil until the boot generator finishes — body shows the boot splash
    /// (with a real progress bar) until then.
    @State var engine: GridEngine? = nil
    var buildMs: Double = 0

    @State var slice: TimeSlice = .instant(GridShell.initialInterval)
    @State var wheel: SeasonHourFilter = SeasonHourFilter()
    @State var lensMetric: LensMetric = .carbonIntensity
    @State var focusZone: Zone? = nil
    @State var inspectedEdge: Int? = nil
    @State var snapshot: GridSnapshot? = nil

    @State var lensZone: Zone? = nil
    var lensPx = 0.0
    var lensPy = 0.0

    @State var brushMode: Bool = false
    @State var playing: Bool = false
    @State var brushLo: Int = GridShell.initialInterval - 4 * GridDataset.intervalsPerDay
    @State var brushHi: Int = GridShell.initialInterval + 3 * GridDataset.intervalsPerDay

    // Native-listener plumbing (populated in later tasks).
    let mapRef = Ref<JSObject>()
    let scrubberRef = Ref<JSObject>()
    let canvasRef = Ref<JSObject>()
    let raf = RAFLoop()
    var retainedClosures: [JSClosure] = []
    var listenersAttached = false
    var sparkPath = ""
    var canvasCtx: JSObject? = nil
    var particlePhases: [[Double]] = []          // [edge][particle] in 0..<1
    var frameCount = 0
    var lastFpsStamp = 0.0
    @State var hudFps: Int = 0
    @State var hudOpen: Bool = true
    enum DragTarget { case playhead, brushLoHandle, brushHiHandle }
    var dragTarget: DragTarget? = nil
    var wheelPainting = false

    // Boot (chunked dataset generation, so the splash can paint between
    // slices) + delta-time playback state.
    @State var bootDaysDone: Int = 0
    private var bootSession: GeneratorSession? = nil
    private var bootTimer: TimerHandle? = nil      // retained: TimerHandle cancels on deinit
    private var bootStartMs: Double = 0
    var lastFrameTs: Double = 0
    var playCarry: Double = 0

    /// January 20th, 18:00 — a cold winter evening, the grid at its most
    /// interesting.
    static let initialInterval = 20 * GridDataset.intervalsPerDay + 18 * 12

    func onAppear() {
        raf.onFrame = { [weak self] ts in self?.tick(ts) }
        raf.start()
        bootStartMs = nowMs()
        bootSession = GeneratorSession(seed: 0xC0FFEE)
        scheduleBootSlice()
    }

    // MARK: - Boot

    /// Generates the year in day-sized chunks, yielding to the browser
    /// between slices so the splash's progress bar actually paints.
    private func scheduleBootSlice() {
        bootTimer = after(0) { [weak self] in self?.bootSlice() }
    }

    private func bootSlice() {
        guard let session = bootSession else { return }
        session.generateDays(8)
        bootDaysDone = session.daysGenerated
        if session.isComplete {
            let data = session.finish()
            bootSession = nil
            buildMs = nowMs() - bootStartMs
            buildSpark(data)
            engine = GridEngine(data: data)
            runQuery()
        } else {
            scheduleBootSlice()
        }
    }

    /// National daily mean demand → the sparkline drawn INSIDE the
    /// scrubber track. 365 points, built once at boot completion.
    private func buildSpark(_ data: GridDataset) {
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

    /// The single query funnel: every control mutation ends here.
    func runQuery() {
        guard let engine else { return }
        let t0 = nowMs()
        var snap = engine.query(GridQuery(slice: slice, wheel: wheel,
                                          lensMetric: lensMetric, focusZone: focusZone))
        snap.stats.elapsedMs = nowMs() - t0
        snapshot = snap
    }

    /// Per-frame driver: playback stepping + the canvas flow pass + a
    /// 1 Hz fps stamp (a @State write per second, not per frame).
    ///
    /// Playback is DELTA-TIMED: rAF fires at the display's refresh rate
    /// (60 Hz on Safari, 120 Hz on ProMotion Chrome/Firefox), so a fixed
    /// per-frame step would play the year twice as fast on 120 Hz screens.
    /// The rate is anchored to the old 60 fps feel: 360 intervals/second
    /// (= 30 simulated hours per real second), with a fractional carry so
    /// odd frame times don't drop time.
    func tick(_ ts: Double) {
        let delta = lastFrameTs > 0 ? min(ts - lastFrameTs, 250) : 1000.0 / 60.0
        lastFrameTs = ts
        attachNativeListeners()
        if playing, case .instant(let t) = slice {
            playCarry += delta * 0.36           // 360 intervals per 1000 ms
            let step = Int(playCarry)
            if step > 0 {
                playCarry -= Double(step)
                slice = .instant((t + step) % GridDataset.intervalCount)
                runQuery()
            }
        }
        drawFlows(ts)
        frameCount += 1
        if ts - lastFpsStamp > 1000 {
            if lastFpsStamp > 0 {
                hudFps = Int((Double(frameCount) * 1000 / (ts - lastFpsStamp)).rounded())
            }
            frameCount = 0
            lastFpsStamp = ts
        }
    }

    /// Idempotent, ref-gated: called every tick and no-ops until the full
    /// dashboard (post-splash) has mounted and the refs are bound.
    func attachNativeListeners() {
        guard !listenersAttached,
              scrubberRef.wrappedValue != nil,
              mapRef.wrappedValue != nil else { return }
        listenersAttached = true
        attachScrubberListeners()
        attachWheelListeners()
        attachLensListeners()
    }

    var body: VNode {
        guard engine != nil else { return bootSplash() }
        return element("main", attributes: [.class("gb-shell")], children: [
            headerView(),
            element("div", attributes: [.class("gb-main")], children: [
                mapView(),
                sidePanel(),
            ]),
            controlsRow(),
        ])
    }

    /// Boot splash with a determinate progress bar while the year of data
    /// is generated in chunks.
    func bootSplash() -> VNode {
        let pct = bootDaysDone * 100 / GridDataset.dayCount
        let points = GridDataset.intervalCount * Zone.allCases.count * 9
        return element("main", attributes: [.class("gb-boot")], children: [
            element("div", attributes: [.class("gb-boot-card")], children: [
                element("h1", attributes: [], children: [text("Canada Grid — live")]),
                element("p", attributes: [.class("gb-boot-line")], children: [
                    text("Generating a year of 5-minute grid data — \(fmtPts(points)) points, right here in your browser."),
                ]),
                element("div", attributes: [.class("gb-boot-track")], children: [
                    element("div", attributes: [
                        .class("gb-boot-fill"),
                        .style("width", "\(pct)%"),
                    ], children: []),
                ]),
                element("p", attributes: [.class("gb-boot-pct")], children: [
                    text("\(pct)% · day \(bootDaysDone) of \(GridDataset.dayCount)"),
                ]),
            ]),
        ])
    }

    // MARK: placeholder slots — replaced by later tasks

    func headerView() -> VNode {
        element("header", attributes: [.class("gb-header")], children: [
            element("div", attributes: [], children: [
                element("h1", attributes: [], children: [text("Canada Grid — live")]),
                element("p", attributes: [.class("gb-tagline")],
                        children: [text("A year of 5-minute grid data, queried in your browser. No server.")]),
            ]),
            hudView(),
        ])
    }

    func controlsRow() -> VNode {
        element("div", attributes: [.class("gb-controls")], children: [
            scrubberView(),
            wheelView(),
        ])
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { GridShell() }
    }
}
