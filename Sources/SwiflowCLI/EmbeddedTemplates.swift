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
    // SwiflowWeb itself only links Swiflow + JavaScriptKit and doesn't
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
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

import SwiflowWeb

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
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowWeb

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
import SwiflowWeb
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
    // SwiflowWeb itself only links Swiflow + JavaScriptKit and doesn't
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
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
    static var scopedStyles: CSSSheet? = css {
        rule(".info-card") {
            positionAnchor("--info-anchor")
            positionArea("bottom span-right")
            // Popover top-layer reset.
            margin("0.5rem 0 0 0")
            padding("0.75rem 1rem")
            background("color-mix(in oklab, Canvas 92%, CanvasText)")
            color("CanvasText")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            borderRadius("12px")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35)")
            maxWidth("280px")
            fontSize("0.9375rem")
        }
        rule("h3") {
            margin("0 0 0.25rem 0")
            fontSize("0.95rem")
            fontWeight("600")
        }
        rule(".body") {
            margin("0 0 0.5rem 0")
            color("color-mix(in oklab, CanvasText 80%, Canvas)")
        }
        rule("a") {
            color("color-mix(in oklab, CanvasText 70%, blue)")
            textDecoration("none")
        }
        rule("a:hover") { textDecoration("underline") }
    }
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
import SwiflowWeb
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
    static let tokens = css {
        raw("""
            @property --accent {
              syntax: "<color>";
              inherits: true;
              initial-value: oklch(.65 .14 250);
            }
            """)
        rule(":root") {
            cssVar("--accent", "light-dark(oklch(.55 .18 250), oklch(.75 .14 250))")
            cssVar("--surface", "light-dark(oklch(.99 0 0), oklch(.18 .005 250))")
            cssVar("--surface-elev", "light-dark(oklch(.97 0 0), oklch(.22 .005 250))")
            cssVar("--text", "CanvasText")
            cssVar("--text-dim", "color-mix(in oklab, CanvasText 65%, Canvas)")
            cssVar("--border", "color-mix(in oklab, CanvasText 12%, transparent)")
        }
    }

    // ---- layout ----
    static let layout = css {
        host {
            display("block")
            maxWidth("520px")
            margin("2.5rem auto")
            padding("2rem")
            containerType("inline-size")
        }
        rule(".card") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            padding("1.75rem")
            borderRadius("16px")
            background("var(--surface)")
            border("1px solid var(--border)")
            boxShadow("0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25)")
        }
        rule(".header") {
            display("flex")
            alignItems("center")
            justifyContent("space-between")
            gap("0.5rem")
            margin("0")
            padding("0")
            border("0")
        }
        rule(".greeting-heading") {
            margin("0")
            fontSize("1.4rem")
            fontWeight("600")
        }
        rule(".info-trigger") {
            anchorName("--info-anchor")
            display("grid")
            placeItems("center")
            width("1.75rem")
            height("1.75rem")
            borderRadius("50%")
            border("1px solid var(--border)")
            background("transparent")
            color("var(--text-dim)")
            cursor("pointer")
            fontSize("0.9rem")
        }
        rule(".actions") {
            display("flex")
            flexWrap("wrap")
            gap("0.5rem")
        }
        rule(".greeting-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
        }
        rule(".greeting-row input") {
            flex("1")
            padding("0.4rem 0.6rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
        }
        rule(".checkbox-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            cursor("pointer")
        }
        rule(".inspector") {
            border("1px solid var(--border)")
            borderRadius("10px")
            padding("0.5rem 0.75rem")
            interpolateSize("allow-keywords")
        }
        rule(".inspector summary") {
            cursor("pointer")
            listStyle("none")
            fontSize("0.95rem")
            color("var(--text-dim)")
        }
        rule(".inspector summary::-webkit-details-marker") {
            display("none")
        }
        rule(".inspector summary::before") {
            property("content", "\"▸ \"")
            display("inline-block")
            transition("transform .15s ease")
        }
        rule(".inspector[open] summary::before") {
            transform("rotate(90deg)")
        }
        rule(".inspector-list") {
            margin("0.5rem 0 0 0")
            padding("0 0 0 1.25rem")
            color("var(--text-dim)")
            fontSize("0.9rem")
        }
    }

    // ---- theme ----
    static let theme = css {
        rule(".count") {
            margin("0")
            fontSize("1.6rem")
            fontWeight("600")
            color("var(--accent)")
            transition("--accent .25s ease")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("var(--accent)")
            color("Canvas")
            cursor("pointer")
            fontSize("0.95rem")
        }
        rule(".secondary") {
            background("transparent")
            color("var(--text)")
        }
        rule("button:focus-visible") {
            outline("2px solid var(--accent)")
            outlineOffset("2px")
        }
        rule("input:focus-visible") {
            outline("2px solid var(--accent)")
            outlineOffset("2px")
        }
        rule(".checkbox-row:focus-visible") {
            outline("2px solid var(--accent)")
            outlineOffset("2px")
        }

        // <dialog> + ::backdrop styling, animated entirely in CSS — no JS, no
        // View Transition. A modal <dialog> moves through the top layer, so we
        // transition `overlay` and `display` with `allow-discrete` to keep the
        // element painted through its exit animation; `@starting-style` (below)
        // supplies the values it animates *from* on open.
        rule(".signin-dialog") {
            border("0")
            borderRadius("16px")
            padding("0")
            background("var(--surface-elev)")
            color("var(--text)")
            boxShadow("0 24px 48px -16px rgb(0 0 0 / .45)")
            maxWidth("min(90vw, 420px)")
            opacity("0")
            transform("translateY(8px) scale(.98)")
            transition("opacity .2s ease, transform .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete")
        }
        rule(".signin-dialog[open]") {
            opacity("1")
            transform("translateY(0) scale(1)")
        }
        rule(".signin-dialog .signin") {
            padding("1.5rem")
        }
        rule(".signin-dialog::backdrop") {
            background("color-mix(in oklab, Canvas 30%, transparent)")
            backdropFilter("blur(6px)")
            opacity("0")
            transition("opacity .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete")
        }
        rule(".signin-dialog[open]::backdrop") {
            opacity("1")
        }
        // Entry animation origin: without these, the dialog would pop in at full
        // opacity instead of fading/sliding from the closed state.
        startingStyle {
            rule(".signin-dialog[open]") {
                opacity("0")
                transform("translateY(8px) scale(.98)")
            }
            rule(".signin-dialog[open]::backdrop") {
                opacity("0")
            }
        }
    }

    // ---- animations ----
    static let animations = css {
        keyframes("counter-in") {
            from { opacity("0"); transform("translateY(-6px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        host {
            animation("counter-in 0.3s ease forwards")
        }
    }

    // ---- responsive ----
    // `container(...)` scopes its nested rules through the normal pipeline, so
    // there's no hand-pasted `.swiflow-Counter` prefix and no coupling to the
    // scope-class naming scheme — the framework owns that.
    static let responsive = css {
        container("(max-width: 380px)") {
            rule(".actions") {
                flexDirection("column")
                alignItems("stretch")
            }
            rule(".card") {
                padding("1.25rem")
                gap("0.75rem")
            }
        }
    }
}

"""##,
                "Sources/App/SignIn+Styles.swift": ##"""
// Sources/App/SignIn+Styles.swift
import Swiflow

extension SignIn {
    static var scopedStyles: CSSSheet? = css {
        rule(".signin") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            maxWidth("320px")
            fontFamily("system-ui, sans-serif")
        }
        rule(".title") {
            margin("0")
            fontSize("1.25rem")
        }
        rule(".field") {
            display("flex")
            flexDirection("column")
            gap("0.25rem")
        }
        rule("input") {
            padding("0.4rem 0.6rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
            fontSize("0.9375rem")
            accentColor("CanvasText")
        }
        rule("input:focus-visible") {
            outline("2px solid color-mix(in oklab, CanvasText 50%, blue)")
            outlineOffset("2px")
        }
        rule(".error") {
            margin("0.125rem 0 0 0")
            color("oklch(.55 .2 25)")
            fontSize("0.85rem")
        }
        rule(".welcome") {
            margin("0")
            fontSize("1rem")
        }
        rule(".actions") {
            display("flex")
            gap("0.5rem")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("color-mix(in oklab, Canvas 90%, CanvasText)")
            color("CanvasText")
            cursor("pointer")
            fontSize("0.9375rem")
        }
        rule("button:focus-visible") {
            outline("2px solid color-mix(in oklab, CanvasText 50%, blue)")
            outlineOffset("2px")
        }
        rule(".secondary") {
            background("transparent")
        }
        rule("button[disabled]") {
            opacity("0.5")
            cursor("not-allowed")
        }
    }
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

    static let layout = css {
        host {
            position("fixed")
            insetBlockEnd("1.5rem")
            insetInline("0")
            marginInline("auto")
            width("max-content")
            maxWidth("min(90vw, 360px)")
            display("flex")
            alignItems("center")
            gap("0.625rem")
            padding("0.75rem 1rem")
            // Popover top-layer rendering resets these — set them explicitly.
            margin("auto auto 1.5rem auto")
            inset("auto 0 0 0")
            border("0")
        }
        rule(".icon") {
            display("grid")
            placeItems("center")
            width("1.25rem")
            height("1.25rem")
            borderRadius("50%")
            fontSize("0.8rem")
        }
    }

    static let theme = css {
        host {
            background("color-mix(in oklab, Canvas 88%, CanvasText)")
            color("CanvasText")
            borderRadius("999px")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35), 0 2px 6px -2px rgb(0 0 0 / .15)")
            fontSize("0.9375rem")
        }
        rule(".icon") {
            background("color-mix(in oklab, currentColor 18%, transparent)")
        }
    }

    static let animations = css {
        keyframes("toast-in") {
            from { opacity("0"); transform("translateY(12px) scale(.96)") }
            to   { opacity("1"); transform("translateY(0) scale(1)") }
        }
        keyframes("toast-out") {
            to { opacity("0"); transform("translateY(12px) scale(.98)") }
        }
        host {
            animation("toast-in .22s cubic-bezier(.2,.7,.2,1) forwards")
        }
    }
}

"""##,
                "Sources/App/Toast.swift": ##"""
// Sources/App/Toast.swift
import Swiflow
import SwiflowWeb
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
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
import SwiflowWeb
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
import SwiflowWeb
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
import SwiflowWeb
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
import SwiflowWeb
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
import SwiflowWeb
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
    // SwiflowWeb itself only links Swiflow + JavaScriptKit and doesn't
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
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
import SwiflowWeb
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
                .product(name: "SwiflowQuery", package: "Swiflow"),
                // The fetch + JSON-decode story now lives in the SwiflowHTTP
                // module (graduated from this example's old Net.swift); it pulls
                // in JavaScriptKit/JavaScriptEventLoop transitively.
                .product(name: "SwiflowHTTP", package: "Swiflow"),
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
- The real `fetch` + JSON-decode idiom for WASM via the **`SwiflowHTTP`** module
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
import SwiflowWeb
import SwiflowQuery
import SwiflowHTTP

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
