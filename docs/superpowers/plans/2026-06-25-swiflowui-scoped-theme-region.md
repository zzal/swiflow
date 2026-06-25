# SwiflowUI Scoped Theme Region Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Theme(.accent(…), .radius(…)) { … }` container that scopes typed `--sw-*` overrides to its subtree with zero layout impact.

**Architecture:** `Theme` is a stateless free function (matching `Card`/`Grid`/`Stack`) that renders a `<div>` with `display: contents` carrying the overrides as inline custom properties via the existing `.style(_:_:)` Attribute. `display: contents` removes the wrapper's box (no flex/grid disruption) while custom properties still inherit to descendants. No new CSS sheet, no runtime color math.

**Tech Stack:** Swift 6 (language mode v6), Swift Testing (`import Testing`/`@Suite`/`@Test`/`#expect`), the Swiflow DSL (`element`, `Attribute.style`, `@ChildrenBuilder`, `VNode`).

**Spec:** [`docs/superpowers/specs/2026-06-25-swiflowui-scoped-theme-region-design.md`](../specs/2026-06-25-swiflowui-scoped-theme-region-design.md)

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/SwiflowUI/ThemeScope.swift` (new) | `ThemeToken` value type + the `Theme` component |
| `Tests/SwiflowUITests/ThemeScopeTests.swift` (new) | unit tests for both |

**Conventions (verified against the codebase):**
- Container components are `@MainActor public func`s returning `element("div", attributes: […], children: children())`, taking `@ChildrenBuilder children: () -> [VNode] = { [] }` (see `Card`, `Grid`, `Stack`).
- Tests inspect the rendered node with `guard case .element(let data) = node`; `data.style` is `[String: String]` (custom props included), `data.tag` is the element name, `data.children` is `[VNode]`. The `styleOf` helper below is copied from `GridTests.swift`.
- `Attribute.style(_ name: String, _ value: String)` sets one (custom) property; the framework merges multiple into the element's `style`.

---

### Task 1: `ThemeToken` value type

**Files:**
- Create: `Sources/SwiflowUI/ThemeScope.swift`
- Create: `Tests/SwiflowUITests/ThemeScopeTests.swift`

- [ ] **Step 1: Write the failing test** — Create `Tests/SwiflowUITests/ThemeScopeTests.swift`:

```swift
import Testing
import Swiflow
@testable import SwiflowUI

@Suite("ThemeToken")
struct ThemeTokenTests {
    @Test("Typed statics map to the right --sw-* names")
    func typedStatics() {
        #expect(ThemeToken.accent("#7c3aed") == ThemeToken(name: "--sw-accent", value: "#7c3aed"))
        #expect(ThemeToken.radius("12px").name  == "--sw-radius")
        #expect(ThemeToken.surface("#fff").name == "--sw-surface")
        #expect(ThemeToken.text("#111").name    == "--sw-text")
        #expect(ThemeToken.border("#ccc").name  == "--sw-border")
        #expect(ThemeToken.danger("#dc2626").name  == "--sw-danger")
        #expect(ThemeToken.success("#16a34a").name == "--sw-success")
    }

    @Test(".token is a passthrough escape hatch")
    func tokenEscapeHatch() {
        let t = ThemeToken.token("--sw-space-md", "1rem")
        #expect(t.name == "--sw-space-md")
        #expect(t.value == "1rem")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeTokenTests`. Expected: FAIL — `ThemeToken` undefined.

- [ ] **Step 3: Implement** — Create `Sources/SwiflowUI/ThemeScope.swift`:

```swift
// Sources/SwiflowUI/ThemeScope.swift
//
// `Theme { }` — scope a set of `--sw-*` token overrides to a subtree. See the
// `Theme` component below; `ThemeToken` is its typed override vocabulary.

import Swiflow

/// A single `--sw-*` override for a `Theme` region. Use the typed statics for the
/// commonly-branded tokens, or `.token(_:_:)` for anything else.
public struct ThemeToken: Equatable, Sendable {
    public let name: String     // e.g. "--sw-accent"
    public let value: String

    public static func accent(_ v: String)  -> ThemeToken { .init(name: "--sw-accent",  value: v) }
    public static func radius(_ v: String)  -> ThemeToken { .init(name: "--sw-radius",  value: v) }
    public static func surface(_ v: String) -> ThemeToken { .init(name: "--sw-surface", value: v) }
    public static func text(_ v: String)    -> ThemeToken { .init(name: "--sw-text",    value: v) }
    public static func border(_ v: String)  -> ThemeToken { .init(name: "--sw-border",  value: v) }
    public static func danger(_ v: String)  -> ThemeToken { .init(name: "--sw-danger",  value: v) }
    public static func success(_ v: String) -> ThemeToken { .init(name: "--sw-success", value: v) }

    /// Escape hatch for any other token (spacing scale, motion, overlay, custom props).
    public static func token(_ name: String, _ value: String) -> ThemeToken { .init(name: name, value: value) }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeTokenTests`. Expected: PASS (2 tests). (`ThemeToken(name:value:)` in the test resolves to the internal memberwise init, visible via `@testable import`.)

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowUI/ThemeScope.swift Tests/SwiflowUITests/ThemeScopeTests.swift
git commit -m "feat(swiflowui): ThemeToken — typed override vocabulary for scoped theming"
```

---

### Task 2: The `Theme` component

**Files:**
- Modify: `Sources/SwiflowUI/ThemeScope.swift` (append)
- Modify: `Tests/SwiflowUITests/ThemeScopeTests.swift` (append a helper + a suite)

- [ ] **Step 1: Write the failing test** — Append to `Tests/SwiflowUITests/ThemeScopeTests.swift`:

```swift
// Mirrors GridTests.swift's helper — pulls the merged inline style dict off a node.
@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Theme")
@MainActor
struct ThemeComponentTests {
    @Test("Theme renders a display:contents div carrying the overrides as custom props")
    func rendersContentsDiv() {
        let node = Theme(.accent("#7c3aed"), .radius("12px")) { text("x") }
        let s = styleOf(node)
        #expect(s["display"] == "contents")
        #expect(s["--sw-accent"] == "#7c3aed")
        #expect(s["--sw-radius"] == "12px")
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.tag == "div")
        #expect(data.children.count == 1)
    }

    @Test(".token override lands as a custom property")
    func tokenOverride() {
        #expect(styleOf(Theme(.token("--sw-space-md", "1rem")) { text("x") })["--sw-space-md"] == "1rem")
    }

    @Test("No tokens still renders a display:contents wrapper")
    func emptyTokens() {
        #expect(styleOf(Theme { text("x") })["display"] == "contents")
    }

    @Test("Nesting renders nested themed divs, each with its own override")
    func nesting() {
        let outer = Theme(.accent("#7c3aed")) { Theme(.radius("4px")) { text("x") } }
        #expect(styleOf(outer)["--sw-accent"] == "#7c3aed")
        guard case .element(let od) = outer, case .element(let inner)? = od.children.first else {
            Issue.record("nesting structure"); return
        }
        #expect(inner.style["--sw-radius"] == "4px")
        #expect(inner.style["display"] == "contents")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeComponentTests`. Expected: FAIL — `Theme` (the function) undefined.

- [ ] **Step 3: Implement** — Append to `Sources/SwiflowUI/ThemeScope.swift`:

```swift
/// Scope a set of `--sw-*` token overrides to a subtree. Renders a `display: contents`
/// wrapper carrying the overrides as inline custom properties: the wrapper's box is
/// removed (children participate in the parent's layout directly), but the element stays
/// in the DOM tree so its custom properties inherit to descendants. Zero layout impact,
/// no new stylesheet, no runtime color math — it just re-points explicit token values.
///
///     Theme(.accent("#7c3aed"), .radius("12px")) {
///         Card { Button("Branded") { … } }    // accent family + radius re-skinned here
///     }
@MainActor
public func Theme(
    _ tokens: ThemeToken...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    let styleAttrs: [Attribute] = [.style("display", "contents")] + tokens.map { .style($0.name, $0.value) }
    return element("div", attributes: styleAttrs, children: children())
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeComponentTests`. Expected: PASS (4 tests).

- [ ] **Step 5: Run the full SwiflowUI suite** — `swift test --filter SwiflowUITests`. Expected: PASS — nothing regressed.

- [ ] **Step 6: Commit**
```bash
git add Sources/SwiflowUI/ThemeScope.swift Tests/SwiflowUITests/ThemeScopeTests.swift
git commit -m "feat(swiflowui): Theme — scoped token-override region (display: contents)"
```

---

## Final verification (after all tasks)

- [ ] Full suite: `swift test` → all green.
- [ ] **Demo eyeball** (CI skips example builds — do it locally): add a small themed section to `examples/SwiflowUIDemo` — e.g.
  ```swift
  Theme(.accent("#dc2626")) {
      Card { Button("Danger-branded") { } }
  }
  ```
  then `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo`, serve, and confirm: (a) the button inside re-skins to the red accent (and one outside stays default), and (b) **no layout shift** — the themed region sits exactly where a normal block would, proving `display: contents` removed the wrapper box. Revert the demo's stamped `swiflow-service-worker.js`/driver afterward; keep the themed-section source change only if you want it in the PR.
- [ ] Dispatch the final code reviewer.

## Notes for the implementer

- **No `installControlSheet` / no CSS sheet** — `Theme` has no rules of its own; it only emits inline custom properties. It still calls `ensureBaseStyles()` (like its siblings) so the `:root` defaults it overrides exist.
- **Playwright deferred (intentional).** The spec mentions a browser check; a dedicated Playwright spec is low-value here — `display: contents` + custom-property inheritance is standard, well-supported behavior, the unit tests cover the component's emitted markup, and the demo eyeball confirms the browser result. Add a spec later only if a regression surfaces.
- **Don't add caller `Attribute...` passthrough** (out of scope for v1) — `Theme` is a styling-only wrapper. An app needing an `id`/class on a real box wraps its own element.
