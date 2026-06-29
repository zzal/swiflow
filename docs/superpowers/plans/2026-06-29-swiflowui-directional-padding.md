# SwiflowUI directional padding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an edge selector to the padding modifier — `.padding(.lg, .horizontal)`, `.padding(.sm, [.top, .leading])` — via a logical/RTL-aware `Edge` OptionSet, without breaking existing `.padding(.lg)` call sites and with deterministic composition.

**Architecture:** One new value type (`Edge: OptionSet`) in `Tokens.swift` and one replacement `VNode.padding(_:_:)` overload in `Modifiers.swift`. The modifier maps the selected edges to the **four atomic logical-longhand** `padding-*` properties (`padding-block-start/-end`, `padding-inline-start/-end`) — never a shorthand — so chained calls compose by distinct dictionary key and are order-independent over the unordered `ElementData.style` dict. No core/framework change.

**Tech Stack:** Swift 6.3, SwiflowUI (`VNode` DSL + the core `VNode.style(_:_:)` postfix modifier), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-29-swiflowui-directional-padding-design.md`

---

## File Structure

- **Modify** `Sources/SwiflowUI/Tokens.swift` — add the `Edge` OptionSet + its `logicalSides` mapping.
- **Modify** `Sources/SwiflowUI/Modifiers.swift` — replace the all-edges `padding(_:)` with the `padding(_:_:)` overload (default `edges: .all`).
- **Modify** `Tests/SwiflowUITests/ModifierTests.swift` — update the two existing padding assertions; add directional + composition tests.
- **Modify** `docs/guides/swiflowui.md` — one-line note + example.

---

## Reference facts (verified against current code)

- Current modifier (`Sources/SwiflowUI/Modifiers.swift`): `func padding(_ s: Spacing) -> VNode { style("padding", s.css) }`. `.gap(_:)` lives beside it and is unchanged.
- `Spacing` (`Sources/SwiflowUI/Tokens.swift`) has `.css` → e.g. `var(--sw-space-lg)`, `.custom("3px")` → `"3px"`.
- Core `VNode.style(_ property:_ value:)` (`Sources/Swiflow/DSL/VNodeModifiers.swift:27`) sets `data.style[property] = value` and is a no-op + DEBUG diagnostic on non-element nodes.
- `ElementData.style` is `[String: String]` (unordered); the JS driver applies styles per-property (`node.style[name] = value`, `js-driver/swiflow-driver.js:207`) — hence atomic-longhand-only.
- Existing tests (`Tests/SwiflowUITests/ModifierTests.swift`): `paddingAppendsTokenVar` asserts `s["padding"] == "var(--sw-space-lg)"` and `s["display"] == "flex"`; `customSpacingPassesThrough` asserts `…padding(.custom("3px")))["padding"] == "3px"`. Both must be updated (the shorthand `padding` key is no longer emitted). `styleOf(_:)` helper returns `data.style`.

---

## Task 1: `Edge` OptionSet + directional `padding(_:_:)`

**Files:**
- Modify: `Sources/SwiflowUI/Tokens.swift` (add `Edge` after the `Spacing` enum)
- Modify: `Sources/SwiflowUI/Modifiers.swift` (replace the `padding(_:)` overload)
- Test: `Tests/SwiflowUITests/ModifierTests.swift`

- [ ] **Step 1: Update the two existing tests + add the new tests (write them first)**

In `Tests/SwiflowUITests/ModifierTests.swift`, replace the body of `struct ModifierTests` so it reads:

```swift
@Suite("Modifiers")
@MainActor
struct ModifierTests {
    @Test(".padding(.all) emits the four atomic logical longhands, no shorthand") func paddingAllEdges() {
        let s = styleOf(VStack { text("x") }.padding(.lg))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-end"] == "var(--sw-space-lg)")
        #expect(s["padding"] == nil)        // no shorthand emitted
        #expect(s["display"] == "flex")     // doesn't disturb existing styles
    }

    @Test(".gap overrides the spacing set in the stack constructor") func gapModifierOverridesConstructorGap() {
        let s = styleOf(VStack(spacing: .md) { text("x") }.gap(.sm))
        #expect(s["gap"] == "var(--sw-space-sm)")
    }

    @Test(".custom spacing passes its raw CSS value through to every edge") func customSpacingPassesThrough() {
        let s = styleOf(HStack { text("x") }.padding(.custom("3px")))
        #expect(s["padding-block-start"] == "3px")
        #expect(s["padding-inline-end"] == "3px")
    }

    @Test(".horizontal pads only the inline edges") func paddingHorizontal() {
        let s = styleOf(VStack { text("x") }.padding(.lg, .horizontal))
        #expect(s["padding-inline-start"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-end"] == "var(--sw-space-lg)")
        #expect(s["padding-block-start"] == nil)
        #expect(s["padding-block-end"] == nil)
    }

    @Test(".vertical pads only the block edges") func paddingVertical() {
        let s = styleOf(VStack { text("x") }.padding(.lg, .vertical))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("an explicit edge subset pads exactly those edges") func paddingSubset() {
        let s = styleOf(VStack { text("x") }.padding(.sm, [.top, .leading]))
        #expect(s["padding-block-start"] == "var(--sw-space-sm)")    // top
        #expect(s["padding-inline-start"] == "var(--sw-space-sm)")   // leading
        #expect(s["padding-block-end"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("a single edge with a custom length") func paddingSingleEdgeCustom() {
        let s = styleOf(VStack { text("x") }.padding(.custom("3px"), .bottom))
        #expect(s["padding-block-end"] == "3px")
        #expect(s["padding-block-start"] == nil)
        #expect(s["padding-inline-start"] == nil)
        #expect(s["padding-inline-end"] == nil)
    }

    @Test("chained directional calls compose deterministically (later overrides its edges only)") func paddingComposition() {
        let s = styleOf(VStack { text("x") }.padding(.lg).padding(.md, .horizontal))
        #expect(s["padding-block-start"] == "var(--sw-space-lg)")    // unchanged by the 2nd call
        #expect(s["padding-block-end"] == "var(--sw-space-lg)")
        #expect(s["padding-inline-start"] == "var(--sw-space-md)")   // overridden
        #expect(s["padding-inline-end"] == "var(--sw-space-md)")
    }
}
```

(The `styleOf(_:)` private helper and imports at the top of the file are unchanged.)

- [ ] **Step 2: Run the tests and confirm they fail to compile**

Run: `swift test --filter ModifierTests`
Expected: COMPILE FAILURE — `Edge` is undefined and `padding(_:_:)` (the two-argument overload) does not exist yet.

- [ ] **Step 3: Add the `Edge` OptionSet to `Tokens.swift`**

In `Sources/SwiflowUI/Tokens.swift`, after the `Spacing` enum, add:

```swift
/// A set of box edges for directional spacing modifiers (e.g. `.padding(.lg, .horizontal)`).
/// Logical / writing-mode & RTL aware: `leading`/`trailing` follow text direction
/// (inline-start/-end), `top`/`bottom` are block-start/-end.
public struct Edge: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top      = Edge(rawValue: 1 << 0)   // block-start
    public static let bottom   = Edge(rawValue: 1 << 1)   // block-end
    public static let leading  = Edge(rawValue: 1 << 2)   // inline-start
    public static let trailing = Edge(rawValue: 1 << 3)   // inline-end

    public static let horizontal: Edge = [.leading, .trailing]
    public static let vertical:   Edge = [.top, .bottom]
    public static let all:        Edge = [.top, .bottom, .leading, .trailing]

    /// The atomic logical box-side suffixes this set covers (`block-start`, `inline-end`, …), in a
    /// stable order. Atomic only — never the `inline`/`block` axis shorthands — so directional
    /// spacing composes deterministically across chained modifiers over the unordered style dict.
    var logicalSides: [String] {
        var sides: [String] = []
        if contains(.top)      { sides.append("block-start") }
        if contains(.bottom)   { sides.append("block-end") }
        if contains(.leading)  { sides.append("inline-start") }
        if contains(.trailing) { sides.append("inline-end") }
        return sides
    }
}
```

- [ ] **Step 4: Replace the `padding` modifier in `Modifiers.swift`**

In `Sources/SwiflowUI/Modifiers.swift`, replace the existing `padding(_ s: Spacing)` function with the edge-aware overload (leave `.gap(_:)` untouched):

```swift
    /// Adds (or overwrites) padding on the given `edges` using a `--sw-space-*` token (or raw
    /// length). Edges are logical (RTL-aware); defaults to `.all`, so `.padding(.md)` is unchanged.
    /// Emits the four atomic logical longhands (`padding-block-start/-end`, `padding-inline-start/-end`)
    /// — never a shorthand — so chained calls compose deterministically:
    /// `.padding(.lg).padding(.md, .horizontal)` ⇒ block `lg`, inline `md`. A no-op on non-element
    /// nodes (the core `style(_:_:)` diagnostic path).
    func padding(_ s: Spacing, _ edges: Edge = .all) -> VNode {
        var node = self
        for side in edges.logicalSides {
            node = node.style("padding-\(side)", s.css)
        }
        return node
    }
```

- [ ] **Step 5: Run the tests and confirm green**

Run: `swift test --filter ModifierTests`
Expected: PASS (all 8 tests).

- [ ] **Step 6: Confirm the whole package still builds (no broken `.padding` call sites)**

Run: `swift build`
Expected: builds clean. (Existing `.padding(.lg)` calls bind to the new overload via the `.all` default.)

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowUI/Tokens.swift Sources/SwiflowUI/Modifiers.swift Tests/SwiflowUITests/ModifierTests.swift
git commit -m "feat(swiflowui): directional padding via logical Edge OptionSet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Document directional padding in the guide

**Files:**
- Modify: `docs/guides/swiflowui.md` (the spacing-modifiers paragraph, ~line 63)

- [ ] **Step 1: Update the spacing-modifiers note**

In `docs/guides/swiflowui.md`, replace this paragraph:

```markdown
Stacks take postfix modifiers: `.padding(.lg)`, `.gap(.sm)`. `Grid(columns: "1fr 2fr")`
accepts any `grid-template-columns` value. Spacing is the `Spacing` scale
(`.xs/.sm/.md/.lg/.xl/.none`).
```

with:

```markdown
Stacks take postfix modifiers: `.padding(.lg)`, `.gap(.sm)`. `Grid(columns: "1fr 2fr")`
accepts any `grid-template-columns` value. Spacing is the `Spacing` scale
(`.xs/.sm/.md/.lg/.xl/.none`).

`.padding` takes an optional edge set as a second argument — `.padding(.lg, .horizontal)`,
`.padding(.sm, [.top, .leading])`. Edges are logical/RTL-aware (`Edge`: `.top`/`.bottom`/
`.leading`/`.trailing` plus the `.horizontal`/`.vertical`/`.all` presets, where `leading`/
`trailing` follow text direction). Chained calls compose per-edge, e.g.
`.padding(.md, .horizontal).padding(.sm, .vertical)` for 16px-horizontal / 8px-vertical.
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/swiflowui.md
git commit -m "docs(swiflowui): document directional .padding edge sets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (controller, after all tasks)

- [ ] `swift build` — clean.
- [ ] `swift test --filter ModifierTests` — green (8 tests).
- [ ] `swift test` — full SwiflowUI suite green (no regression from the emitted-CSS change).
- [ ] Dispatch a final code reviewer over the branch diff.
- [ ] Use superpowers:finishing-a-development-branch → open PR from `feat/swiflowui-directional-padding` (branched from origin/main) → **hold merge** until the user says "merge it — CI is green", then `gh pr merge <n> --admin --rebase`.

---

## Self-Review

- **Spec coverage:** `Edge` OptionSet with logical naming + presets (T1 Step 3); `.padding(_:_:)` default `.all` keeps `.padding(.lg)` working (T1 Step 4/6); atomic-longhand-only emission + deterministic composition (T1 Step 3 `paddingComposition` + Step 4 impl); padding-only scope (no `.gap`/`.margin` touched); docs note (T2). All covered.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** `Edge`, `logicalSides`, `padding(_:_:)`, and the property names `padding-block-start`/`-end`/`padding-inline-start`/`-end` are used identically across the impl and every test assertion. `Spacing.css` values (`var(--sw-space-lg)`, `3px`) match the spec and existing token behavior.
