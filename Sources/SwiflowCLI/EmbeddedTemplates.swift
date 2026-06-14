// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-templates.swift
//
// Source: examples/*/

enum EmbeddedTemplates {
    struct Template {
        let name: String
        let files: [String: String]
    }

    static let all: [Template] = [
        Template(
            name: "AsyncFetch",
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
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A Swiflow example demonstrating `.task(rerunOn:)` — Phase 20 async task effects.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A heading: **Async fetch demo**
- A paragraph that starts at **Status: idle** for one frame, flips to
  **Status: loading…** as the `.task` fires for `userID = 1`, then after ~400 ms
  shows **Status: loaded user #1**.
- A button: **Load next user** — each click increments `userID` (the `.task`'s
  `rerunOn:` dependency), which cancels the in-flight task and re-runs the effect:
  status goes `loading…` then `loaded user #N`.

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift

import SwiflowDOM

@MainActor @Component
final class {{NAME}} {
    // `state` is a flat status string for demo brevity:
    // "idle" | "loading…" | "loaded user #N".
    @State var userID: Int = 1
    @State var state: String = "idle"

    var body: VNode {
        div {
            h1("Async fetch demo")
            p("Status: \(state)")
            // The button is an action — clicking bumps `userID`, which is the
            // `.task`'s dependency, so the effect re-runs for the next user.
            button("Load next user", .on(.click) { self.userID += 1 })
        }
        .task(rerunOn: userID) {
            self.state = "loading…"
            try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
            self.state = "loaded user #\(self.userID)"
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { {{NAME}}() }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Async fetch demo</title>
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
@MainActor @Component
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
    static var scopedStyles: CSSSheet? = css {
        host { display("block"); maxWidth("760px"); margin("1.5rem auto"); padding("0 1rem") }
        rule("section") {
            border("1px solid color-mix(in oklab, CanvasText 15%, transparent)")
            borderRadius("8px"); padding("0.75rem 1rem"); margin("0 0 1rem 0")
        }
        rule("h2") { fontSize("1rem"); margin("0 0 0.5rem 0") }
        rule("button") {
            margin("0 0.35rem 0.35rem 0"); padding("0.3rem 0.7rem")
            border("1px solid color-mix(in oklab, CanvasText 25%, transparent)")
            borderRadius("6px"); background("Canvas"); color("CanvasText"); cursor("pointer")
        }
        rule("input") {
            padding("0.25rem 0.5rem"); border("1px solid color-mix(in oklab, CanvasText 25%, transparent)")
            borderRadius("6px"); background("Canvas"); color("CanvasText")
        }
        rule(".row") { display("flex"); gap("0.4rem"); alignItems("center"); flexWrap("wrap") }
        rule(".tag") { fontFamily("ui-monospace, monospace"); fontSize("0.8rem"); color("var(--text-dim, GrayText)") }
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
@MainActor @Component
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
    static var scopedStyles: CSSSheet? = #css("""
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
@MainActor @Component
final class AboutPopover {
    var body: VNode {
        div(.id("about-popover"),
            .attr("popover", "auto"),
            .class("info-card")) {
            h3("About Swiflow")
            p("Swift, compiled to WASM, with a reactive component model.",
              .class("body"))
            link("View on GitHub",
                 .attr("href", "https://github.com/aduchesneau/swiflow"),
                 .attr("target", "_blank"),
                 .attr("rel", "noopener"))
        }
    }
}

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowDOM
import JavaScriptKit

/// Counter — the {{NAME}} showcase root.
///
/// Wires the framework primitives + a curated set of modern HTML/CSS
/// surfaces. See the design spec for the full picture; in summary:
/// - `host { }` + Task-1 dual-selector class rules so scoped CSS hits the root.
/// - Native `<dialog>` for Sign In: focus trap, Escape-to-close, ::backdrop,
///   with a CSS-only open/close animation (`@starting-style` +
///   `transition-behavior: allow-discrete`). No JS, no View Transition —
///   gesture-immediate and robust across browsers.
/// - Popover API + anchor positioning for About (declarative — no Swift handler).
/// - `<details>` disclosure with animated open/close via `interpolate-size`.
/// - `color-mix` + `light-dark` system colors — auto-themes from OS.
/// - `@container` query on the card via the scoped `container(...)` primitive.
/// - `@property --accent` registered custom property, animated on increment.
@MainActor @Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showToast: Bool = false
    @State var showSignIn: Bool = false
    let greetingInput = Ref<JSObject>()
    let signInDialog = Ref<JSObject>()

    var body: VNode {
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
                button("Increment", .on(.click) { self.count += 1 })
                button("Show toast", .class("secondary"),
                       .on(.click) { self.showToast = true })
                button("Sign in…", .class("secondary"),
                       .on(.click) { self.openSignIn() })
            }

            div(.class("greeting-row")) {
                label("Greeting:", .attr("for", "g"))
                input(.id("g"), .value($greeting), .ref(greetingInput))
            }

            label(.class("checkbox-row")) {
                input(.attr("type", "checkbox"), .checked($celebrate))
                text(" Celebrate")
            }

            details(.class("inspector")) {
                summary("What's running here?")
                ul(.class("inspector-list")) {
                    li("Sign in… — opens a native <dialog> with a CSS open/close animation.")
                    li("ⓘ — opens an `auto` popover anchored via CSS Anchor Positioning.")
                    li("Show toast — mounts a `manual` popover with a 2.5s auto-dismiss.")
                }
            }

            // The toast sits mid-list, *before* the dialog, on purpose — to
            // demonstrate that a conditional child can live anywhere now. Each
            // builder `if`/`for` is one stable `.fragment` slot, so toggling the
            // toast off (its 2.5s auto-dismiss) empties its slot without shifting
            // the dialog's slot — the dialog is never recreated. (This is what
            // the "Toast auto-dismiss does not close an open dialog" e2e proves.)
            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }

            embed { AboutPopover() }

            // Dismissal paths: Escape (native <dialog> behavior), Cancel /
            // Sign out / Close buttons inside SignIn. Backdrop-click-to-close
            // is omitted because EventInfo doesn't expose `event.target`
            // identity, and a generic .on(.click) on the dialog catches
            // every click that bubbles up from the form content.
            dialog(.ref(signInDialog), .class("signin-dialog")) {
                if showSignIn {
                    embed { SignIn(onClose: { self.closeSignIn() }) }
                }
            }
        }
    }

    func onAppear() {
        if let el = greetingInput.wrappedValue { _ = el.focus?() }
    }

    // Open/close are synchronous and tied directly to the click gesture — the
    // dialog appears the same frame, and the fade/slide is handled entirely in
    // CSS (see Counter+Styles.swift). showModal() must run before the @State
    // change schedules its render so the [open] transition fires immediately.
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
    static var scopedStyles: CSSSheet? = tokens + layout + theme + animations + responsive

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
    // The component root carries .card itself, so that rule compounds with
    // the scope class via `&.card`; :host styles the same element at the
    // lower specificity the DSL's host {} block had.
    static let layout = #css("""
        :host {
          display: block;
          max-width: 520px;
          margin: 2.5rem auto;
          padding: 2rem;
          container-type: inline-size;
        }
        &.card {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          padding: 1.75rem;
          border-radius: 16px;
          background: var(--surface);
          border: 1px solid var(--border);
          box-shadow: 0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25);
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
        .greeting-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
        }
        .greeting-row input {
          flex: 1;
          padding: 0.4rem 0.6rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: Canvas;
          color: CanvasText;
        }
        .checkbox-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
          cursor: pointer;
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
    static let theme = #css("""
        .count {
          margin: 0;
          font-size: 1.6rem;
          font-weight: 600;
          color: var(--accent);
          transition: --accent .25s ease;
        }
        button {
          padding: 0.4rem 0.9rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--accent);
          color: Canvas;
          cursor: pointer;
          font-size: 0.95rem;
        }
        .secondary {
          background: transparent;
          color: var(--text);
        }
        button:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }
        input:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }
        .checkbox-row:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
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
        .signin-dialog .signin {
          padding: 1.5rem;
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
        :host {
          animation: counter-in 0.3s ease forwards;
        }
        """)

    // ---- responsive ----
    // @container nests inside the scope wrapper, so its rules stay scoped
    // through the normal pipeline — no hand-pasted `.swiflow-Counter` prefix
    // and no coupling to the scope-class naming scheme.
    static let responsive = #css("""
        @container (max-width: 380px) {
          .actions {
            flex-direction: column;
            align-items: stretch;
          }
          &.card {
            padding: 1.25rem;
            gap: 0.75rem;
          }
        }
        """)
}

"""##,
                "Sources/App/SignIn+Styles.swift": ##"""
// Sources/App/SignIn+Styles.swift
import Swiflow

extension SignIn {
    // The component root carries .signin itself, so the rule compounds with
    // the scope class via `&.signin` (what the DSL's dual emission matched).
    static var scopedStyles: CSSSheet? = #css("""
        &.signin {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          max-width: 320px;
          font-family: system-ui, sans-serif;
        }
        .title {
          margin: 0;
          font-size: 1.25rem;
        }
        .field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        input {
          padding: 0.4rem 0.6rem;
          border: 1px solid color-mix(in oklab, CanvasText 18%, transparent);
          border-radius: 6px;
          background: Canvas;
          color: CanvasText;
          font-size: 0.9375rem;
          accent-color: CanvasText;
        }
        input:focus-visible {
          outline: 2px solid color-mix(in oklab, CanvasText 50%, blue);
          outline-offset: 2px;
        }
        .error {
          margin: 0.125rem 0 0 0;
          color: oklch(.55 .2 25);
          font-size: 0.85rem;
        }
        .welcome {
          margin: 0;
          font-size: 1rem;
        }
        .actions {
          display: flex;
          gap: 0.5rem;
        }
        button {
          padding: 0.4rem 0.9rem;
          border: 1px solid color-mix(in oklab, CanvasText 18%, transparent);
          border-radius: 6px;
          background: color-mix(in oklab, Canvas 90%, CanvasText);
          color: CanvasText;
          cursor: pointer;
          font-size: 0.9375rem;
        }
        button:focus-visible {
          outline: 2px solid color-mix(in oklab, CanvasText 50%, blue);
          outline-offset: 2px;
        }
        .secondary {
          background: transparent;
        }
        button[disabled] {
          opacity: 0.5;
          cursor: not-allowed;
        }
        """)
}

"""##,
                "Sources/App/SignIn.swift": ##"""
// Sources/App/SignIn.swift
import Swiflow

/// SignIn — Phase 12b form validation demo, now hosted inside Counter's
/// <dialog>. All inline .style(...) calls migrated to SignIn+Styles.swift.
@MainActor @Component
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

        return div(.class("signin")) {
            if submitted {
                p("Signed in as \(email)!", .class("welcome"))
                div(.class("actions")) {
                    button("Sign out", .class("secondary"), .on(.click) {
                        self.submitted = false
                        self.email = ""
                        self.password = ""
                        self.ctrl = FormController()
                    })
                    button("Close", .on(.click) { self.onClose() })
                }
            } else {
                h2("Sign In", .class("title"))

                div(.class("field")) {
                    label("Email", .attr("for", "signin-email"))
                    input(.id("signin-email"),
                          .attr("type", "email"),
                          .value($email),
                          .on(.blur) { em.markTouched() })
                    if em.touched, let err = em.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("field")) {
                    label("Password", .attr("for", "signin-password"))
                    input(.id("signin-password"),
                          .attr("type", "password"),
                          .value($password),
                          .on(.blur) { pw.markTouched() })
                    if pw.touched, let err = pw.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("actions")) {
                    button("Sign In",
                           .attr("disabled", !form.isValid),
                           .on(.click) {
                               form.touchAll()
                               guard form.isValid else { return }
                               self.submitted = true
                           })
                    button("Reset", .class("secondary"), .on(.click) { form.reset() })
                    button("Cancel", .class("secondary"), .on(.click) { self.onClose() })
                }
            }
        }
    }
}

"""##,
                "Sources/App/Toast+Styles.swift": ##"""
// Sources/App/Toast+Styles.swift
import Swiflow

extension Toast {
    static var scopedStyles: CSSSheet? = layout + theme + animations

    static let layout = #css("""
        :host {
          position: fixed;
          inset-block-end: 1.5rem;
          inset-inline: 0;
          margin-inline: auto;
          width: max-content;
          max-width: min(90vw, 360px);
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.75rem 1rem;
          /* Popover top-layer rendering resets these — set them explicitly. */
          margin: auto auto 1.5rem auto;
          inset: auto 0 0 0;
          border: 0;
        }
        .icon {
          display: grid;
          place-items: center;
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 50%;
          font-size: 0.8rem;
        }
        """)

    static let theme = #css("""
        :host {
          background: color-mix(in oklab, Canvas 88%, CanvasText);
          color: CanvasText;
          border-radius: 999px;
          border: 1px solid color-mix(in oklab, CanvasText 12%, transparent);
          box-shadow: 0 12px 32px -12px rgb(0 0 0 / .35), 0 2px 6px -2px rgb(0 0 0 / .15);
          font-size: 0.9375rem;
        }
        .icon {
          background: color-mix(in oklab, currentColor 18%, transparent);
        }
        """)

    static let animations = #css("""
        @keyframes toast-in {
          from { opacity: 0; transform: translateY(12px) scale(.96); }
          to   { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes toast-out {
          to { opacity: 0; transform: translateY(12px) scale(.98); }
        }
        :host {
          animation: toast-in .22s cubic-bezier(.2,.7,.2,1) forwards;
        }
        """)
}

"""##,
                "Sources/App/Toast.swift": ##"""
// Sources/App/Toast.swift
import Swiflow
import SwiflowDOM
import JavaScriptKit

/// Toast — top-layer notification using the Popover API.
///
/// - `popover="manual"` keeps the toast on the top layer without
///   light-dismiss (other clicks aren't hijacked).
/// - Auto-dismisses after 2.5s via `after(_:do:)`; the timer is cancelled
///   in `onDisappear` so an early parent unmount doesn't fire `onDone`.
/// - `exitAnimation` / `exitDuration` still drive the exit animation when
///   the parent toggles `showToast = false`.
@MainActor @Component
final class Toast {
    let message: String
    let onDone: () -> Void
    let root = Ref<JSObject>()
    var dismissTimer: TimerHandle?

    init(message: String, onDone: @escaping () -> Void) {
        self.message = message
        self.onDone = onDone
    }

    static var exitAnimation: String? = "toast-out 0.2s ease forwards"
    static var exitDuration: Double?  = 0.2

    var body: VNode {
        div(.attr("popover", "manual"),
            .attr("role", "status"),
            .attr("aria-live", "polite"),
            .ref(root),
            .on(.click) { self.onDone() }) {
            span(.class("icon"), .attr("aria-hidden", "true")) { text("\u{2713}") }
            text(message)
        }
    }

    func onAppear() {
        if let el = root.wrappedValue {
            _ = el.showPopover?()
        }
        dismissTimer = after(2.5) { [weak self] in self?.onDone() }
    }

    func onDisappear() {
        dismissTimer?.cancel()
        dismissTimer = nil
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
            name: "MiniRouter",
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
                .product(name: "SwiflowRouter", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A Swiflow project demonstrating client-side routing with `SwiflowRouter`.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A navbar with **Home**, **About**, and **Users** links.
- Clicking a link swaps the page content without a full reload — the
  router renders the matching `Route` from `Sources/App/App.swift`.
- `/users/:id` shows a dynamic `:id` segment via `ctx.params["id"]`.

"""##,
                "Sources/App/App.swift": ##"""
import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in
                    UsersPage(userId: ctx.params["id"] ?? "unknown")
                }
            }
        }
    }
}

"""##,
                "Sources/App/NavBar.swift": ##"""
import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

final class NavBar: Component {
    var body: VNode {
        nav {
            embed { Link("/", "Home") }
            embed { Link("/about", "About") }
            embed { Link("/users/42", "User 42") }
        }
    }
}

"""##,
                "Sources/App/Pages/AboutPage.swift": ##"""
import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        // Accessing self.router from a click handler (outside body) would see the
        // default no-op.
        let back = router.back
        return div {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
            button("Back", .on(.click) { _ in back() })
        }
    }
}

"""##,
                "Sources/App/Pages/HomePage.swift": ##"""
import Swiflow
import SwiflowDOM
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("Home")
            p("Welcome to the {{NAME}} demo.")
        }
    }
}

"""##,
                "Sources/App/Pages/UsersPage.swift": ##"""
import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

final class UsersPage: Component {
    let userId: String
    @Environment(\.router) var router

    init(userId: String) {
        self.userId = userId
    }

    var body: VNode {
        // Read router.navigate HERE inside body, where AmbientEnvironment.current
        // is set by the diff. Accessing self.router from a click handler (outside
        // body) would see the default no-op.
        let navigate = router.navigate
        return div {
            embed { NavBar() }
            h1("User: \(userId)")
            p("Loaded via the :id route param.")
            button("Go Home", .on(.click) { _ in navigate("/") })
        }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{NAME}}</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; }
      nav { display: flex; gap: 1rem; margin-bottom: 2rem; border-bottom: 1px solid #ccc; padding-bottom: 1rem; }
      nav a { text-decoration: none; color: #0070f3; }
      nav a:hover { text-decoration: underline; }
      button { padding: 0.4rem 1rem; cursor: pointer; }
    </style>
  </head>
  <body>
    <div id="app"></div>

    <!-- The Swiflow driver script owns WASM initialisation.
         It dynamically imports the PackageToJS module and calls init()
         so no <script type="module"> block is needed here. -->
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
        "/data/reverse-geocode-client?latitude=\(latitude)&longitude=\(longitude)&localityLanguage=en"
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

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { WeatherPage() }
                Route("/quakes") { QuakesPage() }
            }
        }
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
/// styling targets `nav a` from the scoped sheet rather than per-link classes.
final class NavBar: Component {
    static var scopedStyles: CSSSheet? = css {
        // `host {}` — the <nav> is the component root, and scoped `rule(...)`
        // selectors only reach descendants.
        host {
            display("flex")
            alignItems("center")
            gap("var(--sw-space-sm)")
            padding("var(--sw-space-sm) var(--sw-space-md)")
            borderBottom("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)")
        }
        rule("a") {
            color("var(--sw-text)")
            textDecoration("none")
            padding("var(--sw-space-xs) var(--sw-space-md)")
            borderRadius("var(--sw-radius)")
        }
        rule("a:hover") {
            background("color-mix(in srgb, var(--sw-accent) 15%, transparent)")
        }
        rule(".brand") {
            fontWeight("700")
            marginRight("var(--sw-space-md)")
        }
    }

    var body: VNode {
        nav {
            span(.class("brand")) { text("🌍 Mission Control") }
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
struct QuakeFeedQuery: Query {
    let magnitude: String   // "all" | "1.0" | "2.5" | "4.5" | "significant"
    let window: String      // "hour" | "day" | "week"

    var queryKey: QueryKey { ["quakes", .string(magnitude), .string(window)] }
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

/// One feed row. A plain VNode factory (not a component) so the list can key
/// rows directly with `.key(quake.id)`.
@MainActor
func quakeRow(_ quake: Quake, nowMs: Double) -> VNode {
    let mag = quake.properties.mag
    return li(.key(quake.id), .class("quake-row")) {
        span(.class("mag \(magnitudeClass(mag))")) {
            text(mag.map { "M \(($0 * 10).rounded() / 10)" } ?? "M ?")
        }
        span(.class("place")) { text(quake.properties.place ?? "Unknown location") }
        span(.class("when")) { text(relativeTime(fromMs: quake.properties.time, nowMs: nowMs)) }
    }
}

/// Badge color bucket: calm below M3, watchful to M5, alarming above.
func magnitudeClass(_ mag: Double?) -> String {
    switch mag ?? 0 {
    case ..<3:   "mag-low"
    case ..<5:   "mag-mid"
    default:     "mag-high"
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
    static var scopedStyles: CSSSheet? = #css("""
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

        .filters select {
          padding: var(--sw-space-xs) var(--sw-space-sm);
          border-radius: var(--sw-radius);
          font: inherit;
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

        .mag {
          justify-self: start;
          padding: 2px var(--sw-space-sm);
          border-radius: 999px;
          font-size: 0.8rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .mag-low {
          background: color-mix(in srgb, light-dark(#16a34a, #4ade80) 18%, transparent);
          color: light-dark(#166534, #4ade80);
        }
        .mag-mid {
          background: color-mix(in srgb, light-dark(#d97706, #fbbf24) 18%, transparent);
          color: light-dark(#92400e, #fbbf24);
        }
        .mag-high {
          background: color-mix(in srgb, light-dark(#dc2626, #f87171) 22%, transparent);
          color: light-dark(#991b1b, #f87171);
        }

        @keyframes mc-spin {
          to { transform: rotate(360deg); }
        }
        .live-dot {
          display: inline-block;
          color: var(--sw-accent);
          animation: mc-spin 1s linear infinite;
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

@MainActor @Component
final class QuakesPage {
    @State var magnitude: String = "2.5"
    @State var window: String = "day"
    /// Wall-clock anchor for relative timestamps, ticked by the bare `.task`.
    @State var nowMs: Double = 0

    /// The filter selections outlive this page (the router recreates it on every
    /// navigation), so they're persisted to IndexedDB and rehydrated on mount —
    /// the @State values above are just first-visit defaults.
    private let store = PersistentStore()
    private static let magnitudeKey = "quakes-magnitude"
    private static let windowKey = "quakes-window"

    var body: VNode {
        let feed = query(QuakeFeedQuery(magnitude: magnitude, window: window))
        return VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("🌐 Live seismic feed")
                if feed.isFetching {
                    span(.class("live-dot"), .attr("title", "refreshing")) { text("⟳") }
                }
            }

            HStack(spacing: .sm, align: .center, .class("filters")) {
                label("Magnitude", .attr("for", "mag"))
                // The `selected` attrs mirror the initial @State: at mount the
                // select's bound `value` property lands before its <option>
                // children, so without them the browser falls back to the
                // first option.
                select(.id("mag"), .selection($magnitude)) {
                    option("All", .attr("value", "all"))
                    option("M1.0+", .attr("value", "1.0"))
                    option("M2.5+", .attr("value", "2.5"), .attr("selected", ""))
                    option("M4.5+", .attr("value", "4.5"))
                    option("Significant", .attr("value", "significant"))
                }
                label("Window", .attr("for", "win"))
                select(.id("win"), .selection($window)) {
                    option("Past hour", .attr("value", "hour"))
                    option("Past day", .attr("value", "day"), .attr("selected", ""))
                    option("Past week", .attr("value", "week"))
                }
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
        // Rehydrate the saved filter selections on mount.
        .task { await self.hydrate() }
    }

    private func hydrate() async {
        if let m = try? await store.load(String.self, forKey: Self.magnitudeKey) { magnitude = m }
        if let w = try? await store.load(String.self, forKey: Self.windowKey) { window = w }
    }

    /// Persist each filter when it changes. `onChange(of:)` seeds silently on the
    /// first call and fires only on a real change, so neither write clobbers the
    /// value `hydrate()` restores. Distinct `key:`s — the default `#function`
    /// would collide between the two calls.
    func onChange() {
        onChange(of: magnitude, key: "magnitude") { m in
            Task { try? await self.store.save(m, forKey: Self.magnitudeKey) }
        }
        onChange(of: window, key: "window") { w in
            Task { try? await self.store.save(w, forKey: Self.windowKey) }
        }
    }
}

"""##,
                "Sources/App/Weather/CityCard+Styles.swift": ##"""
// Sources/App/Weather/CityCard+Styles.swift
import Swiflow

extension CityCard {
    static var scopedStyles: CSSSheet? = css {
        host {
            display("block")
            property("min-width", "200px")
            padding("var(--sw-space-md) var(--sw-space-lg)")
            borderRadius("calc(var(--sw-radius) * 1.5)")
            background("var(--sw-surface)")
            border("1px solid color-mix(in srgb, var(--sw-text) 12%, transparent)")
            boxShadow("0 16px 32px -24px rgb(0 0 0 / .35)")
        }
        rule(".city-name") {
            fontSize("1.05rem")
            margin("0")
        }
        rule(".temp") {
            fontSize("2.2rem")
            fontWeight("700")
            lineHeight("1")
        }
        rule(".wmo") {
            fontSize("1.6rem")
        }
        rule(".wmo-label, .range") {
            margin("0")
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            fontSize("0.85rem")
        }
        rule(".unpin") {
            border("none")
            background("transparent")
            color("color-mix(in srgb, var(--sw-text) 50%, transparent)")
            cursor("pointer")
            fontSize("0.9rem")
            padding("0 var(--sw-space-xs)")
        }
        rule(".unpin:hover") {
            color("light-dark(#b91c1c, #fca5a5)")
        }
        rule(".live-dot") {
            color("var(--sw-accent)")
            fontSize("0.9rem")
        }
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
            margin("0")
        }
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
@MainActor @Component
final class CityCard {
    let city: City
    let unit: String
    let onUnpin: () -> Void

    init(city: City, unit: String, onUnpin: @escaping () -> Void) {
        self.city = city
        self.unit = unit
        self.onUnpin = onUnpin
    }

    var body: VNode {
        let weather = query(CurrentWeatherQuery(city: city, unit: unit))
        return VStack(spacing: .sm, .class("city-card")) {
            HStack(spacing: .sm, align: .center, justify: .between) {
                h2(city.name, .class("city-name"))
                button("✕", .class("unpin"),
                       .attr("aria-label", "Unpin \(city.name)"),
                       .on(.click) { self.onUnpin() })
            }
            if let f = weather.data {
                let wmo = wmoDescription(f.current.weatherCode)
                HStack(spacing: .sm, align: .center) {
                    span(.class("temp")) {
                        text("\(Int(f.current.temperature.rounded()))\(f.currentUnits.temperature)")
                    }
                    span(.class("wmo"), .attr("title", wmo.label)) { text(wmo.emoji) }
                    if weather.isFetching {
                        span(.class("live-dot")) { text("⟳") }
                    }
                }
                p(wmo.label, .class("wmo-label"))
                if let high = f.daily.highs.first, let low = f.daily.lows.first {
                    p("H \(Int(high.rounded()))° · L \(Int(low.rounded()))° · wind \(Int(f.current.windSpeed.rounded())) km/h",
                      .class("range"))
                }
            } else if weather.isLoading {
                p("…", .class("temp"))
            } else if weather.error != nil {
                p("offline", .class("error"))
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
    static var scopedStyles: CSSSheet? = layout + theme

    static let layout = css {
        host {
            display("block")
            maxWidth("860px")
            margin("0 auto")
            padding("0 var(--sw-space-lg) var(--sw-space-xl)")
        }
        rule("h1") {
            fontSize("1.4rem")
            margin("0")
        }
        rule(".search-box input") {
            width("100%")
            property("box-sizing", "border-box")
            padding("var(--sw-space-sm) var(--sw-space-md)")
            borderRadius("var(--sw-radius)")
            fontSize("1rem")
        }
        rule(".search-results") {
            listStyle("none")
            margin("0")
            padding("var(--sw-space-xs)")
            display("flex")
            flexDirection("column")
            gap("var(--sw-space-xs)")
        }
        rule(".search-hit") {
            width("100%")
            textAlign("left")
            padding("var(--sw-space-xs) var(--sw-space-md)")
            borderRadius("var(--sw-radius)")
            cursor("pointer")
        }
    }

    static let theme = css {
        rule(".search-box input") {
            border("1px solid color-mix(in srgb, var(--sw-text) 20%, transparent)")
            background("var(--sw-surface)")
            color("var(--sw-text)")
        }
        rule(".search-results") {
            background("var(--sw-surface)")
            border("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)")
            borderRadius("var(--sw-radius)")
        }
        rule(".search-hit") {
            border("none")
            background("transparent")
            color("var(--sw-text)")
            property("font", "inherit")
        }
        rule(".search-hit:hover") {
            background("color-mix(in srgb, var(--sw-accent) 15%, transparent)")
        }
        rule(".search-status") {
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            margin("0")
        }
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
            margin("0")
        }
        rule(".unit-select") {
            padding("var(--sw-space-xs) var(--sw-space-sm)")
            borderRadius("var(--sw-radius)")
            property("font", "inherit")
        }
    }
}

"""##,
                "Sources/App/Weather/WeatherPage.swift": ##"""
// Sources/App/Weather/WeatherPage.swift
//
// Pinned-city weather over Open-Meteo. Demonstrates:
// - `.task(rerunOn:)` as a debouncer — 300 ms after the last keystroke the
//   raw input text is committed to `debouncedText`; superseded sleeps are
//   cancelled and their writes dropped by the runtime,
// - a conditional, text-keyed geocoding query (one request per settled
//   prefix, cached for an hour),
// - per-card weather queries keyed on (city, unit) — toggling °C → °F
//   refetches, toggling back paints instantly from cache,
// - SwiflowUI stacks + tokens for the whole layout.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowStore
import SwiflowUI

@MainActor @Component
final class WeatherPage {
    @State var searchText: String = ""
    @State var debouncedText: String = ""
    @State var pinned: [City] = City.seeds
    @State var unit: String = "celsius"

    /// Pins and the unit toggle outlive this page: the router destroys
    /// `WeatherPage` on every navigation, so they're persisted to IndexedDB and
    /// rehydrated on mount. `City.seeds` / "celsius" are just first-visit defaults.
    private let store = PersistentStore()
    private static let pinnedKey = "pinned-cities"
    private static let unitKey = "weather-unit"

    var body: VNode {
        let results: QueryState<GeoSearchResponse>? =
            debouncedText.count >= 2 ? query(CitySearchQuery(name: debouncedText)) : nil

        return VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("🌍 Weather")
                select(.class("unit-select"), .selection($unit)) {
                    option("°C", .attr("value", "celsius"))
                    option("°F", .attr("value", "fahrenheit"))
                }
            }

            VStack(spacing: .xs, .class("search-box")) {
                input(.attr("type", "search"),
                      .attr("placeholder", "Search a city to pin…"),
                      .value($searchText))
                if let results {
                    if let cities = results.data?.results, !cities.isEmpty {
                        ul(.class("search-results")) {
                            for city in cities {
                                li(.key("hit-\(city.id)")) {
                                    button(city.fullName, .class("search-hit"),
                                           .on(.click) { self.pin(city) })
                                }
                            }
                        }
                    } else if results.isLoading {
                        p("Searching…", .class("search-status"))
                    } else if results.error != nil {
                        p("Search unavailable — check your connection.", .class("error"))
                    } else {
                        p("No matches for “\(debouncedText)”.", .class("search-status"))
                    }
                }
            }

            HStack(spacing: .md, .class("card-grid"), .style("flex-wrap", "wrap")) {
                for city in pinned {
                    // Embedded instances are reused at a (type, key) position —
                    // the factory runs on first mount only, so a changed prop
                    // never reaches a live instance. Encoding `unit` in the
                    // embed key remounts the card on toggle; the cache (keyed
                    // on city + unit) makes the swap back instant.
                    div(.key("city-\(city.id)")) {
                        embed("card-\(city.id)-\(unit)") {
                            CityCard(city: city, unit: self.unit,
                                     onUnpin: { self.unpin(city) })
                        }
                    }
                }
            }
            if pinned.isEmpty {
                p("Nothing pinned — search above to add a city.", .class("search-status"))
            }
        }
        // Debounce: each keystroke re-keys this task; the previous sleep is
        // cancelled and only a 300 ms-settled value reaches `debouncedText`.
        .task(rerunOn: searchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.debouncedText = self.searchText
        }
        // Runs once per mount (i.e. on every return to this page): rehydrate the
        // saved pins, then refresh the geolocated first card.
        .task { await self.bootstrap() }
    }

    func pin(_ city: City) {
        if !pinned.contains(where: { $0.id == city.id }) {
            pinned.append(city)
        }
        searchText = ""
        debouncedText = ""
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
            Task { try? await self.store.save(newUnit, forKey: Self.unitKey) }
        }
    }

    // MARK: - Persistence + geolocation

    /// Restore persisted pins + unit (keeping the defaults only on a first-ever
    /// visit), then ask the browser for the current location and pin it first.
    private func bootstrap() async {
        if let saved = try? await store.load([City].self, forKey: Self.pinnedKey) {
            pinned = saved
        }
        if let savedUnit = try? await store.load(String.self, forKey: Self.unitKey) {
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
        Task { try? await store.save(pinned, forKey: Self.pinnedKey) }
    }
}

"""##,
                "Sources/App/Weather/WeatherQueries.swift": ##"""
// Sources/App/Weather/WeatherQueries.swift
import SwiflowQuery

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// Percent-encode a user-typed query for a URL. Foundation's
/// `addingPercentEncoding` isn't available under WASM, so this defers to the
/// browser's `encodeURIComponent`. (Host fallback is identity — the host
/// build only typechecks, it never fetches.)
func urlEncoded(_ s: String) -> String {
    #if canImport(JavaScriptKit)
    return JSObject.global.encodeURIComponent.function?(s).string ?? s
    #else
    return s
    #endif
}

/// Geocode a (debounced) city-name fragment. The caller gates on
/// `name.count >= 2`; `query()` is render-scoped, so a query simply not
/// observed this render drops its subscription — conditional calls are fine.
struct CitySearchQuery: Query {
    let name: String

    var queryKey: QueryKey { ["geocode", .string(name.lowercased())] }
    /// Place names don't move; retyping the same prefix within the hour is a
    /// pure cache hit.
    var staleTime: Duration { .seconds(3600) }

    func fetch() async throws -> GeoSearchResponse {
        try await API.geocoding.get("/v1/search?name=\(urlEncoded(name))&count=5")
    }
}

/// Current conditions + today's range for one pinned city. Keyed on
/// (city id, unit) — `latitude`/`longitude` ride along as captured
/// dependencies, excluded from the key per the `Query` contract.
struct CurrentWeatherQuery: Query {
    let city: City
    let unit: String   // "celsius" | "fahrenheit"

    var queryKey: QueryKey { ["weather", .int(city.id), .string(unit)] }
    var tags: Set<QueryTag> { ["weather"] }

    /// Fresh for a minute: re-renders, re-pins, and tab switches inside that
    /// window paint from cache with zero requests.
    var staleTime: Duration { .seconds(60) }
    /// Background refresh every 5 minutes while a card is on screen.
    var refetchInterval: Duration? { .seconds(300) }

    func fetch() async throws -> Forecast {
        try await API.forecast.get(
            "/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)"
            + "&current=temperature_2m,weather_code,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&temperature_unit=\(unit)"
        )
    }
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

struct UserByID: Query {
    let id: Int
    let api: FakeAPI
    var queryKey: QueryKey { ["users", .int(id)] }
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }

    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}

struct RenameUser: Mutation {
    let id: Int
    let api: FakeAPI

    func perform(_ newName: String) async throws -> User {
        try await api.renameUser(id, name: newName)
    }

    func optimistic(_ newName: String) -> [OptimisticEdit] {
        let id = self.id
        return [.update(UserByID(id: id)) { _ in User(id: id, name: newName) }]
    }

    func invalidations(input: String, output: User) -> [Invalidation] {
        [.exact(["users", .int(id)])]
    }
}

@MainActor @Component
final class {{NAME}} {
    @State var userID: Int = 1
    @State var newName: String = ""
    @MutationState var rename: RenameUser

    init() {
        self.rename = RenameUser(id: 1, api: FakeAPI())
    }

    var body: VNode {
        let u = query(UserByID(id: userID))
        // Keep rename mutation in sync with the current userID.
        self.rename = RenameUser(id: userID, api: FakeAPI())
        return div {
            h1("Query demo")
            div {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { span { text(" ⟳") } }
            }
            button("Next user", .on(.click) { self.userID += 1 })
            div {
                h2("Rename user")
                input(.value($newName), .on(.input) { self.newName = $0.targetValue ?? "" })
                button("Rename", .on(.click) { self.$rename.mutate(self.newName) },
                       .attr("disabled", $rename.isPending))
                if $rename.isPending { p("Renaming…") }
                if $rename.isError { p("Error renaming user.") }
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { {{NAME}}() }
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

## Spec

See [`docs/superpowers/specs/2026-06-03-swiflowui-foundation-design.md`](../../docs/superpowers/specs/2026-06-03-swiflowui-foundation-design.md) for the full design rationale.

"""##,
                "Sources/App/App.swift": ##"""
import Swiflow
import SwiflowDOM
import SwiflowUI

@MainActor @Component
final class Demo {
    @State var name: String = ""
    @State var email: String = ""
    @State var subscribed: Bool = false
    @State var color: String = ""
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let emailField = Field("email", $email, $ctrl, .required(), .email)

        return VStack(spacing: .lg, align: .stretch) {
            h1("SwiflowUI — primitives, buttons & forms")

            // --- Stacks --------------------------------------------------
            h2("Stacks")
            HStack(spacing: .md, align: .center) {
                Button("One") {}; Button("Two") {}; Button("Three") {}
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")

            p("The row above uses HStack(spacing: .md). Change --sw-space-md "
              + "in index.html's <style> to reskin every gap at once.")

            Divider()

            // --- Grid ----------------------------------------------------
            h2("Grid")
            Grid(columns: 3, spacing: .md) {
                for n in 1...6 { card("Cell \(n)") }
            }
            p("Grid(columns: 3, spacing: .md) — equal columns via "
              + "repeat(3, minmax(0, 1fr)).")

            Divider()

            // --- Spacer --------------------------------------------------
            h2("Spacer")
            HStack(align: .center) {
                Button("Leading", variant: .secondary) {}
                Spacer()
                Button("Trailing", variant: .secondary) {}
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")
            p("A Spacer() between the buttons pushes them to opposite ends.")

            Divider()

            // --- Buttons -------------------------------------------------
            h2("Buttons")
            HStack(spacing: .md, align: .center) {
                Button("Primary") {}
                Button("Secondary", variant: .secondary) {}
                Button("Ghost", variant: .ghost) {}
                Button("Disabled", disabled: true) {}
            }
            HStack(spacing: .md, align: .center) {
                Button("Small", size: .sm) {}
                Button("Medium", size: .md) {}
                Button("Large", size: .lg) {}
            }
            p("Variants and sizes are skinned entirely by --sw-* tokens. Toggle your "
              + "system dark mode / increased contrast / reduced motion to see the "
              + "@media token layers re-skin them with no code change.")

            Divider()

            // --- Form controls -------------------------------------------
            h2("Form controls")
            VStack(spacing: .md, align: .stretch) {
                TextField("Name", text: $name, placeholder: "Ada Lovelace")
                TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                Toggle("Subscribe to updates", isOn: $subscribed)
            }
            if !name.isEmpty { p("Hello, \(name)!\(subscribed ? " (subscribed)" : "")") }
            p("TextField binds to @State. The email field uses Field(...) + validators — "
              + "blur it empty (or with bad input) to see the role=alert error and aria-invalid.")
        }
        .padding(.xl)
    }

    /// A small surfaced tile used to fill the grid demo.
    private func card(_ title: String) -> VNode {
        div { text(title) }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border", "var(--sw-border-width) solid var(--sw-border)")
            .style("border-radius", "var(--sw-radius)")
            .style("text-align", "center")
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}

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

See the SwiflowQuery design in `docs/superpowers/specs/` and the lifecycle diagram in
`docs/diagrams/swiflow-update-lifecycle.html`.

"""##,
                "Sources/App/App.swift": ##"""
import SwiflowDOM
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

struct TodoList: Query {
    var queryKey: QueryKey { ["todos"] }
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }   // live polling against the real API
    func fetch() async throws -> [Todo] {
        try await api.get("/todos", as: [Todo].self)
    }
}

// MARK: - Mutations

struct AddTodo: Mutation {
    /// Monotonic temp-id source for optimistic rows (negative so it never
    /// collides with a real server id). The `["todos"]` refetch replaces it.
    static var tempSeq = -1

    func perform(_ title: String) async throws -> Todo {
        try await api.post("/todos", json: ["title": .string(title)], as: Todo.self)
    }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        let tmp = AddTodo.tempSeq; AddTodo.tempSeq -= 1
        return [.update(TodoList()) { $0 + [Todo(id: tmp, title: title, done: false)] }]
    }
    func invalidations(input: String, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

struct ToggleTodo: Mutation {
    struct Input: Sendable { let id: Int; let done: Bool }
    func perform(_ i: Input) async throws -> Todo {
        try await api.put("/todos/\(i.id)", json: ["done": .bool(i.done)], as: Todo.self)
    }
    func optimistic(_ i: Input) -> [OptimisticEdit] {
        [.update(TodoList()) { todos in
            todos.map { $0.id == i.id ? Todo(id: $0.id, title: $0.title, done: i.done) : $0 }
        }]
    }
    func invalidations(input: Input, output: Todo) -> [Invalidation] { [.exact(["todos"])] }
}

struct DeleteTodo: Mutation {
    func perform(_ id: Int) async throws {
        try await api.delete("/todos/\(id)")
    }
    func optimistic(_ id: Int) -> [OptimisticEdit] {
        [.update(TodoList()) { $0.filter { $0.id != id } }]
    }
    func invalidations(input: Int, output: Void) -> [Invalidation] { [.exact(["todos"])] }
}

// MARK: - Component

@MainActor @Component
final class TodoApp {
    @State var draft: String = ""
    @MutationState var add: AddTodo
    @MutationState var toggle: ToggleTodo
    @MutationState var remove: DeleteTodo

    init() {
        self.add = AddTodo()
        self.toggle = ToggleTodo()
        self.remove = DeleteTodo()
    }

    var body: VNode {
        let list = query(TodoList())
        return div {
            h1("Todo CRUD")
            p("Reads via query(); writes via @MutationState with optimistic updates — against a real Bun + SQLite API.")

            div {
                input(.value($draft), .attr("placeholder", "New todo…"),
                      .on(.input) { self.draft = $0.targetValue ?? "" })
                button("Add", .on(.click) {
                    let t = self.draft
                    guard !t.isEmpty, !t.allSatisfy(\.isWhitespace) else { return }
                    self.$add.mutate(t)
                    self.draft = ""
                }, .attr("disabled", $add.isPending))
                if list.isFetching { span { text(" ⟳ syncing…") } }
            }

            if list.isLoading { p("Loading…") }
            if let e = list.error { p("Failed to load: \(e)") }
            if $add.isError { p("Add failed.") }
            if $toggle.isError { p("Toggle failed.") }
            if $remove.isError { p("Delete failed.") }

            if let todos = list.data {
                ul {
                    for todo in todos {
                        li(.key("todo-\(todo.id)")) {
                            input(.attr("type", "checkbox"),
                                  .checked(Binding(get: { todo.done },
                                                   set: { self.$toggle.mutate(.init(id: todo.id, done: $0)) })))
                            span { text(todo.title) }
                            button("✕", .on(.click) { self.$remove.mutate(todo.id) })
                        }
                    }
                }
            }
        }
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
