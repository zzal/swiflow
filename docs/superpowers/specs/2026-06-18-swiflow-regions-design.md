# Swiflow Regions — polyglot opaque-canvas guests

**Status:** Design / pre-implementation
**Date:** 2026-06-18 (rev. 3 — adds the taylor-otwell-reviewer API-taste pass; rev. 2 incorporated the swift-innovator-expert code-verified review)
**Author:** brainstormed with Claude

## Summary

Let a Swiflow layout host a **region** whose pixels are drawn by an external,
separately-compiled WebAssembly guest (Rust/C/AssemblyScript/Zig) — the
"`<iframe>` for wasm" idea, scoped to an **opaque canvas**. Swiflow owns the
element's *box* (create, position, size, destroy); the guest owns the *pixels*
and never touches the host DOM. The two communicate over a small, versioned
**Swiflow Region Protocol**: props flow in, typed events flow out.

The design is a deliberate **hybrid** of three boundary options considered
during brainstorming:

- **Web Component as the transport boundary** (`<sf-region>`) — so Swiflow
  renders it through the VNode model it *already has* and guests stay
  framework-agnostic.
- **A typed, versioned protocol layered on top** (the Component-Model
  *discipline*: shared-nothing, typed messages) — without paying the
  impossible bill of a pure "host-provides-graphics-imports" core-wasm ABI.
- **Raw "mount as-is" as a documented escape hatch** (deferred to v1.1).

## Why not "build on WASI 0.3 / the Component Model"

Researched 2026-06-18. The conclusions that shaped this design:

1. **WASI ≠ Component Model.** WASI (incl. 0.3, released 2026-06-11) is a
   *system interface* (files/sockets/clocks); its 0.3 headline feature is
   native async I/O composition — a server/edge concern, largely redundant in
   the browser where the JS event loop already provides async. The thing worth
   borrowing is the **Component Model** underneath: typed WIT interfaces +
   shared-nothing linking.
2. **Nothing runs the Component Model natively in a browser.** It can't reach
   1.0 until two engines ship it. The only browser path is `jco transpile` →
   core modules + generated JS glue — which is conceptually *what Swiflow's JS
   driver already is*.
3. **Swift can't cleanly produce/consume components.** `wit-bindgen` has no
   Swift guest generator; SwiftWasm emits `wasi_snapshot_preview1` core
   modules. So "Swiflow-as-a-component" is a research project; Swiflow-as-host
   realistically stays **core-wasm + its JS driver**.
4. **In the browser, guest pixels need graphics imports (WebGL/WebGPU/2D) that
   come from JS glue regardless.** Re-deriving those as host-provided wasm
   imports is a multi-year project. So the boundary we design is the
   *lifecycle + messaging* contract, **not** the pixel contract.

**Decision:** adopt the Component Model's *interface discipline* (typed,
versioned, shared-nothing messages; a protocol that is transcribable to WIT
later), implement it over what runs in the browser today (custom element +
worker), and do **not** pin the architecture to WASI 0.3.

## The two-contracts framing

The "bridge" is two separate contracts, and we only own one of them:

| Contract | Owner | Notes |
|---|---|---|
| **Lifecycle + messaging** (mount/resize/visibility, props-in, events-out) | **Swiflow** (this design) | Typed, versioned, batched. Where the value is. |
| **Pixels** (WebGL/WebGPU/canvas2d) | **Guest's own toolchain** (wasm-bindgen / Emscripten / wgpu) | Swiflow never touches it. |

## Architecture

```
  Swift (WASM)                JS driver (main thread)            Web Worker
 ┌────────────┐   patches    ┌──────────────────────┐  port   ┌─────────────┐
 │ region(...) │ ──────────▶ │  <sf-region> element │ ◀═════▶ │ worker shim │
 │ in @Component             │  • custom element    │ Offscr. │  + guest    │
 │            │ ◀────────── │  • props→worker (rAF) │ Canvas  │   wasm       │
 └────────────┘  __swiflow   │  • CustomEvent←worker │ ──────▶ │  (own glue) │
                 Dispatch     └──────────────────────┘         └─────────────┘
```

**Load-bearing claim, corrected.** `region(...)` lowers to a plain
`.element(tag: "sf-region")` carrying the existing `properties` bag (props-in),
`handlers` bag (events-out registration), and `style` bag (sizing). Swiflow's
diff already creates/positions/sizes/destroys an element with an arbitrary tag
(`VNode.swift:28-29,59`; driver `createElement(p.tag)` is unfiltered,
`swiflow-driver.js:103`) and `Patch.setProperty` is already generic
(`Patch.swift:50`). So there is **no new VNode kind and no new patch op.**

The earlier draft's claim that events-out "route through the existing
`__swiflowDispatch` path *unchanged*" was **wrong** and is corrected here (see
*Serialization*): carrying an event payload requires **one additive field on
`EventInfo`** and **one line in the driver's `serializeEvent`**. That's the
entire net-new core surface; everything else is reuse or lives in separate
browser-only assets.

**Two invariants that make "opaque interior" true:**

1. **`<sf-region>` carries zero Swiflow children.** The diff *always* reconciles
   `.element` children (`Diff.swift:169-190`); "Swiflow never diffs the interior"
   holds *only* because `region(...)` emits no child VNodes. The `<canvas>` is
   created **internally** by the custom element in `connectedCallback`, not as a
   Swiflow VNode.
2. **The fallback is a *sibling*, never a child** of `<sf-region>` (see
   *Fallback rendering*). This resolves the contradiction in rev. 1, where the
   fallback slot implied Swiflow-managed interior content.

### Components

| Component | Layer | Responsibility |
|---|---|---|
| `region(...)` DSL + sizing/`.onEvent`/`.onError` modifiers | Swift — **JSKit-free**, pure VNode construction | Build the `<sf-region>` VNode: encoded props, handler closures, sizing, identity. Compiles under `swift test`. |
| Region props/event codec | Swift — **foundation-free** | `Encodable` props → JSON `String` (reuses SwiflowStore's encoder pattern); JSON `String` → typed `RegionEvent`. |
| `<sf-region>` custom element | JS (separate asset) | Create internal canvas, `transferControlToOffscreen()` (once), spawn worker, forward props (rAF-coalesced), dispatch `CustomEvent`s, observe size/visibility, lifecycle. |
| Worker shim | JS (separate asset) | Instantiate guest wasm, own the OffscreenCanvas, translate protocol ↔ guest exports/imports. |
| Guest SDK | Rust crate + JS shim | ~5-line conformance: wrap a normal wasm-bindgen canvas as a conforming guest. |
| Reference guest | Rust | Canonical example + e2e fixture + demo. |
| DevTools Regions panel | Extension | Inspect live regions (status, size, last props, recent events, FPS). |

## Swift author API

A guest's contract — `source` + `Props` + `Event` — is declared once as a
`RegionGuest` type. Binding the three together is what lets every handler
*infer* its event type, so call sites carry **no type annotations**:

```swift
struct SceneProps: Encodable { var count: Int; var hue: Double }
struct SceneEvent: RegionEvent {                 // RegionEvent: Decodable
    enum Kind: String, Decodable { case select, hover }
    let kind: Kind
    let id: Int
}
enum Scene: RegionGuest {                         // the contract, authored once
    typealias Props = SceneProps
    typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

region(Scene.self, key: "hero", props: SceneProps(count: n, hue: h))
    .onEvent { e in selected = e.id }            // e: SceneEvent — inferred, no annotation
    .onError { err in showStaticPreview = true }  // graceful fallback (sibling)
    .fill()                                        // sizing (default if omitted)
```

`region(_:key:props:)` returns a typed `RegionView<Scene>` (lowering to the same
`<sf-region>` VNode), so `.onEvent`'s closure parameter is `Scene.Event`
inferred. A **secondary inline form** serves quick/dynamic guests that skip the
type declaration — at the cost of one annotation per handler:

```swift
region(source: "regions/scene.wasm", key: "hero", props: someEncodableProps)
    .onEvent { (e: SceneEvent) in selected = e.id }   // annotation needed here
```

Design choices, all flowing from the reviews:

- **Typed-guest form is primary; inference deletes the annotation.** Binding
  `Props`+`Event`+`source` to a `RegionGuest` type doesn't just make misuse
  unrepresentable (you can't hang a `SceneEvent` handler on a `ChartProps`
  region) — it *infers* the event type at every call site. The inline `source:`
  form stays for one-offs.
- **`source:`, not `guest:`.** A bare URL is a *where*, not a *who*: `guest` is
  the **type** (`Scene.self`); `source` is its URL (the `static let`, or the
  inline label). Matches the `guest-src` vocabulary used throughout.
- **Typed events, not an untyped dict.** The fix for the events-out blocker
  doubles as the API's best feature: the framework decodes the envelope payload
  into the author's `RegionEvent` type — replacing rev. 1's unimplementable
  `e.detail["id"]`.
- **`.onEvent`, not `.on`.** The existing `.on(Event)` modifier
  (`EventModifiers.swift:30-58`) attaches DOM listeners and receives the
  fixed-shape `EventInfo`. Region events are a *different channel*; overloading
  `.on` would conflate them. `.onError` is the symmetric error channel.
- **`key` stays `key`, and stays required.** Swiflow's identity vocabulary is
  already `key` (`ElementData.key`, `embedKeyed`, the "encode changing identity
  in the embed key" rule this spec's HMR survival mirrors). A missing/unstable
  key silently re-instantiates the worker and drops the guest's GL state, so it
  is a **required, visible** constructor argument — not a forgettable `.id()`
  modifier.
- **No `@RegionProps` macro in v1 (Swift side).** Macros tax the WASM
  cross-compile and this repo has been bitten by macro/cross-compile
  interactions. A Swift macro to derive a compact binary codec is a
  *post-profiling* optimization, explicitly deferred. (A *Rust* proc-macro in
  the guest SDK is fine — different toolchain; see Guest authoring.)

Sizing options (all pure host/CSS — the guest only ever sees device pixels):

- `.fill()` — `width:100% height:100%`; **the default when no sizing modifier
  is given.**
- `.frame(width:height:)` — fixed CSS px (still DPR-tracked).
- `.aspectRatio(16, 9)` — self-sufficient: CSS `aspect-ratio`, fills available
  width, height derives. (Two ints, not `16/9` — a bare ratio would be Swift
  integer division.)

## Guest authoring (the SDK)

The "~5-line conformance" promise, made concrete. The Rust guest SDK ships a
`#[region]` proc-macro that generates the worker entry + envelope wiring; the
author writes only a trait impl:

```rust
use swiflow_region::{region, Guest, Canvas};

#[region]                                  // generates worker entry + protocol plumbing
impl Guest for Scene {
    type Props = SceneProps;               // #[derive(Deserialize)] — decoded from JSON
    type Event = SceneEvent;               // #[derive(Serialize)]   — emitted as JSON

    fn init(canvas: Canvas) -> Self { Scene::new(canvas) }   // OffscreenCanvas handle
    fn props(&mut self, p: SceneProps) { self.apply(p); }    // host → guest
    fn frame(&mut self, dt: f32) { self.render(dt); }        // optional rAF tick
    fn resize(&mut self, w: u32, h: u32, dpr: f32) { /* … */ }
    // emit with `region::emit(SceneEvent { kind: .Select, id })`
}
```

`init` and `props` are the only required methods; `frame`/`resize` are
defaulted. The macro is Rust-side, so it never touches the Swift WASM
cross-compile.

## Serialization & the foundation-free constraint

**This is the section rev. 1 was missing, and the review's `JSONEncoder`
suggestion is wrong for the runtime.** Foundation's `JSONEncoder`/`JSONDecoder`
are **unavailable under WASM** — explicit in `SwiflowFetcher/HTTPClient.swift:32`
and `SwiflowStore/JSONValueEncoder.swift:5`; core `Swiflow` has no
`import Foundation`. Every `JSONEncoder` in the tree is host-side (`SwiflowCLI`).
So:

### Props-in (Swift → guest)

- `region(...)` encodes `props: some Encodable` to a JSON `String` using a
  **foundation-free encoder** — promote/reuse the proven
  `SwiflowStore/JSONValueEncoder` into a shared internal utility (pure Swift, no
  Foundation, **no JavaScriptKit**, so `region(...)` stays testable on macOS).
- That string is set as the DOM property **`sfProps`** — a
  `PropertyValue.string` (`PropertyValue.swift:5-14` is primitives-only, so a
  string is the only viable carrier; no new `PropertyValue` case). It rides the
  existing `setProperty` patch (`Patch.swift:50` → `swiflow-driver.js:178-194`,
  which does `node.sfProps = "<json>"`).
- **Diff/dedup:** props compare as one opaque string — any field change re-sends
  the whole blob. With per-frame coalescing on the element side this is fine.
  Bound the blob size with a dev-mode warning.
- The element forwards the raw string to the worker; the worker parses it once.

### Events-out (guest → Swift) — the corrected wire

The guest `emit`s a JSON payload → worker → `<sf-region>` dispatches
`CustomEvent("sf:event", { detail })`. To carry `detail` to Swift:

1. **Driver** (`serializeEvent`, `swiflow-driver.js:75-93`): add **one general
   line** — `if (event.detail !== undefined) out.detail = JSON.stringify(event.detail)`.
   Backward-compatible; benefits any CustomEvent. *(This is a core-driver edit →
   it triggers the embed/sync dance — see Asset placement.)*
2. **`EventInfo`** (`VNode.swift:158-223`): add **`detail: String? = nil`**.
   A `String` keeps `EventInfo` `Sendable` and keeps core `Swiflow` free of
   JavaScriptKit (the JS payload must **not** cross as a `JSObject` — that would
   break both the Sendable guarantee and the core/DOM layering, since
   `DispatcherBridge` is the only JSKit-aware piece, `DispatcherBridge.swift:3`).
3. **`DispatcherBridge`** (`DispatcherBridge.swift:34-57`): read
   `payload.detail.string` into `EventInfo.detail`.
4. **Typed decode** (in the region module, which *may* use JSKit): `.onEvent`
   registers an internal `EventHandler` for `"sf:event"` that decodes
   `EventInfo.detail` into the author's `RegionEvent`.

### The decoder gap (key implementation decision)

The repo has a foundation-free *encoder* but **no general foundation-free JSON
*decoder***. Two viable v1 paths for step 4 — pick during planning:

- **(a, preferred) Ship a small foundation-free JSON decoder** mirroring
  `JSONValueEncoder`. Symmetric, pure Swift, **unit-testable on macOS**, no
  browser needed for the decode path.
- **(b, fallback) Decode at the browser layer** via native `JSON.parse`
  (`JSObject.global.JSON`) + JavaScriptKit value-coding/manual `JSObject` field
  reads. No macOS test coverage for decode; browser-only.

Recommend (a) for testability and core-purity; (b) is the escape hatch if (a)
proves heavy.

## The Swiflow Region Protocol (v1)

Versioned envelope; **v1 framing is JSON** (debuggable; a compact binary frame
is the deferred macro/profiling path):

```
Envelope = { v: 1, kind, payload }

Host → Worker
  init    { payload: { protocol: 1, size: {w,h,dpr}, props: "<json>"|null, options } }
          // posted together with the transferred OffscreenCanvas
  props   { payload: "<json>" }            // raw guest props JSON, verbatim
  resize  { payload: { w, h, dpr } }       // device pixels
  pause | resume | destroy { }

Worker → Host
  ready   { payload: { protocol: 1, guest?: { name, version } } }
  event   { payload: "<json>" }            // → CustomEvent("sf:event", { detail: <parsed> })
  error   { payload: { code, message } }   // → CustomEvent("sf:error", { detail })
```

**Version negotiation:** host advertises `protocol: 1` in `init`; guest echoes
its supported `protocol` in `ready`. On incompatibility (guest can't satisfy the
host version, or no `ready` within the timeout, or an explicit
`error{code:"protocol-mismatch"}`), the host enters the error state and
dispatches `sf:error`. The protocol is the guest's **entire capability surface**
beyond its pixels — which is what makes the worker sandbox meaningful — and is
deliberately **transcribable to WIT** later.

**Data channel** (optional `MessagePort` for high-rate byte streams that bypass
the DOM event system): **deferred** to when a guest needs it.

## Sizing & the mandatory resize broadcast

A canvas has two sizes on opposite sides of the worker boundary:

| | Lives where | Set by |
|---|---|---|
| **CSS/layout size** | Main thread (`<sf-region>`) | CSS — px, %, flex, grid, `aspect-ratio` |
| **Drawing-buffer size** | The **worker** (post-`transferControlToOffscreen()`) | `canvas.width/height`, device pixels |

After transfer, **layout stays on the main thread** — the worker cannot observe
the laid-out size. Therefore **`resize` is a guaranteed, always-on part of the
contract**, not an optional event. This holds even for fixed sizing, because
*pixel* size still changes when `devicePixelRatio` changes (zoom, multi-monitor).

Mechanism (host side, browser primitives only):

- A **`ResizeObserver`** per region observing `box: 'device-pixel-content-box'`
  (size already × DPR → exact buffer dimensions, no manual math).
- **Fallback** where `device-pixel-content-box` is unsupported (older Safari):
  `content-box × devicePixelRatio` — **and** on this path you must *also* listen
  for DPR changes via `matchMedia('(resolution: …dppx)')`, because the
  content-box observer alone won't fire on a zoom/monitor change. (The primary
  path needs no `matchMedia`; the fallback does.)
- Coalesce to **one `resize` message per animation frame**; post only on actual
  change.
- Worker sets `offscreen.width/height`, calls guest `on_resize(w,h,dpr)`.
  Resizing a canvas buffer **clears it** and resets the GL viewport — the guest
  SDK redraws after resize.
- **Initial size + props are latched and replayed at `ready`** (see Lifecycle),
  so the guest never paints into the canvas default of **300×150**.

## Lifecycle & HMR

Mount/teardown ride the custom element's native callbacks — no new Swiflow
lifecycle machinery:

- **`connectedCallback`** → create internal `<canvas>` → **`transferControlToOffscreen()`
  (exactly once)** → spawn worker → `postMessage(offscreen, [offscreen])` →
  send `init` (latched `{w,h,dpr}` + latest props) → guest emits `sf:ready`.
- **`pause`/`resume`** → `IntersectionObserver` + `document.visibilitychange`
  stop the guest's rAF when off-screen / tab hidden.
- **`disconnectedCallback`** → `destroy` → `worker.terminate()`, disconnect both
  observers, close the `MessagePort`.

**The one-shot-transfer invariant.** `transferControlToOffscreen()` can be
called **only once** per canvas. The element creates the canvas and transfers
exactly once at first connect and **never** recreates or re-transfers for its
lifetime.

**HMR survival is *implemented by* the keyed diff, not a special path.** A
region's identity is **`guest-src` + `key`**. On a Swift hot-swap (which
preserves `@State`), the keyed-children diff **matches the existing
`<sf-region>` and emits no destroy/create** when identity is unchanged — so the
element stays connected, the canvas stays transferred, and the worker keeps
running; only `sfProps` updates flow. If `guest-src` or `key` changes, the diff
destroys the old element (→ `disconnectedCallback` → terminate) and creates a
fresh one (new canvas + worker). This mirrors the existing `embed()`
instance-reuse rule ("encode changing identity in the key") — document them
together.

**Quiescence / replay.** Because the surviving element is never disconnected
during HMR, there is no teardown window to coordinate: the element latches the
*most recent* `{w,h,dpr}` and `sfProps`, replays them only on first
`ready`, and afterward just forwards property updates through its own rAF — which
naturally serializes against in-flight worker messages. (A resize *during* HMR
will clear+redraw the buffer; acceptable, but note it can briefly flash the very
state HMR survival protects, so coalesce aggressively.)

## Fallback rendering

`.onError` flips host `@State`; the app conditionally renders a **sibling** node
(e.g. a static `<img>` preview) — or simply stops rendering the `region(...)`
node, which unmounts the element and terminates the worker. The fallback is
**never interior** to `<sf-region>` (that would re-introduce Swiflow-managed
children and fight the diff). The error path must also disconnect the observers
and close the port even when the element is *not* removed (e.g. app keeps the
region mounted but hidden).

## Loading, dev server, service worker

- Guest wasm is a project asset (e.g. `public/regions/*.wasm`); the dev server
  already serves arbitrary `public/` files and `.wasm` as `application/wasm`
  (`HTTPRouter.swift:82`) — so dev serving is free.
- **Service-worker rationale (corrected).** The current `swiflow-sw.js` *does*
  call `self.skipWaiting()` (`:132`) and sha256-verifies before caching
  (`fetchVerifiedInto`, `:76-93`) — rev. 1's "no skipWaiting / no hash check"
  was stale. Content-hashed guest URLs (`scene.<hash>.wasm`) are still the right
  call, **but for a different reason**: guest assets aren't in
  `swiflow-manifest.json`, so they're never precached and fall through to
  network on cache-miss (`:153-159`). A hashed URL guarantees a changed guest is
  a changed URL.
- **Shared module cache.** Two regions with the same `guest-src` must **not**
  double-fetch/double-compile. Cache the compiled `WebAssembly.Module` by
  hashed URL and instantiate per-worker from it.
- **Cross-origin isolation.** Threaded guests (SharedArrayBuffer) need COOP/COEP.
  v1 keeps guests **single-threaded, same-origin** — and this is a **guest-build
  contract**, not just a host posture: a guest's toolchain output *must not
  require `SharedArrayBuffer`* (some wgpu/Emscripten builds enable it by
  default and will fail silently without COEP). Document the contract; COOP/COEP
  opt-in for threaded guests is deferred.

## Error handling — never crash the host

| Failure | Response |
|---|---|
| wasm 404 / instantiate fails / `transferControlToOffscreen` unsupported | element → error state, `sf:error`, **sibling fallback** |
| OffscreenCanvas/WebGL-in-worker unsupported (Safari floor) | `sf:error` + clear diagnostic; degrade, don't break |
| guest traps / worker crashes | caught → `sf:error`, optional `restartPolicy: .once/.never` |
| no `sf:ready` within timeout, or `protocol-mismatch` | error + diagnostic |
| malformed / oversized envelope from guest | drop + `sf:error`, never `postMessage` a non-cloneable payload |
| props fail to encode (Swift side) | dev-mode trap with the offending type; never ship a partial blob |
| `webglcontextlost` / `GPUDevice.lost` | protocol `context-lost` lifecycle message → guest SDK restore hook |

## Observability — DevTools Regions panel

Pillar #3. Add a **Regions** section to the existing panel listing each live
region: `guest-src`, protocol version, worker status
(booting/ready/paused/errored), current pixel size + DPR, last props payload, a
rolling log of recent events-out, and guest-reported FPS. Because the protocol
is framed/typed, this is just tapping the message stream.

## Security posture (v1)

Worker + opaque-canvas = strong isolation by default: the guest holds **only**
an OffscreenCanvas and one MessagePort — no host DOM, separate linear memory,
shared-nothing. **The protocol *is* the capability surface.** v1 targets
*trusted-but-isolated* first-party, same-origin, single-threaded guests. The
untrusted-third-party-plugin capability system is a separate use case (out of
scope) and this boundary is forward-compatible with it.

## Asset placement

The custom-element + worker-shim code ships as a **separate, on-demand asset**
(`swiflow-regions.js`), **not** folded into `swiflow-driver.js`: apps that don't
use regions pay zero bytes, and it trips none of the three byte-equality gates
keyed to the driver/SW files (`embed-driver.swift:21-22`,
`DriverEmbedderTests.swift:23-39`, `TemplatesTests.swift:30-39`). **Exception:**
the one-line `serializeEvent` change *is* in the core driver, so that single
edit still requires the embed regen + 6-example copy + release-CLI rebuild. New
CLI plumbing: serve `swiflow-regions.js` in dev (free via `public/`) and an
embed-or-publish path for `swiflow build`.

## SSR / non-browser lowering

`region(...)` is **pure VNode construction** using only the foundation-free
codec — no JavaScriptKit, no Foundation — so it compiles and runs under
`swift test` on macOS, and on any non-browser/SSR build it simply produces the
`.element(tag:"sf-region", …)` VNode (inert until a browser loads
`swiflow-regions.js`). This resolves the "where does `region(...)` live" open
question: **core `Swiflow` (DSL), not a JSKit-bound module.**

## Implementation surface (file-by-file)

**New**

- `Sources/Swiflow/DSL/Region.swift` — `region(_:key:props:)` (typed) +
  `region(source:key:props:)` (inline), `RegionView<Guest>`, sizing modifiers,
  `.onEvent`/`.onError`, `RegionGuest`/`RegionEvent` protocols. (Core; JSKit-free.)
- `Sources/Swiflow/JSON/` — promote `SwiflowStore/JSONValueEncoder` to a shared
  foundation-free encoder; add the matching decoder (decision (a)).
- `js-driver/swiflow-regions.js` — `<sf-region>` custom element + worker shim
  (separate asset).
- `guest-sdk/` (Rust crate + JS shim) + `examples/RegionDemo/` reference guest.
- Tests: `RegionDSLTests`, `RegionCodecTests`, region e2e spec, DevTools panel.

**Modified**

- `Sources/Swiflow/VNode.swift` — `EventInfo.detail: String? = nil`.
- `Sources/SwiflowDOM/DispatcherBridge.swift` — decode `payload.detail.string`.
- `js-driver/swiflow-driver.js` — forward `event.detail` in `serializeEvent`
  (triggers the embed/sync dance + release-CLI rebuild).
- `Sources/SwiflowCLI/…` — serve/embed `swiflow-regions.js`; route guest
  `.wasm` with hashed URLs.
- DevTools extension — Regions panel.

## Exit criteria

- A reference guest renders into a `region(...)` and recolors on a prop change;
  a guest-emitted event decodes into a typed `RegionEvent` and updates `@State`.
- Resize (window + container + DPR change on both observer paths) reaches the
  guest; no 300×150 flash on mount.
- HMR with unchanged `guest-src`+`key` preserves guest GL state (no
  re-instantiation); changing either reinitializes.
- Off-screen / hidden-tab regions pause; teardown terminates the worker and
  releases observers + port (incl. the error path).
- A failing guest dispatches `sf:error` and the app shows a sibling fallback;
  Swiflow never crashes.
- Two regions sharing a `guest-src` compile the module once.
- `swift test` covers DSL lowering + props/event codec on macOS, with no
  browser; e2e covers the worker/OffscreenCanvas path (release CLI built first).

## Testing strategy

| Layer | Proves | How (+ gotcha respected) |
|---|---|---|
| **Codec** (pure) | props→JSON string, JSON string→`RegionEvent`, version framing | `swift test` on macOS, foundation-free, no browser — the `PatchPayload`/`JSONValueEncoder` pattern |
| **VNode lowering** (headless) | `region(...)` → correct `.element(tag:"sf-region", sfProps, handlers, style)`; sizing → CSS; `key` identity | `SwiflowTesting`, no worker |
| **Integration** (e2e) | one-shot transfer, props coalesce/frame, resize (both observer paths), typed event round-trip to `@State`, pause-on-scroll-off, error→sibling-fallback, **HMR preserves worker**, shared-module single compile | Playwright — run locally first; `swift build -c release --product swiflow` **before** the run (harness reuses stale CLI) |
| **Reference guest** | the whole loop | ~50-line Rust guest: recolor-on-prop, emit click coords, report FPS — e2e fixture + SDK example + demo |

## Scope

### v1 (in)

- Opaque canvas · worker + OffscreenCanvas · async-first.
- Region Protocol **v1** (JSON framing): control channel — props (per-frame
  coalesced), lifecycle (`ready`/`resize`/`pause`/`resume`/`destroy`/`context-lost`),
  typed events-out.
- Always-on resize broadcast (`device-pixel-content-box` + fallback + DPR via
  `matchMedia` on the fallback path); latch + replay at `ready`.
- Swift API: **typed `region(Guest.self, key:, props:)` primary** (event type
  inferred) + inline `region(source:key:props:)` secondary; `.onEvent`,
  `.onError`, sizing (`.fill()` default · `.frame` · `.aspectRatio(16, 9)`);
  `RegionGuest`/`RegionEvent`/`RegionView`; foundation-free codec.
- `EventInfo.detail` + `serializeEvent` + `DispatcherBridge` events-out wire.
- HMR survival via keyed diff; one-shot-transfer invariant.
- `swiflow-regions.js` (separate asset) + Rust guest SDK + reference guest.
- DevTools **Regions** section.
- Shared `WebAssembly.Module` cache; content-hashed guest URLs; error/fallback.
- Trust: trusted, same-origin, single-threaded (+ no-SAB guest-build contract).

### Deferred (designed-compatible, not built)

- Data channel / `MessagePort` high-rate streaming — motivating use case:
  audio-reactive guests (FFT/waveform frames captured host-side on the main
  thread, streamed into the worker for the guest to draw).
- **`AsyncStream` events-out** (`for await e in region.events`) as a v1.1
  adapter over the closure `.onEvent` — delightful for stream-shaped guests, but
  needs careful lifecycle/cancellation tie-in (reuse phase20's superseded-write
  guard) and risks two idioms; ship the closure first.
- Raw "mount a wasm-bindgen module as-is" escape hatch (option B) — cheap
  follow-on (`refBindings` already exist); **v1.1**.
- Binary envelope framing + a `@RegionProps` codec macro (post-profiling).
- Main-thread mode · threaded guests (SAB + COOP/COEP) · DOM-subtree guests. The
  litmus test for main-thread mode is *app-shaped* guests that own the page —
  e.g. [`waltonseymour/visualizer`](https://github.com/waltonseymour/visualizer),
  whose Rust `run()` grabs the DOM canvas by id, owns the `AudioContext` + rAF
  loop, and reads `window.*` controls — which the worker model can't host
  without a fork.
- **Real-world external-guest validation + adapter recipe.** Prove the polyglot
  promise by hosting an off-the-shelf compiled wasm we didn't write, via a thin
  guest adapter. First target: [`rustwasm/wasm_game_of_life`](https://github.com/rustwasm/wasm_game_of_life)
  — its DOM-free `Universe` compute is reused unmodified; a ~30-line adapter
  ticks it and draws the cell bitmap to the OffscreenCanvas. Generalize into a
  documented "wrap an external wasm module" recipe in the guest SDK.
  **Guest-shape doctrine:** Regions host *component-shaped* guests (accept a
  canvas; no global `document`/`window`/audio; controls via props), not
  *app-shaped* monoliths that own the page.
- Untrusted-plugin capability system.
- WIT transcription + jco / native Component-Model path.
- Non-Rust guest SDKs (AssemblyScript/C/Zig).

## Open questions for the implementation plan

- **Decoder:** ship a foundation-free JSON decoder (a, preferred) vs. browser
  `JSON.parse` + JSKit value-coding (b). Affects macOS test coverage of the
  decode path.
- **`RegionEvent` discriminator:** single DOM event name `"sf:event"` with an
  in-payload `kind` (current design) vs. distinct DOM event names per kind.
- **Props blob ceiling:** soft dev-warning threshold and whether to chunk large
  props over the data channel (ties to the deferred `MessagePort`).
