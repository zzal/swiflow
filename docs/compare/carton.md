# Swiflow vs Carton + Tokamak

A structural comparison of Swiflow against the prevailing Swift-on-the-web
stack: [Carton](https://github.com/swiftwasm/carton) (build/dev tool) combined
with [Tokamak](https://github.com/TokamakUI/Tokamak) (SwiftUI-compatible UI
framework).

> **Scope note.** This report deliberately sets aside "maturity" arguments
> (number of contributors, GitHub stars, issue counts, time in production).
> Those are real but not interesting — they describe where the projects
> *are*, not what their designs imply they *can be*. This report compares
> the architectures.

## Framing: the comparison is asymmetric

Carton and Tokamak are two tools that compose. Swiflow aspires to be a single
integrated stack that covers both responsibilities:

| Responsibility | "Other stack" | Swiflow |
| --- | --- | --- |
| Build & dev server | Carton | Phase 2b/2c CLI (`swiflow init/build/dev`) — **planned** |
| Runtime (VDOM, diff, bridge) | Tokamak | `Swiflow` + `SwiflowDOM` — **shipping in Phase 2a** |
| UI authoring DSL | Tokamak (SwiftUI-shaped) | Swiflow (HTML-shaped) |
| Bridge to JS | Tokamak's reconciler talks directly to JSKit | `Swiflow` emits a patch list; vanilla JS driver applies it |

The runtime comparison is meaningful today. The CLI comparison is a
comparison of an existing tool against a roadmap promise — treated as such
below.

---

## Where Swiflow's design wins

These are architectural choices that survive any honest comparison,
independent of project maturity.

### 1. One bridge crossing per render

The single most important decision in any Swift-WASM web framework is how
often it crosses the WASM/JS boundary. JavaScriptKit interop is not free;
every `JSObject` access pays a serialization cost. In benchmarks of
Swift-on-web rendering, bridge crossings — not Swift execution — dominate
total render time.

Swiflow batches **every** mutation from a render cycle into a single `JSArray`
and ships it in one `window.swiflow.applyPatches(...)` call
(`Sources/SwiflowDOM/Renderer.swift:41-49`). Tokamak's reconciler
issues many small JS calls per node mutation as it walks the diff.

This is the central perf premise of the framework and it is correct.

### 2. Honest web mental model

Swiflow's DSL is HTML-shaped:

```swift
div(.class("container")) {
    h1("Hello, Swiflow!")
    ul {
        for item in items {
            li(.key(item.id)) { p(item.text) }
        }
    }
}
```

What you write maps 1:1 to what you inspect in DevTools. The DSL is just
sugar over a `VNode` tree whose structure mirrors the DOM.

Tokamak makes you write SwiftUI (`VStack`, `Text`, `.padding()`, etc.) and
silently translates to HTML/CSS. When SwiftUI semantics map cleanly to the
web (most of the time), that's a nice abstraction. When they don't (z-order,
flexbox, scroll containers, focus, accessibility), you're forced to either
escape the abstraction or fight it. Swiflow has no such gap because there is
no abstraction to fight.

### 3. The patch list is a clean intermediate representation

The contract between `Swiflow` and any backend is:

- 16 opcodes (`Sources/Swiflow/Patch.swift`)
- Integer handles for DOM nodes, allocated Swift-side
- A JSON-shaped serialization (`PatchSerializer`)

This is a serializable, testable, transport-agnostic IR. You could swap the
JS driver for:

- a snapshot renderer for tests
- a server-side renderer that emits HTML
- a native renderer for an Electron-style host
- a record/replay driver for time-travel debugging

…without touching the Swift side. Tokamak's reconciler is more entangled
with its renderer backends; swapping is a much heavier operation.

### 4. Vanilla, dependency-free JS driver

`js-driver/swiflow-driver.js` is one file, zero dependencies, no build step.
It is readable end-to-end in 10 minutes and debuggable directly in DevTools —
the opcodes flowing through are exactly what you read in the source. For
security-sensitive deploys, the auditable surface is enormous.

Tokamak's runtime is structurally much larger and harder to vendor or audit.

### 5. Auditable XSS surface

Exactly one escape hatch (`rawHTML(_:)`), loud name, grep-able:

```bash
rg "rawHTML\("
```

That call enumerates every site where unsanitized markup can reach the DOM.
This is a defensible security posture by construction. Tokamak's surface is
much wider; finding every potential injection site is a research project.

### 6. Smaller WASM bundle (structural, not maturity)

Tokamak's runtime mirrors a large slice of SwiftUI's API surface. Swiflow's
runtime is ~10 source files plus a DSL. All else being equal, a Swiflow app
should produce meaningfully smaller `.wasm` than a Tokamak app — and *can
never lose this comparison even at full maturity*, because Swiflow never
opted into that scope.

For web, where every kilobyte over the wire affects time-to-interactive,
this is a real product differentiator.

### 7. Vite-inspired integrated CLI (planned)

Carton is a build/serve tool. The Swiflow Phase 2b/2c roadmap promises
`init / build / dev` as one integrated experience with conventions baked in.
If executed, that's a meaningfully better DX than `carton + your own Tokamak
config + your own bundling story`.

This is a promise today, not a feature.

---

## Where Tokamak's design wins

These are not "Swiflow will catch up" gaps. They are load-bearing pieces of
any real UI framework that Tokamak has and Swiflow does not.

### 1. State primitives exist

Tokamak gives you `@State`, `@Binding`, `@ObservedObject`, `@Environment` —
the SwiftUI data-flow vocabulary. Swiflow gives you a global `var count` and
a manual `Swiflow.rerender()` call, as shown in the Phase 2a HelloWorld
example (`examples/HelloWorld/Sources/App/App.swift:11-32`).

For any non-trivial app, you would hand-roll your own state layer on top of
Swiflow. Phase 3 will add this, but today, *the framework has no opinion
about where state lives*.

### 2. A render scheduler exists

SwiftUI's data-flow semantics naturally coalesce multiple state mutations
into one reconcile pass. Tokamak inherits this property.

Swiflow renders synchronously on every `rerender()` call. There is **zero**
batching across renders:

```
$ grep -rn -i "requestAnimationFrame\|raf\|schedule\|debounce\|throttle\|setTimeout\|queueMicrotask" Sources/ js-driver/
# zero matches
```

Ten `rerender()` calls in one event handler = ten full diff cycles + ten
bridge crossings + ten patch encodes. This is fine for toy apps; it is
wasteful for any UI with multiple state mutations per event.

### 3. Component model exists

Tokamak has `View` composition with identity, lifecycle hooks
(`onAppear`/`onDisappear`), and encapsulated per-component state.

Swiflow is "function returns VNode." There is no per-subtree identity, no
lifecycle, no way for a subtree to own its own state. You can structure
functions however you like, but the framework provides no support for
component-as-a-unit-of-organization.

### 4. A layout system exists

Tokamak inherits SwiftUI's stacks, frames, spacers, alignment guides, and
preference keys. You declare layout intent and the framework handles it.

Swiflow gives you raw HTML — meaning **you write CSS by hand**. For Swift
developers who chose Swift-on-web specifically to escape CSS+JS, this is a
regression. For Swift developers who are comfortable with the web platform
and want HTML/CSS exposed, it is a feature. The audience split is real and
worth being explicit about.

### 5. Accessibility scaffolding exists

Tokamak maps SwiftUI accessibility modifiers to ARIA attributes
(imperfectly, but present). Swiflow can carry any ARIA attribute through its
`attributes` bag, but provides zero guidance, zero defaults, zero typed API.
Accessibility is 100% on the developer.

### 6. UI is typed at compile time

Tokamak's typed modifiers catch typos and illegal attribute/element
combinations at compile time. Swiflow's surface DSL is typed
(`.class(...)`, `.key(...)`, `.on("click", ...)`) but the underlying bags
are stringly-typed:

```swift
attributes: [String: String]
style:      [String: String]
handlers:   [String: EventHandler]
```

Typos in attribute names, illegal attribute/element combinations, and
platform-specific quirks surface at runtime, not compile time. A typed HTML
schema (along the lines of `swift-html`) would close this gap but does not
exist in Swiflow today.

### 7. Cross-platform code reuse

A Tokamak codebase can — with caveats — share view code with a real SwiftUI
app on iOS/macOS. That is Tokamak's entire pitch.

A Swiflow codebase is web-only by construction, because the DSL *is* HTML.
If the business case is "one Swift codebase across iOS + macOS + Web,"
Tokamak wins on premise alone and Swiflow can never win there.

### 8. View identity makes diff cheap

SwiftUI's `View` value-equality gives the framework free structural identity
for diffing. Swiflow's diff has to compute structural identity from the
VNode tree on every render. This is not a bug — Swiflow's diff is well-built
(hybrid index-pair + two-pointer + Map + LIS) — but it is work the SwiftUI
model gets for free.

---

## The performance crossover

The "one bridge crossing per render" win has a floor. For a single attribute
change:

- Swiflow pays: build a one-element `JSArray`, encode the patch object,
  cross the bridge once, driver iterates a 1-element loop, calls
  `setAttribute`.
- Tokamak pays: cross the bridge once, call `setAttribute`.

Below a handful of patches per render, Tokamak's per-call approach is
competitive. Above that, Swiflow's batching pulls ahead, and the lead
widens with scale.

The crossover point has not been measured. Empirically determining it would
be a useful Phase 2b/2c benchmark.

Practical implication:

| App shape | Likely winner today |
| --- | --- |
| Tiny UI, rare updates, needs SwiftUI primitives | Tokamak |
| Real app, non-trivial trees, frequent updates | Swiflow architecture |
| Bandwidth-constrained users | Swiflow architecture (bundle size) |
| Sharing view code with iOS/macOS | Tokamak (Swiflow can't compete) |
| Auditability / security-sensitive | Swiflow (smaller, transparent IR) |

---

## Side-by-side summary

| Dimension | Swiflow | Carton + Tokamak |
| --- | --- | --- |
| Mental model | HTML-shaped, web-native | SwiftUI-shaped, translated to web |
| Bridge crossings per render | **1** (batched) | many (per-mutation) |
| Diff IR | Public, 16 opcodes, serializable | Internal to reconciler |
| JS-side runtime | One vanilla file, no deps | Larger, more entangled |
| State primitives | None (manual `rerender()`) | `@State` / `@Binding` / etc. |
| Render scheduler | None (synchronous) | SwiftUI data-flow coalescing |
| Component lifecycle | None | Full `View` lifecycle |
| Layout system | None (you write CSS) | SwiftUI layout primitives |
| Accessibility | None (you wire ARIA) | SwiftUI a11y → ARIA mapping |
| UI compile-time typing | DSL typed, attribute bags stringly | Typed modifiers throughout |
| WASM bundle size | Smaller (structural) | Larger (mirrors SwiftUI surface) |
| Cross-platform reuse | Web-only by construction | Shares with SwiftUI on Apple platforms |
| XSS audit surface | One escape hatch | Wider |
| CLI / dev server | Phase 2b/2c roadmap | Carton, shipping |

---

## Honest TL;DR

**Swiflow's biggest real architectural win** is the patch-list IR plus the
single-bridge-call protocol. That is a genuinely different and better
foundation than Tokamak's "reconciler talks directly to JS" approach for
the web specifically. Combined with smaller bundles and an auditable
driver, it gives Swiflow a defensible identity that doesn't depend on
catching up to Tokamak.

**Swiflow's biggest real architectural limitation** is the absence of a
component model and a render scheduler. These are not maturity gaps — they
are load-bearing pieces of any UI framework, and the design choices for
both have not been made yet (both are Phase 3 work). Until they exist,
Swiflow is a proving ground for the bridge protocol, not an alternative
for shipping real apps.

**Strategic positioning takeaway.** Swiflow wins when the pitch is
*"embrace the web platform, batch the bridge, expose a clean IR, ship
small bundles."* Swiflow loses when the pitch drifts toward *"SwiftUI but
for the web,"* because Tokamak has the right architecture for that pitch
and Swiflow doesn't. Choose the pitch that plays to the design.
