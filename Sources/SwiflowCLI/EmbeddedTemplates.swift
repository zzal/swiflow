// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift run swiflow-codegen templates
//
// Source: examples/*/

enum EmbeddedTemplates {
    struct Template {
        let name: String
        let files: [String: String]
    }

    static let all: [Template] = [
        Template(
            name: "EdgeCases",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        {{SWIFLOW_DEP}},
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowDOM

/// EdgeLab — adversarial reconciliation stress harness. Each embedded trap is a
/// self-contained <section data-testid="trapN"> exercising one nesting/identity
/// edge case, with a sentinel that only survives if the reconciler reuses nodes
/// rather than recreating them. See the design spec.
@Component
final class EdgeLab {
    var body: VNode {
        div(.class("lab")) {
            h2("Swiflow reconciliation traps")
            embed { Trap1CondBeforeFocus() }
            embed { Trap2ForOfIf() }
            embed { Trap3ForIfFor() }
            embed { Trap4LoopInCond() }
            embed { Trap5KeyedWithFragments() }
            embed { Trap6TwoAdjacentConds() }
            embed { Trap7ComponentLifecycle() }
            embed { Trap8RapidCycle() }
            embed { Trap9KeyedItemsInnerState() }
            embed { Trap10RawSpread() }
            embed { Trap11DynamicList() }
            embed { Trap12ControlledValuePatch() }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { EdgeLab() }
    }
}

"""##,
                "Sources/App/EdgeLab+Styles.swift": ##"""
// Sources/App/EdgeLab+Styles.swift
import Swiflow

extension EdgeLab {
    @MainActor static var scopedStyles: CSSSheet? = css {
        host(.display("block"), .maxWidth("760px"), .margin("1.5rem auto"), .padding("0 1rem"))
        rule("section",
             .border("1px solid color-mix(in oklab, CanvasText 15%, transparent)"),
             .borderRadius("8px"), .padding("0.75rem 1rem"), .margin("0 0 1rem 0"))
        rule("h2", .fontSize("1rem"), .margin("0 0 0.5rem 0"))
        rule("button",
             .margin("0 0.35rem 0.35rem 0"), .padding("0.3rem 0.7rem"),
             .border("1px solid color-mix(in oklab, CanvasText 25%, transparent)"),
             .borderRadius("6px"), .background("Canvas"), .color("CanvasText"), .cursor("pointer"))
        rule("input",
             .padding("0.25rem 0.5rem"), .border("1px solid color-mix(in oklab, CanvasText 25%, transparent)"),
             .borderRadius("6px"), .background("Canvas"), .color("CanvasText"))
        rule(".row", .display("flex"), .gap("0.4rem"), .alignItems("center"), .flexWrap("wrap"))
        rule(".tag", .fontFamily("ui-monospace, monospace"), .fontSize("0.8rem"), .color("var(--text-dim, GrayText)"))
    }
}

"""##,
                "Sources/App/Trap10RawSpread.swift": ##"""
// Sources/App/Trap10RawSpread.swift
import Swiflow

/// Trap 10 (KNOWN LIMITATION): a raw [VNode] spread — NOT wrapped in if/for —
/// is flattened, so changing its length shifts the following sibling (the
/// documented buildExpression([VNode]) footgun). This trap asserts the
/// framework doesn't crash and a sentinel in a SEPARATE element is unaffected.
@Component
final class Trap10RawSpread {
    @State var n: Int = 1

    private var spread: [VNode] {
        (0..<n).map { i in span(.class("tag")) { text("s\(i) ") } }
    }

    var body: VNode {
        section(.data("testid", "trap10")) {
            h2("10. raw [VNode] spread (known limitation)")
            button("grow", .data("testid", "trap10-grow"), .on(.click) { self.n += 1 })
            div(.data("testid", "trap10-spread")) {
                spread
                span(.class("tag")) { text("END") }
            }
            div(.class("row")) {
                input(.attr("type", "text"), .data("testid", "trap10-input"))
            }
        }
    }
}

"""##,
                "Sources/App/Trap11DynamicList.swift": ##"""
// Sources/App/Trap11DynamicList.swift
import Swiflow

/// Trap 11: dynamic keyed list with Add +1 / +100 (front and back), Remove,
/// Clear, Swap. Bulk front-insertion stresses insertBefore + LIS; existing rows
/// must NOT be recreated (their typed values + node identity survive), which
/// also proves the diff is minimal (not re-placing the whole list).
@Component
final class Trap11DynamicList {
    @State var rows: [Int] = []
    @State var nextId: Int = 0

    private func add(_ count: Int, front: Bool) {
        let ids = (0..<count).map { _ -> Int in let id = nextId; nextId += 1; return id }
        if front { rows.insert(contentsOf: ids, at: 0) } else { rows.append(contentsOf: ids) }
    }

    var body: VNode {
        section(.data("testid", "trap11")) {
            h2("11. dynamic keyed list (add/remove/swap)")
            div(.class("row")) {
                button("+1 front", .data("testid", "trap11-add1-front"), .on(.click) { self.add(1, front: true) })
                button("+100 front", .data("testid", "trap11-add100-front"), .on(.click) { self.add(100, front: true) })
                button("+1 back", .data("testid", "trap11-add1-back"), .on(.click) { self.add(1, front: false) })
                button("remove first", .data("testid", "trap11-removefirst"),
                       .on(.click) { if !self.rows.isEmpty { self.rows.removeFirst() } })
                button("swap ends", .data("testid", "trap11-swap"),
                       .on(.click) { if self.rows.count >= 2 { self.rows.swapAt(0, self.rows.count - 1) } })
                button("clear", .data("testid", "trap11-clear"), .on(.click) { self.rows = [] })
                span(.data("testid", "trap11-count")) { text("\(rows.count)") }
            }
            ul(.data("testid", "trap11-list")) {
                for id in rows {
                    li(.key("r-\(id)"), .class("row")) {
                        span(.class("tag")) { text("#\(id) ") }
                        input(.attr("type", "text"), .data("testid", "trap11-input-\(id)"))
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Trap12ControlledValuePatch.swift": ##"""
// Sources/App/Trap12ControlledValuePatch.swift
import Swiflow

/// Trap 12: the complement of every other trap. Those use UNCONTROLLED inputs to
/// prove a node was *preserved* (a typed value only survives if the node wasn't
/// recreated). This one uses a CONTROLLED input — its value is bound to `@State`
/// via `.value($text)` — to prove the other direction: when state changes, the
/// reconciler must PATCH the live `.value` of the SAME node (the update path, not
/// the preserve path). A `showFirst` conditional sits before it so the controlled
/// input also has to survive reconciliation while bound.
@Component
final class Trap12ControlledValuePatch {
    @State var text: String = "alpha"
    @State var showFirst: Bool = false

    var body: VNode {
        section(.data("testid", "trap12")) {
            h2("12. controlled input — value patched on state change")
            div(.class("row")) {
                button("set beta", .data("testid", "trap12-set-beta"),
                       .on(.click) { self.text = "beta" })
                button("uppercase", .data("testid", "trap12-upper"),
                       .on(.click) { self.text = self.text.uppercased() })
                button("toggle before", .data("testid", "trap12-toggle"),
                       .on(.click) { self.showFirst.toggle() })
            }
            if showFirst {
                p("conditional content is showing")
            }
            div(.class("row")) {
                label("Controlled:")
                input(.attr("type", "text"), .data("testid", "trap12-input"), .value($text))
            }
        }
    }
}

"""##,
                "Sources/App/Trap1CondBeforeFocus.swift": ##"""
// Sources/App/Trap1CondBeforeFocus.swift
import Swiflow

/// Trap 1: a conditional rendered BEFORE a focused sibling input. Toggling the
/// conditional must not recreate the input (focus + typed value must survive).
/// This is the generalized form of the dialog/toast bug.
@Component
final class Trap1CondBeforeFocus {
    @State var showFirst: Bool = false

    var body: VNode {
        section(.data("testid", "trap1")) {
            h2("1. Conditional before a focused input")
            div(.class("row")) {
                button("Toggle conditional", .data("testid", "trap1-toggle"),
                       .on(.click) { self.showFirst.toggle() })
            }
            if showFirst {
                p("conditional content is showing")
            }
            div(.class("row")) {
                label("Type here:")
                input(.attr("type", "text"), .data("testid", "trap1-input"))
            }
        }
    }
}

"""##,
                "Sources/App/Trap2ForOfIf.swift": ##"""
// Sources/App/Trap2ForOfIf.swift
import Swiflow

/// Trap 2: `for` of `if`. Each list item conditionally renders an inner node.
/// Toggling one item's flag must not recreate a sibling item's input.
@Component
final class Trap2ForOfIf {
    @State var flags: [Bool] = [false, false, false]

    var body: VNode {
        section(.data("testid", "trap2")) {
            h2("2. for-of-if")
            for i in 0..<3 {
                div(.class("row"), .key("item-\(i)")) {
                    button("toggle \(i)", .data("testid", "trap2-toggle-\(i)"),
                           .on(.click) { self.flags[i].toggle() })
                    if flags[i] { span(.class("tag")) { text("[on]") } }
                    input(.attr("type", "text"), .data("testid", "trap2-input-\(i)"))
                }
            }
        }
    }
}

"""##,
                "Sources/App/Trap3ForIfFor.swift": ##"""
// Sources/App/Trap3ForIfFor.swift
import Swiflow

/// Trap 3: three-level imbrication — outer keyed list, per-item conditional,
/// inner keyed sub-list. Mutating one item's inner list must leave the other
/// outer items' inputs untouched.
@Component
final class Trap3ForIfFor {
    @State var counts: [Int] = [1, 1]

    var body: VNode {
        section(.data("testid", "trap3")) {
            h2("3. for-of-if-of-for")
            for outer in 0..<2 {
                div(.class("row"), .key("outer-\(outer)")) {
                    input(.attr("type", "text"), .data("testid", "trap3-input-\(outer)"))
                    button("inner+1", .data("testid", "trap3-add-\(outer)"),
                           .on(.click) { self.counts[outer] += 1 })
                    if counts[outer] > 0 {
                        ul {
                            for inner in 0..<counts[outer] {
                                li(.key("inner-\(outer)-\(inner)")) { text("• row \(inner)") }
                            }
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Trap4LoopInCond.swift": ##"""
// Sources/App/Trap4LoopInCond.swift
import Swiflow

/// Trap 4: a loop nested inside a conditional, with a <details open> sentinel
/// AFTER it. Toggling the whole loop on/off must not recreate the details
/// (its open state must survive), and refilled items appear before it.
@Component
final class Trap4LoopInCond {
    @State var showList: Bool = true

    var body: VNode {
        section(.data("testid", "trap4")) {
            h2("4. loop inside a conditional")
            button("toggle list", .data("testid", "trap4-toggle"),
                   .on(.click) { self.showList.toggle() })
            if showList {
                ul {
                    for i in 0..<3 { li(.key("l-\(i)")) { text("loop item \(i)") } }
                }
            }
            details(.data("testid", "trap4-details")) {
                summary("sentinel disclosure")
                p("the open state here must survive toggling the loop above")
            }
        }
    }
}

"""##,
                "Sources/App/Trap5KeyedWithFragments.swift": ##"""
// Sources/App/Trap5KeyedWithFragments.swift
import Swiflow

/// Trap 5: keyed elements interspersed with fragments. Swapping the keyed
/// items and toggling the conditional must reuse the keyed inputs (identity
/// preserved), with the fragments holding their positions.
@Component
final class Trap5KeyedWithFragments {
    @State var order: [String] = ["a", "b"]
    @State var showX: Bool = false

    var body: VNode {
        section(.data("testid", "trap5")) {
            h2("5. keyed reorder with interspersed fragments")
            div(.class("row")) {
                button("swap", .data("testid", "trap5-swap"),
                       .on(.click) { self.order.reverse() })
                button("toggle x", .data("testid", "trap5-togglex"),
                       .on(.click) { self.showX.toggle() })
            }
            div {
                input(.attr("type", "text"), .data("testid", "trap5-input-\(order[0])"), .key("k-\(order[0])"))
                if showX { span(.class("tag"), .key("frag-x")) { text("[x]") } }
                input(.attr("type", "text"), .data("testid", "trap5-input-\(order[1])"), .key("k-\(order[1])"))
                for i in 0..<2 { span(.class("tag"), .key("f-\(i)")) { text(" f\(i) ") } }
            }
        }
    }
}

"""##,
                "Sources/App/Trap6TwoAdjacentConds.swift": ##"""
// Sources/App/Trap6TwoAdjacentConds.swift
import Swiflow

/// Trap 6: two adjacent conditionals before a sentinel input, inside a div that
/// also has a keyed sibling (forces the keyed path → exercises the structural-
/// sibling bucketKey fix). The input must survive all four a/b combinations.
@Component
final class Trap6TwoAdjacentConds {
    @State var a: Bool = false
    @State var b: Bool = false

    var body: VNode {
        section(.data("testid", "trap6")) {
            h2("6. two adjacent conditionals (bucketKey)")
            div(.class("row")) {
                button("toggle a", .data("testid", "trap6-a"), .on(.click) { self.a.toggle() })
                button("toggle b", .data("testid", "trap6-b"), .on(.click) { self.b.toggle() })
            }
            div {
                span(.class("tag"), .key("anchor")) { text("keyed-anchor ") }
                if a { span(.class("tag"), .key("cond-a")) { text("[a]") } }
                if b { span(.class("tag"), .key("cond-b")) { text("[b]") } }
                input(.attr("type", "text"), .data("testid", "trap6-input"), .key("sentinel"))
            }
        }
    }
}

"""##,
                "Sources/App/Trap7ComponentLifecycle.swift": ##"""
// Sources/App/Trap7ComponentLifecycle.swift
import Swiflow
import SwiflowDOM
import JavaScriptKit

/// A child whose mount/unmount bumps shared counters via callbacks, so the test
/// can assert onAppear/onDisappear fire exactly once per toggle.
@Component
final class LifecycleChild {
    let onUp: () -> Void
    let onDown: () -> Void
    init(onUp: @escaping () -> Void, onDown: @escaping () -> Void) {
        self.onUp = onUp; self.onDown = onDown
    }
    var body: VNode { span(.class("tag")) { text("child-mounted") } }
    func onAppear() { onUp() }
    func onDisappear() { onDown() }
}

/// A sibling component holding its OWN @State counter. If the reconciler
/// recreates it while the LifecycleChild churns, this counter resets to 0.
@Component
final class Keeper {
    @State var n: Int = 0
    var body: VNode {
        div(.class("row")) {
            button("keeper+1", .data("testid", "trap7-keeper-inc"), .on(.click) { self.n += 1 })
            span(.data("testid", "trap7-keeper-count")) { text("\(n)") }
        }
    }
}

/// Trap 7: a component inside an emptying fragment, beside a stateful sibling
/// component. Toggling the child off/on must fire onDisappear/onAppear exactly
/// once each and must NOT reset the sibling Keeper's @State.
@Component
final class Trap7ComponentLifecycle {
    @State var showChild: Bool = false
    @State var appears: Int = 0
    @State var disappears: Int = 0

    var body: VNode {
        section(.data("testid", "trap7")) {
            h2("7. component in an emptying fragment + lifecycle")
            div(.class("row")) {
                button("toggle child", .data("testid", "trap7-toggle"),
                       .on(.click) { self.showChild.toggle() })
                span(.data("testid", "trap7-appears")) { text("up:\(appears)") }
                span(.data("testid", "trap7-disappears")) { text("down:\(disappears)") }
            }
            if showChild {
                embed { LifecycleChild(onUp: { self.appears += 1 }, onDown: { self.disappears += 1 }) }
            }
            embed { Keeper() }
        }
    }
}

"""##,
                "Sources/App/Trap8RapidCycle.swift": ##"""
// Sources/App/Trap8RapidCycle.swift
import Swiflow

/// Trap 8: rapid empty→full→empty cycling of a fragment. After N toggles the
/// sentinel after it must be intact and the child count must match parity (no
/// duplicated/leaked children).
@Component
final class Trap8RapidCycle {
    @State var show: Bool = false

    var body: VNode {
        section(.data("testid", "trap8")) {
            h2("8. empty→full→empty rapid cycle")
            button("toggle", .data("testid", "trap8-toggle"), .on(.click) { self.show.toggle() })
            if show {
                ul(.data("testid", "trap8-list")) {
                    for i in 0..<3 { li(.key("c-\(i)")) { text("cycle item \(i)") } }
                }
            }
            input(.attr("type", "text"), .data("testid", "trap8-input"))
        }
    }
}

"""##,
                "Sources/App/Trap9KeyedItemsInnerState.swift": ##"""
// Sources/App/Trap9KeyedItemsInnerState.swift
import Swiflow

/// Trap 9: a keyed list whose items each contain their own conditional + input.
/// Expanding one item and typing in it, then reordering the list, must move the
/// expanded state + typed value WITH the item (identity preserved, not stranded).
@Component
final class Trap9KeyedItemsInnerState {
    @State var order: [String] = ["x", "y", "z"]
    @State var expanded: [String: Bool] = ["x": false, "y": false, "z": false]

    var body: VNode {
        section(.data("testid", "trap9")) {
            h2("9. keyed items with inner if/for + state")
            button("rotate", .data("testid", "trap9-rotate"),
                   .on(.click) { self.order = Array(self.order.dropFirst()) + self.order.prefix(1) })
            ul {
                for id in order {
                    li(.key("row-\(id)"), .class("row")) {
                        button("expand \(id)", .data("testid", "trap9-expand-\(id)"),
                               .on(.click) { self.expanded[id, default: false].toggle() })
                        if expanded[id, default: false] {
                            input(.attr("type", "text"), .data("testid", "trap9-input-\(id)"))
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{NAME}}</title>
    <style>
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed; inset: 0; display: grid; place-items: center;
        background: Canvas; color: CanvasText; font: 16px/1.4 system-ui, sans-serif; z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "GridBoard",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        {{SWIFLOW_DEP}},
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        // Pure Swift data core: generator + columnar store + aggregation
        // engine. No Foundation, no JavaScriptKit, no Swiflow — so it
        // compiles and tests on the host. This is the seam to replace
        // when pointing the dashboard at your own data.
        .target(name: "GridCore", path: "Sources/GridCore"),
        .executableTarget(
            name: "App",
            dependencies: [
                "GridCore",
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
        .testTarget(name: "GridCoreTests", dependencies: ["GridCore"], path: "Tests/GridCoreTests"),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A serverless, Electricity-Maps-style dashboard of the Canadian grid —
and a showcase of what WASM compute makes possible in the browser.

Every interaction is a full-dataset query: a year of 5-minute-resolution
data for 13 provinces and territories (~12M data points) lives in WASM
linear memory, and dragging the scrubber, painting the season×hour
wheel, or hovering a province re-scans it between two frames. No server,
no API, no precomputed tiles. The perf HUD shows the receipts.

## Run it

    swiflow dev

## The tour

- **Time scrubber** — the year's demand curve IS the track. Drag the
  playhead, press play, or switch to Brush and drag a range.
- **Season×hour wheel** — outer ring months, inner ring hours. Paint
  "January evenings" and the whole map re-aggregates for that slice.
- **Provinces** — click to focus the right-hand panel; hover for a live
  lens (trailing-24h sparkline computed per pointer-move).
- **Donut** — click a source to recolor the map by that source's share.
- **Flow arcs** — click an interconnect for its flow-duration curve.

## Point it at your data

`Sources/GridCore` is the seam. It is pure Swift — no Foundation, no
browser imports — and the app only ever calls `GridEngine.query(_:)`
plus two helpers. Replace `GridDataset.generate(seed:)` with a loader
for your own columnar data and everything downstream follows. The
GridCore test suite (`swift test`) runs on the host.

One caveat: the scrubber's time axis assumes the generator's shape (a
365-day year at 5-minute resolution). Loading data with a different
resolution or date range also means updating the interval math in
`Sources/App/Scrubber.swift`.

## Architecture notes

- `GridCore` — columnar struct-of-arrays store, deterministic synthetic
  generator, brute-force masked-scan aggregation engine.
- `App` — one Swiflow component (`GridShell`) owning all state; SVG map
  and controls are plain VNodes; the flow particles are the one canvas
  layer, painted through the `.ref` escape hatch; native pointer
  listeners supply the coordinates Swiflow events don't carry.

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
//
// {{NAME}} — the Canadian grid, live, with no server.
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

    /// Per-frame driver: playback stepping + the canvas flow pass + a
    /// 1 Hz fps stamp (a @State write per second, not per frame).
    func tick(_ ts: Double) {
        if playing, case .instant(let t) = slice {
            slice = .instant((t + 6) % GridDataset.intervalCount)
            runQuery()
        }
        drawFlows()
        frameCount += 1
        if ts - lastFpsStamp > 1000 {
            if lastFpsStamp > 0 {
                hudFps = Int((Double(frameCount) * 1000 / (ts - lastFpsStamp)).rounded())
            }
            frameCount = 0
            lastFpsStamp = ts
        }
    }

    /// Idempotent — later tasks append coordinate listeners here.
    func attachNativeListeners() {
        guard !listenersAttached else { return }
        listenersAttached = true
        attachScrubberListeners()
        attachWheelListeners()
        attachLensListeners()
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

"""##,
                "Sources/App/Charts.swift": ##"""
// Sources/App/Charts.swift
//
// SVG path builders. Input is already ≤200 points (the engine
// downsamples) — these only turn numbers into `d` strings.
import Swiflow
import GridCore

func sourceColor(_ s: Source) -> String {
    switch s {
    case .hydro: "#3d85c8"
    case .nuclear: "#8867c9"
    case .gas: "#d98a3d"
    case .coal: "#6b5d52"
    case .wind: "#5fb88a"
    case .solar: "#e0c33f"
    case .diesel: "#a05252"
    }
}

/// Polyline path scaled into w×h, y-flipped (0 at the bottom).
func linePath(_ values: [Double], w: Double, h: Double, maxV: Double) -> String {
    guard values.count > 1, maxV > 0 else { return "" }
    var d = ""
    for (i, v) in values.enumerated() {
        let x = Double(i) / Double(values.count - 1) * w
        let y = h - min(1, max(0, v / maxV)) * h
        d += (i == 0 ? "M" : "L") + "\(x),\(y)"
    }
    return d
}

/// Stacked area bands, bottom-up in Source order. Returns one closed
/// path per source that has any generation.
func stackedAreaPaths(_ bySource: [[Double]], w: Double, h: Double) -> [(Source, String)] {
    let count = bySource.first?.count ?? 0
    guard count > 1 else { return [] }
    var cumulative = [Double](repeating: 0, count: count)
    var tops: [[Double]] = []
    for s in 0..<bySource.count {
        for i in 0..<count { cumulative[i] += bySource[s][i] }
        tops.append(cumulative)
    }
    let maxV = max(1, cumulative.max() ?? 1)
    var out: [(Source, String)] = []
    var lower = [Double](repeating: 0, count: count)
    for (s, top) in tops.enumerated() {
        let source = Source(rawValue: s)!
        if bySource[s].allSatisfy({ $0 <= 0 }) { lower = top; continue }
        func xy(_ i: Int, _ v: Double) -> String {
            "\(Double(i) / Double(count - 1) * w),\(h - v / maxV * h)"
        }
        var d = "M" + xy(0, lower[0])
        for i in 0..<count { d += "L" + xy(i, top[i]) }
        for i in stride(from: count - 1, through: 0, by: -1) { d += "L" + xy(i, lower[i]) }
        out.append((source, d + "Z"))
        lower = top
    }
    return out
}

"""##,
                "Sources/App/FlowCanvas.swift": ##"""
// Sources/App/FlowCanvas.swift
//
// The one canvas layer: flow particles along the interconnect arcs,
// painted imperatively every frame through the .ref seam. Swiflow never
// reconciles inside the canvas — it only owns the element shell.
//
// Bridge-chattiness budget: ≤ ~40 particles/edge × 14 edges ≈ 560
// particles, one beginPath+arc+fill batch PER EDGE (15 fill calls, not
// 560). If the Task 15 perf checkpoint shows dropped frames, halve
// PARTICLE_BUDGET before reaching for lineDashOffset streams.
import Swiflow
import JavaScriptKit
import GridCore

private let PARTICLE_BUDGET = 40                 // max per edge

extension GridShell {
    @MainActor
    func drawFlows() {
        guard let snap = snapshot else { return }
        if canvasCtx == nil, let canvas = canvasRef.wrappedValue {
            canvasCtx = canvas.getContext!("2d").object
            particlePhases = Interconnect.all.indices.map { i in
                var rng = SplitMix64(seed: UInt64(1000 + i))
                return (0..<PARTICLE_BUDGET).map { _ in rng.unit() }
            }
        }
        guard let ctx = canvasCtx else { return }
        _ = ctx.clearRect!(0, 0, MapGeometry.viewWidth, MapGeometry.viewHeight)

        for (i, tie) in Interconnect.all.enumerated() {
            let mean = snap.edges[i].meanFlowMW
            let load = min(1, abs(mean) / tie.capacityMW)
            guard load > 0.01 else { continue }
            let count = max(2, Int(Double(PARTICLE_BUDGET) * load))
            let speed = (0.001 + 0.006 * load) * (mean >= 0 ? 1 : -1)
            let (p0, c, p1) = arcControlPoints(i)

            ctx.fillStyle = .string(mean >= 0 ? "rgba(96, 165, 250, 0.85)" : "rgba(251, 146, 60, 0.85)")
            _ = ctx.beginPath!()
            for p in 0..<count {
                particlePhases[i][p] += speed
                if particlePhases[i][p] > 1 { particlePhases[i][p] -= 1 }
                if particlePhases[i][p] < 0 { particlePhases[i][p] += 1 }
                let u = particlePhases[i][p]
                // Quadratic bezier point.
                let v = 1 - u
                let x = v * v * p0.0 + 2 * v * u * c.0 + u * u * p1.0
                let y = v * v * p0.1 + 2 * v * u * c.1 + u * u * p1.1
                _ = ctx.moveTo!(x + 2.2, y)
                _ = ctx.arc!(x, y, 2.2, 0, 6.2832)
            }
            _ = ctx.fill!()
        }
    }
}

"""##,
                "Sources/App/FocusPanel.swift": ##"""
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

"""##,
                "Sources/App/HoverLens.swift": ##"""
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

"""##,
                "Sources/App/Inspector.swift": ##"""
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
        guard let i = inspectedEdge else {
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

"""##,
                "Sources/App/JSInterop.swift": ##"""
// Sources/App/JSInterop.swift
//
// The App target's few imperative touches: a monotonic clock, native
// event listeners (Swiflow's EventInfo carries no pointer coordinates),
// and a requestAnimationFrame loop. Every JSClosure is retained for the
// app's lifetime — GridShell never unmounts.
import JavaScriptKit

@MainActor
func nowMs() -> Double {
    let performance = JSObject.global.performance.object!
    return performance.now.function!(this: performance).number ?? 0
}

/// Attaches a native DOM listener and returns the retained closure.
/// Caller stores it (listener lifetime == app lifetime).
@MainActor
@discardableResult
func addNativeListener(_ target: JSObject, _ event: String,
                       _ handler: @escaping (JSValue) -> Void) -> JSClosure {
    let closure = JSClosure { args in
        handler(args.first ?? .undefined)
        return .undefined
    }
    _ = target.addEventListener!(event, closure)
    return closure
}

/// A per-frame driver for playback + the canvas flow layer.
@MainActor
final class RAFLoop {
    private var closure: JSClosure?
    var onFrame: ((Double) -> Void)?

    func start() {
        guard closure == nil else { return }
        let c = JSClosure { [weak self] args in
            self?.onFrame?(args.first?.number ?? 0)
            self?.schedule()
            return .undefined
        }
        closure = c
        schedule()
    }

    private func schedule() {
        guard let closure else { return }
        _ = JSObject.global.requestAnimationFrame!(closure)
    }
}

"""##,
                "Sources/App/MapGeometry.swift": ##"""
// Sources/App/MapGeometry.swift
//
// Baked, pre-projected low-poly geometry. No runtime geo pipeline: the
// polygons ARE the map. Coordinates are viewBox units (1000 × 760,
// y-down). Multi-polygon zones render as one path with multiple
// subpaths (M…Z M…Z) and hit-test each polygon.
import GridCore

struct ProvinceShape {
    let zone: Zone
    let polygons: [[(Double, Double)]]
}

enum MapGeometry {
    static let viewWidth = 1000.0
    static let viewHeight = 760.0

    static let shapes: [ProvinceShape] = [
        ProvinceShape(zone: .yt, polygons: [[(60, 60), (150, 60), (150, 205), (100, 205), (60, 150)]]),
        ProvinceShape(zone: .nt, polygons: [[(150, 60), (330, 45), (355, 205), (150, 205)]]),
        ProvinceShape(zone: .nu, polygons: [[(330, 45), (700, 25), (760, 120), (700, 255), (430, 255), (355, 205)]]),
        ProvinceShape(zone: .bc, polygons: [[(75, 205), (210, 205), (210, 470), (158, 470), (118, 415), (75, 330)]]),
        ProvinceShape(zone: .ab, polygons: [[(210, 205), (300, 205), (300, 470), (210, 470)]]),
        ProvinceShape(zone: .sk, polygons: [[(300, 205), (385, 205), (385, 470), (300, 470)]]),
        ProvinceShape(zone: .mb, polygons: [[(385, 205), (470, 205), (470, 470), (385, 470)]]),
        ProvinceShape(zone: .on, polygons: [[(470, 205), (560, 225), (620, 255), (640, 315), (640, 420),
                                             (600, 470), (555, 555), (505, 535), (470, 470)]]),
        ProvinceShape(zone: .qc, polygons: [[(620, 255), (640, 205), (720, 175), (800, 215), (830, 300),
                                             (805, 415), (730, 470), (680, 430), (640, 420), (640, 315)]]),
        ProvinceShape(zone: .nl, polygons: [
            [(720, 175), (705, 95), (790, 80), (850, 150), (830, 215), (800, 215)],
            [(850, 330), (915, 320), (935, 368), (872, 392)],
        ]),
        ProvinceShape(zone: .nb, polygons: [[(770, 470), (828, 468), (834, 525), (776, 530)]]),
        ProvinceShape(zone: .pe, polygons: [[(845, 478), (882, 474), (886, 489), (850, 493)]]),
        ProvinceShape(zone: .ns, polygons: [[(838, 505), (928, 520), (940, 558), (852, 566), (824, 536)]]),
    ]

    /// Southern anchor for each zone's US-export arrow.
    static let usAnchors: [Zone: (Double, Double)] = [
        .bc: (160, 468), .mb: (427, 468), .on: (557, 553), .qc: (705, 462), .nb: (800, 528),
    ]

    static func pathString(_ shape: ProvinceShape) -> String {
        shape.polygons.map { poly in
            "M" + poly.map { "\($0.0),\($0.1)" }.joined(separator: "L") + "Z"
        }.joined()
    }

    /// Vertex mean of the first (main) polygon — good enough for labels
    /// and arc endpoints on a stylized map.
    static func centroid(_ zone: Zone) -> (Double, Double) {
        let poly = shapes.first { $0.zone == zone }!.polygons[0]
        let sx = poly.reduce(0.0) { $0 + $1.0 }
        let sy = poly.reduce(0.0) { $0 + $1.1 }
        return (sx / Double(poly.count), sy / Double(poly.count))
    }

    static func usAnchor(_ zone: Zone) -> (Double, Double) { usAnchors[zone]! }

    static func hitTest(x: Double, y: Double) -> Zone? {
        for shape in shapes {
            for poly in shape.polygons where contains(poly, x: x, y: y) {
                return shape.zone
            }
        }
        return nil
    }

    /// Standard even-odd ray cast.
    private static func contains(_ poly: [(Double, Double)], x: Double, y: Double) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (xi, yi) = poly[i]
            let (xj, yj) = poly[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

"""##,
                "Sources/App/MapView.swift": ##"""
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
        p1 = (a.0 + 18, 660)
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
                .attr("width", "1000"), .attr("height", "760"),
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

"""##,
                "Sources/App/PerfHUD.swift": ##"""
// Sources/App/PerfHUD.swift
//
// The receipts: dataset size, rows touched by the LAST query, its
// elapsed ms, live fps, and the startup generation time. Collapsible so
// screenshots can go chrome-less.
import Swiflow
import GridCore

extension GridShell {
    @MainActor
    func fmtPts(_ n: Int) -> String {
        if n >= 1_000_000 {
            let tenths = (n * 10) / 1_000_000
            return "\(tenths / 10).\(tenths % 10)M"
        }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }

    @MainActor
    func fmtMs(_ ms: Double) -> String {
        let tenths = Int((ms * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }

    @MainActor
    func hudView() -> VNode {
        let datasetPts = GridDataset.intervalCount * Zone.allCases.count * 9
        var children: [VNode] = [
            element("button", attributes: [
                .class("gb-hud-toggle"),
                .on(.click) { [weak self] in self?.hudOpen.toggle() },
            ], children: [text(hudOpen ? "⌄" : "⌃")]),
        ]
        if hudOpen {
            let stats = snapshot?.stats
            children.append(element("dl", attributes: [.class("gb-hud-grid")], children: [
                hudCell(fmtPts(datasetPts), "dataset pts"),
                hudCell(stats.map { fmtPts($0.rowsTouched) } ?? "—", "rows / query"),
                hudCell(stats.map { "\(fmtMs($0.elapsedMs)) ms" } ?? "—", "scan time"),
                hudCell("\(hudFps)", "fps"),
                hudCell("\(Int(buildMs.rounded())) ms", "generated in"),
            ]))
        }
        return element("div", attributes: [.class("gb-hud")], children: children)
    }

    @MainActor
    private func hudCell(_ value: String, _ label: String) -> VNode {
        element("div", attributes: [.class("gb-hud-cell")], children: [
            element("dt", attributes: [], children: [text(label)]),
            element("dd", attributes: [], children: [text(value)]),
        ])
    }
}

"""##,
                "Sources/App/Scrubber.swift": ##"""
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

"""##,
                "Sources/App/SeasonWheel.swift": ##"""
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

"""##,
                "Sources/App/Shell+Styles.swift": ##"""
// Sources/App/Shell+Styles.swift
import Swiflow

extension GridShell {
    @MainActor static var scopedStyles: CSSSheet? = base + map + scrubber + wheel + panel + lens + arcs + canvas + hud

    static let base = #css("""
        :root {
          --gb-bg: light-dark(oklch(.98 .005 250), oklch(.16 .01 250));
          --gb-panel: light-dark(oklch(.995 0 0), oklch(.21 .012 250));
          --gb-text: CanvasText;
          --gb-dim: color-mix(in oklab, CanvasText 60%, Canvas);
          --gb-border: color-mix(in oklab, CanvasText 14%, transparent);
          --gb-accent: oklch(.62 .17 255);
        }
        :host { display: block; min-height: 100dvh; background: var(--gb-bg); }
        .gb-shell {
          display: grid;
          grid-template-rows: auto 1fr auto;
          gap: 12px;
          max-width: 1400px;
          margin: 0 auto;
          padding: 16px 20px 20px;
          min-height: 100dvh;
          box-sizing: border-box;
        }
        .gb-header h1 { margin: 0; font-size: 22px; letter-spacing: -0.02em; }
        .gb-tagline { margin: 2px 0 0; color: var(--gb-dim); font-size: 13px; }
        .gb-main {
          display: grid;
          grid-template-columns: 1fr 340px;
          gap: 14px;
          min-height: 0;
        }
        .gb-panel {
          background: var(--gb-panel);
          border: 1px solid var(--gb-border);
          border-radius: 12px;
          padding: 14px;
          overflow-y: auto;
        }
        .gb-controls { display: grid; grid-template-columns: 1fr auto; gap: 14px; align-items: end; }
        """)

    static let map = #css("""
        .gb-map-wrap { position: relative; }
        .gb-map { width: 100%; height: auto; display: block; }
        .gb-zone {
          stroke: light-dark(oklch(.98 0 0 / .85), oklch(.14 .01 250 / .9));
          stroke-width: 1.5;
          cursor: pointer;
          transition: fill 220ms ease;
        }
        .gb-zone:hover { filter: brightness(1.12); }
        .gb-zone--focus { stroke: var(--gb-accent); stroke-width: 3; }
        .gb-zone-label {
          font: 600 12px system-ui, sans-serif;
          fill: light-dark(oklch(.99 0 0 / .92), oklch(.95 0 0 / .92));
          text-anchor: middle;
          pointer-events: none;
          paint-order: stroke;
          stroke: rgb(0 0 0 / .25);
          stroke-width: 2;
        }
        """)

    static let scrubber = #css("""
        .gb-scrubber { display: grid; gap: 6px; }
        .gb-scrubber-bar { display: flex; gap: 8px; align-items: center; }
        .gb-btn {
          border: 1px solid var(--gb-border);
          background: var(--gb-panel);
          color: var(--gb-text);
          border-radius: 8px;
          padding: 4px 12px;
          font: 500 13px system-ui, sans-serif;
          cursor: pointer;
        }
        .gb-btn--on { background: var(--gb-accent); color: white; border-color: transparent; }
        .gb-readout { color: var(--gb-dim); font: 500 13px ui-monospace, monospace; }
        .gb-track {
          width: 100%;
          height: 64px;
          display: block;
          background: color-mix(in oklab, var(--gb-panel) 70%, var(--gb-bg));
          border: 1px solid var(--gb-border);
          border-radius: 10px;
          cursor: ew-resize;
          touch-action: none;
        }
        .gb-spark { fill: color-mix(in oklab, var(--gb-accent) 25%, transparent); stroke: var(--gb-accent); stroke-width: 1; vector-effect: non-scaling-stroke; }
        .gb-tick { stroke: var(--gb-border); }
        .gb-playhead { stroke: var(--gb-text); stroke-width: 2; vector-effect: non-scaling-stroke; }
        .gb-playhead-knob { fill: var(--gb-accent); stroke: white; stroke-width: 2; vector-effect: non-scaling-stroke; }
        .gb-brush-range { fill: color-mix(in oklab, var(--gb-accent) 18%, transparent); }
        .gb-thumb { stroke: var(--gb-accent); stroke-width: 4; vector-effect: non-scaling-stroke; cursor: ew-resize; }
        """)

    static let wheel = #css("""
        .gb-wheel-svg { width: 148px; height: 148px; display: block; user-select: none; }
        .gb-seg {
          fill: color-mix(in oklab, var(--gb-text) 8%, var(--gb-panel));
          stroke: var(--gb-bg);
          stroke-width: 1;
          cursor: pointer;
          transition: fill 120ms ease;
        }
        .gb-seg:hover { fill: color-mix(in oklab, var(--gb-accent) 30%, var(--gb-panel)); }
        .gb-seg--on { fill: var(--gb-accent); }
        .gb-seg-label { font: 600 8px system-ui; fill: var(--gb-dim); text-anchor: middle; pointer-events: none; }
        .gb-wheel-clear { fill: var(--gb-panel); stroke: var(--gb-border); cursor: pointer; }
        .gb-wheel-clear--idle { opacity: 0.6; }
        .gb-wheel-clear-label { font: 600 9px system-ui; fill: var(--gb-dim); text-anchor: middle; pointer-events: none; }
        """)

    static let panel = #css("""
        .gb-panel-title { margin: 0 0 8px; font-size: 17px; }
        .gb-empty { color: var(--gb-dim); font-style: italic; }
        .gb-stat-row { display: flex; gap: 18px; margin-bottom: 8px; }
        .gb-stat { display: grid; }
        .gb-stat strong { font-size: 17px; }
        .gb-stat small { color: var(--gb-dim); }
        .gb-donut { width: 160px; margin: 0 auto; display: block; }
        .gb-donut-seg { cursor: pointer; transition: opacity 120ms ease; stroke: var(--gb-panel); stroke-width: 1; }
        .gb-donut-seg:hover { opacity: 0.85; }
        .gb-donut-hole { fill: var(--gb-panel); cursor: pointer; }
        .gb-donut-label { text-anchor: middle; font: 600 12px system-ui; fill: var(--gb-dim); pointer-events: none; }
        .gb-legend { list-style: none; margin: 8px 0; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 4px 10px; font-size: 12px; }
        .gb-legend-item { display: flex; align-items: center; gap: 6px; }
        .gb-legend-swatch { width: 10px; height: 10px; border-radius: 3px; display: inline-block; }
        .gb-chart-card h3 { margin: 10px 0 4px; font-size: 12px; color: var(--gb-dim); text-transform: uppercase; letter-spacing: 0.04em; }
        .gb-chart { width: 100%; display: block; background: color-mix(in oklab, var(--gb-text) 4%, var(--gb-panel)); border-radius: 8px; }
        .gb-area { opacity: 0.9; }
        .gb-price-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        """)

    static let lens = #css("""
        .gb-lens {
          position: absolute;
          z-index: 5;
          pointer-events: none;
          background: var(--gb-panel);
          border: 1px solid var(--gb-border);
          border-radius: 10px;
          box-shadow: 0 6px 24px rgb(0 0 0 / 0.18);
          padding: 8px 10px;
          width: 160px;
          font-size: 12px;
          display: grid;
          gap: 5px;
        }
        .gb-lens--hidden { display: none; }
        .gb-lens-stats { color: var(--gb-dim); }
        .gb-lens-mix { width: 100%; border-radius: 3px; }
        .gb-lens-spark { width: 100%; }
        .gb-lens-spark-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        """)

    static let arcs = #css("""
        .gb-arc {
          fill: none;
          stroke: color-mix(in oklab, var(--gb-accent) 70%, white);
          stroke-linecap: round;
          opacity: 0.65;
          pointer-events: none;
          transition: stroke-width 220ms ease;
        }
        .gb-arc--reverse { stroke: color-mix(in oklab, oklch(.7 .15 60) 80%, white); }
        .gb-arc--focus { opacity: 1; stroke: var(--gb-accent); }
        .gb-arc-hit { fill: none; stroke: transparent; stroke-width: 14; cursor: pointer; }
        .gb-inspector-head { display: flex; justify-content: space-between; align-items: start; }
        .gb-duration-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        .gb-cap-line { stroke: var(--gb-dim); stroke-dasharray: 4 4; vector-effect: non-scaling-stroke; }
        .gb-inspector-note { color: var(--gb-dim); font-size: 12px; }
        """)

    static let canvas = #css("""
        .gb-flow-canvas {
          position: absolute;
          inset: 0;
          width: 100%;
          height: auto;
          aspect-ratio: 1000 / 760;
          pointer-events: none;
        }
        """)

    static let hud = #css("""
        .gb-header { display: flex; justify-content: space-between; align-items: start; gap: 16px; }
        .gb-hud {
          display: flex;
          gap: 8px;
          align-items: start;
          background: var(--gb-panel);
          border: 1px solid var(--gb-border);
          border-radius: 10px;
          padding: 8px 10px;
        }
        .gb-hud-toggle { border: none; background: none; color: var(--gb-dim); cursor: pointer; font-size: 14px; padding: 0 2px; }
        .gb-hud-grid { display: flex; gap: 14px; margin: 0; }
        .gb-hud-cell dt { font: 500 10px system-ui; color: var(--gb-dim); text-transform: uppercase; letter-spacing: 0.05em; }
        .gb-hud-cell dd { margin: 0; font: 600 14px ui-monospace, monospace; }
        @media (max-width: 900px) {
          .gb-main { grid-template-columns: 1fr; }
          .gb-header { flex-direction: column; }
        }
        """)
}

"""##,
                "Sources/GridCore/Generator.swift": ##"""
// Sources/GridCore/Generator.swift
//
// libc, not Foundation: sin/cos/exp/pow come from the platform C library
// (WASILibc on wasm32) — GridCore's no-Foundation constraint holds.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

// Real-shaped synthetic year. Profiles are tuned for plausibility, not
// accuracy: winter-peaking demand (electric heating), latitude-aware
// solar, autocorrelated wind, nuclear baseload with outage windows,
// hydro/thermal dispatched against residual load, flows from a static
// contract shape modulated by season and hour.
//
// Replace `GridDataset.generate(seed:)` with your own loader to point
// the dashboard at real data — everything downstream only sees
// GridDataset.
struct ZoneProfile {
    let basePeakMW: Double      // reference demand scale
    let meanTempC: Double
    let tempAmpC: Double        // seasonal swing (winter = mean - amp)
    let heatShare: Double       // demand sensitivity to cold
    let coolShare: Double       // demand sensitivity to heat
    let solarSeason: Double     // latitude penalty on winter daylight (0…1, 1 = strong swing)
    let caps: [Double]          // MW by Source.rawValue order
    let merit: [Source]         // dispatch order for dispatchables
}

private let profiles: [Zone: ZoneProfile] = [
    .bc: ZoneProfile(basePeakMW: 8_000, meanTempC: 9, tempAmpC: 11, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [16_000, 0, 1_200, 0, 700, 100, 0], merit: [.hydro, .gas, .diesel]),
    .ab: ZoneProfile(basePeakMW: 10_000, meanTempC: 4, tempAmpC: 16, heatShare: 0.45, coolShare: 0.15, solarSeason: 0.60,
                     caps: [900, 0, 11_000, 1_500, 6_000, 1_800, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .sk: ZoneProfile(basePeakMW: 3_800, meanTempC: 3, tempAmpC: 17, heatShare: 0.45, coolShare: 0.15, solarSeason: 0.60,
                     caps: [900, 0, 2_800, 1_500, 800, 300, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .mb: ZoneProfile(basePeakMW: 3_500, meanTempC: 3, tempAmpC: 18, heatShare: 0.60, coolShare: 0.10, solarSeason: 0.60,
                     caps: [5_600, 0, 300, 0, 260, 50, 0], merit: [.hydro, .gas, .diesel]),
    .on: ZoneProfile(basePeakMW: 16_000, meanTempC: 8, tempAmpC: 14, heatShare: 0.35, coolShare: 0.35, solarSeason: 0.50,
                     caps: [9_000, 13_000, 10_000, 0, 5_500, 500, 0], merit: [.hydro, .gas, .diesel]),
    .qc: ZoneProfile(basePeakMW: 21_000, meanTempC: 5, tempAmpC: 16, heatShare: 0.80, coolShare: 0.15, solarSeason: 0.55,
                     caps: [37_000, 0, 0, 0, 4_000, 50, 0], merit: [.hydro, .diesel]),
    .nb: ZoneProfile(basePeakMW: 1_800, meanTempC: 6, tempAmpC: 13, heatShare: 0.60, coolShare: 0.10, solarSeason: 0.55,
                     caps: [900, 660, 400, 500, 300, 50, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .pe: ZoneProfile(basePeakMW: 150, meanTempC: 6, tempAmpC: 12, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [0, 0, 0, 0, 200, 10, 100], merit: [.diesel]),
    .ns: ZoneProfile(basePeakMW: 1_400, meanTempC: 7, tempAmpC: 12, heatShare: 0.55, coolShare: 0.10, solarSeason: 0.55,
                     caps: [400, 0, 500, 1_200, 600, 100, 0], merit: [.hydro, .coal, .gas, .diesel]),
    .nl: ZoneProfile(basePeakMW: 1_200, meanTempC: 2, tempAmpC: 12, heatShare: 0.70, coolShare: 0.05, solarSeason: 0.60,
                     caps: [6_800, 0, 0, 0, 50, 0, 100], merit: [.hydro, .diesel]),
    .yt: ZoneProfile(basePeakMW: 60, meanTempC: -3, tempAmpC: 20, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.80,
                     caps: [95, 0, 0, 0, 5, 2, 30], merit: [.hydro, .diesel]),
    .nt: ZoneProfile(basePeakMW: 55, meanTempC: -5, tempAmpC: 22, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.85,
                     caps: [55, 0, 0, 0, 5, 2, 70], merit: [.hydro, .diesel]),
    .nu: ZoneProfile(basePeakMW: 40, meanTempC: -10, tempAmpC: 22, heatShare: 0.70, coolShare: 0.02, solarSeason: 0.95,
                     caps: [0, 0, 0, 0, 2, 1, 200], merit: [.diesel]),
]

/// Static contract bias per interconnect (share of capacity flowing
/// from → to in an average hour). Index-aligned with `Interconnect.all`.
private let flowBias: [Double] = [
    0.15,   // BC→AB — swings with AB scarcity
    0.30,   // AB→SK
    0.25,   // SK→MB — often reverses (MB hydro pushes back)
    0.60,   // MB→ON — Manitoba hydro exports east
    0.55,   // QC→ON contract flow
    0.55,   // QC→NB
    0.55,   // NB→NS
    0.45,   // NB→PE
    0.88,   // NL→QC — Churchill Falls, near-constant
    0.45,   // BC→US
    0.60,   // MB→US
    0.40,   // ON→US
    0.70,   // QC→US
    0.35,   // NB→US
]
// Convention: bias ≈ mean of `flow / capacity`, positive = from → to.

extension GridDataset {
    public static func generate(seed: UInt64) -> GridDataset {
        let n = intervalCount
        let zoneCount = Zone.allCases.count
        var rng = SplitMix64(seed: seed)
        let cal = calendar()

        var demand = [Float](repeating: 0, count: zoneCount * n)
        var price = [Float](repeating: 0, count: zoneCount * n)
        var gen = [[Float]](repeating: [Float](repeating: 0, count: zoneCount * n),
                            count: Source.allCases.count)
        var flow = [[Float]](repeating: [Float](repeating: 0, count: n),
                             count: Interconnect.all.count)

        // Per-zone autocorrelated states (wind + cloud), advanced per interval.
        var windState = [Double](repeating: 0.35, count: zoneCount)
        var cloudState = [Double](repeating: 0.5, count: zoneCount)

        for t in 0..<n {
            let d = t / intervalsPerDay
            let hour = Double(t % intervalsPerDay) / 12.0          // 0..<24, fractional
            let dayPhase = Double(d)
            let weekend = (d % 7 == 5 || d % 7 == 6)
            // Seasonal factors shared by all zones this interval.
            let seasonCos = _cos(2 * .pi * (dayPhase - 15) / 365)  // 1 ≈ mid-January
            let sunSeason = 0.5 - 0.5 * seasonCos                  // 0 winter … 1 summer

            // --- flows first (they shape dispatch via netExport) ---
            var netExport = [Double](repeating: 0, count: zoneCount)
            for (i, tie) in Interconnect.all.enumerated() {
                let diurnal = 0.75 + 0.25 * _sin((hour - 6) * .pi / 12)
                let winterBoost = tie.from == .qc || tie.from == .mb ? (1 + 0.25 * seasonCos) : 1
                let wobble = 0.9 + 0.2 * rng.unit()
                var f = tie.capacityMW * flowBias[i] * diurnal * winterBoost * wobble
                if tie.from == .bc, tie.to == .ab {
                    // BC↔AB genuinely swings sign with Alberta's evening peak.
                    f = tie.capacityMW * (0.35 * _sin((hour - 17) * .pi / 6) + 0.1 * (rng.unit() - 0.5))
                }
                f = _clamp(f, -tie.capacityMW, tie.capacityMW)
                flow[i][t] = Float(f)
                netExport[tie.from.rawValue] += f
                if let to = tie.to { netExport[to.rawValue] -= f }
            }

            for z in Zone.allCases {
                let p = profiles[z]!
                let zi = z.rawValue
                let idx = zi * n + t

                // --- demand ---
                let temp = p.meanTempC - p.tempAmpC * seasonCos
                let heating = p.heatShare * max(0, 16 - temp) / 28
                let cooling = p.coolShare * max(0, temp - 22) / 15
                let diurnal = 0.82
                    + 0.13 * _exp(-((hour - 8) * (hour - 8)) / 8)
                    + 0.16 * _exp(-((hour - 18.5) * (hour - 18.5)) / 10)
                let dm = p.basePeakMW * diurnal * (weekend ? 0.92 : 1.0)
                    * (1 + heating + cooling) * (1 + 0.03 * (rng.unit() - 0.5))
                demand[idx] = Float(dm)

                // --- must-run: wind, solar, nuclear ---
                // Wind: mean-reverting walk, clamped capacity factor.
                windState[zi] += 0.02 * (0.35 - windState[zi]) + 0.05 * (rng.unit() - 0.5)
                windState[zi] = _clamp(windState[zi], 0.02, 0.95)
                var wind = p.caps[Source.wind.rawValue] * windState[zi]

                // Solar: daylight bell scaled by season and slow-moving cloud.
                cloudState[zi] += 0.03 * (0.5 - cloudState[zi]) + 0.06 * (rng.unit() - 0.5)
                cloudState[zi] = _clamp(cloudState[zi], 0.05, 0.95)
                let halfDay = 4.2 + 2.8 * (sunSeason * (0.4 + 0.6 * (1 - p.solarSeason)) + sunSeason * p.solarSeason)
                let elev = _cos((hour - 12.75) * .pi / (2 * halfDay))
                var solar = elev > 0
                    ? p.caps[Source.solar.rawValue] * _pow(elev, 1.4) * (0.35 + 0.65 * sunSeason) * (1 - 0.7 * cloudState[zi])
                    : 0
                // Nuclear: flat with outage windows.
                var nuclearFactor = 1.0
                if z == .on { if (110...140).contains(d) || (250...270).contains(d) { nuclearFactor = 0.85 } }
                if z == .nb { if (200...215).contains(d) { nuclearFactor = 0 } }
                var nuclear = p.caps[Source.nuclear.rawValue] * nuclearFactor

                // --- dispatch: fill demand + netExport, preserve identity ---
                var need = dm + netExport[zi] - (wind + solar + nuclear)
                if need < 0 {
                    // Curtail wind, then solar, then nuclear to maintain Σgen == demand + netExport.
                    let cut = -need
                    let windCut = min(wind, cut)
                    wind -= windCut
                    let solarCut = min(solar, cut - windCut)
                    solar -= solarCut
                    let nuclearCut = min(nuclear, cut - windCut - solarCut)
                    nuclear -= nuclearCut
                    need = 0
                }
                var dispatched: [Source: Double] = [:]
                for s in p.merit {
                    let take = min(p.caps[s.rawValue], need)
                    dispatched[s] = take
                    need -= take
                    if need <= 0 { break }
                }
                if need > 0 {
                    // Emergency peakers beyond nameplate — keeps the identity
                    // and reads as scarcity in the price.
                    dispatched[.gas, default: 0] += need
                }

                gen[Source.wind.rawValue][idx] = Float(wind)
                gen[Source.solar.rawValue][idx] = Float(solar)
                gen[Source.nuclear.rawValue][idx] = Float(nuclear)
                for (s, mw) in dispatched { gen[s.rawValue][idx] += Float(mw) }

                // --- price: quadratic in dispatch tightness ---
                let dispCap = p.merit.reduce(0.0) { $0 + p.caps[$1.rawValue] }
                let tightness = dispCap > 0 ? _clamp((dm + netExport[zi] - nuclear) / dispCap, 0, 1.4) : 1.0
                var pr = 20 + 90 * tightness * tightness + 4 * (rng.unit() - 0.5)
                if tightness > 0.9 { pr += 400 * (tightness - 0.9) }
                price[idx] = Float(max(5, pr))
            }
        }
        return GridDataset(demand: demand, price: price, gen: gen, flow: flow,
                           monthOfInterval: cal.month, hourOfInterval: cal.hour)
    }
}

@inline(__always) func _sin(_ x: Double) -> Double { sin(x) }
@inline(__always) func _cos(_ x: Double) -> Double { cos(x) }
@inline(__always) func _exp(_ x: Double) -> Double { exp(x) }
@inline(__always) func _pow(_ x: Double, _ y: Double) -> Double { pow(x, y) }
@inline(__always) func _clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }

"""##,
                "Sources/GridCore/GridDataset.swift": ##"""
// Sources/GridCore/GridDataset.swift
//
// Columnar struct-of-arrays store. Zone-major layout (`z * N + t`) keeps
// each zone's year contiguous, so per-zone scans are cache-linear.
public struct GridDataset: Sendable {
    public static let intervalsPerDay = 288          // 5-minute resolution
    public static let dayCount = 365
    public static let intervalCount = 105_120        // 365 × 288

    /// Cumulative day-of-year at each month start (non-leap).
    public static let monthStartDay: [Int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

    public var demand: [Float]        // [zone × interval]
    public var price: [Float]         // [zone × interval]
    public var gen: [[Float]]         // [source][zone × interval]
    public var flow: [[Float]]        // [interconnect][interval]
    public var monthOfInterval: [UInt8]
    public var hourOfInterval: [UInt8]

    public init(demand: [Float], price: [Float], gen: [[Float]], flow: [[Float]],
                monthOfInterval: [UInt8], hourOfInterval: [UInt8]) {
        self.demand = demand
        self.price = price
        self.gen = gen
        self.flow = flow
        self.monthOfInterval = monthOfInterval
        self.hourOfInterval = hourOfInterval
    }

    /// Interval count of THIS dataset instance, derived from array length.
    /// The generator always builds `Self.intervalCount` (the full year);
    /// tests build small fixtures — the engine and helpers index with this
    /// so both work.
    @inline(__always)
    public var intervals: Int { demand.count / Zone.allCases.count }

    @inline(__always)
    public func demand(_ z: Zone, _ t: Int) -> Float {
        demand[z.rawValue * intervals + t]
    }

    @inline(__always)
    public func price(_ z: Zone, _ t: Int) -> Float {
        price[z.rawValue * intervals + t]
    }

    @inline(__always)
    public func gen(_ s: Source, _ z: Zone, _ t: Int) -> Float {
        gen[s.rawValue][z.rawValue * intervals + t]
    }

    /// Builds the two calendar arrays for a full standard year.
    public static func calendar() -> (month: [UInt8], hour: [UInt8]) {
        var month = [UInt8](repeating: 0, count: intervalCount)
        var hour = [UInt8](repeating: 0, count: intervalCount)
        var m = 0
        for d in 0..<dayCount {
            if m < 11 && d >= monthStartDay[m + 1] { m += 1 }
            for i in 0..<intervalsPerDay {
                let t = d * intervalsPerDay + i
                month[t] = UInt8(m)
                hour[t] = UInt8(i / 12)                  // 12 five-minute steps per hour
            }
        }
        return (month, hour)
    }
}

"""##,
                "Sources/GridCore/GridEngine.swift": ##"""
// Sources/GridCore/GridEngine.swift
//
// Brute-force masked scans over the columnar arrays — deliberately no
// precomputed rollups (honest per-frame compute is the demo; summaries
// could slot in behind this same interface later). Zone-major layout
// makes the inner t-loop cache-linear per zone.
public struct GridEngine: Sendable {
    public let data: GridDataset

    public init(data: GridDataset) { self.data = data }

    public func query(_ q: GridQuery) -> GridSnapshot {
        let n = data.intervals
        var lo: Int, hi: Int
        switch q.slice {
        case .instant(let t):
            lo = min(max(0, t), n - 1); hi = lo
        case .range(let a, let b):
            lo = min(max(0, min(a, b)), n - 1)
            hi = min(max(0, max(a, b)), n - 1)
        }

        // Precompute the wheel mask once for the range (identity → nil).
        var mask: [Bool]? = nil
        var visited = hi - lo + 1
        if !q.wheel.isIdentity {
            var m = [Bool](repeating: false, count: hi - lo + 1)
            var c = 0
            for t in lo...hi {
                let ok = q.wheel.passes(month: data.monthOfInterval[t], hour: data.hourOfInterval[t])
                m[t - lo] = ok
                if ok { c += 1 }
            }
            mask = m
            visited = c
        }

        let zoneCount = Zone.allCases.count
        let srcCount = Source.allCases.count
        let isEmpty = visited == 0

        // --- per-zone scan ---
        var zones: [ZoneAggregate] = []
        zones.reserveCapacity(zoneCount)
        var natDemand = 0.0
        var natGen = [Double](repeating: 0, count: srcCount)
        for z in Zone.allCases {
            var dSum = 0.0, pSum = 0.0
            var gSum = [Double](repeating: 0, count: srcCount)
            if !isEmpty {
                let base = z.rawValue * n
                for t in lo...hi {
                    if let mask, !mask[t - lo] { continue }
                    dSum += Double(data.demand[base + t])
                    pSum += Double(data.price[base + t])
                    for s in 0..<srcCount { gSum[s] += Double(data.gen[s][base + t]) }
                }
            }
            let c = Double(max(1, visited))
            let genMW = gSum.map { $0 / c }
            let totalGen = genMW.reduce(0, +)
            let intensity = totalGen > 0
                ? zip(genMW, Source.allCases).reduce(0.0) { $0 + $1.0 * $1.1.gCO2PerKWh } / totalGen
                : 0
            let lens: Double
            switch q.lensMetric {
            case .carbonIntensity: lens = intensity
            case .sourceShare(let s): lens = totalGen > 0 ? genMW[s.rawValue] / totalGen : 0
            }
            zones.append(ZoneAggregate(zone: z, meanDemandMW: dSum / c, meanPriceDollars: pSum / c,
                                       genMW: genMW, carbonIntensity: intensity, lensValue: lens))
            natDemand += dSum / c
            for s in 0..<srcCount { natGen[s] += genMW[s] }
        }
        let natTotal = natGen.reduce(0, +)
        let natIntensity = natTotal > 0
            ? zip(natGen, Source.allCases).reduce(0.0) { $0 + $1.0 * $1.1.gCO2PerKWh } / natTotal
            : 0
        let national = NationalAggregate(totalDemandMW: natDemand, genMW: natGen, carbonIntensity: natIntensity)

        // --- per-edge scan ---
        var edges: [EdgeAggregate] = []
        edges.reserveCapacity(Interconnect.all.count)
        for (i, tie) in Interconnect.all.enumerated() {
            var fSum = 0.0, peak = 0.0
            var congested = 0
            if !isEmpty {
                let limit = tie.capacityMW * 0.95
                for t in lo...hi {
                    if let mask, !mask[t - lo] { continue }
                    let f = Double(data.flow[i][t])
                    fSum += f
                    let a = abs(f)
                    if a > peak { peak = a }
                    if a > limit { congested += 1 }
                }
            }
            let c = Double(max(1, visited))
            edges.append(EdgeAggregate(index: i, meanFlowMW: fSum / c, peakAbsMW: peak,
                                       congestionShare: Double(congested) / c))
        }

        // --- chart series (focus zone, or national sum) ---
        let bucketCount = isEmpty ? 0 : min(200, hi - lo + 1)
        var sDemand = [Double](repeating: 0, count: bucketCount)
        var sPrice = [Double](repeating: 0, count: bucketCount)
        var sBySource = [[Double]](repeating: [Double](repeating: 0, count: bucketCount), count: srcCount)
        if bucketCount > 0 {
            var counts = [Int](repeating: 0, count: bucketCount)
            let span = hi - lo + 1
            let focus = q.focusZone
            for t in lo...hi {
                if let mask, !mask[t - lo] { continue }
                let b = min(bucketCount - 1, (t - lo) * bucketCount / span)
                counts[b] += 1
                if let z = focus {
                    sDemand[b] += Double(data.demand(z, t))
                    sPrice[b] += Double(data.price(z, t))
                    for s in 0..<srcCount { sBySource[s][b] += Double(data.gen[s][z.rawValue * n + t]) }
                } else {
                    for z in Zone.allCases {
                        sDemand[b] += Double(data.demand(z, t))
                        for s in 0..<srcCount { sBySource[s][b] += Double(data.gen[s][z.rawValue * n + t]) }
                    }
                    // National price: demand-agnostic simple mean across zones.
                    var p = 0.0
                    for z in Zone.allCases { p += Double(data.price(z, t)) }
                    sPrice[b] += p / Double(zoneCount)
                }
            }
            for b in 0..<bucketCount where counts[b] > 0 {
                let c = Double(counts[b])
                sDemand[b] /= c; sPrice[b] /= c
                for s in 0..<srcCount { sBySource[s][b] /= c }
            }
            // Empty buckets (wheel gaps): carry the previous bucket's value
            // so charts stay continuous.
            for b in 1..<bucketCount where counts[b] == 0 {
                sDemand[b] = sDemand[b - 1]; sPrice[b] = sPrice[b - 1]
                for s in 0..<srcCount { sBySource[s][b] = sBySource[s][b - 1] }
            }
        }
        let series = ChartSeries(bucketCount: bucketCount, demand: sDemand, bySource: sBySource, price: sPrice)

        // Rows touched: every (interval × zone) cell read across demand,
        // price, and the 7 gen arrays, plus the per-edge flow reads.
        let rows = visited * zoneCount * (2 + srcCount) + visited * Interconnect.all.count
        return GridSnapshot(zones: zones, edges: edges, national: national, series: series,
                            stats: QueryStats(rowsTouched: rows, elapsedMs: 0), isEmpty: isEmpty)
    }
}

/// Bucket-mean downsampling to at most `target` points. Empty input
/// stays empty; short input passes through unchanged.
public func downsample(_ values: [Double], to target: Int) -> [Double] {
    guard values.count > target, target > 0 else { return values }
    var out = [Double](repeating: 0, count: target)
    var counts = [Int](repeating: 0, count: target)
    for (i, v) in values.enumerated() {
        let b = min(target - 1, i * target / values.count)
        out[b] += v
        counts[b] += 1
    }
    for b in 0..<target where counts[b] > 0 { out[b] /= Double(counts[b]) }
    return out
}

public struct LensSeries: Sendable {
    public let demand24h: [Double]     // ≤ 48 points, trailing 24 h
    public let mixMW: [Double]         // instant MW by source at `around`
}

public struct DurationCurve: Sendable {
    public let points: [Double]        // |flow| sorted descending, ≤ 100 points
    public let meanMW: Double          // signed mean
    public let peakMW: Double
    public let congestionHours: Double
}

extension GridEngine {
    /// Trailing-24h demand sparkline + instant mix for the hover lens.
    public func lensSeries(zone: Zone, around t: Int) -> LensSeries {
        let n = data.intervals
        let tc = min(max(0, t), n - 1)
        let lo = max(0, tc - GridDataset.intervalsPerDay + 1)
        var raw: [Double] = []
        raw.reserveCapacity(tc - lo + 1)
        for i in lo...tc { raw.append(Double(data.demand(zone, i))) }
        let mix = Source.allCases.map { Double(data.gen($0, zone, tc)) }
        return LensSeries(demand24h: downsample(raw, to: 48), mixMW: mix)
    }

    /// Flow-duration curve for one interconnect over the active slice+wheel.
    public func durationCurve(edge: Int, slice: TimeSlice, wheel: SeasonHourFilter) -> DurationCurve {
        let n = data.intervals
        var lo: Int, hi: Int
        switch slice {
        case .instant(let t):
            // A single instant has no curve — widen to the surrounding day.
            let tc = min(max(0, t), n - 1)
            lo = max(0, tc - GridDataset.intervalsPerDay / 2)
            hi = min(n - 1, lo + GridDataset.intervalsPerDay - 1)
        case .range(let a, let b):
            lo = min(max(0, min(a, b)), n - 1)
            hi = min(max(0, max(a, b)), n - 1)
        }
        let cap = Interconnect.all[edge].capacityMW
        var absFlows: [Double] = []
        var sum = 0.0, peak = 0.0
        var congested = 0
        for t in lo...hi {
            if !wheel.isIdentity,
               !wheel.passes(month: data.monthOfInterval[t], hour: data.hourOfInterval[t]) { continue }
            let f = Double(data.flow[edge][t])
            let a = abs(f)
            absFlows.append(a)
            sum += f
            if a > peak { peak = a }
            if a > cap * 0.95 { congested += 1 }
        }
        absFlows.sort(by: >)
        let count = max(1, absFlows.count)
        return DurationCurve(points: downsample(absFlows, to: 100),
                             meanMW: sum / Double(count),
                             peakMW: peak,
                             congestionHours: Double(congested) * 5.0 / 60.0)
    }
}

"""##,
                "Sources/GridCore/QueryTypes.swift": ##"""
// Sources/GridCore/QueryTypes.swift
//
// The engine's entire caller-facing vocabulary. The App target sees
// nothing below this interface — no raw arrays cross it.
public enum TimeSlice: Equatable, Sendable {
    case instant(Int)
    case range(Int, Int)       // inclusive lo...hi (order-normalized by the engine)
}

/// The season×hour wheel's selection. Bit m of `months` = month m
/// selected; bit h of `hours` = hour h. All-zero on a dimension means
/// "no filter" on that dimension.
public struct SeasonHourFilter: Equatable, Sendable {
    public var months: UInt16
    public var hours: UInt32

    public init(months: UInt16 = 0, hours: UInt32 = 0) {
        self.months = months
        self.hours = hours
    }

    @inline(__always)
    public func passes(month: UInt8, hour: UInt8) -> Bool {
        (months == 0 || (months >> month) & 1 == 1)
            && (hours == 0 || (hours >> hour) & 1 == 1)
    }

    public var isIdentity: Bool { months == 0 && hours == 0 }
}

public enum LensMetric: Equatable, Sendable {
    case carbonIntensity
    case sourceShare(Source)
}

public struct GridQuery: Equatable, Sendable {
    public var slice: TimeSlice
    public var wheel: SeasonHourFilter
    public var lensMetric: LensMetric
    public var focusZone: Zone?

    public init(slice: TimeSlice, wheel: SeasonHourFilter = SeasonHourFilter(),
                lensMetric: LensMetric = .carbonIntensity, focusZone: Zone? = nil) {
        self.slice = slice
        self.wheel = wheel
        self.lensMetric = lensMetric
        self.focusZone = focusZone
    }
}

public struct ZoneAggregate: Sendable {
    public let zone: Zone
    public let meanDemandMW: Double
    public let meanPriceDollars: Double
    public let genMW: [Double]          // mean MW by Source.rawValue
    public let carbonIntensity: Double  // gCO2/kWh, generation-weighted
    public let lensValue: Double        // intensity, or the share (0…1) for .sourceShare
}

public struct EdgeAggregate: Sendable {
    public let index: Int               // into Interconnect.all
    public let meanFlowMW: Double       // signed, + = from → to
    public let peakAbsMW: Double
    public let congestionShare: Double  // fraction of intervals with |flow| > 95% cap
}

public struct NationalAggregate: Sendable {
    public let totalDemandMW: Double
    public let genMW: [Double]
    public let carbonIntensity: Double
}

/// Panel series, pre-downsampled in-engine — the UI never receives more
/// than `bucketCount` points per series.
public struct ChartSeries: Sendable {
    public let bucketCount: Int
    public let demand: [Double]
    public let bySource: [[Double]]     // [source][bucket]
    public let price: [Double]
}

public struct QueryStats: Sendable {
    public let rowsTouched: Int
    /// Stamped by the caller boundary (App shell, performance.now) so the
    /// engine stays clock-free and host-testable.
    public var elapsedMs: Double
}

public struct GridSnapshot: Sendable {
    public let zones: [ZoneAggregate]
    public let edges: [EdgeAggregate]
    public let national: NationalAggregate
    public let series: ChartSeries
    public var stats: QueryStats
    public let isEmpty: Bool
}

"""##,
                "Sources/GridCore/SplitMix64.swift": ##"""
// Sources/GridCore/SplitMix64.swift
//
// Deterministic PRNG for the synthetic dataset. SplitMix64: tiny, fast,
// statistically fine for demo data, and — critically — identical output
// on host and wasm32 because everything is explicit UInt64 (wasm32's
// native Int is 32-bit; bare-Int mixing would differ or trap).
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1) with 53 bits of mantissa.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}

"""##,
                "Sources/GridCore/Zones.swift": ##"""
// Sources/GridCore/Zones.swift
//
// The fixed universe: 13 Canadian provinces/territories, 7 generation
// sources, and the interconnects between zones (plus US-export ties,
// modeled as `to: nil`). Capacities are round, plausible figures — this
// is a demo dataset, not a grid model.
public enum Zone: Int, CaseIterable, Sendable, Equatable {
    case bc, ab, sk, mb, on, qc, nb, pe, ns, nl, yt, nt, nu

    public var code: String {
        switch self {
        case .bc: "BC"; case .ab: "AB"; case .sk: "SK"; case .mb: "MB"
        case .on: "ON"; case .qc: "QC"; case .nb: "NB"; case .pe: "PE"
        case .ns: "NS"; case .nl: "NL"; case .yt: "YT"; case .nt: "NT"
        case .nu: "NU"
        }
    }

    public var name: String {
        switch self {
        case .bc: "British Columbia"; case .ab: "Alberta"
        case .sk: "Saskatchewan"; case .mb: "Manitoba"
        case .on: "Ontario"; case .qc: "Québec"
        case .nb: "New Brunswick"; case .pe: "Prince Edward Island"
        case .ns: "Nova Scotia"; case .nl: "Newfoundland and Labrador"
        case .yt: "Yukon"; case .nt: "Northwest Territories"
        case .nu: "Nunavut"
        }
    }
}

public enum Source: Int, CaseIterable, Sendable, Equatable {
    case hydro, nuclear, gas, coal, wind, solar, diesel

    public var label: String {
        switch self {
        case .hydro: "Hydro"; case .nuclear: "Nuclear"; case .gas: "Gas"
        case .coal: "Coal"; case .wind: "Wind"; case .solar: "Solar"
        case .diesel: "Diesel"
        }
    }

    /// Lifecycle emission factors, gCO2eq/kWh (IPCC-style medians).
    public var gCO2PerKWh: Double {
        switch self {
        case .hydro: 24; case .nuclear: 12; case .gas: 490
        case .coal: 820; case .wind: 11; case .solar: 45; case .diesel: 650
        }
    }
}

/// A directed transmission tie. Positive flow = `from` → `to`.
/// `to == nil` models a US export interface (the US side is not a zone).
public struct Interconnect: Sendable, Equatable {
    public let from: Zone
    public let to: Zone?
    public let capacityMW: Double

    public var label: String { "\(from.code) → \(to?.code ?? "US")" }

    public init(from: Zone, to: Zone?, capacityMW: Double) {
        self.from = from
        self.to = to
        self.capacityMW = capacityMW
    }

    public static let all: [Interconnect] = [
        Interconnect(from: .bc, to: .ab, capacityMW: 1_200),
        Interconnect(from: .ab, to: .sk, capacityMW: 150),
        Interconnect(from: .sk, to: .mb, capacityMW: 300),
        Interconnect(from: .mb, to: .on, capacityMW: 250),
        Interconnect(from: .qc, to: .on, capacityMW: 2_700),
        Interconnect(from: .qc, to: .nb, capacityMW: 1_000),
        Interconnect(from: .nb, to: .ns, capacityMW: 500),
        Interconnect(from: .nb, to: .pe, capacityMW: 560),
        Interconnect(from: .nl, to: .qc, capacityMW: 5_000),   // Churchill Falls
        Interconnect(from: .bc, to: nil, capacityMW: 3_000),
        Interconnect(from: .mb, to: nil, capacityMW: 2_100),
        Interconnect(from: .on, to: nil, capacityMW: 2_500),
        Interconnect(from: .qc, to: nil, capacityMW: 4_000),
        Interconnect(from: .nb, to: nil, capacityMW: 1_000),
    ]
}

"""##,
                "Tests/GridCoreTests/EngineTests.swift": ##"""
import Testing
@testable import GridCore

@Suite("GridEngine")
struct EngineTests {
    static func fixture() -> GridEngine {
        let zc = Zone.allCases.count, n = 4
        var demand = [Float](repeating: 0, count: zc * n)
        var price = [Float](repeating: 0, count: zc * n)
        var gen = [[Float]](repeating: [Float](repeating: 0, count: zc * n), count: Source.allCases.count)
        var flow = [[Float]](repeating: [Float](repeating: 0, count: n), count: Interconnect.all.count)
        let qc = Zone.qc.rawValue * n, ab = Zone.ab.rawValue * n
        for t in 0..<n {
            demand[qc + t] = Float(10 * (t + 1))
            gen[Source.hydro.rawValue][qc + t] = Float(10 * (t + 1))
            price[qc + t] = Float(t + 1)
            demand[ab + t] = 100
            gen[Source.gas.rawValue][ab + t] = 60
            gen[Source.coal.rawValue][ab + t] = 40
            price[ab + t] = 50
        }
        flow[0] = [100, -100, 200, 1200]
        let data = GridDataset(demand: demand, price: price, gen: gen, flow: flow,
                               monthOfInterval: [0, 0, 6, 6], hourOfInterval: [3, 20, 3, 20])
        return GridEngine(data: data)
    }

    @Test("instant query reads a single interval exactly")
    func instant() {
        let snap = Self.fixture().query(GridQuery(slice: .instant(2)))
        let qc = snap.zones[Zone.qc.rawValue]
        #expect(qc.meanDemandMW == 30)
        #expect(qc.genMW[Source.hydro.rawValue] == 30)
        #expect(qc.carbonIntensity == 24)                    // pure hydro
        let ab = snap.zones[Zone.ab.rawValue]
        #expect(ab.meanDemandMW == 100)
        // AB intensity: (60·490 + 40·820) / 100 = 622
        #expect(abs(ab.carbonIntensity - 622) < 0.001)
        #expect(!snap.isEmpty)
    }

    @Test("range query means; national aggregate sums zones")
    func range() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let qc = snap.zones[Zone.qc.rawValue]
        #expect(qc.meanDemandMW == 25)                       // (10+20+30+40)/4
        #expect(qc.meanPriceDollars == 2.5)
        #expect(snap.national.totalDemandMW == 125)          // 25 + 100
        #expect(abs(snap.national.genMW[Source.hydro.rawValue] - 25) < 0.001)
    }

    @Test("wheel filter: month mask selects January intervals only")
    func wheelMonths() {
        // months bit 0 = January → intervals 0 and 1.
        let wheel = SeasonHourFilter(months: 1)
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: wheel))
        #expect(snap.zones[Zone.qc.rawValue].meanDemandMW == 15)   // (10+20)/2
    }

    @Test("wheel filter: month × hour intersect; impossible combo → isEmpty")
    func wheelIntersection() {
        // January (bit 0) AND hour 20 (bit 20) → interval 1 only.
        let both = SeasonHourFilter(months: 1, hours: 1 << 20)
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: both))
        #expect(snap.zones[Zone.qc.rawValue].meanDemandMW == 20)
        // July (bit 6) AND hour 5 (unused) → nothing passes.
        let none = SeasonHourFilter(months: 1 << 6, hours: 1 << 5)
        let empty = Self.fixture().query(GridQuery(slice: .range(0, 3), wheel: none))
        #expect(empty.isEmpty)
        #expect(empty.zones[Zone.qc.rawValue].meanDemandMW == 0)
    }

    @Test("lens metric: sourceShare returns the generation share")
    func lens() {
        let q = GridQuery(slice: .instant(0), wheel: SeasonHourFilter(),
                          lensMetric: .sourceShare(.gas))
        let snap = Self.fixture().query(q)
        #expect(abs(snap.zones[Zone.ab.rawValue].lensValue - 0.6) < 0.001)
        #expect(snap.zones[Zone.qc.rawValue].lensValue == 0)
    }

    @Test("edges: mean, peak, congestion share")
    func edges() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let e = snap.edges[0]                                // BC→AB, cap 1200
        #expect(e.meanFlowMW == 350)                         // (100-100+200+1200)/4
        #expect(e.peakAbsMW == 1200)
        #expect(e.congestionShare == 0.25)                   // only 1200 > 1140
    }

    @Test("series: buckets equal the range length when short; focus zone respected")
    func series() {
        let snap = Self.fixture().query(GridQuery(slice: .range(0, 3), focusZone: .qc))
        #expect(snap.series.bucketCount == 4)
        #expect(snap.series.demand == [10, 20, 30, 40])
        #expect(snap.series.bySource[Source.hydro.rawValue] == [10, 20, 30, 40])
    }

    @Test("rows touched scales with visited intervals")
    func stats() {
        let full = Self.fixture().query(GridQuery(slice: .range(0, 3)))
        let one = Self.fixture().query(GridQuery(slice: .instant(0)))
        #expect(full.stats.rowsTouched == 4 * 13 * 9 + 4 * 14)
        #expect(one.stats.rowsTouched == 13 * 9 + 14)
    }
}

@Suite("GridEngine extras")
struct EngineExtrasTests {
    @Test("downsample: bucket means, pass-through when short")
    func downsampleBasics() {
        #expect(downsample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
        #expect(downsample([1, 2], to: 4) == [1, 2])
        #expect(downsample([], to: 4) == [])
    }

    @Test("lensSeries: trailing window clamps at zero; mix reads the instant")
    func lens() {
        let e = EngineTests.fixture()
        let s = e.lensSeries(zone: .qc, around: 2)
        #expect(s.demand24h == [10, 20, 30])                 // 4-interval fixture, t ≤ 2
        #expect(s.mixMW[Source.hydro.rawValue] == 30)
        #expect(s.mixMW[Source.gas.rawValue] == 0)
    }

    @Test("durationCurve: sorted descending, congestion in hours")
    func duration() {
        let e = EngineTests.fixture()
        let c = e.durationCurve(edge: 0, slice: .range(0, 3), wheel: SeasonHourFilter())
        #expect(c.points == [1200, 200, 100, 100])
        #expect(c.meanMW == 350)
        #expect(c.peakMW == 1200)
        #expect(abs(c.congestionHours - 5.0 / 60.0) < 0.0001)  // one 5-min interval
    }
}

"""##,
                "Tests/GridCoreTests/GeneratorTests.swift": ##"""
import Testing
@testable import GridCore

/// Small-N generation would be nicer, but the generator is fixed-size by
/// design (the whole point is the 105k-interval year). One shared instance
/// keeps the suite fast; generation is ~a second on host.
@Suite("Generator", .serialized)
struct GeneratorTests {
    static let a = GridDataset.generate(seed: 1)

    @Test("deterministic: same seed → identical arrays; different seed diverges")
    func determinism() {
        let b = GridDataset.generate(seed: 1)
        let c = GridDataset.generate(seed: 2)
        #expect(Self.a.demand == b.demand)
        #expect(Self.a.price == b.price)
        #expect(Self.a.gen == b.gen)
        #expect(Self.a.flow == b.flow)
        #expect(Self.a.demand != c.demand)
    }

    @Test("physical sanity: no NaN, no negatives, flows within capacity")
    func sanity() {
        let d = Self.a
        #expect(!d.demand.contains { $0.isNaN || $0 < 0 })
        #expect(!d.price.contains { $0.isNaN || $0 < 0 })
        for s in d.gen { #expect(!s.contains { $0.isNaN || $0 < 0 }) }
        for (i, tie) in Interconnect.all.enumerated() {
            let cap = Float(tie.capacityMW)
            #expect(!d.flow[i].contains { $0.isNaN || abs($0) > cap * 1.001 })
        }
    }

    @Test("dispatch identity: Σgen == demand + netExport (per zone, sampled)")
    func identity() {
        let d = Self.a
        let n = GridDataset.intervalCount
        for t in stride(from: 0, to: n, by: 997) {
            var netExport = [Double](repeating: 0, count: Zone.allCases.count)
            for (i, tie) in Interconnect.all.enumerated() {
                let f = Double(d.flow[i][t])
                netExport[tie.from.rawValue] += f
                if let to = tie.to { netExport[to.rawValue] -= f }
            }
            for z in Zone.allCases {
                let total = Source.allCases.reduce(0.0) { $0 + Double(d.gen($1, z, t)) }
                let target = Double(d.demand(z, t)) + netExport[z.rawValue]
                // Curtailment floors generation at demand+export ≥ 0; the
                // identity holds within Float rounding either way.
                #expect(abs(total - max(0, target)) < max(1.0, abs(target) * 0.001),
                        "zone \(z.code) t=\(t): gen \(total) vs target \(target)")
            }
        }
    }

    @Test("shape: winter-peaking Québec, daylight-bounded solar, calendar sane")
    func shape() {
        let d = Self.a
        let n = GridDataset.intervalCount
        // Mean QC demand in January > mean QC demand in July.
        var jan = 0.0, jul = 0.0, janN = 0, julN = 0
        for t in 0..<n {
            if d.monthOfInterval[t] == 0 { jan += Double(d.demand(.qc, t)); janN += 1 }
            if d.monthOfInterval[t] == 6 { jul += Double(d.demand(.qc, t)); julN += 1 }
        }
        #expect(jan / Double(janN) > jul / Double(julN) * 1.2)
        // No solar at 2am anywhere, ever.
        for t in 0..<n where d.hourOfInterval[t] == 2 {
            for z in Zone.allCases { #expect(d.gen(.solar, z, t) == 0) }
        }
        // Calendar: month array is monotone non-decreasing, hours cycle 0–23.
        #expect(d.monthOfInterval.first == 0 && d.monthOfInterval.last == 11)
        #expect(Set(d.hourOfInterval) == Set(0...23))
    }
}

"""##,
                "Tests/GridCoreTests/PRNGTests.swift": ##"""
import Testing
@testable import GridCore

@Suite("SplitMix64")
struct PRNGTests {
    @Test("same seed produces the same stream; different seeds diverge")
    func determinism() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42), c = SplitMix64(seed: 43)
        let streamA = (0..<64).map { _ in a.next() }
        let streamB = (0..<64).map { _ in b.next() }
        let streamC = (0..<64).map { _ in c.next() }
        #expect(streamA == streamB)
        #expect(streamA != streamC)
    }

    @Test("unit() stays in [0,1) and range() respects bounds")
    func bounds() {
        var r = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let u = r.unit()
            #expect(u >= 0 && u < 1)
            let v = r.range(-3, 5)
            #expect(v >= -3 && v < 5)
        }
    }

    @Test("universe shape: 13 zones, 7 sources, 14 interconnects")
    func universe() {
        #expect(Zone.allCases.count == 13)
        #expect(Source.allCases.count == 7)
        #expect(Interconnect.all.count == 14)
        // Every non-US tie references two distinct zones.
        for tie in Interconnect.all where tie.to != nil {
            #expect(tie.from != tie.to)
        }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{NAME}}</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; overscroll-behavior: none; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "HelloWorld",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    // SwiflowDOM itself only links Swiflow + JavaScriptKit and doesn't
    // need macOS 14; SwiftPM just propagates the package-level platform
    // floor to every consumer, regardless of which product they import.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        {{SWIFLOW_DEP}},
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A Swiflow project — Swift-to-WebAssembly with a Vite-inspired dev loop.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Phase 2b doesn't ship a dev server yet (Phase 2c will). Any static HTTP
server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A heading: **Hello, Swiflow!**
- A paragraph: **Count: 0**
- A button: **Increment** that increments the count on each click.

"""##,
                "Sources/App/AboutPopover+Styles.swift": ##"""
// Sources/App/AboutPopover+Styles.swift
import Swiflow

extension AboutPopover {
    // The component root carries .info-card itself, so the rule compounds
    // with the scope class via `&.info-card`.
    @MainActor static var scopedStyles: CSSSheet? = #css("""
        &.info-card {
          position-anchor: --info-anchor;
          position-area: bottom span-right;
          /* Popover top-layer reset. */
          margin: 0.5rem 0 0 0;
          padding: 0.75rem 1rem;
          background: color-mix(in oklab, Canvas 92%, CanvasText);
          color: CanvasText;
          border: 1px solid color-mix(in oklab, CanvasText 12%, transparent);
          border-radius: 12px;
          box-shadow: 0 12px 32px -12px rgb(0 0 0 / .35);
          max-width: 280px;
          font-size: 0.9375rem;
        }
        h3 {
          margin: 0 0 0.25rem 0;
          font-size: 0.95rem;
          font-weight: 600;
        }
        .body {
          margin: 0 0 0.5rem 0;
          color: color-mix(in oklab, CanvasText 80%, Canvas);
        }
        a {
          color: color-mix(in oklab, CanvasText 70%, blue);
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
        """)
}

"""##,
                "Sources/App/AboutPopover.swift": ##"""
// Sources/App/AboutPopover.swift
import Swiflow

/// AboutPopover — declarative popover using the Popover API.
///
/// The trigger lives in Counter and uses `popovertarget="about-popover"`
/// — no Swift event handler needed. CSS Anchor Positioning floats this
/// card next to the trigger (which sets `anchor-name: --info-anchor`).
@Component
final class AboutPopover {
    var body: VNode {
        div(.id("about-popover"),
            .attr("popover", "auto"),
            .class("info-card")) {
            h3("About Swiflow")
            p("Swift, compiled to WASM, with a reactive component model.",
              .class("body"))
            link("View on GitHub",
                 .href("https://github.com/zzal/swiflow"),
                 .newTab())
        }
    }
}

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowDOM
import SwiflowUI
import JavaScriptKit

/// Counter — the {{NAME}} showcase root, now dogfooding SwiflowUI.
///
/// The card's chrome and the modern-CSS surfaces are still hand-authored (that's
/// what {{NAME}} showcases), but every reusable control is a SwiflowUI component:
/// - `Button` for the actions (token-skinned).
/// - `TextField` / `Checkbox` for the greeting + Celebrate inputs.
/// - `ToastStack` (an app-owned `[ToastItem]` queue) replaces the hand-rolled toast.
/// - `SignIn` (in the native `<dialog>`) is built from `TextField`/`Button`.
///
/// Still hand-rolled (no SwiflowUI equivalent in 1.0): the native `<dialog>` chrome,
/// the `ⓘ` Popover-API trigger + `AboutPopover`, the `<details>` inspector.
///
/// The `ToastStack` is a sibling of `.card`, not a child: `.card` is a
/// `container-type` query container, which establishes a containing block — a
/// `position: fixed` toast nested inside would anchor to the card, not the viewport.
@Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showSignIn: Bool = false
    @ReducerState var toasts: ToastQueue
    let signInDialog = Ref<JSObject>()

    var body: VNode {
        div {
            div(.class("card")) {
                header(.class("header")) {
                    h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")",
                       .class("greeting-heading"))
                    button("ⓘ",
                           .class("info-trigger"),
                           .attr("popovertarget", "about-popover"),
                           .attr("aria-label", "About Swiflow"))
                }

                p("Count: \(count)",
                  .class("count"),
                  .attr("aria-live", "polite"))

                div(.class("actions")) {
                    Button("Increment") { self.count += 1 }
                    Button("Show toast", variant: .secondary) {
                        self.$toasts.send(.show(ToastItem("Saved!", variant: .success)))
                    }
                    Button("Sign in…", variant: .secondary) { self.openSignIn() }
                }

                TextField("Greeting", text: $greeting)
                Checkbox("Celebrate", isOn: $celebrate)

                details(.class("inspector")) {
                    summary("What's running here?")
                    ul(.class("inspector-list")) {
                        li("Sign in… — opens a native <dialog> with a CSS open/close animation, built from SwiflowUI TextField + Button.")
                        li("ⓘ — opens an `auto` popover anchored via CSS Anchor Positioning.")
                        li("Show toast — pushes a SwiflowUI ToastStack notification (auto-dismiss, pause on hover/focus).")
                    }
                }

                embed { AboutPopover() }

                // Dismissal: Escape (native <dialog>), or Cancel / Sign out / Close
                // inside SignIn. Backdrop-click-to-close is omitted (EventInfo doesn't
                // expose event.target identity).
                dialog(.ref(signInDialog), .class("signin-dialog")) {
                    if showSignIn {
                        embed { SignIn(onClose: { self.closeSignIn() }) }
                    }
                }
            }

            // Sibling of .card (see the type doc): the fixed ToastStack anchors to the
            // viewport, not the query-container card.
            ToastStack(queue: $toasts)
        }
    }

    // Open/close are synchronous and tied to the click gesture — the dialog appears
    // the same frame, and the fade/slide is CSS (Counter+Styles.swift). showModal()
    // must run before the @State change schedules its render so [open] transitions in.
    func openSignIn() {
        showSignIn = true
        if let el = signInDialog.wrappedValue { _ = el.showModal?() }
    }

    func closeSignIn() {
        if let el = signInDialog.wrappedValue { _ = el.close?() }
        showSignIn = false
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}

"""##,
                "Sources/App/Counter+Styles.swift": ##"""
// Sources/App/Counter+Styles.swift
import Swiflow

extension Counter {
    @MainActor static var scopedStyles: CSSSheet? = tokens + layout + theme + animations + responsive

    // ---- tokens ----
    // @property and :root escape scoping automatically (hoisted/unscoped).
    static let tokens = #css("""
        @property --accent {
          syntax: "<color>";
          inherits: true;
          initial-value: oklch(.65 .14 250);
        }
        :root {
          --accent: light-dark(oklch(.55 .18 250), oklch(.75 .14 250));
          --surface: light-dark(oklch(.99 0 0), oklch(.18 .005 250));
          --surface-elev: light-dark(oklch(.97 0 0), oklch(.22 .005 250));
          --text: CanvasText;
          --text-dim: color-mix(in oklab, CanvasText 65%, Canvas);
          --border: color-mix(in oklab, CanvasText 12%, transparent);
        }
        """)

    // ---- layout ----
    // The component root is now a plain wrapper (:host) holding the visible `.card`
    // plus a sibling ToastStack. `container-type` + the card chrome live on `.card`:
    // a query container establishes a containing block, so keeping it OFF the wrapper
    // lets the fixed-position toast anchor to the viewport rather than the card.
    static let layout = #css("""
        :host {
          display: block;
        }
        .card {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          max-width: 520px;
          margin: 2.5rem auto;
          padding: 1.75rem;
          border-radius: 16px;
          background: var(--surface);
          border: 1px solid var(--border);
          box-shadow: 0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25);
          container-type: inline-size;
        }
        .header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          margin: 0;
          padding: 0;
          border: 0;
        }
        .greeting-heading {
          margin: 0;
          font-size: 1.4rem;
          font-weight: 600;
        }
        .info-trigger {
          anchor-name: --info-anchor;
          display: grid;
          place-items: center;
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 50%;
          border: 1px solid var(--border);
          background: transparent;
          color: var(--text-dim);
          cursor: pointer;
          font-size: 0.9rem;
        }
        .actions {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .inspector {
          border: 1px solid var(--border);
          border-radius: 10px;
          padding: 0.5rem 0.75rem;
          interpolate-size: allow-keywords;
        }
        .inspector summary {
          cursor: pointer;
          list-style: none;
          font-size: 0.95rem;
          color: var(--text-dim);
        }
        .inspector summary::-webkit-details-marker {
          display: none;
        }
        .inspector summary::before {
          content: "▸ ";
          display: inline-block;
          transition: transform .15s ease;
        }
        .inspector[open] summary::before {
          transform: rotate(90deg);
        }
        .inspector-list {
          margin: 0.5rem 0 0 0;
          padding: 0 0 0 1.25rem;
          color: var(--text-dim);
          font-size: 0.9rem;
        }
        """)

    // ---- theme ----
    // Buttons/inputs/checkbox are now SwiflowUI components (their own token sheets) —
    // the old bare `button`/`input`/`.secondary` rules are gone so they don't override
    // the `.sw-*` styling. Only the card-specific surfaces remain here.
    static let theme = #css("""
        .count {
          margin: 0;
          font-size: 1.6rem;
          font-weight: 600;
          color: var(--accent);
          transition: --accent .25s ease;
        }

        /* <dialog> + ::backdrop styling, animated entirely in CSS — no JS, no
           View Transition. A modal <dialog> moves through the top layer, so we
           transition `overlay` and `display` with `allow-discrete` to keep the
           element painted through its exit animation; `@starting-style` (below)
           supplies the values it animates *from* on open. */
        .signin-dialog {
          border: 0;
          border-radius: 16px;
          padding: 0;
          background: var(--surface-elev);
          color: var(--text);
          box-shadow: 0 24px 48px -16px rgb(0 0 0 / .45);
          max-width: min(90vw, 420px);
          opacity: 0;
          transform: translateY(8px) scale(.98);
          transition: opacity .2s ease, transform .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete;
        }
        .signin-dialog[open] {
          opacity: 1;
          transform: translateY(0) scale(1);
        }
        .signin-dialog::backdrop {
          background: color-mix(in oklab, Canvas 30%, transparent);
          backdrop-filter: blur(6px);
          opacity: 0;
          transition: opacity .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete;
        }
        .signin-dialog[open]::backdrop {
          opacity: 1;
        }
        /* Entry animation origin: without these, the dialog would pop in at full
           opacity instead of fading/sliding from the closed state. */
        @starting-style {
          .signin-dialog[open] {
            opacity: 0;
            transform: translateY(8px) scale(.98);
          }
          .signin-dialog[open]::backdrop {
            opacity: 0;
          }
        }
        """)

    // ---- animations ----
    static let animations = #css("""
        @keyframes counter-in {
          from { opacity: 0; transform: translateY(-6px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .card {
          animation: counter-in 0.3s ease forwards;
        }
        """)

    // ---- responsive ----
    // @container nests inside the scope wrapper; the container is `.card`, so this
    // queries the card's inline-size and stacks the actions on narrow widths.
    static let responsive = #css("""
        @container (max-width: 380px) {
          .actions {
            flex-direction: column;
            align-items: stretch;
          }
        }
        """)
}

"""##,
                "Sources/App/SignIn.swift": ##"""
// Sources/App/SignIn.swift
import Swiflow
import SwiflowUI

/// SignIn — a form-validation demo, hosted inside Counter's <dialog>. Dogfoods
/// SwiflowUI: `TextField(field:)` for the labelled, validated fields (label + input
/// + role=alert error + aria-invalid, with blur→markTouched wired) and `Button` for
/// the actions, laid out with `VStack`/`HStack`. No hand-rolled field/button chrome
/// or per-component CSS — it all comes from SwiflowUI's token-driven sheets.
@Component
final class SignIn {
    @State var email: String    = ""
    @State var password: String = ""
    @State var ctrl: FormController = FormController()
    @State var submitted: Bool  = false
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: VNode {
        let em = Field("email",    $email,    $ctrl, .required(), .email)
        let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let form = Form($ctrl) { em; pw }

        return VStack(spacing: .md, align: .stretch) {
            if submitted {
                p("Signed in as \(email)!")
                HStack(spacing: .sm) {
                    Button("Sign out", variant: .secondary) {
                        self.submitted = false
                        self.email = ""
                        self.password = ""
                        self.ctrl = FormController()
                    }
                    Button("Close") { self.onClose() }
                }
            } else {
                h2("Sign In")
                TextField("Email", field: em, type: .email)
                TextField("Password", field: pw, type: .password)
                HStack(spacing: .sm) {
                    Button("Sign In", disabled: !form.isValid) {
                        form.touchAll()
                        guard form.isValid else { return }
                        self.submitted = true
                    }
                    Button("Reset", variant: .secondary) { form.reset() }
                    Button("Cancel", variant: .secondary) { self.onClose() }
                }
            }
        }
        .padding(.lg)   // the dialog has padding:0; the content pads itself
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{NAME}}</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "MissionControl",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        {{SWIFLOW_DEP}},
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
                .product(name: "SwiflowRouter", package: "Swiflow"),
                .product(name: "SwiflowQuery", package: "Swiflow"),
                .product(name: "SwiflowFetcher", package: "Swiflow"),
                .product(name: "SwiflowStore", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# Mission Control

Watching the planet live from Swift in the browser — the flagship *networked*
sampler. Two routed tabs over free, keyless, CORS-open APIs:

- **Weather** (`/`) — pinned city cards on [Open-Meteo](https://open-meteo.com)
  (forecast + geocoding), with debounced search-to-pin and a °C/°F toggle.
- **Quakes** (`/quakes`) — the live
  [USGS earthquake feed](https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php),
  filtered by magnitude and time window, polling every 30 s.

Unlike `AsyncFetch` and `QueryDemo` (which simulate latency with `Task.sleep`),
everything here hits real servers.

## Run it

```sh
cd examples/{{NAME}}
swiflow dev        # builds WASM, serves, hot-reloads on save
```

## What's demonstrated where

| Feature | Where |
|---|---|
| `.task(rerunOn:)` | `WeatherPage` — 300 ms search debounce keyed on the input text; superseded keystrokes cancel the sleep and the runtime drops their writes |
| bare `.task { }` | `QuakesPage` — mount-scoped ticker keeping "n min ago" honest |
| `VStack`/`HStack` + tokens | all layout; spacing/alignment from the `--sw-*` scale |
| `HTTPClient` (SwiflowFetcher) | `API.swift` — three real clients; `Decodable` models with explicit snake_case `CodingKeys` (`JSValueDecoder` has no key strategy) |
| Keyed queries + cache | per-(city, unit) and per-(magnitude, window) keys — flip a filter back, or unpin → re-pin, and it paints instantly from cache |
| `refetchInterval` | quake feed polls every 30 s; weather refreshes every 5 min |
| `staleTime` / `refetchOnFocus` | weather is fresh for 60 s; both feeds revalidate on window focus |
| `isFetching` vs `isLoading` | the "⟳" pulses during background polls while rendered data stays put (stale-while-revalidate) |
| `SwiflowRouter` | `RouterRoot` + two `Route`s + `Link` tabs |
| Two-way bindings | `.value($searchText)`, `.selection(...)` on every select |
| `scopedStyles` | every component; theme on SwiflowUI's `--sw-*` token contract |

**Not here:** `Mutation` / optimistic edits — neither API accepts writes.
`examples/QueryDemo` remains the mutation demo.

## Things to try

1. Type "par" in the search box, slowly, then quickly — watch the network
   panel: one geocoding request per *settled* prefix, never per keystroke.
2. Pin Paris, unpin it, re-pin it within a minute — no request the second time.
3. Toggle °C → °F (refetch) → °C (instant, cached).
4. Switch tabs back and forth — instant both ways; no spinners after first load.
5. Leave the Quakes tab open — rows appear/reorder as the planet rumbles,
   the "⟳" spinning on each 30 s poll.
6. DevTools → Network → Offline: cards and feed show error states; restore
   and refocus the window to watch `refetchOnFocus` recover everything.

"""##,
                "Sources/App/API.swift": ##"""
// Sources/App/API.swift
//
// HTTP clients + Decodable models for the two live APIs.
//
// Both APIs are free, keyless, and CORS-open:
//   - Open-Meteo  (forecast + geocoding) — https://open-meteo.com
//   - USGS earthquake feed               — https://earthquake.usgs.gov
//
// Decoding note: responses decode with JavaScriptKit's `JSValueDecoder`
// (see SwiflowFetcher), which has no key-decoding strategy — so every model
// spells out snake_case keys in explicit `CodingKeys`.
import SwiflowFetcher

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

// MARK: - Clients

enum API {
    /// Open-Meteo runs geocoding and forecasts on separate hosts.
    static let geocoding = HTTPClient(baseURL: "https://geocoding-api.open-meteo.com")
    static let forecast = HTTPClient(baseURL: "https://api.open-meteo.com")
    static let usgs = HTTPClient(baseURL: "https://earthquake.usgs.gov")
    /// Open-Meteo's geocoder is forward-only (name → coords); BigDataCloud's
    /// `reverse-geocode-client` is the keyless, CORS-open reverse of that, used
    /// to label the browser-geolocated "current location" pin with a real place.
    static let reverseGeocoding = HTTPClient(baseURL: "https://api.bigdatacloud.net")
}

/// Wall-clock epoch milliseconds via JS `Date.now()` — Foundation's `Date`
/// isn't available under WASM. (Returns 0 on the host, which only typechecks
/// this target and never renders.)
@MainActor
func epochNowMs() -> Double {
    #if canImport(JavaScriptKit)
    return JSObject.global.Date.object?.now?().number ?? 0
    #else
    return 0
    #endif
}

// MARK: - Open-Meteo geocoding
// GET /v1/search?name={q}&count=5
// {"results":[{"id":6077243,"name":"Montreal","latitude":45.50884,
//   "longitude":-73.58781,"country":"Canada","admin1":"Quebec",...}], ...}
// `results` is absent entirely when nothing matches.

struct GeoSearchResponse: Decodable, Equatable, Sendable {
    let results: [City]?
}

// `Codable` (not just `Decodable`): the pinned list is persisted to IndexedDB
// via `SwiflowStore`, which encodes it back out.
struct City: Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    /// "Montreal, Quebec, Canada" — admin1/country are optional in the feed.
    var fullName: String {
        [name, admin1, country].compactMap(\.self).joined(separator: ", ")
    }

    /// Sentinel id for the geolocated "current location" pin, so it can be
    /// recognised, replaced with a fresh fix, and kept first in the list.
    static let currentLocationID = -1
    var isCurrentLocation: Bool { id == City.currentLocationID }
}

// MARK: - BigDataCloud reverse geocoding
// GET /data/reverse-geocode-client?latitude=…&longitude=…&localityLanguage=en
// {"city":"Montreal","locality":"Ville-Marie","principalSubdivision":"Quebec",
//  "countryName":"Canada", …} — fields can be empty strings when unknown.

struct ReverseGeocodeResponse: Decodable, Equatable, Sendable {
    let city: String?
    let locality: String?
    let principalSubdivision: String?
    let countryName: String?
}

/// Resolve a coordinate to a labelled `City` (sentinel `currentLocationID`) for
/// the geolocated pin. Falls back to "Current location" when the reverse
/// geocoder returns no usable place name.
func reverseGeocodedCity(latitude: Double, longitude: Double) async throws -> City {
    let place: ReverseGeocodeResponse = try await API.reverseGeocoding.get(
        "/data/reverse-geocode-client",
        query: ["latitude": .double(latitude), "longitude": .double(longitude), "localityLanguage": "en"]
    )
    let name = [place.city, place.locality]
        .compactMap(\.self)
        .first(where: { !$0.isEmpty }) ?? "Current location"
    return City(id: City.currentLocationID, name: name,
                latitude: latitude, longitude: longitude,
                country: place.countryName, admin1: place.principalSubdivision)
}

// MARK: - Open-Meteo forecast
// GET /v1/forecast?latitude=…&longitude=…
//     &current=temperature_2m,weather_code,wind_speed_10m
//     &daily=temperature_2m_max,temperature_2m_min
//     &timezone=auto&temperature_unit={celsius|fahrenheit}

struct Forecast: Decodable, Equatable, Sendable {
    let current: Current
    let currentUnits: CurrentUnits
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
        case daily
    }

    struct Current: Decodable, Equatable, Sendable {
        let temperature: Double
        let weatherCode: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct CurrentUnits: Decodable, Equatable, Sendable {
        let temperature: String   // "°C" / "°F"

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
        }
    }

    struct Daily: Decodable, Equatable, Sendable {
        let highs: [Double]
        let lows: [Double]

        enum CodingKeys: String, CodingKey {
            case highs = "temperature_2m_max"
            case lows = "temperature_2m_min"
        }
    }
}

/// WMO weather interpretation codes (the `weather_code` field) → display.
/// Table per Open-Meteo's documentation.
func wmoDescription(_ code: Int) -> (emoji: String, label: String) {
    switch code {
    case 0:          ("☀️", "Clear sky")
    case 1:          ("🌤️", "Mainly clear")
    case 2:          ("⛅️", "Partly cloudy")
    case 3:          ("☁️", "Overcast")
    case 45, 48:     ("🌫️", "Fog")
    case 51, 53, 55: ("🌦️", "Drizzle")
    case 56, 57:     ("🌧️", "Freezing drizzle")
    case 61, 63, 65: ("🌧️", "Rain")
    case 66, 67:     ("🌧️", "Freezing rain")
    case 71, 73, 75: ("🌨️", "Snow")
    case 77:         ("🌨️", "Snow grains")
    case 80, 81, 82: ("🌦️", "Rain showers")
    case 85, 86:     ("🌨️", "Snow showers")
    case 95:         ("⛈️", "Thunderstorm")
    case 96, 99:     ("⛈️", "Thunderstorm with hail")
    default:         ("❓", "Unknown")
    }
}

// MARK: - USGS earthquake feed
// GET /earthquakes/feed/v1.0/summary/{magnitude}_{window}.geojson
// GeoJSON FeatureCollection; `properties.time` is epoch ms (exceeds Int32 —
// wasm32's Int — so it stays a Double), `mag`/`place` can be null.

struct QuakeFeed: Decodable, Equatable, Sendable {
    let metadata: Metadata
    let features: [Quake]

    struct Metadata: Decodable, Equatable, Sendable {
        let title: String
        let count: Int
    }
}

struct Quake: Decodable, Equatable, Sendable {
    let id: String
    let properties: Properties

    struct Properties: Decodable, Equatable, Sendable {
        let mag: Double?
        let place: String?
        let time: Double   // epoch milliseconds
        let url: String
    }
}

"""##,
                "Sources/App/App+Styles.swift": ##"""
// Sources/App/App+Styles.swift
//
// App-wide styles, owned by the root `Shell` component. `scopedStyles` is a
// `@Component` hook — the runtime injects it (scoped to `.swiflow-Shell`) when
// the type first mounts, so rules here reach every routed page as descendant
// selectors. (A plain struct like the `@main` entry can't host scopedStyles:
// nothing ever mounts it, so the sheet would silently never be installed.)
import Swiflow

extension Shell {
    @MainActor static var scopedStyles: CSSSheet? = #css("""
        .page-title {
            font-weight: 100;
            font-size: 3rem;
        }
    """)
}

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
//
// Mission Control — watching the planet live from Swift in the browser.
// Two routed tabs over free, keyless, CORS-open APIs:
//   /        Weather  — Open-Meteo forecast + geocoding
//   /quakes  Quakes   — USGS earthquake feed
import Swiflow
import SwiflowDOM
import SwiflowRouter

/// Root shell around the router. A `@Component` (unlike the `@main` entry
/// struct) so it can own app-wide `scopedStyles` — every routed page renders
/// inside it, so its descendant rules (see `App+Styles.swift`) reach them.
@Component
final class Shell {
    var body: VNode {
        embed {
            RouterRoot {
                Route("/") { WeatherPage() }
                Route("/quakes") { QuakesPage() }
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Shell() }
    }
}

"""##,
                "Sources/App/NavBar.swift": ##"""
// Sources/App/NavBar.swift
import Swiflow
import SwiflowDOM
import SwiflowRouter
import SwiflowUI

/// Tab bar shared by both pages. `Link` renders a fixed-shape `<a>`, so the
/// styling targets `nav a` from the scoped sheet rather than per-link classes;
/// the current page is styled via the `aria-current="page"` marker Link emits.
final class NavBar: Component {
    @MainActor static var scopedStyles: CSSSheet? = css {
        // `host(...)` — the <nav> is the component root, and scoped `rule(...)`
        // selectors only reach descendants.
        host(.display("flex"),
             .alignItems("center"),
             .gap("var(--sw-space-sm)"),
             .padding("var(--sw-space-sm) var(--sw-space-md)"),
             .borderBottom("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)"))
        rule("a",
             .color("var(--sw-text)"),
             .textDecoration("none"),
             .padding("var(--sw-space-xs) var(--sw-space-md)"),
             .borderRadius("var(--sw-radius)"))
        rule("a:hover",
             .background("color-mix(in srgb, var(--sw-accent) 15%, transparent)"))
        // "You are here": Link marks the current page's <a> with
        // aria-current="page" — a free, class-less styling hook.
        rule("a[aria-current=\"page\"]",
             .background("color-mix(in srgb, var(--sw-accent) 20%, transparent)"),
             .fontWeight("600"))
        rule(".brand",
             .fontWeight("700"),
             .marginRight("var(--sw-space-md)"))
    }

    var body: VNode {
        nav {
            span(.class("brand")) { text("📡 Mission Control") }
            embed { Link("/", "Weather") }
            embed { Link("/quakes", "Quakes") }
        }
    }
}

"""##,
                "Sources/App/Quakes/QuakeQueries.swift": ##"""
// Sources/App/Quakes/QuakeQueries.swift
import SwiflowQuery

/// USGS publishes one feed per (magnitude floor × time window) pair, so the
/// two filter selects map 1:1 onto feed URLs — and each combination is
/// naturally its own cache entry.
@Query(prefix: "quakes") struct QuakeFeedQuery {
    @Key let magnitude: String   // "all" | "1.0" | "2.5" | "4.5" | "significant"
    @Key let window: String      // "hour" | "day" | "week"

    var tags: Set<QueryTag> { ["quakes"] }

    /// Poll every 30 s — earthquakes don't wait for a refresh button.
    var refetchInterval: Duration? { .seconds(30) }
    /// Anything younger than the polling cadence is fresh; switching filters
    /// back within 30 s renders instantly from cache without a refetch.
    var staleTime: Duration { .seconds(30) }

    func fetch() async throws -> QuakeFeed {
        try await API.usgs.get("/earthquakes/feed/v1.0/summary/\(magnitude)_\(window).geojson")
    }
}

"""##,
                "Sources/App/Quakes/QuakeRow.swift": ##"""
// Sources/App/Quakes/QuakeRow.swift
import Swiflow
import SwiflowDOM
import SwiflowUI

/// One feed row. A plain VNode factory (not a component) so the list can key
/// rows directly with `.key(quake.id)`.
@MainActor
func quakeRow(_ quake: Quake, nowMs: Double) -> VNode {
    let mag = quake.properties.mag
    return li(.key(quake.id), .class("quake-row")) {
        // SwiflowUI Badge for the magnitude pill; `justify-self` keeps it left in
        // the row's grid column (Badge brings its own pill styling + token colors).
        Badge(mag.map { "M \(($0 * 10).rounded() / 10)" } ?? "M ?",
              variant: magnitudeBadge(mag),
              .style("justify-self", "start"))
        span(.class("place")) { text(quake.properties.place ?? "Unknown location") }
        span(.class("when")) { text(relativeTime(fromMs: quake.properties.time, nowMs: nowMs)) }
    }
}

/// Severity bucket → Badge variant: calm below M3, watchful to M5, alarming above.
/// The default theme has no amber/warning token, so "watchful" maps to `.accent`.
func magnitudeBadge(_ mag: Double?) -> BadgeVariant {
    switch mag ?? 0 {
    case ..<3:   .success
    case ..<5:   .accent
    default:     .danger
    }
}

/// "just now" / "12 min ago" / "3 h ago" / "2 d ago". Clamps negative deltas
/// (clock skew between USGS and the client) to "just now".
func relativeTime(fromMs: Double, nowMs: Double) -> String {
    let minutes = Int(max(0, nowMs - fromMs) / 60_000)
    switch minutes {
    case 0:        return "just now"
    case ..<60:    return "\(minutes) min ago"
    case ..<1440:  return "\(minutes / 60) h ago"
    default:       return "\(minutes / 1440) d ago"
    }
}

"""##,
                "Sources/App/Quakes/QuakesPage+Styles.swift": ##"""
// Sources/App/Quakes/QuakesPage+Styles.swift
//
// Written with #css — real CSS, structurally validated at compile time,
// scoped to the component via native CSS nesting. The other example pages
// use the css { rule(...) } builder DSL; both are first-class.
import Swiflow

extension QuakesPage {
    @MainActor static var scopedStyles: CSSSheet? = #css("""
        :host {
          display: block;
          max-width: 860px;
          margin: 0 auto;
          padding: 0 var(--sw-space-lg) var(--sw-space-xl);
        }

        h1 {
          font-size: 1.4rem;
          margin: 0;
        }

        .feed-meta {
          margin: 0;
          color: color-mix(in srgb, var(--sw-text) 60%, transparent);
          font-size: 0.85rem;
        }

        .quake-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
        }

        .quake-row {
          display: grid;
          grid-template-columns: 5.5rem 1fr max-content;
          align-items: center;
          gap: var(--sw-space-md);
          padding: var(--sw-space-sm) var(--sw-space-xs);
          border-bottom: 1px solid color-mix(in srgb, var(--sw-text) 10%, transparent);
        }

        .when {
          color: color-mix(in srgb, var(--sw-text) 60%, transparent);
          font-size: 0.85rem;
          font-variant-numeric: tabular-nums;
        }

        .error {
          color: light-dark(#b91c1c, #fca5a5);
        }
        """)
}

"""##,
                "Sources/App/Quakes/QuakesPage.swift": ##"""
// Sources/App/Quakes/QuakesPage.swift
//
// Live USGS earthquake feed. Demonstrates:
// - a polling query (`refetchInterval` 30 s) whose data changes while you watch,
// - `isFetching` vs `isLoading` — the "⟳" pulses on background polls while the
//   already-rendered list stays put (stale-while-revalidate),
// - filter selects whose values are the query key — every (magnitude, window)
//   pair is its own cache entry, so flipping back is instant,
// - a bare `.task { }` ticker that keeps "n min ago" honest without refetching.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowStore
import SwiflowUI

@Component
final class QuakesPage {
    /// The filter selections outlive this page (the router recreates it on
    /// every navigation) — @Persisted rehydrates them from IndexedDB on
    /// mount and saves on change; the defaults are first-visit values.
    @Persisted var magnitude: String = "2.5"
    @Persisted var window: String = "day"
    /// Wall-clock anchor for relative timestamps, ticked by the bare `.task`.
    @State var nowMs: Double = 0

    var body: VNode {
        let feed = query(QuakeFeedQuery(magnitude: magnitude, window: window))
        return VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("Live seismic feed", .class("page-title"))
                // Background-poll indicator: SwiflowUI Spinner (role=status, token-driven,
                // pauses under reduced-motion). The list stays put (stale-while-revalidate).
                if feed.isFetching {
                    Spinner(size: .sm, label: "Refreshing")
                }
            }

            // SwiflowUI Select marks the bound option `selected`, so the persisted
            // magnitude/window (rehydrated below) renders correctly at mount.
            HStack(spacing: .sm, align: .end, .class("filters")) {
                Select("Magnitude", selection: $magnitude, options: [
                    SelectOption("all", "All"),
                    SelectOption("1.0", "M1.0+"),
                    SelectOption("2.5", "M2.5+"),
                    SelectOption("4.5", "M4.5+"),
                    SelectOption("significant", "Significant"),
                ])
                Select("Window", selection: $window, options: [
                    SelectOption("hour", "Past hour"),
                    SelectOption("day", "Past day"),
                    SelectOption("week", "Past week"),
                ])
            }

            if let data = feed.data {
                p("\(data.metadata.count) events — updates every 30 s",
                  .class("feed-meta"))
                ul(.class("quake-list")) {
                    for quake in data.features {
                        quakeRow(quake, nowMs: nowMs)
                    }
                }
            } else if feed.isLoading {
                p("Listening to the planet…", .class("feed-meta"))
            } else if feed.error != nil {
                p("Couldn't reach the USGS feed — check your connection. Recovers automatically on refocus.",
                  .class("error"))
            }
        }
        // Bare `.task` = mount-scoped effect: tick the relative-time anchor
        // every 30 s. Cancellation on unmount makes Task.sleep throw, and the
        // isCancelled check exits the loop; the runtime would drop any stale
        // write anyway.
        .task {
            while !Task.isCancelled {
                self.nowMs = epochNowMs()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

"""##,
                "Sources/App/Weather/CityCard+Styles.swift": ##"""
// Sources/App/Weather/CityCard+Styles.swift
import Swiflow

extension CityCard {
    // The card surface (bg / shadow / radius / padding) now comes from SwiflowUI's
    // `Card`; only the content typography is styled here.
    @MainActor static var scopedStyles: CSSSheet? = css {
        rule(".city-name",
             .fontSize("1.05rem"),
             .margin("0"))
        rule(".temp",
             .fontSize("2.2rem"),
             .fontWeight("700"),
             .lineHeight("1"))
        rule(".wmo",
             .fontSize("1.6rem"))
        rule(".wmo-label, .range",
             .margin("0"),
             .color("color-mix(in srgb, var(--sw-text) 60%, transparent)"),
             .fontSize("0.85rem"))
        rule(".error",
             .color("light-dark(#b91c1c, #fca5a5)"),
             .margin("0"))
    }
}

"""##,
                "Sources/App/Weather/CityCard.swift": ##"""
// Sources/App/Weather/CityCard.swift
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowUI

/// One pinned city. Holds no `@State` of its own — the weather lives in the
/// query cache under (city id, unit), which is what makes unpin → re-pin
/// inside `staleTime` paint instantly.
///
/// `unit` is a plain `var` so the parent can push a °C↔°F toggle into this
/// live instance via `embed(_:refresh:)` — re-keying on `unit` would remount
/// the card (and churn its query subscription) on every toggle instead.
@Component
final class CityCard {
    let city: City
    var unit: String
    let onUnpin: () -> Void

    init(city: City, unit: String, onUnpin: @escaping () -> Void) {
        self.city = city
        self.unit = unit
        self.onUnpin = onUnpin
    }

    var body: VNode {
        let weather = query(CurrentWeatherQuery(city: city, unit: unit))
        // SwiflowUI Card supplies the surface (token bg/shadow/radius/padding); the
        // card keeps a min-width so it tiles nicely in the wrapping grid.
        return Card(variant: .elevated, .style("min-width", "12.5rem")) {
            VStack(spacing: .sm) {
                HStack(spacing: .sm, align: .center, justify: .between) {
                    h2(city.name, .class("city-name"))
                    Button("✕", variant: .ghost, size: .sm,
                           .attr("aria-label", "Unpin \(city.name)")) { self.onUnpin() }
                }
                if let f = weather.data {
                    let wmo = wmoDescription(f.current.weatherCode)
                    HStack(spacing: .sm, align: .center) {
                        span(.class("temp")) {
                            text("\(Int(f.current.temperature.rounded()))\(f.currentUnits.temperature)")
                        }
                        span(.class("wmo"), .attr("title", wmo.label)) { text(wmo.emoji) }
                        if weather.isFetching {
                            Spinner(size: .sm, label: "Updating")
                        }
                    }
                    p(wmo.label, .class("wmo-label"))
                    if let high = f.daily.highs.first, let low = f.daily.lows.first {
                        p("H \(Int(high.rounded()))° · L \(Int(low.rounded()))° · wind \(Int(f.current.windSpeed.rounded())) km/h",
                          .class("range"))
                    }
                } else if weather.isLoading {
                    Spinner(size: .lg, label: "Loading weather")
                } else if weather.error != nil {
                    p("offline", .class("error"))
                }
            }
        }
    }
}

"""##,
                "Sources/App/Weather/Geolocation.swift": ##"""
// Sources/App/Weather/Geolocation.swift
//
// A one-shot bridge to the browser's `navigator.geolocation`. This is a browser
// API (not persistence), so it stays in the example rather than the framework.
// It mirrors Swiflow's JS-interop discipline: retain the callback `JSClosure`s
// until one fires, and fail soft — a denied permission or missing API resolves
// to `nil` so the caller just keeps its existing pins.

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

enum Geolocation {
    /// Ask the browser for the current position once. Resolves to `nil` if
    /// geolocation is unavailable or the user denies/errors out.
    @MainActor
    static func currentPosition() async -> (latitude: Double, longitude: Double)? {
        #if canImport(JavaScriptKit)
        await withCheckedContinuation { (continuation: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>) in
            guard let geolocation = JSObject.global.navigator.object?.geolocation.object else {
                continuation.resume(returning: nil)
                return
            }

            // Retain the handlers across this synchronous setup via a retainer ↔
            // closures cycle; the first to fire breaks it (see SwiflowStore's
            // PersistentStore for the same pattern).
            let retainer = ClosureRetainer()
            let onSuccess = JSClosure { args in
                retainer.closures = []
                guard let position = args.first,
                      let lat = position.coords.latitude.number,
                      let lon = position.coords.longitude.number else {
                    continuation.resume(returning: nil)
                    return .undefined
                }
                continuation.resume(returning: (lat, lon))
                return .undefined
            }
            let onError = JSClosure { _ in
                retainer.closures = []
                continuation.resume(returning: nil)
                return .undefined
            }
            retainer.closures = [onSuccess, onError]

            _ = geolocation.getCurrentPosition!(JSValue.object(onSuccess), JSValue.object(onError))
        }
        #else
        return nil
        #endif
    }
}

#if canImport(JavaScriptKit)
private final class ClosureRetainer {
    var closures: [JSClosure] = []
}
#endif

"""##,
                "Sources/App/Weather/WeatherPage+Styles.swift": ##"""
// Sources/App/Weather/WeatherPage+Styles.swift
import Swiflow

extension WeatherPage {
    @MainActor static var scopedStyles: CSSSheet? = layout + overrides + theme

    // Example of CSSSheetBuilder
    static let layout = css {
        host(.display("block"),
             .maxWidth("860px"),
             .margin("0 auto"),
             .padding("0 var(--sw-space-lg) var(--sw-space-xl)"))
        rule("h1",
             .fontSize("1.4rem"),
             .margin("0"))
    }

    // Example of CSSMacro:
    static let overrides = #css("""
    .add-a-city-wrapper {
        flex: 1;
         .swiflow-AutocompleteBox {
            flex: 1;
            width: auto;
        }
    }
    """)

    static let theme = css {
        rule(".search-status",
             .color("color-mix(in srgb, var(--sw-text) 60%, transparent)"),
             .margin("0"))
    }
}

"""##,
                "Sources/App/Weather/WeatherPage.swift": ##"""
// Sources/App/Weather/WeatherPage.swift
//
// Pinned-city weather over Open-Meteo. Demonstrates:
// - SwiflowUI's async `Autocomplete(loader:)` as the city search — it owns
//   the debounce, keystroke cancellation, and Searching / error / empty
//   panel states that this page used to hand-roll,
// - a consume-and-clear `Binding`: committing a suggestion pins the city
//   and resets the field instead of holding a selection,
// - per-card weather queries keyed on (city, unit) — toggling °C → °F
//   refetches, toggling back paints instantly from cache,
// - SwiflowUI stacks + tokens for the whole layout.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowStore
import SwiflowUI

@Component
final class WeatherPage {
    @State var pinned: [City] = City.seeds
    @State var unit: String = "celsius"

    /// The cities behind the latest Autocomplete suggestions, keyed by option
    /// value (the stringified geocoding id), so a committed selection resolves
    /// back to the full record. Plain var — nothing renders from it.
    private var searchHits: [String: City] = [:]

    /// Pins and the unit toggle outlive this page: the router destroys
    /// `WeatherPage` on every navigation, so they're persisted to IndexedDB and
    /// rehydrated on mount. `City.seeds` / "celsius" are just first-visit defaults.
    private let store = PersistentStore()
    /// Typed keys: name + value type in one declaration — the load sites
    /// below can't restate a drifted type.
    private static let pinnedKey = StoreKey<[City]>("pinned-cities")
    private static let unitKey = StoreKey<String>("weather-unit")

    var body: VNode {
        VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            h1("Weather", .class("page-title"))

            HStack(spacing: .md, align: .center, justify: .between, .style("width", "100%")) {
                div(.class("add-a-city-wrapper")) {
                    // Strict select-from-list combobox over the geocoder. The binding
                    // never holds a value: a commit pins the city and the empty `get`
                    // hands the field back cleared, ready for the next search.
                    Autocomplete("Add a City",
                        selection: Binding(
                            get: { "" },
                            set: { id in
                                if let city = self.searchHits[id] { self.pin(city) }
                            }),
                        loader: { q in try await self.searchCities(q) },
                        placeholder: "Search a city to pin…",
                        minChars: 2
                    )
                }

                Select("Units", selection: $unit, options: [
                    SelectOption("celsius", "°C"),
                    SelectOption("fahrenheit", "°F"),
                ])
            }

            HStack(spacing: .md, .class("card-grid"), .style("flex-wrap", "wrap")) {
                for city in pinned {
                    // Embedded instances are reused at a (type, key) position —
                    // the factory runs on first mount only. The `unit` toggle is
                    // pushed into the LIVE card via `refresh:` (a stable key), so
                    // °C↔°F changes it in place instead of remounting the card and
                    // churning its query subscription. The card re-renders, its
                    // (city, unit) query key changes, and the cache paints the
                    // toggle-back instantly.
                    div(.key("city-\(city.id)")) {
                        embed("card-\(city.id)") {
                            CityCard(city: city, unit: self.unit,
                                     onUnpin: { self.unpin(city) })
                        } refresh: { card in
                            card.unit = self.unit
                        }
                    }
                }
            }
            if pinned.isEmpty {
                p("Nothing pinned — search above to add a city.", .class("search-status"))
            }
        }
        // Runs once per mount (i.e. on every return to this page): rehydrate the
        // saved pins, then refresh the geolocated first card.
        .task { await self.bootstrap() }
    }

    /// Autocomplete loader: geocode the (already debounced) query and remember
    /// the `City` behind each option so a commit can pin the full record, not
    /// just its id. Place names don't move, so no cache layer is needed here —
    /// Autocomplete's cancellation already collapses rapid keystrokes.
    private func searchCities(_ q: String) async throws -> [SelectOption] {
        let response: GeoSearchResponse =
            try await API.geocoding.get("/v1/search", query: ["name": .string(q), "count": 5])
        let cities = response.results ?? []
        for city in cities { searchHits[String(city.id)] = city }
        return cities.map { SelectOption(String($0.id), $0.fullName) }
    }

    func pin(_ city: City) {
        if !pinned.contains(where: { $0.id == city.id }) {
            pinned.append(city)
        }
        persist()
    }

    func unpin(_ city: City) {
        pinned.removeAll { $0.id == city.id }
        persist()
    }

    /// Persist the unit toggle whenever it changes. `onChange(of:)` seeds
    /// silently on the first call and fires only on a real change, so it never
    /// clobbers the value `bootstrap()` rehydrates.
    func onChange() {
        onChange(of: unit, key: "unit") { newUnit in
            Task { try? await self.store.save(newUnit, for: Self.unitKey) }
        }
    }

    // MARK: - Persistence + geolocation

    /// Restore persisted pins + unit (keeping the defaults only on a first-ever
    /// visit), then ask the browser for the current location and pin it first.
    private func bootstrap() async {
        if let saved = try? await store.load(Self.pinnedKey) {
            pinned = saved
        }
        if let savedUnit = try? await store.load(Self.unitKey) {
            unit = savedUnit
        }
        guard let fix = await Geolocation.currentPosition(),
              let here = try? await reverseGeocodedCity(latitude: fix.latitude, longitude: fix.longitude) else {
            return   // unavailable / denied / lookup failed → keep the list as-is
        }
        // Keep "current location" unique and first; replace any prior fix.
        pinned.removeAll { $0.isCurrentLocation }
        pinned.insert(here, at: 0)
        persist()
    }

    /// Fire-and-forget save — `@State` mutations already repainted; persistence
    /// trails behind without blocking the UI.
    private func persist() {
        Task { try? await store.save(pinned, for: Self.pinnedKey) }
    }
}

"""##,
                "Sources/App/Weather/WeatherQueries.swift": ##"""
// Sources/App/Weather/WeatherQueries.swift
import SwiflowQuery

/// Current conditions + today's range for one pinned city. Keyed on
/// (city id, unit) — `latitude`/`longitude` ride along as captured
/// dependencies, excluded from the key per the `Query` contract.
@Query(prefix: "weather") struct CurrentWeatherQuery {
    @Key let city: City   // contributes .int(city.id) via City: QueryKeyConvertible
    @Key let unit: String   // "celsius" | "fahrenheit"

    var tags: Set<QueryTag> { ["weather"] }

    /// Fresh for a minute: re-renders, re-pins, and tab switches inside that
    /// window paint from cache with zero requests.
    var staleTime: Duration { .seconds(60) }
    /// Background refresh every 5 minutes while a card is on screen.
    var refetchInterval: Duration? { .seconds(300) }

    func fetch() async throws -> Forecast {
        try await API.forecast.get("/v1/forecast", query: [
            "latitude": .double(city.latitude),
            "longitude": .double(city.longitude),
            "current": "temperature_2m,weather_code,wind_speed_10m",
            "daily": "temperature_2m_max,temperature_2m_min",
            "timezone": "auto",
            "temperature_unit": .string(unit),
        ])
    }
}

/// `City` contributes its stable `id` to a query key, so `@Key let city: City`
/// keys a weather query on the city without dragging lat/long into the cache slot.
extension City: QueryKeyConvertible {
    var keyComponents: [QueryKeyComponent] { [.int(id)] }
}

extension City {
    /// Starter pins (real Open-Meteo geocoding records, fetched 2026-06-11)
    /// so the dashboard shows live data before the first search.
    static let seeds: [City] = [
        City(id: 6077243, name: "Montréal", latitude: 45.50884, longitude: -73.58781,
             country: "Canada", admin1: "Quebec"),
        City(id: 1850147, name: "Tokyo", latitude: 35.6895, longitude: 139.69171,
             country: "Japan", admin1: "Tokyo"),
        City(id: 2267057, name: "Lisbon", latitude: 38.72509, longitude: -9.1498,
             country: "Portugal", admin1: "Lisbon District"),
    ]
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Mission Control</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "QueryDemo",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    // SwiflowDOM itself only links Swiflow + JavaScriptKit and doesn't
    // need macOS 14; SwiftPM just propagates the package-level platform
    // floor to every consumer, regardless of which product they import.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        {{SWIFLOW_DEP}},
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
                .product(name: "SwiflowQuery", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A Swiflow example demonstrating `SwiflowQuery` — cached, deduplicated,
stale-while-revalidate data fetching with a `.task`-free `query()` call.

A `Query` is a value that knows how to fetch itself (`fetch()`) and where it
lives in the cache (`queryKey`). The component just *consumes* it:

```swift
let u = query(UserByID(id: userID))
```

No `.task`, no `@State` for the loading flag — `query()` returns a
`QueryState` (`data` / `error` / `isLoading` / `isFetching`) backed by the
per-root `QueryClient` cache.

## Build

```bash
swiflow dev
```

This compiles the example to WASM and serves it. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`. Then open the printed URL.

## What you should see

- A heading: **Query demo**
- For ~400 ms, **Loading…** while `UserByID(id: 1)` fetches; then
  **Loaded: User #1**.
- A button: **Next user** — each click bumps `userID`, which changes the
  query key (`["users", .int(id)]`). The new key triggers a fetch for that
  user. Keys you have visited before are cached, so revisiting shows the
  cached value instantly while a background revalidation runs.
- A small **⟳** spinner appears whenever a fetch is in flight in the
  background (`isFetching`) — including the stale-while-revalidate refetch
  over already-cached data.

## How it works

- **Key-driven fetching.** A fetch happens on mount, on key change, or on
  `invalidate` — *not* on every re-render. The `userID` lives in the key, so
  bumping it is what drives the next fetch.
- **Dedup.** Two components asking for the same key at the same time share one
  in-flight fetch.
- **Stale-while-revalidate.** With the default `staleTime` of `.zero`, every
  trigger revalidates: cached data renders immediately, and a background
  refetch updates it when it lands.
- **Invalidation.** A `QueryClient` (installed automatically per render root)
  can refetch by key prefix (`invalidate(["users"])`), exact key
  (`invalidate(["users", 1], exact: true)`), or tag (`invalidate(tag:
  "users")`).

See [`docs/guides/query.md`](../../docs/guides/query.md) for the full guide.

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import SwiflowDOM
import SwiflowUI
import SwiflowQuery

struct User: Equatable, Sendable { let id: Int; let name: String }

/// Simulated API: a non-identity dependency captured by the key.
struct FakeAPI: Sendable {
    func user(_ id: Int) async -> User {
        try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
        return User(id: id, name: "User #\(id)")
    }

    func renameUser(_ id: Int, name: String) async throws -> User {
        try? await Task.sleep(nanoseconds: 300_000_000)   // simulate latency
        return User(id: id, name: name)
    }
}

@Query(prefix: "users") struct UserByID {
    @Key let id: Int
    var api: FakeAPI = FakeAPI()        // captured dependency; defaulted = test seam
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }
}

@Mutation struct RenameUser {
    // Only the stable dependency lives on the mutation. The VARYING data
    // (which user, and the new name) travels in `Input` at call time — so the
    // @MutationState instance is built once and never rebuilt per render. Baking
    // a changing `let id` into the mutation is the resync trap this demo used to
    // model: it forced a `self.rename = RenameUser(id: userID, …)` inside `body`
    // on every render just to keep the captured id current.
    var api: FakeAPI = FakeAPI()

    struct Input: Sendable {
        let id: Int
        let name: String
    }

    func perform(_ input: Input) async throws -> User {
        try await api.renameUser(input.id, name: input.name)
    }

    // No invalidations override: the default derives the refetch from the
    // UserByID key that optimistic() declares — one source of truth for
    // "what this mutation touches."
    func optimistic(_ input: Input) -> [OptimisticEdit] {
        [.update(UserByID(id: input.id)) { _ in User(id: input.id, name: input.name) }]
    }
}

@Component
final class QueryRoot {
    @State var userID: Int = 1
    @State var newName: String = ""
    // Stable across renders — @Component synthesizes `self.rename = RenameUser()`
    // (api is defaulted), and it is never reassigned. The current userID reaches
    // the mutation through `Input` at the call site, not through the instance.
    @MutationState var rename: RenameUser

    var body: VNode {
        let u = query(UserByID(id: userID))
        return VStack(spacing: .lg, align: .start) {
            h1("Query demo")
            HStack(spacing: .sm, align: .center) {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { Spinner(size: .sm, label: "Fetching") }
            }
            HStack(spacing: .sm, align: .center) {
                Button("Next user") { self.userID += 1 }
                // Imperative refetch: the snapshot carries its client + key,
                // so a click handler can force this exact query stale and
                // refetch it — watch the Spinner flash (FakeAPI's 400ms).
                Button("Refresh") { u.refetch() }
            }

            VStack(spacing: .sm, align: .start) {
                h2("Rename user")
                HStack(spacing: .sm, align: .end) {
                    TextField("New name", text: $newName)
                    Button("Rename", disabled: $rename.isPending) {
                        // Varying data flows in via Input — no per-render resync.
                        self.$rename.mutate(.init(id: self.userID, name: self.newName))
                    }
                }
                if $rename.isPending { p("Renaming…") }
                if $rename.isError { p("Error renaming user.") }
            }
        }
        .padding(.xl)
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { QueryRoot() }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Query demo</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "SwiflowUIDemo",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "App", targets: ["App"])],
    dependencies: [
        {{SWIFLOW_DEP}},
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
                .product(name: "SwiflowRouter", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

Browser proof-of-concept for the SwiflowUI v0 layout primitives.

## What it shows

- `VStack` / `HStack` with token-var spacing (`.md`, `.lg`, `.xl`)
- `.padding(_:)` postfix modifier that maps to `--sw-space-*` CSS custom properties
- Token-based reskin: overriding `--sw-space-md` in one `:root` rule changes every gap at once

## Run

```bash
swiflow dev --port 3003
```

Open <http://localhost:3003> in a browser.

## Reskin experiment

Open `index.html` and uncomment the `:root` override inside `<style>`:

```css
/* :root { --sw-space-md: 2.5rem } */
```

Reload — every `HStack(spacing: .md)` gap widens instantly, with no Swift recompile needed.

"""##,
                "Sources/App/App.swift": ##"""
import Swiflow
import SwiflowDOM

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Shell() } }
}

"""##,
                "Sources/App/Catalog.swift": ##"""
// The explicit story registry — drives the navbar and the landing index.
// No reflection on wasm: adding a story = 1 file + 1 entry here + 1 Route in Shell.
import Swiflow

enum StoryCategory: String, CaseIterable {
    case layout = "Layout"
    case typography = "Typography"
    case controls = "Controls"
    case feedback = "Feedback"
    case overlays = "Overlays"
    case navigation = "Navigation"
    case data = "Data"
    case theming = "Theming"
    case patterns = "Patterns"
}

struct StoryEntry {
    let slug: String
    let title: String
    let category: StoryCategory
}

enum Catalog {
    static func path(_ slug: String) -> String { "/component/\(slug)" }

    /// Sidebar/index order is array order within each category.
    static let stories: [StoryEntry] = [
        StoryEntry(slug: "stacks", title: "Stacks", category: .layout),
        StoryEntry(slug: "grid", title: "Grid", category: .layout),
        StoryEntry(slug: "spacer", title: "Spacer", category: .layout),
        StoryEntry(slug: "container", title: "Container", category: .layout),
        StoryEntry(slug: "accordion", title: "Accordion", category: .layout),
        StoryEntry(slug: "text", title: "Text", category: .typography),
        StoryEntry(slug: "button", title: "Button", category: .controls),
        StoryEntry(slug: "textfield", title: "TextField", category: .controls),
        StoryEntry(slug: "select", title: "Select", category: .controls),
        StoryEntry(slug: "autocomplete", title: "Autocomplete", category: .controls),
        StoryEntry(slug: "checkbox", title: "Checkbox", category: .controls),
        StoryEntry(slug: "radiogroup", title: "RadioGroup", category: .controls),
        StoryEntry(slug: "toggle", title: "Toggle", category: .controls),
        StoryEntry(slug: "toggle-button-group", title: "ToggleButtonGroup", category: .controls),
        StoryEntry(slug: "textarea", title: "TextArea", category: .controls),
        StoryEntry(slug: "numberfield", title: "NumberField", category: .controls),
        StoryEntry(slug: "slider", title: "Slider", category: .controls),
        StoryEntry(slug: "labeledfield", title: "LabeledField", category: .controls),
        StoryEntry(slug: "feedback", title: "Feedback & display", category: .feedback),
        StoryEntry(slug: "skeleton", title: "Skeleton", category: .feedback),
        StoryEntry(slug: "avatar", title: "Avatar", category: .feedback),
        StoryEntry(slug: "icon", title: "Icon", category: .feedback),
        StoryEntry(slug: "callout", title: "Callout", category: .feedback),
        StoryEntry(slug: "tooltip", title: "Tooltip", category: .feedback),
        StoryEntry(slug: "overlays", title: "Overlays", category: .overlays),
        StoryEntry(slug: "modal", title: "Modal", category: .overlays),
        StoryEntry(slug: "popover", title: "Popover", category: .overlays),
        StoryEntry(slug: "textlink", title: "TextLink", category: .navigation),
        StoryEntry(slug: "breadcrumbs", title: "Breadcrumbs", category: .navigation),
        StoryEntry(slug: "tabs", title: "Tabs", category: .navigation),
        StoryEntry(slug: "pagination", title: "Pagination", category: .navigation),
        StoryEntry(slug: "datatable", title: "DataTable", category: .data),
        StoryEntry(slug: "datatable-virtual", title: "DataTable — virtualized", category: .data),
        StoryEntry(slug: "theming", title: "Scoped theming", category: .theming),
        StoryEntry(slug: "reducer-wizard", title: "Reducer wizard", category: .patterns),
    ]

    static func entries(in category: StoryCategory) -> [StoryEntry] {
        stories.filter { $0.category == category }
    }
}

"""##,
                "Sources/App/Shell.swift": ##"""
// Root shell: theme-playground header (Task 10 fills it in — starts with just
// the Dark-mode toggle), left vertical navbar, story outlet. The navbar is a
// fixed-width, full-height, vertically-scrollable left column; the outlet
// scrolls independently and fills the remaining width.
import Swiflow
import SwiflowDOM
import SwiflowUI
import SwiflowRouter
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

@Component
final class Shell {
    @State var isDark: Bool = false
    @State var accentChoice: String = "Default"
    @State var radiusChoice: String = "Default"
    /// The current hash route, mirrored from `location.hash` so the sidebar can
    /// mark the active link. The Shell sits ABOVE `RouterRoot`, so it doesn't
    /// re-render on navigation on its own — a `hashchange` listener drives this.
    @State var currentPath: String = "/"

    private static let accents: [String: String] = [
        "Crimson": "#dc2626", "Violet": "#7c3aed", "Emerald": "#059669",
    ]

    #if canImport(JavaScriptKit)
    private var hashListener: JSClosure? = nil
    #endif

    var body: VNode {
        VStack(spacing: .none, align: .stretch) {
            // --- header -------------------------------------------------
            HStack(align: .center) {
                h1("SwiflowUI Catalog").style("font-size", "1.1rem")
                Spacer()
                Select("Accent", selection: $accentChoice,
                       options: ["Default", "Crimson", "Violet", "Emerald"], size: .sm,
                       layout: .horizontal(labelColumn: .hug))
                Select("Radius", selection: $radiusChoice,
                       options: ["Default", "2px", "8px", "16px"], size: .sm,
                       layout: .horizontal(labelColumn: .hug))
                Toggle("Dark mode", isOn: $isDark)
            }
            .padding(.md)
            .style("border-bottom", "\(Token.borderWidth.css) solid \(Token.border.css)")

            // --- navbar + outlet -----------------------------------------
            HStack(spacing: .none, align: .stretch) {
                sidebar
                storyOutlet
            }
            .style("flex", "1 1 auto")
            .style("min-height", "0")
        }
        .style("height", "100vh")
        .style("background", "var(--sw-bg)")
        .style("color", "var(--sw-text)")
    }

    private var sidebar: VNode {
        nav(.class("catalog-nav"), .attr("aria-label", "Components")) {
            VStack(spacing: .sm, align: .stretch) {
                navLink("/", "Overview")
                for category in StoryCategory.allCases
                where !Catalog.entries(in: category).isEmpty {
                    h2(category.rawValue).style("font-size", "0.75rem")
                        .style("text-transform", "uppercase")
                        .style("opacity", "0.6")
                        .style("margin", "var(--sw-space-md) 0 0")
                    for entry in Catalog.entries(in: category) {
                        navLink(Catalog.path(entry.slug), entry.title)
                    }
                }
            }
            .padding(.md)
        }
        .style("flex", "0 0 220px")
        .style("overflow-y", "auto")
        .style("border-right", "\(Token.borderWidth.css) solid \(Token.border.css)")
    }

    /// A sidebar nav link. A PLAIN hash anchor, deliberately NOT `SwiflowRouter.Link`:
    /// the sidebar sits outside `RouterRoot` (a sibling of the outlet), so a Router
    /// `Link` here would capture the no-op default router — its click handler would
    /// `preventDefault()` the native hash navigation and then no-op, giving dead links.
    /// A plain `#/…` anchor navigates natively; `RouterRoot`'s own `hashchange` listener
    /// picks it up. Active state is marked from `currentPath` (mirrored via the listener).
    private func navLink(_ path: String, _ label: String) -> VNode {
        let active = currentPath == path
        var attrs: [Attribute] = [
            .href("#" + path),
            .style("display", "block"),
            .style("padding", "var(--sw-space-xs) var(--sw-space-sm)"),
            .style("border-radius", "var(--sw-radius-sm)"),
            .style("text-decoration", "none"),
            .style("font-size", "0.875rem"),
            .style("color", active ? "var(--sw-accent-strong)" : "var(--sw-text)"),
            .style("background", active
                ? "color-mix(in oklab, var(--sw-accent) 12%, transparent)" : "transparent"),
            .style("font-weight", active ? "600" : "400"),
        ]
        if active { attrs.append(.attr("aria-current", "page")) }
        return element("a", attributes: attrs, children: [text(label)])
    }

    private var outlet: VNode {
        embed {
            RouterRoot {
                Route("/") { IndexStory() }
                Route("/component/stacks") { StacksStory() }
                Route("/component/grid") { GridStory() }
                Route("/component/spacer") { SpacerStory() }
                Route("/component/container") { ContainerStory() }
                Route("/component/accordion") { AccordionStory() }
                Route("/component/text") { TextStory() }
                Route("/component/button") { ButtonStory() }
                Route("/component/textfield") { TextFieldStory() }
                Route("/component/select") { SelectStory() }
                Route("/component/autocomplete") { AutocompleteStory() }
                Route("/component/checkbox") { CheckboxStory() }
                Route("/component/radiogroup") { RadioGroupStory() }
                Route("/component/toggle") { ToggleStory() }
                Route("/component/toggle-button-group") { ToggleButtonGroupStory() }
                Route("/component/textarea") { TextAreaStory() }
                Route("/component/numberfield") { NumberFieldStory() }
                Route("/component/slider") { SliderStory() }
                Route("/component/labeledfield") { LabeledFieldStory() }
                Route("/component/feedback") { FeedbackStory() }
                Route("/component/skeleton") { SkeletonStory() }
                Route("/component/avatar") { AvatarStory() }
                Route("/component/icon") { IconStory() }
                Route("/component/callout") { CalloutStory() }
                Route("/component/tooltip") { TooltipStory() }
                Route("/component/overlays") { OverlaysStory() }
                Route("/component/modal") { ModalStory() }
                Route("/component/popover") { PopoverStory() }
                Route("/component/textlink") { TextLinkStory() }
                Route("/component/breadcrumbs") { BreadcrumbsStory() }
                Route("/component/tabs") { TabsStory() }
                Route("/component/pagination") { PaginationStory() }
                Route("/component/datatable") { DataTableStory() }
                Route("/component/datatable-virtual") { DataTableVirtualStory() }
                Route("/component/theming") { ThemingStory() }
                Route("/component/reducer-wizard") { ReducerWizardStory() }
                // One Route per story:
            } notFound: { ctx in
                NotFoundStory(path: ctx.path)
            }
        }
    }

    /// The always-present outlet wrapper. Playground overrides ride as inline
    /// `--sw-*` custom properties on THIS div rather than a conditionally
    /// present `Theme(...)` wrapper: the old approach changed the VNode tree
    /// shape (outlet vs. Theme-wrapped outlet) whenever an override toggled,
    /// which remounted the RouterRoot subtree underneath and reset story
    /// `@State`. Keeping the div itself constant and only diffing its style
    /// dict is safe — `diffStyle` (Sources/Swiflow/Diff/Diff.swift) emits a
    /// `removeStyle` patch for any key present in the old render but absent
    /// from the new one, and the js-driver applies it via
    /// `style.removeProperty` (swiflow-driver.js, `removeStyle` case), which
    /// correctly clears `--sw-*` custom properties. So simply omitting the
    /// key when the choice is "Default" reverts it cleanly — no need for an
    /// explicit revert value.
    private var storyOutlet: VNode {
        var node = div(.class("story-outlet")) { outlet }
            .padding(.xl)
            .style("flex", "1 1 auto")
            .style("min-width", "0")
            .style("overflow-y", "auto")
        if let accent = Shell.accents[accentChoice] {
            node = node.style(Token.accent.name, accent)
            // Re-derive the accent family (focus ring, focused borders, hover/active)
            // from the overridden accent. Those tokens are declared at :root, so a
            // scoped --sw-accent override doesn't re-resolve them without this — same
            // set Theme(.accent:) applies. (Inline here, not a Theme wrapper, to keep
            // the stable-div structure that avoids remounting the routed subtree.)
            for d in swAccentFamilyDerivations { node = node.style(d.name, d.value) }
        }
        if radiusChoice != "Default" {
            node = node.style(Token.radius.name, radiusChoice)
        }
        return node
    }

    // Dark-mode must sync at the document root (see Global Constraints).
    func onAppear() {
        syncColorScheme()
        syncCurrentPath()
        startHashListener()
    }
    func onChange() { syncColorScheme() }
    func onDisappear() { stopHashListener() }

    /// Read `location.hash` (`"#/component/x"`) into `currentPath` (`"/component/x"`);
    /// empty hash → `"/"`. Idempotent read-diff-write, so it's cheap to call often.
    private func syncCurrentPath() {
        #if canImport(JavaScriptKit)
        // Subscript access (not `.location`/`.hash` dot-members, which collide with
        // Swift's own `hash`), mirroring SwiflowRouter's BrowserNavigator.
        guard let window = JSObject.global.window.object,
              let location = window["location"].object else { return }
        let raw = location["hash"].string ?? ""
        let stripped = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let next = stripped.isEmpty ? "/" : stripped
        if currentPath != next { currentPath = next }
        #endif
    }

    /// Mirror hash navigations into `currentPath` so the active nav link updates.
    /// The Shell is above `RouterRoot`, so it doesn't re-render on route change by
    /// itself — this window listener (the same mechanism `RouterRoot` uses) drives it.
    private func startHashListener() {
        #if canImport(JavaScriptKit)
        guard hashListener == nil, let window = JSObject.global.window.object else { return }
        let closure = JSClosure { [weak self] _ in
            MainActor.assumeIsolated { self?.syncCurrentPath() }
            return .undefined
        }
        _ = window.addEventListener!("hashchange", closure)
        hashListener = closure
        #endif
    }

    private func stopHashListener() {
        #if canImport(JavaScriptKit)
        if let window = JSObject.global.window.object, let closure = hashListener {
            _ = window.removeEventListener!("hashchange", closure)
        }
        hashListener = nil
        #endif
    }

    private func syncColorScheme() {
        #if canImport(JavaScriptKit)
        guard let html = JSObject.global.document.object?.documentElement.object,
              let style = html.style.object else { return }
        let want = isDark ? "dark" : "light"
        if style.colorScheme.string != want { style.colorScheme = .string(want) }
        #endif
    }
}

@Component
final class NotFoundStory {
    var path: String

    init(path: String) {
        self.path = path
    }

    var body: VNode {
        storyPage("Not found", blurb: "No story at \(path).") {
            embed { Link("/", "Back to overview") }
        }
    }
}

"""##,
                "Sources/App/Stories/AccordionStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class AccordionStory {
    var body: VNode {
        storyPage("Accordion",
                  blurb: "Native <details>/<summary> disclosure — no JS. AccordionItem is a stateless "
                       + "free function; Accordion is a thin @Component facade that exists purely to keep "
                       + "a stable group name across re-renders. exclusive: true groups every item under "
                       + "the same native <details name> value, so the browser enforces one-open-at-a-time "
                       + "(Baseline 2024) with no wiring on your end.") {
            variantSection("Independent (default)", snippet: """
            Accordion {
                AccordionItem("Shipping", open: true) {
                    p("Ships within two business days.")
                }
                AccordionItem("Returns") {
                    p("Returns are accepted within 30 days of delivery.")
                }
                AccordionItem("Warranty") {
                    p("Covers manufacturing defects for one year.")
                }
            }
            """) {
                Accordion {
                    AccordionItem("Shipping", open: true) {
                        p("Ships within two business days.")
                    }
                    AccordionItem("Returns") {
                        p("Returns are accepted within 30 days of delivery.")
                    }
                    AccordionItem("Warranty") {
                        p("Covers manufacturing defects for one year.")
                    }
                }
            }
            variantSection("Exclusive — one open at a time", snippet: """
            Accordion(exclusive: true) {
                AccordionItem("What is Swiflow?", open: true) {
                    p("A Swift-native framework for building web UIs that compile to WebAssembly.")
                }
                AccordionItem("Does it need JavaScript?") {
                    p("Not for this — <details name> grouping is a native platform feature.")
                }
                AccordionItem("Is it accessible?") {
                    p("Yes — <details>/<summary> carry disclosure semantics to assistive tech for free.")
                }
            }
            """) {
                Accordion(exclusive: true) {
                    AccordionItem("What is Swiflow?", open: true) {
                        p("A Swift-native framework for building web UIs that compile to WebAssembly.")
                    }
                    AccordionItem("Does it need JavaScript?") {
                        p("Not for this — <details name> grouping is a native platform feature.")
                    }
                    AccordionItem("Is it accessible?") {
                        p("Yes — <details>/<summary> carry disclosure semantics to assistive tech for free.")
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/AutocompleteStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class AutocompleteStory {
    @State var element: String = ""
    @State var asyncElement: String = ""

    /// Shared by the sync Autocomplete (static options) and the async one (a loader that
    /// filters the same list behind a simulated network delay).
    static let periodicElements: [String] = [
        "Hydrogen", "Helium", "Lithium", "Beryllium", "Boron", "Carbon", "Nitrogen", "Oxygen",
        "Fluorine", "Neon", "Sodium", "Magnesium", "Aluminium", "Silicon", "Phosphorus", "Sulfur",
        "Chlorine", "Argon", "Potassium", "Calcium", "Titanium", "Chromium", "Iron", "Cobalt",
        "Nickel", "Copper", "Zinc", "Silver", "Tin", "Iodine", "Gold", "Mercury", "Lead",
        "Radon", "Uranium", "Plutonium",
    ]

    var body: VNode {
        storyPage("Autocomplete",
                  blurb: "A type-to-filter combobox over a Binding<String> — static options, or an "
                       + "async loader for remote data (debounced, cancellation-safe, with a "
                       + "Searching… state).") {
            variantSection("Static options", snippet: """
            Autocomplete("Element", selection: $element, options: periodicElements.map { SelectOption($0) })
            """) {
                Card(variant: .plain) {
                    // A non-address domain on purpose: Chrome forces address autofill onto
                    // anything it reads as a "Country" field (ignoring autocomplete="off"),
                    // and that overlay covers the custom listbox.
                    Autocomplete("Element", selection: $element,
                                 options: AutocompleteStory.periodicElements.map { SelectOption($0) },
                                 placeholder: "Type to search…")
                }
            }
            variantSection("Async loader", snippet: """
            Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                try await Task.sleep(nanoseconds: 350_000_000)   // simulated network
                return periodicElements
                    .filter { $0.lowercased().contains(query.lowercased()) }
                    .map { SelectOption($0) }
            })
            """) {
                Card(variant: .plain) {
                    // Async/remote variant: the loader filters behind a simulated 350ms delay,
                    // so you see the Searching… state, then results. Debounced (rapid typing
                    // fires one request) and cancellation-safe via .task(rerunOn:).
                    Autocomplete("Element (async)", selection: $asyncElement, loader: { query in
                        try await Task.sleep(nanoseconds: 350_000_000)
                        return AutocompleteStory.periodicElements
                            .filter { $0.lowercased().contains(query.lowercased()) }
                            .map { SelectOption($0) }
                    }, placeholder: "Search the periodic table…")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/AvatarStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class AvatarStory {
    // A real relative URL, served from the example root. NOT a data: URI — the
    // previous data:-based placeholder rendered a broken image: URLSanitizer
    // strips data: srcs by default (allowDataURLs is an opt-in startup knob).
    private let placeholderSrc = "avatar.svg"

    var body: VNode {
        storyPage("Avatar",
                  blurb: "A user/entity picture — Badge's shape, sized via ControlSize — that falls back "
                       + "to initials when there's no image. With src, an <img> (the URL is sanitized via "
                       + ".src, exactly like TextLink's href). Without one, a role=img span filled with "
                       + "the name's initials.") {
            variantSection("Sizes", snippet: """
            HStack(spacing: .md, align: .center) {
                Avatar("Ada Lovelace", size: .sm)
                Avatar("Ada Lovelace", size: .md)
                Avatar("Ada Lovelace", size: .lg)
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Avatar("Ada Lovelace", size: .sm)
                    Avatar("Ada Lovelace", size: .md)
                    Avatar("Ada Lovelace", size: .lg)
                }
            }
            variantSection("Shapes", snippet: """
            HStack(spacing: .md, align: .center) {
                Avatar("Grace Hopper", shape: .circle)
                Avatar("Grace Hopper", shape: .rounded)
                Avatar("Grace Hopper", shape: .square)
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Avatar("Grace Hopper", shape: .circle)
                    Avatar("Grace Hopper", shape: .rounded)
                    Avatar("Grace Hopper", shape: .square)
                }
            }
            variantSection("With an image", snippet: """
            Avatar("Ada Lovelace", src: "avatar.svg")   // renders <img>; initials when src is nil
            // NB: data: srcs are stripped by URLSanitizer unless you opt in at startup
            // (URLSanitizer.allowDataURLs = true) — use real URLs for avatar images.
            """) {
                Avatar("Ada Lovelace", src: placeholderSrc)
            }
        }
    }
}

"""##,
                "Sources/App/Stories/BreadcrumbsStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class BreadcrumbsStory {
    var body: VNode {
        storyPage("Breadcrumbs",
                  blurb: "A stateless <nav aria-label=\"Breadcrumb\"> + <ol> trail. The last crumb is "
                       + "always the current page — plain text with aria-current=\"page\", never a link, "
                       + "even if given an href. Renders plain sanitized <a> anchors (never SwiflowRouter "
                       + "Link), so it stays usable with or without a router.") {
            variantSection("Trail", snippet: """
            Breadcrumbs([
                Crumb("Home", href: "/"),
                Crumb("Products", href: "/products"),
                Crumb("Widgets", href: "/products/widgets"),
                Crumb("Blue Widget"),
            ])
            """) {
                Card(variant: .plain) {
                    Breadcrumbs([
                        Crumb("Home", href: "/"),
                        Crumb("Products", href: "/products"),
                        Crumb("Widgets", href: "/products/widgets"),
                        Crumb("Blue Widget"),
                    ])
                }
            }
            variantSection("Custom SVG separator", snippet: """
            let chevronRight = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' "
                             + "fill='none' stroke='currentColor' stroke-width='1.75' "
                             + "stroke-linecap='round' stroke-linejoin='round'><path d='M6 4l4 4-4 4'/></svg>"
            Breadcrumbs([...], separator: chevronRight)
            """) {
                Card(variant: .plain) {
                    Breadcrumbs([
                        Crumb("Home", href: "/"),
                        Crumb("Products", href: "/products"),
                        Crumb("Widgets", href: "/products/widgets"),
                        Crumb("Blue Widget"),
                    ], separator: "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' "
                                + "fill='none' stroke='currentColor' stroke-width='1.75' "
                                + "stroke-linecap='round' stroke-linejoin='round'><path d='M6 4l4 4-4 4'/></svg>")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ButtonStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ButtonStory {
    // Knobs
    @State var variantName: String = "primary"
    @State var sizeName: String = "md"
    @State var disabled: Bool = false
    @State var label: String = "Click me"

    private var variant: ButtonVariant {
        switch variantName {
        case "secondary": .secondary
        case "ghost": .ghost
        case "danger": .danger
        default: .primary
        }
    }
    private var size: ControlSize {
        switch sizeName { case "xs": .xs; case "sm": .sm; case "lg": .lg; default: .md }
    }

    var body: VNode {
        storyPage("Button",
                  blurb: "Variants and sizes are skinned entirely by --sw-* tokens.") {
            variantSection("Variants", snippet: """
            Button("Primary") {}
            Button("Secondary", variant: .secondary) {}
            Button("Ghost", variant: .ghost) {}
            Button("Danger", variant: .danger) {}
            Button("Disabled", disabled: true) {}
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("Primary") {}
                        Button("Secondary", variant: .secondary) {}
                        Button("Ghost", variant: .ghost) {}
                        Button("Danger", variant: .danger) {}
                        Button(variant: .secondary, action: {}) { span(.attr("aria-hidden", true)) { text("↻") }; text("Retry") }
                        Button(variant: .ghost, .attr("aria-label", "Delete"), action: {}) { span(.attr("aria-hidden", true)) { text("🗑") } }
                        Button("Disabled", disabled: true) {}
                    }
                }
            }
            variantSection("Sizes", snippet: """
            Button("X-Small", size: .xs) {}
            Button("Small", size: .sm) {}
            Button("Medium", size: .md) {}
            Button("Large", size: .lg) {}
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("X-Small", size: .xs) {}
                        Button("Small", size: .sm) {}
                        Button("Medium", size: .md) {}
                        Button("Large", size: .lg) {}
                    }
                }
            }
            variantSection("Playground") {
                Card(variant: .outlined) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Label", text: $label)
                        Select("Variant", selection: $variantName,
                               options: ["primary", "secondary", "ghost", "danger"])
                        RadioGroup("Size", selection: $sizeName,
                                   options: ["xs", "sm", "md", "lg"], size: .sm)
                        Toggle("Disabled", isOn: $disabled)
                        Divider()
                        HStack(align: .center) {
                            Button(label, variant: variant, size: size, disabled: disabled) {}
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/CalloutStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class CalloutStory {
    var body: VNode {
        storyPage("Callout",
                  blurb: "A stateless semantic status banner — a bordered, soft-tinted div with an "
                       + "optional title, a message, and an optional actions slot. role/aria-live map "
                       + "like Toast: .danger is assertive (role=alert), the other three are polite "
                       + "(role=status). No icon — that's M14.") {
            variantSection("Variants", snippet: """
            Callout("This is an informational note.")
            Callout("Changes saved.", variant: .success)
            Callout("Your session will expire soon.", variant: .warning)
            Callout("Couldn't reach the server.", variant: .danger)
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Callout("This is an informational note.")
                    Callout("Changes saved.", variant: .success)
                    Callout("Your session will expire soon.", variant: .warning)
                    Callout("Couldn't reach the server.", variant: .danger)
                }
            }
            variantSection("Title + actions", snippet: """
            Callout("We couldn't process your last payment.", variant: .danger, title: "Payment failed") {
                Button("Retry") {}
                TextLink("Contact support", href: "https://example.com/support")
            }
            """) {
                Callout("We couldn't process your last payment.", variant: .danger, title: "Payment failed") {
                    Button("Retry") {}
                    TextLink("Contact support", href: "https://example.com/support")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/CheckboxStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class CheckboxStory {
    @State var accepted: Bool = false
    @State var simple: Bool = true
    @State var ctrl: FormController = FormController()
    @State var name: String = ""

    var body: VNode {
        let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })

        return storyPage("Checkbox",
                          blurb: "A custom-drawn checkbox (identical pixels in every browser) over a "
                            + "Binding<Bool>. Checkbox is for confirmation — a value submitted with a "
                            + "form; for an immediate on/off setting reach for Toggle instead.") {
            variantSection("Binding", snippet: """
            Checkbox("Email me a receipt", isOn: $simple)
            """) {
                Card(variant: .plain) {
                    Checkbox("Email me a receipt", isOn: $simple)
                }
            }
            variantSection("Field-validated", snippet: """
            let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })
            Checkbox("I accept the terms", field: termsField)
            """) {
                Card(variant: .plain) {
                    Checkbox("I accept the terms", field: termsField)
                }
                p("Check then uncheck (or blur unchecked): the box turns aria-invalid and a "
                  + "role=alert message appears.")
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            Checkbox("Email me a receipt", isOn: $simple, layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, layout: .horizontal)
                        Checkbox("Email me a receipt", isOn: $simple, layout: .horizontal)
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ContainerStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ContainerStory {
    var body: VNode {
        storyPage("Container",
                  blurb: "The simplest layout primitive: a stateless centered max-width div over the "
                       + "--sw-container-{sm,md,lg,xl} tokens (character-measure widths for readable "
                       + "line lengths) — the page shell most apps wrap their content in. margin-inline: "
                       + "auto centers it once it hits its max-width. Default size is .lg.") {
            variantSection("Widths", snippet: """
            Container(size: .sm) { tintedCard("sm — 30ch") }
            Container(size: .md) { tintedCard("md — 60ch") }
            Container(size: .lg) { tintedCard("lg — 90ch (default)") }
            Container(size: .xl) { tintedCard("xl — 120ch") }
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Container(size: .sm) { tintedCard("sm — 30ch") }
                    Container(size: .md) { tintedCard("md — 60ch") }
                    Container(size: .lg) { tintedCard("lg — 90ch (default)") }
                    Container(size: .xl) { tintedCard("xl — 120ch") }
                }
            }
        }
    }

    /// A Card tinted with the accent color (rather than its default plain surface)
    /// so it visibly fills the Container's width — makes the max-width read at a
    /// glance against the story page (which is itself unconstrained width).
    private func tintedCard(_ label: String) -> VNode {
        Card(variant: .outlined, .style("background-color", "color-mix(in oklab, var(--sw-accent) 8%, var(--sw-surface))")) {
            Text(label)
        }
    }
}

"""##,
                "Sources/App/Stories/DataTableStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class DataTableStory {
    @State var selectedPeople: Set<Int> = []
    @State var peoplePage: Int = 0
    @State var roleFilter: String = "All"
    @ReducerState var toasts: ToastQueue

    var body: VNode {
        storyPage("DataTable",
                  blurb: "DataTable with sortable: true, pageSize: 5, and multi-select checkboxes. "
                       + "Click a header to cycle ascending → descending → unsorted. The header stays "
                       + "pinned inside the 360 px scroll container (maxHeight). The role filter changes "
                       + "rows, so a key: encoding the filter remounts the table with fresh data — embedded "
                       + "components freeze rows at first mount. Clicking a row \"opens\" it (onRowClick), "
                       + "while the row checkbox and the in-cell \"Edit\" button do NOT trigger the row "
                       + "click — container clicks ignore interactive descendants (fromInteractiveDescendant).") {
            variantSection("Paged, sortable, selectable", snippet: """
            Select("Filter by role", selection: $roleFilter,
                   options: ["All", "Engineer", "Researcher", "Inventor", "Designer"])
            DataTable(shown,
                      selection: $selectedPeople,
                      sortable: true,
                      pageSize: 5,
                      page: $peoplePage,
                      onRowClick: { p in self.$toasts.show("Opening \\(p.name)", .success) },
                      maxHeight: "360px",
                      key: "people-\\(roleFilter)-\\(shown.count)") {
                Column("Name", value: \\.name)
                Column("Age", value: \\.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
                Column("") { p in
                    Button("Edit", variant: .secondary, size: .sm) {
                        self.$toasts.show("Editing \\(p.name)", .info)
                    }
                }
            }
            """) {
                dataTableSection
            }
            // Mounted once; the row-click and Edit toasts fire into this page's own queue.
            ToastStack(queue: $toasts)
        }
    }

    /// The DataTable showcase. Extracted from `body` to keep that single result-builder
    /// expression within the Swift type-checker's budget. Demonstrates the dynamic-data
    /// `key:` contract: the role filter changes `rows`, and the `key:` (encoding the filter)
    /// remounts the reused table so it re-reads fresh rows.
    private var dataTableSection: VNode {
        let shown = roleFilter == "All"
            ? samplePeople
            : samplePeople.filter { $0.role == roleFilter }
        return VStack(spacing: .md, align: .stretch) {
            Select("Filter by role", selection: $roleFilter,
                   options: ["All", "Engineer", "Researcher", "Inventor", "Designer"])
            // A keyed component can't share a parent with unkeyed siblings (Swiflow's
            // all-or-none keyed-children rule), so the keyed table lives in its own
            // single-child container rather than directly beside the h2/Select/p.
            VStack(spacing: .none, align: .stretch) {
                DataTable(shown,
                          selection: $selectedPeople,
                          sortable: true,
                          pageSize: 5,
                          page: $peoplePage,
                          onRowClick: { p in
                              self.$toasts.show("Opening \(p.name)", .success)
                          },
                          maxHeight: "360px",
                          key: "people-\(roleFilter)-\(shown.count)") {
                    Column("Name", value: \.name)
                    Column("Age", value: \.age).align(.trailing)
                    Column("Role") { p in Badge(p.role, variant: .accent) }
                    Column("") { p in
                        Button("Edit", variant: .secondary, size: .sm) {
                            self.$toasts.show("Editing \(p.name)", .info)
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/DataTableVirtualStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class DataTableVirtualStory {
    var body: VNode {
        storyPage("DataTable — virtualized",
                  blurb: "Virtualized DataTable over 2,000 rows: only the rows in (and just around) "
                       + "the 440 px viewport are in the DOM. Scroll to stream rows; sorting reorders the "
                       + "whole dataset. Columns come from columnsTemplate (per-column .width is ignored "
                       + "when virtualized).") {
            variantSection("2,000 rows, fixed row height", snippet: """
            DataTable(bigPeople,
                      sortable: true,
                      maxHeight: "440px",
                      virtualization: .fixed(rowHeight: 44),
                      columnsTemplate: "2fr 80px 1fr") {
                Column("Name", value: \\.name)
                Column("Age", value: \\.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
            }
            """) {
                virtualTableSection
            }
        }
    }

    /// A 2,000-row virtualized DataTable. `virtualized: .fixed(rowHeight:)` keeps only the
    /// visible window in the DOM; `columnsTemplate` gives the grid its (shared, stable) column
    /// tracks; `maxHeight` is the required scroll container. Static dataset ⇒ no `key:` needed.
    private var virtualTableSection: VNode {
        VStack(spacing: .none, align: .stretch) {
            DataTable(bigPeople,
                      sortable: true,
                      maxHeight: "440px",
                      virtualization: .fixed(rowHeight: 44),
                      columnsTemplate: "2fr 80px 1fr") {
                Column("Name", value: \.name)
                Column("Age", value: \.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/DemoPeople.swift": ##"""
// Shared sample data for the DataTable stories (paged + virtualized).
import Swiflow

struct DemoPerson: Identifiable {
    let id: Int
    let name: String
    let age: Int
    let role: String
}

let samplePeople: [DemoPerson] = [
    DemoPerson(id: 1,  name: "Ada Lovelace",      age: 36, role: "Engineer"),
    DemoPerson(id: 2,  name: "Grace Hopper",       age: 85, role: "Admiral"),
    DemoPerson(id: 3,  name: "Alan Turing",        age: 41, role: "Researcher"),
    DemoPerson(id: 4,  name: "Margaret Hamilton",  age: 87, role: "Engineer"),
    DemoPerson(id: 5,  name: "Linus Torvalds",     age: 55, role: "Maintainer"),
    DemoPerson(id: 6,  name: "Vint Cerf",          age: 81, role: "Architect"),
    DemoPerson(id: 7,  name: "Tim Berners-Lee",    age: 70, role: "Inventor"),
    DemoPerson(id: 8,  name: "Guido van Rossum",   age: 69, role: "Designer"),
    DemoPerson(id: 9,  name: "Brendan Eich",       age: 63, role: "Engineer"),
    DemoPerson(id: 10, name: "Barbara Liskov",     age: 83, role: "Researcher"),
    DemoPerson(id: 11, name: "Katherine Johnson",  age: 101, role: "Mathematician"),
    DemoPerson(id: 12, name: "Dennis Ritchie",     age: 70, role: "Inventor"),
    DemoPerson(id: 13, name: "Ken Thompson",       age: 82, role: "Inventor"),
    DemoPerson(id: 14, name: "Bjarne Stroustrup",  age: 74, role: "Designer"),
]

let bigPeople: [DemoPerson] = (0..<2000).map { i in
    DemoPerson(id: 1000 + i, name: "Person \(i)", age: 18 + (i % 70),
               role: ["Engineer", "Researcher", "Inventor", "Designer"][i % 4])
}

"""##,
                "Sources/App/Stories/FeedbackStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class FeedbackStory {
    var body: VNode {
        storyPage("Feedback & display",
                  blurb: "Cards, badges, spinners and progress — all skinned by --sw-* tokens; "
                       + "flip Dark mode (top-right) to see them re-skin.") {
            variantSection("Cards & badges", snippet: """
            Card {
                h3("Elevated Card")
                p("A surfaced container with a token shadow.")
                HStack(spacing: .sm, align: .center) {
                    Spinner()
                    Badge("New", variant: .accent)
                    Badge("3")
                }
            }
            Card(variant: .outlined) {
                h3("Outlined Card")
                p("Bordered instead of shadowed.")
                HStack(spacing: .sm, align: .center) {
                    Badge("Error", variant: .danger)
                    Badge("Done", variant: .success)
                    Badge("Warn", variant: .warning)
                    Badge("Info", variant: .info)
                    Badge("Muted")
                }
            }
            """) {
                Grid(columns: 2, spacing: .md) {
                    Card {
                        h3("Elevated Card")
                        p("A surfaced container with a token shadow.")
                        HStack(spacing: .sm, align: .center) {
                            Spinner()
                            Badge("New", variant: .accent)
                            Badge("3")
                        }
                    }
                    Card(variant: .outlined) {
                        h3("Outlined Card")
                        p("Bordered instead of shadowed.")
                        HStack(spacing: .sm, align: .center) {
                            Badge("Error", variant: .danger)
                            Badge("Done", variant: .success)
                            Badge("Warn", variant: .warning)
                            Badge("Info", variant: .info)
                            Badge("Muted")
                        }
                    }
                }
            }
            variantSection("Badge sizes", snippet: """
            Badge("xs", size: .xs)
            Badge("sm", size: .sm)
            Badge("md")            // default
            Badge("lg", size: .lg)
            """) {
                HStack(spacing: .sm, align: .center) {
                    Badge("xs", variant: .accent, size: .xs)
                    Badge("sm", variant: .accent, size: .sm)
                    Badge("md", variant: .accent)
                    Badge("lg", variant: .accent, size: .lg)
                }
            }
            variantSection("Progress", snippet: """
            ProgressView(value: 0.6)
            ProgressView(value: 0.6, animated: true)   // macOS-style sheen sweep
            """) {
                ProgressView(value: 0.6)
                ProgressView(value: 0.6, animated: true)
                p("The Spinner and the animated progress sheen pause under "
                  + "prefers-reduced-motion (via --sw-anim-play); cards/badges/progress "
                  + "re-skin with the theme — flip Dark mode to see it.")
            }
        }
    }
}

"""##,
                "Sources/App/Stories/GridStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class GridStory {
    var body: VNode {
        storyPage("Grid",
                  blurb: "Grid(columns: 3, spacing: .md) — equal columns via "
                       + "repeat(3, minmax(0, 1fr)).") {
            variantSection("3 equal columns", snippet: """
            Grid(columns: 3, spacing: .md) {
                for n in 1...6 { card("Cell \\(n)") }
            }
            """) {
                Grid(columns: 3, spacing: .md) {
                    for n in 1...6 { card("Cell \(n)") }
                }
            }

            variantSection("Column & row spans", snippet: """
            Grid(columns: 3, spacing: .md) {
                card("colSpan(2)").colSpan(2)
                card("1")
                card("rowSpan(2)").rowSpan(2)
                card("2"); card("3"); card("4"); card("5")
            }
            """) {
                Grid(columns: 3, spacing: .md) {
                    card("colSpan(2)").colSpan(2)
                    card("1")
                    card("rowSpan(2)").rowSpan(2)
                    card("2"); card("3"); card("4"); card("5")
                }
            }
        }
    }

    /// A small surfaced tile used to fill the grid demo.
    private func card(_ title: String) -> VNode {
        // Typed token spellings: single-token values take a Token directly;
        // composites interpolate .css. A typo'd Token fails at compile time —
        // a typo'd var() string fails silent.
        div { text(title) }
            .padding(.md)
            .style("background", Token.surface)
            .style("border", "\(Token.borderWidth.css) solid \(Token.border.css)")
            .style("border-radius", Token.radius)
            .style("text-align", "center")
    }
}

"""##,
                "Sources/App/Stories/IconStory.swift": ##"""
import Swiflow
import SwiflowUI

/// A simple checkmark — hand-authored, single-color (`stroke="currentColor"`),
/// the shape `Icon`'s mask takes on.
private let checkSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'>"
    + "<path d='M3 8l4 4 6-8'/></svg>"

/// A simple gear/settings glyph, same single-color contract.
private let gearSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'>"
    + "<circle cx='8' cy='8' r='2.25'/>"
    + "<path d='M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4l1.4-1.4M11 5l1.4-1.4'/>"
    + "</svg>"

/// A simple "close" X, used in the labeled (icon-only) example below.
private let closeSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.75' stroke-linecap='round'>"
    + "<path d='M4 4l8 8M12 4l-8 8'/></svg>"

@Component
final class IconStory {
    var body: VNode {
        storyPage("Icon",
                  blurb: "A stateless, single-color SVG seam: a <span> masked to a caller-supplied "
                       + "<svg> string via CSS mask/-webkit-mask, filled with currentColor. Apps bring "
                       + "their own icons — there's no bundled icon set.") {
            variantSection("Sizes", snippet: """
            Icon(checkSVG, size: .sm)
            Icon(checkSVG, size: .md)
            Icon(checkSVG, size: .lg)
            """) {
                HStack(spacing: .md, align: .center) {
                    Icon(checkSVG, size: .sm)
                    Icon(checkSVG, size: .md)
                    Icon(checkSVG, size: .lg)
                }
            }
            variantSection("Tinted", snippet: """
            Icon(gearSVG, size: .lg, .style("color", Token.accent.css))
            """) {
                p("The mask only carries alpha — the icon always renders in currentColor. "
                  + "Tint it with .style(\"color\", …) or nest it under a colored parent.")
                Icon(gearSVG, size: .lg, .style("color", Token.accent.css))
            }
            variantSection("Decorative vs. labeled", snippet: """
            // Decorative — adjacent text already conveys the meaning; aria-hidden, no role.
            HStack(spacing: .sm, align: .center) {
                Icon(checkSVG)
                Text("Saved")
            }

            // Labeled — the icon IS the accessible name; role="img" + aria-label, no aria-hidden.
            Icon(closeSVG, label: "Close")
            """) {
                VStack(spacing: .sm, align: .stretch) {
                    HStack(spacing: .sm, align: .center) {
                        Icon(checkSVG)
                        Text("Saved")
                    }
                    Icon(closeSVG, label: "Close")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/IndexStory.swift": ##"""
import Swiflow
import SwiflowUI
import SwiflowRouter

@Component
final class IndexStory {
    var body: VNode {
        storyPage("SwiflowUI Catalog",
                  blurb: "Every SwiflowUI component, one page each: live variants, "
                       + "code snippets, and knobs. Pick a component from the navbar.") {
            Grid(columns: 3, spacing: .md) {
                for entry in Catalog.stories {
                    Card(variant: .outlined) {
                        h3(entry.title)
                        p(entry.category.rawValue)
                        embed { Link(Catalog.path(entry.slug), "Open") }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/LabeledFieldStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class LabeledFieldStory {
    @State var host: String = ""
    @State var port: String = ""
    @State var token: String = ""
    @State var city: String = ""
    @State var postal: String = ""

    private static let infoIcon =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' " +
        "stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='8' r='6.5'/>" +
        "<path d='M8 7.5v3.5'/><circle cx='8' cy='5' r='0.5' fill='currentColor'/></svg>"

    var body: VNode {
        storyPage("LabeledField",
                  blurb: "The shared field chrome, public: label line (with optional subtle "
                       + "prefix/suffix adornments), your control, and the standard error — plus "
                       + "a horizontal layout whose label column is either a fixed shared width "
                       + "(--sw-field-label-width, so stacked fields align) or hugs each field's "
                       + "own label (labelColumn: .hug). The built-in controls render this "
                       + "internally; use it directly for custom controls.") {
            variantSection("Horizontal settings form", snippet: """
            TextField("Host", text: $host, layout: .horizontal)
            TextField("Port", text: $port, layout: .horizontal)
            TextField("API token", text: $token, layout: .horizontal, labelSuffix: text("optional"))
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Host", text: $host, placeholder: "example.com", layout: .horizontal)
                        TextField("Port", text: $port, placeholder: "443", layout: .horizontal)
                        TextField("API token", text: $token, layout: .horizontal,
                                  labelSuffix: text("optional"))
                    }
                }
            }
            variantSection("Hugging label column", snippet: """
            TextField("City", text: $city, layout: .horizontal(labelColumn: .hug))
            TextField("Postal code", text: $postal, layout: .horizontal(labelColumn: .hug))
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("City", text: $city, placeholder: "Montréal",
                                  layout: .horizontal(labelColumn: .hug))
                        TextField("Postal code", text: $postal, placeholder: "H2X 1Y4",
                                  layout: .horizontal(labelColumn: .hug))
                    }
                }
            }
            variantSection("Label adornments", snippet: """
            TextField("Endpoint", text: $host, labelPrefix: Icon(infoIcon), labelSuffix: text("optional"))
            """) {
                Card(variant: .plain) {
                    TextField("Endpoint", text: $host,
                              labelPrefix: Icon(LabeledFieldStory.infoIcon),
                              labelSuffix: text("optional"))
                }
            }
            variantSection("Custom control", snippet: """
            LabeledField("Favorite hue", layout: .horizontal) {
                element("input", attributes: [.attr("type", "color")])
            }
            """) {
                Card(variant: .plain) {
                    LabeledField("Favorite hue", layout: .horizontal) {
                        element("input", attributes: [.attr("type", "color")])
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ModalStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ModalStory {
    @State var showSettings: Bool = false
    @State var notifyByEmail: Bool = true

    var body: VNode {
        storyPage("Modal",
                  blurb: "Modal is the general-purpose sibling of Alert/Prompt: same native "
                       + "<dialog>.showModal() machinery (top layer, backdrop, focus trap, ESC-to-close), "
                       + "but no baked-in title-required/actions-slot opinion — an optional title, a "
                       + "size (.sm/.md/.lg), and arbitrary content. Unlike Alert, dismissOnBackdrop "
                       + "defaults to true: a generic modal is a casual overlay, so clicking outside "
                       + "to leave is the expected affordance. Reach for Alert/Prompt instead when you "
                       + "specifically need a confirm dialog or a single text-input prompt.") {
            variantSection("A settings modal", snippet: """
            Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
                Toggle("Notify me by email", isOn: self.$notifyByEmail)
                HStack(spacing: .md, align: .center) {
                    Spacer()
                    Button("Close") { self.showSettings = false }
                }
            }
            """) {
                Button("Settings…", variant: .secondary) { self.showSettings = true }
                Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
                    Toggle("Notify me by email", isOn: self.$notifyByEmail)
                    HStack(spacing: .md, align: .center) {
                        Spacer()
                        Button("Close") { self.showSettings = false }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/NumberFieldStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class NumberFieldStory {
    @State var rating: Double = 2.5
    @State var age: Int = 30

    var body: VNode {
        storyPage("NumberField",
                  blurb: "A native <input type=\"number\">: same label/error chrome as TextField, over Int or Double bindings.") {
            variantSection("Double with range", snippet: """
            NumberField("Rating", value: $rating, min: 0, max: 10, step: 0.5)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        NumberField("Rating", value: $rating, min: 0, max: 10, step: 0.5)
                        p("value: \(rating)")
                    }
                }
            }
            variantSection("Int", snippet: """
            NumberField("Age", value: $age, min: 0, max: 120, step: 1)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        NumberField("Age", value: $age, min: 0, max: 120, step: 1)
                        p("value: \(age)")
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/OverlaysStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class OverlaysStory {
    @State var confirmDelete: Bool = false
    @State var deleteResult: String = ""
    @State var showRename: Bool = false
    @State var fileName: String = "untitled"
    @ReducerState var toasts: ToastQueue

    var body: VNode {
        storyPage("Overlays",
                  blurb: "Alert and Prompt are native <dialog>.showModal() modals — top layer, backdrop, "
                       + "focus trap and ESC-to-close all native, sharing one .sw-dialog chrome. Prompt "
                       + "wraps a <form method=\"dialog\">, so Enter submits. The Delete alert demands a "
                       + "deliberate choice (no backdrop dismiss); Rename opts into dismissOnBackdrop, so "
                       + "clicking outside cancels it. Backdrop solidifies under prefers-reduced-transparency "
                       + "and the open animation collapses under prefers-reduced-motion, both via tokens.") {
            variantSection("Modal dialogs", snippet: """
            Alert("Delete this item?", isPresented: $confirmDelete,
                  message: "This can't be undone.") {
                Button("Cancel", variant: .secondary) { self.confirmDelete = false }
                Button("Delete", variant: .danger) { self.deleteResult = "Item deleted"; self.confirmDelete = false }
            }
            Prompt("Rename file", isPresented: $showRename, text: $fileName,
                   message: "Enter a new name", placeholder: "untitled",
                   confirmTitle: "Rename", dismissOnBackdrop: true) { newName in
                self.fileName = newName.isEmpty ? "untitled" : newName
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Button("Delete item…", variant: .secondary) { self.confirmDelete = true }
                    Button("Rename \(fileName)…", variant: .secondary) { self.showRename = true }
                    if !deleteResult.isEmpty { Badge(deleteResult, variant: .success) }
                }
                // A destructive confirm: backdrop dismiss left OFF (the default) so it's not
                // closed by accident.
                Alert("Delete this item?", isPresented: $confirmDelete,
                      message: "This can't be undone.") {
                    Button("Cancel", variant: .secondary) { self.confirmDelete = false }
                    Button("Delete", variant: .danger) { self.deleteResult = "Item deleted"; self.confirmDelete = false }
                }
                // Rename opts into backdrop-to-cancel (clicking outside closes without renaming).
                Prompt("Rename file", isPresented: $showRename, text: $fileName,
                       message: "Enter a new name", placeholder: "untitled",
                       confirmTitle: "Rename", dismissOnBackdrop: true) { newName in
                    // fileName is already bound; this is where an app would persist the change.
                    self.fileName = newName.isEmpty ? "untitled" : newName
                }
            }
            variantSection("Toasts", snippet: """
            Button("Toast: success", variant: .ghost) { self.$toasts.show("Saved successfully", .success) }
            Button("Toast: info", variant: .ghost) { self.$toasts.show("Heads up — sync running") }
            Button("Toast: warning", variant: .ghost) { self.$toasts.show("Low disk space", .warning) }
            Button("Toast: error", variant: .ghost) { self.$toasts.show("Couldn't reach the server", .danger) }
            Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }
            """) {
                HStack(spacing: .md, align: .center) {
                    Button("Toast: success", variant: .ghost) { self.$toasts.show("Saved successfully", .success) }
                    Button("Toast: info", variant: .ghost) { self.$toasts.show("Heads up — sync running") }
                    Button("Toast: warning", variant: .ghost) { self.$toasts.show("Low disk space", .warning) }
                    Button("Toast: error", variant: .ghost) { self.$toasts.show("Couldn't reach the server", .danger) }
                    Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }
                }
            }
            variantSection("Dropdown menu", snippet: """
            Dropdown("Actions") {
                DropdownItem("Edit") { self.$toasts.show("Edit selected") }
                DropdownItem("Duplicate") { self.$toasts.show("Duplicated", .success) }
                DropdownItem("Archive", disabled: true) {}
                DropdownDivider()
                DropdownItem("Delete", variant: .danger) { self.$toasts.show("Deleted", .danger) }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    // Dropdown: a Popover-API menu anchored to its trigger; items close it on
                    // select (popovertargetaction=hide) and fire a toast here.
                    Dropdown("Actions") {
                        DropdownItem("Edit") { self.$toasts.show("Edit selected") }
                        DropdownItem("Duplicate") { self.$toasts.show("Duplicated", .success) }
                        DropdownItem("Archive", disabled: true) {}
                        DropdownDivider()
                        DropdownItem("Delete", variant: .danger) { self.$toasts.show("Deleted", .danger) }
                    }
                }
            }
            // Mounted once; toasts are an app-owned queue ($toasts). They auto-dismiss
            // (4s) or via ✕, removing themselves. Danger toasts announce assertively.
            ToastStack(queue: $toasts)
        }
    }
}

"""##,
                "Sources/App/Stories/PaginationStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class PaginationStory {
    @State var page: Int = 0

    var body: VNode {
        storyPage("Pagination",
                  blurb: "Previous/Next buttons flanking a \"Page X of N\" indicator, bound "
                       + "to a 0-based page index. This is the same control DataTable renders "
                       + "for its own pager — extracted here so any paginated view can share "
                       + "it. Previous is inert on the first page, Next is inert on the last "
                       + "(project rule: inert, not disabled — an inert button carries no "
                       + "click handler at all).") {
            variantSection("Five pages", snippet: """
            @State var page = 0
            …
            Pagination(page: $page, pageCount: 5)
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Pagination(page: $page, pageCount: 5)
                    p("Current page: \(page + 1) of 5")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/PopoverStory.swift": ##"""
import Swiflow
import SwiflowUI
import SwiflowRouter

@Component
final class PopoverStory {
    var body: VNode {
        storyPage("Popover",
                  blurb: "Popover is the general-purpose sibling of Dropdown: same native Popover-API "
                       + "recipe (popover=\"auto\" + CSS anchor positioning, so it's top-layer with "
                       + "native ESC + light-dismiss), but no baked-in menu-item shape — any single "
                       + "trigger element, any content. Popover wires popovertarget/anchor-name onto "
                       + "the trigger you pass in, so its own classes/attrs (like a Button's sw-btn "
                       + "skin) survive untouched.") {
            variantSection("Anchored panel — one per placement", snippet: """
            Popover(placement: .top) {
                Button("Top", variant: .secondary) {}
            } content: {
                p("A short note anchored above the trigger.")
                embed { Link("/component/modal", "See Modal too") }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Popover(placement: .top) {
                        Button("Top", variant: .secondary) {}
                    } content: {
                        p("A short note anchored above the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .bottom) {
                        Button("Bottom", variant: .secondary) {}
                    } content: {
                        p("A short note anchored below the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .leading) {
                        Button("Leading", variant: .secondary) {}
                    } content: {
                        p("A short note anchored before the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .trailing) {
                        Button("Trailing", variant: .secondary) {}
                    } content: {
                        p("A short note anchored after the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                }
            }
            variantSection("Offset — a standoff from the trigger", snippet: """
            Popover(placement: .bottom, offset: 3) {
                Button("3px off", variant: .secondary) {}
            } content: {
                p("Opens with a small gap to the trigger (Tooltip's standoff).")
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Popover(placement: .bottom, offset: 3) {
                        Button("3px off", variant: .secondary) {}
                    } content: {
                        p("Opens with a small gap to the trigger (Tooltip's standoff).")
                    }
                    Popover(placement: .bottom, offset: 8) {
                        Button("8px off", variant: .secondary) {}
                    } content: {
                        p("Any distance works — offset is just pixels.")
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/RadioGroupStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class RadioGroupStory {
    @State var plan: String = "Free"

    var body: VNode {
        storyPage("RadioGroup",
                  blurb: "A <fieldset>/<legend> group of custom-drawn radios (identical pixels in "
                       + "every browser) over a Binding<String> — the native shared name gives "
                       + "roving keyboard focus for free.") {
            variantSection("Selection", snippet: """
            RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
                        p("Selected plan: \(plan)")
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ReducerWizardStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ReducerWizardStory {
    var body: VNode {
        storyPage("Reducer wizard",
                  blurb: "A @ReducerState-backed two-step wizard. \"Next\" and \"Back\" are sync dispatches; "
                       + "\"Submit\" fires an async effect (300 ms simulated round-trip) then dispatches "
                       + "a second action when it completes. The reducer is pure; all async lives at the call site.") {
            embed { SignupWizardView() }
        }
    }
}

// MARK: - Reducer wizard demo

struct SignupWizard: Reducer {
    struct State { var step = 0; var submitting = false; var done = false }
    enum Action { case next, back, submitStarted, submitFinished }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 1: s.step += 1
        case .back where s.step > 0: s.step -= 1
        case .submitStarted: s.submitting = true
        case .submitFinished: s.submitting = false; s.done = true
        default: break
        }
    }
}

@Component
final class SignupWizardView {
    @ReducerState var wiz: SignupWizard
    var body: VNode {
        let s = $wiz.state
        return VStack(spacing: .md, align: .stretch) {
            if s.done {
                p("Done ✓")
            } else {
                p("Step \(s.step + 1) of 2")
                HStack(spacing: .sm, align: .center) {
                    Button("Back", variant: .secondary, disabled: s.step == 0) { self.$wiz.send(.back) }
                    if s.step < 1 {
                        Button("Next") { self.$wiz.send(.next) }
                    } else {
                        Button("Submit", disabled: s.submitting) {
                            self.$wiz.send(.submitStarted)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                self.$wiz.send(.submitFinished)
                            }
                        }
                    }
                }
            }
        }
        .padding(.md)
        .style("background", Token.surface)
        .style("border-radius", Token.radius)
    }
}

"""##,
                "Sources/App/Stories/SelectStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class SelectStory {
    @State var color: String = ""

    var body: VNode {
        storyPage("Select",
                  blurb: "A labelled native <select> over a Binding<String>. Skinned end-to-end where "
                       + "Customizable Select is available (Chrome/Safari) — including the option "
                       + "picker and its drop-and-fade open animation — with a styled-trigger "
                       + "fallback elsewhere.") {
            variantSection("Selection", snippet: """
            Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                        if !color.isEmpty { p("Picked: \(color)") }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/SkeletonStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class SkeletonStory {
    var body: VNode {
        storyPage("Skeleton",
                  blurb: "A stateless shimmering placeholder — Badge's shape (a skinned span) for "
                       + "content that hasn't loaded yet. Purely decorative (aria-hidden) since the "
                       + "real content supplies the accessible semantics once it mounts. The shimmer "
                       + "gates on --sw-anim-play, so prefers-reduced-motion freezes it into a static "
                       + "block for free — no per-component code (the Spinner precedent).") {
            variantSection("Loading card", snippet: """
            HStack(spacing: .md, align: .center) {
                Skeleton(width: "2.5em", height: "2.5em", radius: "50%")
                VStack(spacing: .xs, align: .stretch) {
                    Skeleton(width: "60%")
                    Skeleton(width: "40%")
                }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Skeleton(width: "2.5em", height: "2.5em", radius: "50%")
                    VStack(spacing: .xs, align: .stretch) {
                        Skeleton(width: "60%")
                        Skeleton(width: "40%")
                    }
                }
            }
            variantSection("Text lines", snippet: """
            Skeleton(lines: 3)   // a paragraph-shaped placeholder; the sheet shortens the last line
            """) {
                Skeleton(lines: 3)
            }
        }
    }
}

"""##,
                "Sources/App/Stories/SliderStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class SliderStory {
    @State var volume: Double = 0.5
    @State var rating: Double = 5

    var body: VNode {
        storyPage("Slider",
                  blurb: "A native <input type=\"range\">: same label/error chrome as NumberField, styled over the accent token.") {
            variantSection("Volume", snippet: """
            Slider("Volume", value: $volume)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Slider("Volume", value: $volume)
                        p("value: \(volume)")
                    }
                }
            }
            variantSection("Stepped 0...10", snippet: """
            Slider("Rating", value: $rating, in: 0...10, step: 1)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Slider("Rating", value: $rating, in: 0...10, step: 1)
                        p("value: \(rating)")
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/SpacerStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class SpacerStory {
    var body: VNode {
        storyPage("Spacer",
                  blurb: "A Spacer() between the buttons pushes them to opposite ends.") {
            variantSection("Push apart", snippet: """
            HStack(align: .center) {
                Button("Leading", variant: .secondary) {}
                Spacer()
                Button("Trailing", variant: .secondary) {}
            }
            """) {
                Card(variant: .plain) {
                    HStack(align: .center) {
                        Button("Leading", variant: .secondary) {}
                        Spacer()
                        Button("Trailing", variant: .secondary) {}
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/StacksStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class StacksStory {
    var body: VNode {
        storyPage("Stacks",
                  blurb: "HStack/VStack with token spacing. Change --sw-space-md "
                       + "in index.html's <style> to reskin every gap at once.") {
            variantSection("Horizontal, .md spacing", snippet: """
            HStack(spacing: .md, align: .center) {
                Button("One") {}; Button("Two") {}; Button("Three") {}
            }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("One") {}; Button("Two") {}; Button("Three") {}
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TabsStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TabsStory {
    @State var tab: String = "overview"

    var body: VNode {
        storyPage("Tabs",
                  blurb: "A WAI-ARIA tablist bound to a Binding<ID> selection. Automatic "
                       + "activation: ←/→ move between tabs and wrap, Home/End jump to the "
                       + "ends, and moving focus immediately selects the target tab (its "
                       + "panel swaps and focus follows) — Tab itself is left alone, so it "
                       + "still leaves the tablist for the next element. All tabs' panels "
                       + "render up front (render-all); the inactive ones are simply hidden, "
                       + "so panel state/ARIA stay stable across selection changes.") {
            variantSection("Three tabs", snippet: """
            @State var tab = "overview"
            …
            Tabs(selection: $tab) {
                Tab("Overview", id: "overview") {
                    p("A quick summary of the project.")
                }
                Tab("Details", id: "details") {
                    p("Everything the overview left out.")
                }
                Tab("Settings", id: "settings") {
                    p("Preferences that affect this view.")
                }
            }
            """) {
                Card(variant: .plain) {
                    Tabs(selection: $tab) {
                        Tab("Overview", id: "overview") {
                            p("A quick summary of the project.")
                        }
                        Tab("Details", id: "details") {
                            p("Everything the overview left out.")
                        }
                        Tab("Settings", id: "settings") {
                            p("Preferences that affect this view.")
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TextAreaStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TextAreaStory {
    @State var bio: String = ""
    @State var feedback: String = ""
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let feedbackField = Field("feedback", $feedback, $ctrl, .required())

        return storyPage("TextArea",
                          blurb: "A multi-line text field: same label/error chrome as TextField, over a native <textarea>.") {
            variantSection("Multi-line input", snippet: """
            TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")
                        if !bio.isEmpty { p("\(bio.count) characters") }
                    }
                }
            }
            variantSection("Field-validated", snippet: """
            let feedbackField = Field("feedback", $feedback, $ctrl, .required())
            TextArea("Feedback", field: feedbackField, rows: 4, placeholder: "What should we improve?")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextArea("Feedback", field: feedbackField, rows: 4, placeholder: "What should we improve?")
                    }
                }
                p("Interact then blur to see the role=alert error and aria-invalid.")
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TextFieldStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TextFieldStory {
    @State var name: String = ""
    @State var email: String = ""
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let emailField = Field("email", $email, $ctrl, .required(), .email)

        return storyPage("TextField",
                          blurb: "A labelled text input over a Binding<String>. The Field(...) overload wires "
                            + "FormController validators — interact then blur to see the role=alert error "
                            + "and aria-invalid.") {
            variantSection("Plain binding", snippet: """
            TextField("Name", text: $name, placeholder: "Ada Lovelace")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, placeholder: "Ada Lovelace")
                        if !name.isEmpty { p("Hello, \(name)!") }
                    }
                }
            }
            variantSection("Field-validated", snippet: """
            let emailField = Field("email", $email, $ctrl, .required(), .email)
            TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
            """) {
                Card(variant: .plain) {
                    TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                }
                p("Type something invalid, then blur: the field turns aria-invalid and a "
                  + "role=alert message appears.")
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    TextField("Name", text: $name, placeholder: "Ada Lovelace", layout: .horizontal)
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TextLinkStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TextLinkStory {
    var body: VNode {
        storyPage("TextLink",
                  blurb: "A token-styled inline hyperlink — a plain <a>, not in-app routing. Named TextLink "
                       + "(not Link) because SwiflowRouter.Link already owns in-app navigation; reach for "
                       + "TextLink for external or non-routed destinations. The href is sanitized "
                       + "automatically via URLSanitizer.") {
            variantSection("Inline", snippet: """
            p { text("Read the "); TextLink("documentation", href: "https://example.com/docs"); text(" before you start.") }
            """) {
                Card(variant: .plain) {
                    p {
                        text("Read the ")
                        TextLink("documentation", href: "https://example.com/docs")
                        text(" before you start.")
                    }
                }
            }
            variantSection("External", snippet: """
            TextLink("View on GitHub", href: "https://github.com", external: true)
            """) {
                Card(variant: .plain) {
                    TextLink("View on GitHub", href: "https://github.com", external: true)
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TextStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TextStory {
    var body: VNode {
        storyPage("Text",
                  blurb: "A stateless typography primitive over the type-scale tokens. Each variant "
                       + "renders its own semantic tag by default (title→h1, heading→h2, subheading→h3, "
                       + "body/caption→p, label→span) — pass tag: to keep the styling but render a "
                       + "different element.") {
            variantSection("Variants", snippet: """
            Text("Page title", variant: .title)
            Text("Section heading", variant: .heading)
            Text("Subsection", variant: .subheading)
            Text("Body copy reads at the default size and weight.", variant: .body)
            Text("Caption text is smaller, for supporting detail.", variant: .caption)
            Text("Label text", variant: .label)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .sm, align: .stretch) {
                        Text("Page title", variant: .title)
                        Text("Section heading", variant: .heading)
                        Text("Subsection", variant: .subheading)
                        Text("Body copy reads at the default size and weight.", variant: .body)
                        Text("Caption text is smaller, for supporting detail.", variant: .caption)
                        Text("Label text", variant: .label)
                    }
                }
            }
            variantSection("tag: override", snippet: """
            Text("Styled as a heading, but the page's only h1", variant: .heading, tag: "h1")
            """) {
                Card(variant: .plain) {
                    Text("Styled as a heading, but the page's only h1", variant: .heading, tag: "h1")
                }
            }
            variantSection("Weight & color", snippet: """
            Text("Muted caption", variant: .caption, color: .muted)
            Text("Semibold body", weight: .semibold)
            Text("Danger", color: .danger)
            Text("Success", color: .success)
            Text("Warning", color: .warning)
            Text("Accent", color: .accent)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .sm, align: .stretch) {
                        Text("Muted caption", variant: .caption, color: .muted)
                        Text("Semibold body", weight: .semibold)
                        Text("Danger", color: .danger)
                        Text("Success", color: .success)
                        Text("Warning", color: .warning)
                        Text("Accent", color: .accent)
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ThemingStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ThemingStory {
    var body: VNode {
        storyPage("Scoped theming",
                  blurb: "The right-hand group is wrapped in Theme(.accent(\"#dc2626\"), .radius(\"2px\")). "
                       + "One override re-points --sw-accent; the whole family (fill, ghost text, badge "
                       + "tint, focus ring) and the radius follow — scoped to that subtree only. The "
                       + "wrapper uses display:contents, so it sits inline in the row with no layout shift.") {
            variantSection("Theme(.accent, .radius)", snippet: """
            Button("Default accent") {}
            Theme(.accent("#dc2626"), .radius("2px")) {
                HStack(spacing: .md, align: .center) {
                    Button("Branded primary") {}
                    Button("Branded ghost", variant: .ghost) {}
                    Badge("Tagged", variant: .accent)
                }
            }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("Default accent") {}
                        Theme(.accent("#dc2626"), .radius("2px")) {
                            HStack(spacing: .md, align: .center) {
                                Button("Branded primary") {}
                                Button("Branded ghost", variant: .ghost) {}
                                Badge("Tagged", variant: .accent)
                            }
                        }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ToggleButtonGroupStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ToggleButtonGroupStory {
    @State var align: String = "left"
    @State var formats: Set<String> = ["bold"]

    var body: VNode {
        storyPage("ToggleButtonGroup",
                  blurb: "A segmented control of role=group buttons (aria-pressed) — String-keyed "
                       + "like RadioGroup/Select, in single- and multi-select flavors sharing one "
                       + "lowering. No roving focus: buttons are independently tabbable — for strict "
                       + "single-select with roving, use RadioGroup or Tabs instead.") {
            variantSection("Single-select", snippet: """
            @State var align = "left"
            …
            ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])
            """) {
                VStack(spacing: .md, align: .stretch) {
                    ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])
                    p("Aligned: \(align)")
                }
            }
            variantSection("Multi-select", snippet: """
            @State var formats: Set<String> = ["bold"]
            …
            ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])
            """) {
                VStack(spacing: .md, align: .stretch) {
                    ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])
                    p("Active: \(formats.sorted().joined(separator: ", "))")
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/ToggleStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class ToggleStory {
    @State var subscribed: Bool = false
    @State var name: String = ""

    var body: VNode {
        storyPage("Toggle",
                  blurb: "A switch — an IMMEDIATE on/off setting (like Dark mode, top-right), applied "
                       + "the moment it flips. For a value that's confirmed/submitted with a form, "
                       + "use Checkbox instead.") {
            variantSection("Switch", snippet: """
            Toggle("Subscribe to updates", isOn: $subscribed)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Toggle("Subscribe to updates", isOn: $subscribed)
                        p(subscribed ? "Subscribed — you'll hear from us." : "Not subscribed.")
                    }
                }
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            Toggle("Subscribe to updates", isOn: $subscribed, layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, layout: .horizontal)
                        Toggle("Subscribe to updates", isOn: $subscribed, layout: .horizontal)
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/Stories/TooltipStory.swift": ##"""
import Swiflow
import SwiflowUI

@Component
final class TooltipStory {
    var body: VNode {
        storyPage("Tooltip",
                  blurb: "Tooltip wraps any trigger — hover or focus to reveal. Placement defaults to .top; "
                       + "pass placement: .bottom (or .leading / .trailing) to anchor it on another side. "
                       + "Pure CSS — no JS, no z-index juggling.") {
            variantSection("Placement", snippet: """
            Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
            Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
                        Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
                    }
                }
            }
            variantSection("Arrow", snippet: """
            Tooltip("Points at the trigger", arrow: true) { Button("Arrow on top", variant: .secondary) {} }
            Tooltip("From below", placement: .bottom, arrow: true) { Button("Arrow below") {} }
            Tooltip("Sideways too", placement: .trailing, arrow: true) { Button("Trailing") {} }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Tooltip("Points at the trigger", arrow: true) { Button("Arrow on top", variant: .secondary) {} }
                        Tooltip("From below", placement: .bottom, arrow: true) { Button("Arrow below") {} }
                        Tooltip("Sideways too", placement: .trailing, arrow: true) { Button("Trailing") {} }
                    }
                }
            }
        }
    }
}

"""##,
                "Sources/App/StoryHelpers.swift": ##"""
// Shared page/variant chrome for story pages: a titled page, and per-variant
// sections showing live output above a collapsible hand-maintained code snippet.
import Swiflow
import SwiflowUI

/// A story page: h1 + optional blurb + content.
@MainActor
func storyPage(_ title: String, blurb: String? = nil,
               @ChildrenBuilder content: () -> [VNode]) -> VNode {
    VStack(spacing: .lg, align: .stretch) {
        h1(title)
        if let blurb { p(blurb) }
        for node in content() { node }
    }
}

/// A variant section: titled live output, with the Swift snippet underneath
/// in a native <details> (collapsed by default).
///
/// Parameter named `snippet` (not `code`): the DSL's `<code>` element factory
/// is literally named `code`, so `code` would collide with the parameter name.
@MainActor
func variantSection(_ title: String, snippet: String? = nil,
                    @ChildrenBuilder content: () -> [VNode]) -> VNode {
    VStack(spacing: .md, align: .stretch) {
        h2(title)
        for node in content() { node }
        if let snippet {
            details(.class("story-code")) {
                summary("Swift")
                pre { code(snippet) }
            }
        }
        Divider()
    }
}

"""##,
                "avatar.svg": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6366f1"/>
      <stop offset="1" stop-color="#a855f7"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" fill="url(#g)"/>
  <circle cx="32" cy="24" r="11" fill="#fff" fill-opacity="0.92"/>
  <path d="M10 64c2-14 10-21 22-21s20 7 22 21z" fill="#fff" fill-opacity="0.92"/>
</svg>

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>SwiflowUI Demo</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }

      /* Token reskin experiment — uncomment to widen every HStack/VStack gap: */
      /* :root { --sw-space-md: 2.5rem } */
    </style>
    <!-- Generated by `swiflow theme --primary #7c3aed --neutrals`. An unlayered :root
         override — it beats SwiflowUI's @layer swiflow.base tokens, re-skinning the whole
         gallery (accent family + tinted neutrals) violet. -->
    <link rel="stylesheet" href="theme.css" />
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
                "theme.css": ##"""
/* Generated by `swiflow theme --primary #4800ff --neutrals`. Include after SwiflowUI's styles.
   Re-points --sw-accent (family cascades) + the accent-tinted neutral ramp. */
:root {
  --sw-accent: light-dark(#172bff, #0061ff);
  --sw-bg: light-dark(#f3f5fc, #0a0b0f);
  --sw-surface: light-dark(#fdffff, #15161b);
  --sw-surface-2: light-dark(#f0f1f9, #1e1f24);
  --sw-text: light-dark(#101116, #f0f1f9);
  --sw-text-muted: light-dark(#56585e, #a3a4ab);
  --sw-border: light-dark(#e2e4eb, #2c2d33);
}

@supports (color: oklch(0.5 0.5 0.5)) {
  :root {
    --sw-accent: light-dark(oklch(0.4824 0.296 265.76), oklch(0.5559 0.2541 260.47));
  }
}

@media (prefers-contrast: more) {
  :root {
    --sw-text: light-dark(#030306, #fafbff);
    --sw-text-muted: light-dark(#202127, #dcdee5);
    --sw-border: light-dark(#030306, #fafbff);
  }
}

"""##,
            ]
        ),
        Template(
            name: "TodoCRUD",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        {{SWIFLOW_DEP}},
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
                .product(name: "SwiflowQuery", package: "Swiflow"),
                // The fetch + JSON-decode story now lives in the SwiflowFetcher
                // module (graduated from this example's old Net.swift); it pulls
                // in JavaScriptKit/JavaScriptEventLoop transitively.
                .product(name: "SwiflowFetcher", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

SwiflowQuery against a **real** local CRUD API — Bun + SQLite, Dockerized.

Unlike `QueryDemo`/`AsyncFetch` (which simulate the network with `Task.sleep` and
hardcoded data), this example performs actual HTTP `fetch` calls from the WASM app to a
running backend. The SwiflowQuery machinery — cache, stale-while-revalidate, dedup,
optimistic updates, invalidation — is identical to the simulated examples; only the
`Query.fetch()` / `Mutation.perform()` bodies change to call a real server.

## What it shows

- **Read** the list with `query(TodoList())` → a `QueryState<[Todo]>`.
- **Write** with `@MutationState` mutations — `AddTodo` / `ToggleTodo` / `DeleteTodo` —
  each with an **optimistic** cache edit (append / field-flip / remove) and an
  **`.exact(["todos"])` invalidation** that refetches the canonical list to reconcile.
- The **⟳ spinner** (`isFetching`) during the post-mutation revalidation.
- **Refetch-on-focus**: the list refreshes automatically when you return to the tab,
  so edits made in another tab or by another user appear as soon as you switch back.
- **5-second polling**: `refetchInterval: .seconds(5)` keeps the list live — out-of-band
  edits (made directly against the API or by another browser) appear within ~5 s.
- The real `fetch` + JSON-decode idiom for WASM via the **`SwiflowFetcher`** module
  — `HTTPClient(baseURL:)` over the browser `fetch` + `JSValueDecoder`; no
  `Foundation`/`URLSession`.

## Architecture

```
Browser  ──┐
  WASM app (swiflow dev, :3002)
           │  CORS fetch (GET/POST/PUT/DELETE /todos)
           ▼
  Bun API (:8080)  ──►  bun:sqlite (in-memory)
```

## Run the backend

```bash
cd backend
docker compose up --build      # serves http://localhost:8080
```

## Run the frontend

```bash
# from this directory (examples/{{NAME}})
swiflow dev --port 3002        # compiles to WASM, serves on http://localhost:3002
```

Open the printed URL.

## What you should see

- The three seeded todos render (the first is checked) after a brief **Loading…**.
- Type a title + **Add** → the row appears **instantly** (optimistic), the **⟳** spinner
  shows during revalidation, then the row reconciles to the server-assigned id.
- Toggling a checkbox flips **done** instantly; the `PUT` runs in the background; the
  list reconciles.
- **✕** removes the row instantly; the `DELETE` runs; the list reconciles.
- In the browser Network tab, each mutation is immediately followed by a `GET /todos`
  (the `.exact(["todos"])` invalidation refetch).

## Notes

- **Persistence:** the backend uses an in-memory SQLite DB, re-seeded each container
  start — writes persist for the session. To persist across restarts, change
  `new Database(":memory:")` to `new Database("/data/todos.db")` in `backend/server.ts`
  and uncomment the `volumes:` lines in `backend/docker-compose.yml`.
- **CORS:** the Swiflow dev server is static-only (no proxy), so the backend sends
  permissive CORS headers and answers the `OPTIONS` preflight that POST/PUT/DELETE with
  a JSON body trigger.
- **Config:** change the `HTTPClient(baseURL:)` in `Sources/App/App.swift` to target a different host/port.

See [`docs/guides/query.md`](../../docs/guides/query.md) for the SwiflowQuery guide.

"""##,
                "Sources/App/App.swift": ##"""
import SwiflowDOM
import SwiflowUI
import SwiflowQuery
import SwiflowFetcher

/// The CRUD API, configured once. Point `baseURL` elsewhere to target another
/// host/port; queries and mutations call it with relative paths.
let api = HTTPClient(baseURL: "http://localhost:8080")

// MARK: - Model

struct Todo: Decodable, Equatable, Sendable {
    let id: Int
    let title: String
    let done: Bool
}

// MARK: - Query

@Query(prefix: "todos") struct TodoList {
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }   // live polling against the real API
    func fetch() async throws -> [Todo] {
        try await api.get("/todos", as: [Todo].self)
    }
}

// MARK: - Mutations

@Mutation struct AddTodo {
    /// Monotonic temp-id source for optimistic rows (negative so it never
    /// collides with a real server id). The derived refetch replaces it.
    static var tempSeq = -1

    func perform(_ title: String) async throws -> Todo {
        // A local Encodable struct IS the request contract — the typed `body:`
        // counterpart of hand-building a JSONValue dictionary.
        struct Body: Encodable { let title: String }
        return try await api.post("/todos", body: Body(title: title), as: Todo.self)
    }
    // No invalidations override: the default refetches the keys optimistic()
    // declares — here, TodoList. The temp id is allocated inside the transform
    // (which runs once, when the edit applies), keeping the declaration pure:
    // the derived default re-reads optimistic() on success to learn the keys.
    func optimistic(_ title: String) -> [OptimisticEdit] {
        [.update(TodoList()) { todos in
            let tmp = AddTodo.tempSeq; AddTodo.tempSeq -= 1
            return todos + [Todo(id: tmp, title: title, done: false)]
        }]
    }
}

@Mutation struct ToggleTodo {
    struct Input: Sendable { let id: Int; let done: Bool }
    func perform(_ i: Input) async throws -> Todo {
        struct Body: Encodable { let done: Bool }
        return try await api.put("/todos/\(i.id)", body: Body(done: i.done), as: Todo.self)
    }
    func optimistic(_ i: Input) -> [OptimisticEdit] {
        [.update(TodoList()) { todos in
            todos.map { $0.id == i.id ? Todo(id: $0.id, title: $0.title, done: i.done) : $0 }
        }]
    }
}

@Mutation struct DeleteTodo {
    func perform(_ id: Int) async throws {
        try await api.delete("/todos/\(id)")
    }
    func optimistic(_ id: Int) -> [OptimisticEdit] {
        [.update(TodoList()) { $0.filter { $0.id != id } }]
    }
}

// MARK: - Component

@Component
final class TodoApp {
    @State var draft: String = ""
    // @MutationState mutations carry no captured dependencies, so @Component
    // synthesizes the `init()` that default-constructs them — no boilerplate.
    @MutationState var add: AddTodo
    @MutationState var toggle: ToggleTodo
    @MutationState var remove: DeleteTodo

    var body: VNode {
        let list = query(TodoList())
        return VStack(spacing: .lg, align: .stretch) {
            h1("Todo CRUD")
            p("Reads via query(); writes via @MutationState with optimistic updates — against a real Bun + SQLite API.")

            // Add bar: a SwiflowUI TextField + Button; `align: .end` bottom-aligns
            // the button with the input (the field's label sits above it).
            HStack(spacing: .sm, align: .end) {
                TextField("New todo", text: $draft, placeholder: "What needs doing?")
                    .style("flex", "1")
                Button("Add", disabled: $add.isPending) {
                    let t = self.draft
                    guard !t.isEmpty, !t.allSatisfy(\.isWhitespace) else { return }
                    self.$add.mutate(t)
                    self.draft = ""
                }
                if list.isFetching { Spinner(size: .sm, label: "Syncing") }
            }

            if list.isLoading { p("Loading…") }
            if let e = list.error { p("Failed to load: \(e)") }
            if $add.isError { p("Add failed.") }
            if $toggle.isError { p("Toggle failed.") }
            if $remove.isError { p("Delete failed.") }

            if let todos = list.data {
                VStack(spacing: .sm, align: .stretch) {
                    for todo in todos {
                        // Keyed row: the checkbox carries the title as its label
                        // (toggling either toggles done); ✕ deletes.
                        HStack(spacing: .sm, align: .center, justify: .between, .key("todo-\(todo.id)")) {
                            Checkbox(todo.title, isOn: Binding(get: { todo.done },
                                                              set: { self.$toggle.mutate(.init(id: todo.id, done: $0)) }))
                            Button("✕", variant: .ghost, size: .sm,
                                   .attr("aria-label", "Delete \(todo.title)")) { self.$remove.mutate(todo.id) }
                        }
                    }
                }
            }
        }
        .padding(.xl)
        .style("max-width", "40rem")
        .style("margin", "0 auto")
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { TodoApp() }
    }
}

"""##,
                "backend/Dockerfile": ##"""
FROM oven/bun:1
WORKDIR /app
COPY server.ts .
EXPOSE 8080
CMD ["bun", "run", "server.ts"]

"""##,
                "backend/docker-compose.yml": ##"""
# `name` sets the Compose project name, so the container and network read as
# swiflow-todo-crud* instead of defaulting to the "backend" directory name.
name: swiflow-todo-crud

services:
  api:
    container_name: swiflow-todo-crud
    build: .
    ports: ["8080:8080"]
    # In-memory SQLite, re-seeded each start. To persist instead, in server.ts use
    #   new Database("/data/todos.db")
    # and uncomment:
    # volumes: ["todos-data:/data"]
# volumes: { todos-data: {} }

"""##,
                "backend/server.ts": ##"""
// Bun + bun:sqlite Todos CRUD API — zero npm installs. Run: bun run server.ts
import { Database } from "bun:sqlite";

const db = new Database(":memory:"); // ephemeral; re-seeded each container start
db.run(`CREATE TABLE todos (
  id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)`);
const seed = db.prepare("INSERT INTO todos (title, done) VALUES (?, ?)");
seed.run("Read the SwiflowQuery guide", 1);
seed.run("Wire a real CRUD API", 0);
seed.run("Watch optimistic updates reconcile", 0);

type Row = { id: number; title: string; done: number };
const toTodo = (r: Row) => ({ id: r.id, title: r.title, done: r.done === 1 });

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};
const json = (b: unknown, status = 200) =>
  new Response(b === null ? null : JSON.stringify(b),
    { status, headers: { "Content-Type": "application/json", ...CORS } });

Bun.serve({
  port: 8080,
  async fetch(req) {
    const url = new URL(req.url); const path = url.pathname; const { method } = req;
    if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS }); // preflight
    if (method === "GET" && path === "/todos")
      return json((db.query("SELECT * FROM todos ORDER BY id").all() as Row[]).map(toTodo));
    if (method === "POST" && path === "/todos") {
      const { title } = (await req.json()) as { title?: string };
      if (!title || !title.trim()) return json({ error: "title required" }, 400);
      const info = db.prepare("INSERT INTO todos (title, done) VALUES (?, 0)").run(title.trim());
      return json(toTodo(db.query("SELECT * FROM todos WHERE id = ?").get(Number(info.lastInsertRowid)) as Row), 201);
    }
    const m = path.match(/^\/todos\/(\d+)$/);
    if (m) {
      const id = Number(m[1]);
      if (method === "PUT") {
        const { done } = (await req.json()) as { done?: boolean };
        if (!db.query("SELECT id FROM todos WHERE id = ?").get(id)) return json({ error: "not found" }, 404);
        db.prepare("UPDATE todos SET done = ? WHERE id = ?").run(done ? 1 : 0, id);
        return json(toTodo(db.query("SELECT * FROM todos WHERE id = ?").get(id) as Row));
      }
      if (method === "DELETE") {
        db.prepare("DELETE FROM todos WHERE id = ?").run(id);
        return new Response(null, { status: 204, headers: CORS });
      }
    }
    return json({ error: "not found" }, 404);
  },
});
console.log("{{NAME}} API on http://localhost:8080");

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Todo CRUD</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
    ]

    static func lookup(_ name: String) -> Template? {
        return all.first(where: { $0.name == name })
    }

    static var availableNames: [String] {
        return all.map(\.name)
    }
}
