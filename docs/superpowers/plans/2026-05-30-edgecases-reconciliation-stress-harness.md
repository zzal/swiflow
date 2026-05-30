# EdgeCases Stress Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `examples/EdgeCases` — an adversarial control-panel app of 11 isolated reconciliation "traps", each with a stateful sentinel — plus a Playwright spec that drives each trap and asserts the sentinel survived, to hunt edge-case bugs in the stable-child-slots reconciler.

**Architecture:** One `EdgeLab` root `@MainActor @Component` embeds 11 self-contained trap components (one file each). Each trap renders a `<section data-testid="trapN">` with controls (`@State` toggles/buttons) + a tricky nested structure + a sentinel whose interactive state (focus+value, `<details open>`, a tagged DOM property, a child `@State` counter, computed visibility, or unchanged DOM-node identity) is destroyed only on spurious recreation. A new `edgecases.spec.ts` drives each trap via `data-testid` and asserts the sentinel. The example is built **in-place** (`swiflow dev --path examples/EdgeCases`) for the e2e, then embedded as `swiflow init --template EdgeCases` at the end.

**Tech Stack:** Swift + SwiflowWeb (WASM), the Swiflow DSL (`@Component`, `@State`, `embed`, `if`/`for` builders, `.key`/`.data`/`.on` modifiers), Playwright (`@playwright/test`), `swiflow dev` CLI.

**Spec:** `docs/superpowers/specs/2026-05-30-edgecases-reconciliation-stress-harness-design.md`

---

## Conventions (apply in every trap)

- **Component shape:** `@MainActor @Component final class TrapN_Name { @State var …; var body: VNode { section(.data("testid", "trapN")) { h2("N. <title>"); /* controls */; /* trap structure */; /* sentinel */ } } }`. Types start with a letter (`Trap1CondBeforeFocus`), files match (`Trap1CondBeforeFocus.swift`).
- **Addressability:** section `data-testid="trapN"`; controls `trapN-<verb>` (e.g. `trap1-toggle`); sentinels `trapN-sentinel` / `trapN-input`.
- **Sentinels are UNCONTROLLED** (`input(.attr("type", "text"), .data("testid", …))` with NO value binding) — a controlled input would be re-set from state on re-render and mask recreation. We type into them from Playwright and check survival.
- **Detection (Playwright):** focus → `el === document.activeElement` + `el.value`; details → `open` attribute; tagged node → set `el.__tag = n` via `evaluate`, re-query, assert persists; child `@State` → a visible counter that resets to 0 on recreation; visibility → `getBoundingClientRect()` non-zero when state says visible.
- **Build/test loop:** the example builds in-place; the e2e command is `npm run test:edgecases` (added in Task 1). Filter SwiftPM noise in shell with `| grep -v "Internal Error: DecodingError"`. IGNORE stale SourceKit diagnostics — trust `swiflow build`/the e2e run. Port 3003 must be free for the e2e.
- **Commits** MUST end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (use `git commit -F -`).

## File Structure

**Create under `examples/EdgeCases/`:**
- `Package.swift` — copy of HelloWorld's, `name: "EdgeCases"`.
- `index.html` — copy of HelloWorld's, `<title>EdgeCases</title>`.
- `Sources/App/App.swift` — `EdgeLab` root component + `@main`.
- `Sources/App/Trap1CondBeforeFocus.swift` … `Trap11DynamicList.swift` — one trap each.
- `Sources/App/EdgeLab+Styles.swift` — minimal legible `scopedStyles` (no animation).

**Create under `Tests/playwright/`:**
- `playwright.edgecases.config.ts` — scaffolds nothing; builds `examples/EdgeCases` in-place on port 3003.
- `edgecases.spec.ts` — one `test` per trap.
- Modify `package.json` — add `"test:edgecases"` script.

**Modify at the end (Task 6):** `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerated, so `swiflow init --template EdgeCases` works).

---

## Task 1: Pipeline + skeleton + Trap 1 (prove the whole loop end-to-end)

De-risk first: scaffold the example with ONE real trap, wire the Playwright config, and get a green e2e before adding more.

**Files:** create all `examples/EdgeCases/` skeleton files + `Trap1CondBeforeFocus.swift`; create `Tests/playwright/playwright.edgecases.config.ts`, `edgecases.spec.ts`; modify `Tests/playwright/package.json`.

- [ ] **Step 1: Create `examples/EdgeCases/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeCases",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(path: "../.."),
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
```

- [ ] **Step 2: Create `examples/EdgeCases/index.html`** (HelloWorld's, retitled)

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>EdgeCases</title>
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
```

- [ ] **Step 3: Create `examples/EdgeCases/Sources/App/EdgeLab+Styles.swift`**

```swift
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
```

- [ ] **Step 4: Create `examples/EdgeCases/Sources/App/App.swift`** (root; embeds only Trap 1 for now)

```swift
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
```

- [ ] **Step 5: Create `examples/EdgeCases/Sources/App/Trap1CondBeforeFocus.swift`**

```swift
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
            // The conditional sits BEFORE the sentinel input.
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
```

- [ ] **Step 6: Create `Tests/playwright/playwright.edgecases.config.ts`**

```ts
// Tests/playwright/playwright.edgecases.config.ts
//
// Builds examples/EdgeCases IN-PLACE (swiflow dev --path …) on :3003 — no
// `swiflow init` scaffold, so the e2e tests the real example source directly
// (no template-embedding round-trip). Mirrors playwright.counter.config.ts's
// release-CLI-build guard.
import { defineConfig } from "@playwright/test";
import { existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");
const EXAMPLE_DIR = join(REPO_ROOT, "examples", "EdgeCases");

if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the e2e harness...");
  execFileSync("swift", ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" });
}

export default defineConfig({
  testDir: ".",
  testMatch: ["edgecases.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3003", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3003`,
      url: "http://127.0.0.1:3003",
      reuseExistingServer: false,
      timeout: 300_000, // cold WASM build
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
```

- [ ] **Step 7: Create `Tests/playwright/edgecases.spec.ts`** (helpers + Trap 1 test)

```ts
// Tests/playwright/edgecases.spec.ts
import { test, expect, type Page } from "@playwright/test";

// Type into a sentinel input and confirm it took focus.
async function focusType(page: Page, testid: string, value: string) {
  const input = page.getByTestId(testid);
  await input.click();
  await input.fill(value);
  return input;
}

test.describe("EdgeCases reconciliation traps", () => {
  test("trap1: conditional before focused input — focus+value survive toggle", async ({ page }) => {
    await page.goto("/");
    const input = await focusType(page, "trap1-input", "hello");
    // Toggle the conditional that sits BEFORE the input, twice.
    await page.getByTestId("trap1-toggle").click();
    await page.getByTestId("trap1-toggle").click();
    // The input must be the same node: still focused, still holding its value.
    await expect(input).toBeFocused();
    await expect(input).toHaveValue("hello");
  });
});
```

- [ ] **Step 8: Add the npm script** in `Tests/playwright/package.json` (alongside `test:counter`):

```json
    "test:edgecases": "playwright test --config=playwright.edgecases.config.ts",
```

- [ ] **Step 9: Confirm the example builds and the e2e is green**

Ensure port 3003 is free (`lsof -ti :3003 | xargs -r kill -9`). Then:
```bash
cd Tests/playwright && npm run test:edgecases 2>&1 | tail -20
```
Expected: 1 passed. (First run builds the release CLI if absent + cold WASM build — may take minutes.)

- [ ] **Step 10: Commit**

```bash
git add examples/EdgeCases Tests/playwright/playwright.edgecases.config.ts Tests/playwright/edgecases.spec.ts Tests/playwright/package.json
git commit -F -   # message:
# feat(examples): EdgeCases stress harness — scaffold + Trap 1 (cond before focus) + e2e pipeline
# Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## Task 2: Traps 2–4 (for-of-if, for-of-if-of-for, loop-in-conditional)

**Files:** create `Trap2ForOfIf.swift`, `Trap3ForIfFor.swift`, `Trap4LoopInCond.swift`; modify `App.swift` (embed them); modify `edgecases.spec.ts` (3 tests).

- [ ] **Step 1: Create `Trap2ForOfIf.swift`**

```swift
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
```

- [ ] **Step 2: Create `Trap3ForIfFor.swift`**

```swift
// Sources/App/Trap3ForIfFor.swift
import Swiflow

/// Trap 3: three-level imbrication — outer keyed list, per-item conditional,
/// inner keyed sub-list. Mutating one item's inner list must leave the other
/// outer items' inputs untouched.
@MainActor @Component
final class Trap3ForIfFor {
    @State var counts: [Int] = [1, 1]   // inner list length per outer item

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
```

- [ ] **Step 3: Create `Trap4LoopInCond.swift`**

```swift
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
```

- [ ] **Step 4: Embed traps 2–4 in `App.swift`** — add after the Trap 1 embed:

```swift
            embed { Trap2ForOfIf() }
            embed { Trap3ForIfFor() }
            embed { Trap4LoopInCond() }
```

- [ ] **Step 5: Add the three tests to `edgecases.spec.ts`** (inside the `describe`):

```ts
  test("trap2: for-of-if — toggling one item's flag preserves sibling inputs", async ({ page }) => {
    await page.goto("/");
    const sib = await focusType(page, "trap2-input-2", "keep-me");
    await page.getByTestId("trap2-toggle-0").click(); // mutate item 0's conditional
    await page.getByTestId("trap2-toggle-0").click();
    await expect(sib).toHaveValue("keep-me");
    await expect(sib).toBeFocused();
  });

  test("trap3: for-of-if-of-for — inner mutation leaves other outer items intact", async ({ page }) => {
    await page.goto("/");
    const other = await focusType(page, "trap3-input-1", "outer1");
    await page.getByTestId("trap3-add-0").click(); // grow item 0's inner list
    await page.getByTestId("trap3-add-0").click();
    await expect(other).toHaveValue("outer1");
    await expect(other).toBeFocused();
  });

  test("trap4: loop-in-conditional — details open-state survives toggling the loop", async ({ page }) => {
    await page.goto("/");
    const details = page.getByTestId("trap4-details");
    await details.locator("summary").click();               // open it
    await expect(details).toHaveAttribute("open", "");
    await page.getByTestId("trap4-toggle").click();          // hide loop
    await page.getByTestId("trap4-toggle").click();          // show loop again
    await expect(details).toHaveAttribute("open", "");       // still open ⇒ not recreated
  });
```

- [ ] **Step 6: Run the e2e** (port 3003 free):
```bash
cd Tests/playwright && npm run test:edgecases 2>&1 | tail -20
```
Expected: 4 passed. If a trap test FAILS, that is a discovered bug — record it (trap, expected vs actual) for the Task 6 triage report; do NOT weaken the assertion. Continue to commit so the failing test is captured (a known-failing trap may be marked `test.fixme` with a comment referencing the triage entry).

- [ ] **Step 7: Commit**
```bash
git add examples/EdgeCases/Sources/App Tests/playwright/edgecases.spec.ts
git commit -F -   # feat(examples): EdgeCases traps 2-4 (for-of-if, for-if-for, loop-in-cond) + Co-Authored-By trailer
```

---

## Task 3: Traps 5–7 (keyed+fragments, two-adjacent-conds, component lifecycle)

**Files:** create `Trap5KeyedWithFragments.swift`, `Trap6TwoAdjacentConds.swift`, `Trap7ComponentLifecycle.swift` (+ a `LifecycleChild` and `Keeper` child component, in the Trap 7 file); modify `App.swift`; modify `edgecases.spec.ts`.

- [ ] **Step 1: Create `Trap5KeyedWithFragments.swift`**

```swift
// Sources/App/Trap5KeyedWithFragments.swift
import Swiflow

/// Trap 5: keyed elements interspersed with fragments. Swapping the keyed
/// items and toggling the conditionals must reuse the keyed inputs (identity
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
                if showX { span(.class("tag")) { text("[x]") } }
                input(.attr("type", "text"), .data("testid", "trap5-input-\(order[1])"), .key("k-\(order[1])"))
                for i in 0..<2 { span(.class("tag"), .key("f-\(i)")) { text(" f\(i) ") } }
            }
        }
    }
}
```

- [ ] **Step 2: Create `Trap6TwoAdjacentConds.swift`**

```swift
// Sources/App/Trap6TwoAdjacentConds.swift
import Swiflow

/// Trap 6: two adjacent conditionals before a sentinel input, inside a list
/// that also has a keyed sibling (forces the keyed path → exercises the
/// structural-sibling bucketKey fix). The input must survive all four combos.
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
                if a { span(.class("tag")) { text("[a]") } }
                if b { span(.class("tag")) { text("[b]") } }
                input(.attr("type", "text"), .data("testid", "trap6-input"))
            }
        }
    }
}
```

- [ ] **Step 3: Create `Trap7ComponentLifecycle.swift`** (trap + two child components)

```swift
// Sources/App/Trap7ComponentLifecycle.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// A child whose mount/unmount bumps shared counters via callbacks, so the
/// test can assert onAppear/onDisappear fire exactly once per toggle.
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
```

- [ ] **Step 4: Embed traps 5–7 in `App.swift`** (after Trap 4):
```swift
            embed { Trap5KeyedWithFragments() }
            embed { Trap6TwoAdjacentConds() }
            embed { Trap7ComponentLifecycle() }
```

- [ ] **Step 5: Add tests to `edgecases.spec.ts`**

```ts
  test("trap5: keyed reorder with fragments — keyed inputs reused on swap", async ({ page }) => {
    await page.goto("/");
    const inputA = await focusType(page, "trap5-input-a", "valueA");
    await page.getByTestId("trap5-togglex").click();   // toggle interspersed fragment
    await page.getByTestId("trap5-swap").click();       // reorder keyed inputs
    // Input keyed "a" kept its value through the fragment toggle + reorder.
    await expect(page.getByTestId("trap5-input-a")).toHaveValue("valueA");
  });

  test("trap6: two adjacent conditionals — sentinel survives all 4 combos", async ({ page }) => {
    await page.goto("/");
    const input = await focusType(page, "trap6-input", "combo");
    for (const seq of [["trap6-a"], ["trap6-b"], ["trap6-a"], ["trap6-b"]]) {
      for (const id of seq) await page.getByTestId(id).click();
      await expect(page.getByTestId("trap6-input")).toHaveValue("combo");
    }
    await expect(input).toBeFocused();
  });

  test("trap7: component lifecycle — onAppear/onDisappear once each; sibling @State survives", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("trap7-keeper-inc").click();
    await page.getByTestId("trap7-keeper-inc").click();
    await expect(page.getByTestId("trap7-keeper-count")).toHaveText("2");
    await page.getByTestId("trap7-toggle").click();  // show child  → appears 1
    await page.getByTestId("trap7-toggle").click();  // hide child  → disappears 1
    await expect(page.getByTestId("trap7-appears")).toHaveText("up:1");
    await expect(page.getByTestId("trap7-disappears")).toHaveText("down:1");
    // Keeper's @State must NOT have been reset by the sibling's churn.
    await expect(page.getByTestId("trap7-keeper-count")).toHaveText("2");
  });
```

- [ ] **Step 6: Run the e2e** (port 3003 free): `cd Tests/playwright && npm run test:edgecases 2>&1 | tail -25`. Expected: 7 passed. Record any failure for triage (Task 6); don't weaken assertions.

- [ ] **Step 7: Commit** — `feat(examples): EdgeCases traps 5-7 (keyed+fragments, two-adjacent-conds, lifecycle)` + trailer.

---

## Task 4: Traps 8–9 (rapid cycle, keyed items with inner state)

**Files:** create `Trap8RapidCycle.swift`, `Trap9KeyedItemsInnerState.swift`; modify `App.swift`; modify `edgecases.spec.ts`.

- [ ] **Step 1: Create `Trap8RapidCycle.swift`**

```swift
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
```

- [ ] **Step 2: Create `Trap9KeyedItemsInnerState.swift`**

```swift
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
```

- [ ] **Step 3: Embed traps 8–9 in `App.swift`**:
```swift
            embed { Trap8RapidCycle() }
            embed { Trap9KeyedItemsInnerState() }
```

- [ ] **Step 4: Add tests to `edgecases.spec.ts`**

```ts
  test("trap8: rapid cycle — sentinel intact, no leaked children", async ({ page }) => {
    await page.goto("/");
    const input = await focusType(page, "trap8-input", "stable");
    for (let i = 0; i < 7; i++) await page.getByTestId("trap8-toggle").click(); // odd ⇒ ends shown
    await expect(page.getByTestId("trap8-list").locator("li")).toHaveCount(3); // exactly 3, no dups
    await expect(input).toHaveValue("stable");
  });

  test("trap9: keyed items carry inner state across reorder", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("trap9-expand-y").click();          // expand item y
    const yInput = await focusType(page, "trap9-input-y", "Y-data");
    await page.getByTestId("trap9-rotate").click();            // x,y,z → y,z,x
    // y's input still exists with its value (state moved with the item).
    await expect(page.getByTestId("trap9-input-y")).toHaveValue("Y-data");
  });
```

- [ ] **Step 5: Run the e2e**: `cd Tests/playwright && npm run test:edgecases 2>&1 | tail -25`. Expected: 9 passed. Record failures for triage.

- [ ] **Step 6: Commit** — `feat(examples): EdgeCases traps 8-9 (rapid cycle, keyed inner state)` + trailer.

---

## Task 5: Traps 10–11 (raw [VNode] spread; dynamic keyed list)

**Files:** create `Trap10RawSpread.swift`, `Trap11DynamicList.swift`; modify `App.swift`; modify `edgecases.spec.ts`.

- [ ] **Step 1: Create `Trap10RawSpread.swift`**

```swift
// Sources/App/Trap10RawSpread.swift
import Swiflow

/// Trap 10 (KNOWN LIMITATION): a raw [VNode] spread — NOT wrapped in if/for —
/// is flattened, so changing its length DOES shift the following sibling (the
/// documented buildExpression([VNode]) footgun). This trap asserts the
/// framework doesn't crash and a sibling in a SEPARATE element is unaffected.
@MainActor @Component
final class Trap10RawSpread {
    @State var n: Int = 1

    private var spread: [VNode] {
        (0..<n).map { span(.class("tag")) { text("s\($0) ") } }
    }

    var body: VNode {
        section(.data("testid", "trap10")) {
            h2("10. raw [VNode] spread (known limitation)")
            button("grow", .data("testid", "trap10-grow"), .on(.click) { self.n += 1 })
            // Raw spread, no if/for wrapper — flattened, shifts siblings.
            div(.data("testid", "trap10-spread")) {
                spread
                span(.class("tag")) { text("END") }
            }
            // A sentinel in a SEPARATE element is unaffected by the spread.
            div(.class("row")) {
                input(.attr("type", "text"), .data("testid", "trap10-input"))
            }
        }
    }
}
```

- [ ] **Step 2: Create `Trap11DynamicList.swift`**

```swift
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
```

- [ ] **Step 3: Embed traps 10–11 in `App.swift`**:
```swift
            embed { Trap10RawSpread() }
            embed { Trap11DynamicList() }
```

- [ ] **Step 4: Add tests to `edgecases.spec.ts`**

```ts
  test("trap10: raw spread — separate-element sentinel unaffected; no crash", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto("/");
    const input = await focusType(page, "trap10-input", "safe");
    await page.getByTestId("trap10-grow").click();
    await page.getByTestId("trap10-grow").click();
    // The documented limitation shifts the in-element END marker, but the
    // sentinel input lives in a SEPARATE element and must be unaffected.
    await expect(input).toHaveValue("safe");
    await expect(page.getByTestId("trap10-spread")).toContainText("END");
    expect(errors, "no console errors from the raw spread").toHaveLength(0);
  });

  test("trap11: bulk add/remove/swap — existing rows reused (identity + value survive)", async ({ page }) => {
    await page.goto("/");
    // Seed 100 rows at the back, type into the first one, tag its node.
    await page.getByTestId("trap11-add1-back").click();
    const firstId = await page.getByTestId("trap11-list").locator("li input").first()
      .getAttribute("data-testid"); // e.g. "trap11-input-0"
    const typed = page.getByTestId(firstId!);
    await typed.fill("ANCHOR");
    await typed.evaluate((el) => ((el as any).__tag = "tag-0"));
    // Prepend 100 rows at the FRONT (the stressor).
    await page.getByTestId("trap11-add100-front").click();
    await expect(page.getByTestId("trap11-count")).toHaveText("101");
    // The original row was NOT recreated: same node (tag persists) + value.
    await expect(typed).toHaveValue("ANCHOR");
    expect(await typed.evaluate((el) => (el as any).__tag)).toBe("tag-0");
    // Swap ends, then remove first — original still identifiable + intact.
    await page.getByTestId("trap11-swap").click();
    await expect(typed).toHaveValue("ANCHOR");
    expect(await typed.evaluate((el) => (el as any).__tag)).toBe("tag-0");
  });
```

- [ ] **Step 5: Run the e2e**: `cd Tests/playwright && npm run test:edgecases 2>&1 | tail -30`. Expected: 11 passed. Record failures for triage.

- [ ] **Step 6: Commit** — `feat(examples): EdgeCases traps 10-11 (raw spread, dynamic keyed list)` + trailer.

---

## Task 6: Embed as template, freshness, triage report

**Files:** modify `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerated); create `docs/reviews/edgecases-triage.md` (or append to the spec); possibly framework fixes if quick bugs surfaced.

- [ ] **Step 1: Triage any failing traps**

Collect every trap test that failed in Tasks 1–5. For each: (a) confirm it's a real reconciler defect (not a test bug) by reading the emitted behavior; (b) reproduce at the unit level with a focused test in `Tests/SwiflowTests/DiffTests/` mirroring the trap's tree (these become permanent regression tests); (c) if the fix is small and clearly correct, fix it in the framework and re-run; (d) if non-trivial or a deliberate limitation (Trap 10), log it. Write the outcomes to `docs/reviews/edgecases-triage.md`:

```markdown
# EdgeCases triage — 2026-05-30
| Trap | Result | Bug? | Action |
|------|--------|------|--------|
| 1 …  | pass/fail | … | fixed in <sha> / logged / n/a |
```

(If every trap passed, the table records all-pass and the harness stands as regression coverage.)

- [ ] **Step 2: Embed EdgeCases as a template + verify freshness**

```bash
swift scripts/embed-templates.swift 2>&1 | tail -1
swift test --filter TemplateEmbedder 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "bit-for-bit|Test run|✘|failed" | tail -3
```
Expected: regenerated; freshness test passes. Confirm `swiflow init --help` would list EdgeCases (the embedder walks `examples/*`).

- [ ] **Step 3: Final full e2e + unit suite**
```bash
cd Tests/playwright && npm run test:edgecases 2>&1 | tail -5; cd ../..
swift test --filter DiffTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed" | tail -3
```
Expected: edgecases 11 passed (or known-`fixme` traps documented in triage); DiffTests green (incl. any new unit-repro tests).

- [ ] **Step 4: Commit**
```bash
git add Sources/SwiflowCLI/EmbeddedTemplates.swift docs/reviews/edgecases-triage.md Tests/SwiflowTests
git commit -F -   # chore(examples): embed EdgeCases template; triage report (+ any unit-repro tests) + trailer
```

---

## Self-Review (completed during planning)

- **Spec coverage:** §1 goal (find bugs) → all tasks + Task 6 triage; §2 detection signals → all used (focus+value: traps 1,2,5,6,8,10,11; details-open: 4; tagged DOM prop: 11; child @State counter: 7; child count/no-leak: 8; separate-element isolation + no-console-error: 10); §3 architecture (EdgeLab + per-trap components, data-testid) → Task 1 conventions + every trap; §4 all 11 traps → Tasks 1–5 (1→T1, 2-4→T2, 5-7→T3, 8-9→T4, 10-11→T5); §5 failure handling → Task 6 triage; §6 wiring (examples/EdgeCases, embed-as-template, playwright config + spec + npm script, port 3003) → Task 1 (config/spec/script, in-place build) + Task 6 (embed); §7 out-of-scope respected (no reconciler changes except triaged fixes); §8 build sequence → matches task order.
- **Placeholder scan:** none — every component and test has complete code; the triage table is a real artifact, not a TODO.
- **Type/name consistency:** component types `Trap1CondBeforeFocus`…`Trap11DynamicList` + `LifecycleChild`/`Keeper` are referenced in `App.swift` embeds exactly as defined; `data-testid`s used in tests (`trap1-toggle`, `trap1-input`, `trap2-input-2`, `trap7-keeper-count`, `trap11-add100-front`, …) match those emitted in the components; the `focusType` helper signature is defined once (Task 1) and reused.
- **One deviation from pure TDD, called out:** an example is verified end-to-end by Playwright (needs a WASM build), so tests are authored alongside each trap and run per-batch rather than red-before-green per step. Unit-level red-green happens in Task 6 triage when a trap surfaces a real bug.
