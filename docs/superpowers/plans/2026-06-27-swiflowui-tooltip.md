# SwiflowUI `Tooltip` component — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CSS-only `Tooltip("text") { trigger }` wrapper that reveals a token-styled `role="tooltip"` bubble on hover and keyboard focus, with `aria-describedby` wiring — no JS, no `@Component`.

**Architecture:** One stateless free function in a new `Tooltip.swift`, using the `installControlSheet` seam (like Badge). The bubble is an absolutely-positioned sibling of the trigger inside a `position: relative` wrapper; `:hover`/`:focus-within` on the wrapper reveal it. A file-local helper injects `aria-describedby` into a single-element trigger.

**Tech Stack:** Swift, Swift Testing (`@testable import SwiflowUI`), the SwiflowUIDemo embedded template (needs an embed regen on change).

---

## Context every task needs

- **Spec:** `docs/superpowers/specs/2026-06-27-swiflowui-tooltip-design.md`.
- **Template to copy:** `Sources/SwiflowUI/Badge.swift` — a stateless free fn that calls `ensureBaseStyles()` + `installControlSheet(id:_:)`, splits caller attrs with `splitClasses(_:)`, and defines a `let xStyleSheet: CSSSheet = css { raw(""" … """) }`.
- **Helpers available:** `nextSwID("prefix") -> String` (unique id), `splitClasses(_ attributes:) -> (classes, rest)`, `element(_:attributes:children:)`, `installControlSheet(id:_:)`, `ensureBaseStyles()`.
- **`VNode`** is an `indirect enum` with cases incl. `.element(ElementData)`, `.text(String)`, `.fragment([VNode])`, `.environmentOverride(_, VNode)`, plus a component-anchor case. **`ElementData`** has `public let tag: String` and `public var attributes: [String: String]` and `var children: [VNode]` — so an `.element` node's attributes are a mutable dictionary (this is how we inject `aria-describedby`).
- **Gotcha:** do NOT name the text parameter `text` — it shadows the global `text(_:)` function. Build the bubble's text child as `.text(message)` (the enum case) instead.
- **Gotcha:** the bubble must sit **adjacent** to the trigger (e.g. `bottom: 100%`, no margin gap). `:hover` on the wrapper stays true while the pointer is over any descendant (even an absolutely-positioned one outside the wrapper's box), so an adjacent bubble keeps a continuous hover path (WCAG "hoverable"). A margin gap would break it.
- **SwiflowUIDemo is an embedded template** (`Sources/SwiflowCLI/EmbeddedTemplates.swift`), so any `examples/SwiflowUIDemo/**` change requires `swift scripts/embed-templates.swift` + the `TemplateEmbedder` freshness gate.
- **Run:** `swift build`, `swift test` (host).

---

## Task 1: `Tooltip.swift` + unit tests

**Files:**
- Create: `Sources/SwiflowUI/Tooltip.swift`
- Test: `Tests/SwiflowUITests/TooltipTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowUITests/TooltipTests.swift`:

```swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}
@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                       return s
    case .element(let d):                    return d.children.map(allText).joined()
    case .fragment(let xs):                  return xs.map(allText).joined()
    case .environmentOverride(_, let child): return allText(child)
    default:                                  return ""
    }
}

@MainActor
@Suite("Tooltip")
struct TooltipTests {
    @Test("wraps the trigger, wires aria-describedby to a role=tooltip bubble") func wiresAria() {
        let node = Tooltip("Delete permanently") { Button("Delete") {} }
        let wrap = el(node)
        #expect(wrap?.attributes["class"]?.contains("sw-tooltip-wrap") == true)
        let kids = wrap?.children ?? []
        #expect(kids.count == 2)
        let trigger = el(kids[0]); let bubble = el(kids[1])
        let tipID = bubble?.attributes["id"]
        #expect(tipID?.isEmpty == false)
        #expect(bubble?.attributes["role"] == "tooltip")
        #expect(trigger?.attributes["aria-describedby"] == tipID)
        #expect(allText(kids[1]) == "Delete permanently")
    }

    @Test("placement sets the bubble modifier class") func placement() {
        let node = Tooltip("hi", placement: .bottom) { Button("x") {} }
        let bubble = el(el(node)?.children[1])
        #expect(bubble?.attributes["class"]?.contains("sw-tooltip--bottom") == true)
    }

    @Test("non-element trigger: no crash, no aria link, bubble still role=tooltip") func nonElementTrigger() {
        let node = Tooltip("hi") { VNode.text("plain") }
        let kids = el(node)?.children ?? []
        #expect(kids.count == 2)
        #expect(el(kids[1])?.attributes["role"] == "tooltip")
        // a text trigger has no attributes to carry the aria link — that's fine
    }

    @Test("emitted sheet has reveal selectors + token styling + all placements") func sheet() {
        let css = tooltipStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-tooltip-wrap:hover .sw-tooltip"))
        #expect(css.contains(":focus-within"))
        #expect(css.contains("var(--sw-surface)"))
        #expect(css.contains(".sw-tooltip--top"))
        #expect(css.contains(".sw-tooltip--bottom"))
        #expect(css.contains(".sw-tooltip--leading"))
        #expect(css.contains(".sw-tooltip--trailing"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TooltipTests`
Expected: FAIL — `Tooltip` / `tooltipStyleSheet` don't exist (compile error).

- [ ] **Step 3: Implement `Tooltip.swift`**

Create `Sources/SwiflowUI/Tooltip.swift`:

```swift
// Sources/SwiflowUI/Tooltip.swift
import Swiflow

/// Placement of a `Tooltip` bubble relative to its trigger. `.leading`/`.trailing` use logical
/// offsets, so they flip under RTL.
public enum TooltipPlacement: Equatable {
    case top, bottom, leading, trailing
    var modifierClass: String {
        switch self {
        case .top:      return "top"
        case .bottom:   return "bottom"
        case .leading:  return "leading"
        case .trailing: return "trailing"
        }
    }
}

/// A descriptive overlay shown on hover and keyboard focus of its trigger. CSS-only — no JS,
/// no lifecycle: `:hover`/`:focus-within` on the wrapper reveal a `role="tooltip"` bubble, and
/// `aria-describedby` links the trigger to it so screen readers announce it on focus.
///
///     Tooltip("Delete permanently") { Button("Delete", variant: .danger) { delete() } }
///     Tooltip("Appears below", placement: .bottom) { Button("Below") {} }
///
/// Caller `Attribute...`/`.class` merge onto the WRAPPER. The bubble is a text label only.
///
/// > A11y: revealed on hover AND focus, and "hoverable" (the pointer can move onto the bubble).
/// > It does NOT support Escape-to-dismiss (CSS can't handle keys), so it does not fully meet
/// > WCAG 1.4.13; a future JS-driven variant would add dismissal. Positioned with plain
/// > absolute offsets (every engine); the bubble is not in the top layer, so an ancestor with
/// > `overflow: hidden`/`clip` can crop it.
@MainActor
public func Tooltip(
    _ message: String,
    placement: TooltipPlacement = .top,
    _ attributes: Attribute...,
    content: () -> VNode
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-tooltip", tooltipStyleSheet)

    let tipID = nextSwID("sw-tip")
    let trigger = addingDescribedBy(tipID, to: content())

    let bubble = element("span", attributes: [
        .class("sw-tooltip sw-tooltip--\(placement.modifierClass)"),
        .attr("role", "tooltip"),
        .attr("id", tipID),
    ], children: [.text(message)])

    let (callerClasses, callerRest) = splitClasses(attributes)
    let wrapClass = (["sw-tooltip-wrap"] + callerClasses).joined(separator: " ")
    return element("span", attributes: [.class(wrapClass)] + callerRest,
                   children: [trigger, bubble])
}

/// Add `aria-describedby` to a single-element trigger so SR announces the bubble on focus.
/// Non-element triggers (component anchors, text, fragments) are returned unchanged — the
/// visual tooltip still works; only the explicit SR link is skipped.
private func addingDescribedBy(_ id: String, to node: VNode) -> VNode {
    guard case .element(var data) = node else { return node }
    if let existing = data.attributes["aria-describedby"], !existing.isEmpty {
        data.attributes["aria-describedby"] = existing + " " + id
    } else {
        data.attributes["aria-describedby"] = id
    }
    return .element(data)
}

let tooltipStyleSheet: CSSSheet = css {
    raw("""
    .sw-tooltip-wrap {
      position: relative;
      display: inline-block;
    }
    .sw-tooltip {
      position: absolute;
      z-index: 50;
      width: max-content;
      max-width: 16rem;
      padding: var(--sw-space-xs) var(--sw-space-sm);
      font-size: 0.8125rem;
      line-height: 1.4;
      color: var(--sw-text);
      background: var(--sw-surface);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius-sm);
      box-shadow: var(--sw-shadow);
      /* hidden until revealed; visibility (not display) so aria-describedby still resolves and
         the reveal can transition. */
      opacity: 0;
      visibility: hidden;
      transition: opacity var(--sw-duration) var(--sw-ease),
                  visibility var(--sw-duration) var(--sw-ease);
      transition-delay: 120ms;   /* avoid flicker on pass-through; reset to 0 when shown */
    }
    /* Reveal on hover OR keyboard focus of the trigger. :hover is on the WRAPPER, and an
       adjacent (gap-free) bubble is a descendant, so moving onto the bubble keeps it open. */
    .sw-tooltip-wrap:hover .sw-tooltip,
    .sw-tooltip-wrap:focus-within .sw-tooltip {
      opacity: 1;
      visibility: visible;
      transition-delay: 0s;
    }
    /* Placements — adjacent (no margin gap) so the hover path stays continuous. Logical
       offsets so leading/trailing flip under RTL. */
    .sw-tooltip--top      { bottom: 100%; left: 50%; transform: translateX(-50%); }
    .sw-tooltip--bottom   { top: 100%; left: 50%; transform: translateX(-50%); }
    .sw-tooltip--leading  { inset-inline-end: 100%; top: 50%; transform: translateY(-50%); }
    .sw-tooltip--trailing { inset-inline-start: 100%; top: 50%; transform: translateY(-50%); }
    """)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TooltipTests`
Expected: PASS — all four tests green.

- [ ] **Step 5: Host build**

Run: `swift build`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/Tooltip.swift Tests/SwiflowUITests/TooltipTests.swift
git commit -m "feat(swiflowui): CSS-only Tooltip component

Stateless wrapper free fn: :hover/:focus-within reveal a role=tooltip bubble,
aria-describedby injected onto a single-element trigger, 4 placements, token-only
styling. No JS, no @Component. (No Escape-dismiss — CSS-only limitation.)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Demo gallery example + embed regen

**Files:**
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift`
- Modify (generated): `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Add a Tooltip example to the gallery**

In `examples/SwiflowUIDemo/Sources/App/App.swift`, find a gallery section near the other small components (e.g. the Badge/Button area) and add a Tooltip showcase following the surrounding section idiom (a heading + a row). Use this content:

```swift
Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
```

Match the neighboring section's wrapper (heading text + the `HStack`/row pattern already used for Buttons/Badges). Keep it brief — two triggers demonstrating default `.top` and `.bottom`.

- [ ] **Step 2: Build the demo locally (eyeball)**

Run: `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo 2>&1 | tail -2`
Expected: build exit 0. (Optionally serve and confirm the bubble appears on hover/focus.)

- [ ] **Step 3: Regenerate the embedded template**

Run: `swift scripts/embed-templates.swift`
Then confirm the freshness gate is satisfied:
Run: `swift test --filter TemplateEmbedder`
Expected: PASS — `EmbeddedTemplates.swift` now matches `examples/SwiflowUIDemo`.

- [ ] **Step 4: Commit**

```bash
git add examples/SwiflowUIDemo/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "feat(demo): Tooltip example in SwiflowUIDemo gallery (+ embed regen)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Docs + roadmap

**Files:**
- Modify: `docs/guides/swiflowui.md` (component list)
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md` (move Tooltip out of 1.1+ deferred)

- [ ] **Step 1: Add Tooltip to the component guide**

In `docs/guides/swiflowui.md`, in the component list/section, add a `Tooltip` entry near the other display/overlay components. Use this content:

```markdown
### Tooltip

A descriptive overlay shown on hover and keyboard focus. Wrap any trigger:

```swift
Tooltip("Delete permanently") { Button("Delete", variant: .danger) { delete() } }
Tooltip("Appears below", placement: .bottom) { Button("Below") {} }
```

CSS-only (no JS): `:hover`/`:focus-within` reveal a `role="tooltip"` bubble linked to the trigger
via `aria-describedby`. Placements: `.top` (default), `.bottom`, `.leading`, `.trailing`.

> Limitations (CSS-only): no Escape-to-dismiss (so it doesn't fully meet WCAG 1.4.13), and the
> bubble is not in the top layer, so an ancestor with `overflow: hidden` can crop it. For
> dismissable, top-layer overlays use `Dropdown`/Popover.
```

(If the guide uses a table of components rather than per-component sections, add a `Tooltip` row matching that format instead.)

- [ ] **Step 2: Move Tooltip out of the 1.1+ deferred list**

In `docs/future-work/swiflowui-1.0-roadmap.md`, find the "Deferred to 1.1+" line that lists
`… Menu/Dropdown; Tooltip; full ARIA hardening …` and remove `Tooltip; ` from it. Then add a
shipped note right after that paragraph:

```markdown
**Shipped since:** `Dropdown` and `Tooltip` (CSS-only; hover/focus, `aria-describedby`, 4 placements
— no Escape-dismiss/top-layer, see the component guide) have landed from the 1.1+ list.
```

(If the deferred line doesn't include `Dropdown` anymore, only mention `Tooltip` in the shipped note.)

- [ ] **Step 3: Verify + commit**

Run: `swift build && swift test --filter TooltipTests`
Expected: green (docs-only change; re-confirms nothing regressed).

```bash
git add docs/guides/swiflowui.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(swiflowui): document Tooltip; move it off the 1.1+ deferred list

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final review (after all tasks)

Dispatch a code-review subagent over `git diff origin/main...HEAD`. Verify: `Tooltip` is the only public addition (plus `TooltipPlacement`); the bubble is adjacent (no margin gap) so hover stays continuous; `aria-describedby` injection handles non-element triggers gracefully; styling is token-only (no hardcoded colors); `examples/` is consistent with the regenerated `EmbeddedTemplates.swift` (freshness gate green); and no `@Component`/JS was introduced. Then run `swift build && swift test` fully green and eyeball the demo (hover + keyboard-focus reveal, all four placements).
```
