# Swiflow non-reconciled children escape hatch (`.unmanagedChildren()`) — Design

> **Date:** 2026-06-29 · **Status:** approved, ready for implementation plan
> **Milestone:** the **non-reconciled subtree escape hatch** from roadmap **Cross-cutting #2**
> ("a richer element model"), and the SwiflowUI 1.1+ "richer element-model work" item.
> **Prior art:** the core diff/mount machinery (`Sources/Swiflow/Diff/Diff.swift`),
> `ElementData`'s out-of-band fields (`refBindings`, `taskBindings`), the `.ref(_:)` modifier
> (`Sources/Swiflow/DSL/EventModifiers.swift`).

## Problem

Swiflow reconciles every element's children against its own mount tree on every render. That is
correct for Swiflow-owned DOM but **stomps DOM that something else owns**: a custom element that
builds its own light/shadow children, a `<canvas>` painted by a foreign WASM module, a third-party
widget (date picker, chart, map) that injects nodes into a host element. The diff will remove or
reorder those foreign nodes the next time the owning component re-renders.

Roadmap Cross-cutting #2 calls for three things; **two already ship** and are out of scope here:
- **JS properties** — `.prop("name", value)` / `Attribute.property` + `PropertyValue`; the diff
  applies them via `element[name] = value`. ✅ shipped.
- **`CustomEvent` detail payloads** — the JS driver forwards `event.detail` as JSON
  (`js-driver/swiflow-driver.js:96`); `EventInfo.detail` + `Event.custom("…")` deliver it to any
  handler. ✅ shipped.
- **A "Swiflow does not reconcile inside this node" escape hatch** — ❌ **missing. This is the work.**

The only workaround today is informal: declare an element with no children and a `.ref`, relying on
the fact that Swiflow diffs against its own mount tree (so it never *sees* foreign children). It is
fragile — there is no declared contract, and if the element ever had Swiflow-mounted children the
diff would remove them.

## Goal

A first-class, declarative escape hatch that marks an element as **owning its own children**:
Swiflow creates and reactively manages the element *shell* (tag + attributes/properties/style/
handlers) but **never reconciles its children** after the initial mount — with **no JS driver or
patch-protocol change** (the diff simply emits fewer patches).

## Decisions (from brainstorming)

1. **Mechanism = `ElementData` flag + postfix modifier** (chosen over a new `VNode` case or pure
   convention). Minimal blast radius: one stored field + equality + one diff guard + one modifier.
   A new `VNode` case would touch every `switch` over `VNode` for no benefit; pure convention has no
   contract and is the fragile status quo.
2. **Name = `.unmanagedChildren()`** (postfix `VNode` modifier).
3. **Semantics = "render once, then hands-off inside."** Initial declared children mount exactly
   once (so a placeholder is possible); subsequent renders reconcile the element's four bags but
   never its children.
4. **No driver/protocol change** — purely a Swift-side patch-omission. No `embed-driver` regen.
5. **Scope = the escape hatch only** — JS properties and CustomEvent detail already ship.

## Mechanism

`ElementData` gains a stored flag:

```swift
/// When true, Swiflow mounts this element's initially-declared children once, then NEVER
/// reconciles inside it again — an escape hatch for elements that own their own DOM subtree
/// (custom elements with self-managed light/shadow children, a foreign-painted <canvas>, a
/// third-party widget). The element shell (tag + attributes/properties/style/handlers) is still
/// reactively reconciled; only the children are left alone. Set via `VNode.unmanagedChildren()`.
public var managesOwnChildren: Bool = false
```

It participates in `ElementData.==` (two nodes differing only in the flag are unequal), beside the
existing fields. It is **not** serialized — it never crosses the JS bridge; it only gates patch
generation on the Swift side. (Like `refBindings`/`taskBindings`, it is set after construction by a
modifier, so it need not be a parameter of the public `init`.)

The postfix modifier (in `Sources/Swiflow/DSL/VNodeModifiers.swift`, beside the other `VNode`
modifiers, using the existing `mergeAttribute` helper so non-element nodes get the standard DEBUG
diagnostic + passthrough):

```swift
/// Marks this element as managing its own children: Swiflow mounts the initially-declared
/// children once, then never reconciles inside it again (the element shell is still reconciled).
/// Pair with `.ref(_:)` to populate the element imperatively. A no-op on non-element nodes.
func unmanagedChildren() -> VNode
```

**Mount (`Diff.swift`, `.element` branch):** unchanged. The flag does not affect initial mount —
declared children (zero or more) mount normally, exactly once. (This is what makes an optional
placeholder work, and an empty children list yields a bare foreign-owned shell.)

**Update (`Diff.swift`, same-tag `.element` arm):** the only behavioral change. The element's four
bags still diff (attributes/properties/style/handlers); the children reconcile is guarded:

```swift
if !newData.managesOwnChildren {
    diffChildren(mounted: mounted, newChildren: newData.children, … )
}
```

So once mounted, an `.unmanagedChildren()` element's interior is never read or written by the diff —
foreign-added DOM survives every re-render. (`diffChildren` is the only path that touches a plain
element's children; component bodies are unaffected.)

**Unmount/replace:** unchanged. Destroying the element removes the whole subtree natively (correct
cleanup of foreign DOM too). A tag change replaces it (destroy + fresh mount), which re-runs any
`onAppear`/`.ref` foreign init — hence the contract below.

## Usage

```swift
// A <canvas> a foreign WASM module paints; Swiflow owns the element, not the pixels.
let canvas = Ref<JSObject>()
element("canvas", attributes: [.attr("width", 640), .attr("height", 480)])
    .ref(canvas)
    .unmanagedChildren()
// …in onAppear: hand canvas.wrappedValue to the draw module.

// A custom element that builds its own shadow DOM.
element("my-widget", attributes: [.attr("kind", kind)]).unmanagedChildren()

// A third-party widget mounted into a host div, with a placeholder until it loads.
element("div", children: [Spinner()]).ref(host).unmanagedChildren()
// …in onAppear: thirdPartyChart(host.wrappedValue)  — replaces the spinner; Swiflow won't touch it.
```

## Contract (documented in the guide)

- **Give an unmanaged element a stable position/key** so a sibling diff never destroys + remounts it
  (which would re-run foreign init / lose foreign state).
- **Re-renders that declare different children are intentionally ignored** — the first mount's
  children are what Swiflow puts there; everything after is the foreign owner's responsibility.
- **The flag should be constant for a given element position** (don't toggle managed↔unmanaged in
  place).
- The element **shell stays reactive** — its attributes/properties/style/handlers still update on
  re-render; only children are hands-off.

## Components & boundaries

| Unit | Change |
|------|--------|
| `ElementData` (`VNode.swift`) | new `managesOwnChildren: Bool = false`; add to `==` |
| `VNode.unmanagedChildren()` (`VNodeModifiers.swift`) | new postfix modifier (sets the flag via `mergeAttribute`) |
| `update()` same-tag `.element` arm (`Diff.swift`) | guard the `diffChildren` call on `!newData.managesOwnChildren` |
| docs/guides | escape-hatch note + `<canvas>`/custom-element examples |

All in core `Swiflow`. No JS driver, no patch opcode, no serializer change. Mount path unchanged.

## Testing

- **Unit (`Tests/SwiflowTests/…`, against the patch/mount-tree output):**
  - An `.unmanagedChildren()` element mounts its initially-declared children **once** (initial mount
    emits the expected child create/append patches).
  - A re-render whose VNode declares **different** children emits **no** child patches (no create/
    remove/move/setText for the interior).
  - A re-render that changes the element's **own** attribute/style still emits the bag patch (shell
    stays reactive).
  - `ElementData.==` returns false for two otherwise-equal nodes differing only in the flag.
  - Sanity: a normal (managed) element with the same shape still reconciles children (no regression).
- **`.unmanagedChildren()` on a non-element node** is a no-op (returns the node unchanged; DEBUG
  diagnostic), consistent with the other postfix modifiers.
- **Playwright e2e:** a demo element whose children are mutated imperatively (JS) survives a Swiflow
  re-render — the foreign nodes remain after the host component re-renders.
- **Host `swift build` + `swift test`** green (full suite — this is core, so CI runs it).

## Non-goals

- **No JS properties / CustomEvent-detail work** — both already ship.
- **No new `VNode` case**, no patch-protocol/driver change.
- **No shadow-root ownership model, no "expose a Swiflow component as a custom element"** — those
  are the larger B1 web-components track; this is only the reconciliation escape hatch they depend on.
- **No automatic key/identity management** — the caller keeps an unmanaged element stable (contract).
- **No "freeze the whole node" (attributes too)** — only children are unmanaged; the shell stays
  reactive.

## Decisions resolved during brainstorming

1. **Two of roadmap #2's three items already ship** (JS properties, CustomEvent detail) → scope is
   the escape hatch only.
2. **Mechanism** → `ElementData` flag + postfix modifier (new-`VNode`-case and pure-convention
   rejected).
3. **Name** → `.unmanagedChildren()`.
4. **Semantics** → mount initial children once, then never reconcile inside; element shell stays
   reactive.
5. **No driver change** → the diff simply omits child patches for the marked element.
