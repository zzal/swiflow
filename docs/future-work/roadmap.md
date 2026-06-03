# Roadmap — Real-World & Envelope-Pushing Work

> **Status:** Idea capture, not yet specced. Each item below graduates to its own
> `docs/superpowers/specs/` design (and a `docs/future-work/<topic>.md` deep-dive if
> it needs preserved analysis) when we pick it up. Capture date: 2026-06-03.

## Why this exists

The data layer is shipped (Query Core + Mutations); background revalidation is the
remaining data-layer sub-project (tracked separately). These notes capture the next
wave of ideas — proving Swiflow against *real* backends and pushing into real-world
app capabilities — so we don't re-derive the framing later. Nothing here is committed
scope; it's a menu with enough analysis to plan from.

---

## Theme A — A real, self-contained SwiflowQuery example (read **and** write)

**Goal.** Today's examples (`QueryDemo`, `AsyncFetch`) simulate the network with a
`FakeAPI` + `Task.sleep` returning hardcoded values. Build a self-contained example
that exercises `query()` reads **and** mutation writes against an *actual* HTTP CRUD
API, so the cache / SWR / dedup / optimistic-update machinery is proven end-to-end
over a live network instead of an in-process stub.

**Backend.** A Dockerized CRUD service with **SQLite** as the store, built with
**[VeloxTS](https://veloxts.dev)** (the maintainer's own framework: TypeScript on
Node + Fastify, Prisma 7 ORM, Zod validation, REST + tRPC, has Docker deploy guidance
and a `create-velox-app` scaffolder). Prisma's SQLite provider keeps the DB
zero-dependency and file-based, so the whole backend is one `docker compose up`.
Likely lives at `examples/<name>/backend/` (kept out of the Swift build graph).

**Swiflow side — the actual unlock.** The *only* thing that changes versus the FakeAPI
examples is the body of `Query.fetch()` / `Mutation.perform()`. In WASM there is no
`URLSession`; a real call goes through the browser's `fetch` via JavaScriptKit
(`JSObject.global.fetch(...)`, await the JS promise, decode the JSON body). Everything
downstream — `query(...)`, `@MutationState`, `optimistic()`, `invalidations()` — is
byte-for-byte identical to the simulated version.

**What it will surface.** Whether Swiflow has (or wants) an ergonomic
networking/JSON-decode helper. Right now there's no first-class HTTP story; this
example is the forcing function to decide between (a) "just call `fetch` via
JavaScriptKit, document the pattern," or (b) a small `SwiflowHTTP`-style helper
(typed GET/POST + `Decodable` bridging over the JS `fetch` promise).

**Open questions.**
- **REST vs tRPC** — tRPC's type-safety is TS-to-TS; from Swift we'd consume plain
  REST/JSON endpoints. Plan for REST (or a thin JSON route).
- **CORS** — the dev server is on `:300x`, the API on another port; the backend must
  send permissive CORS for local dev.
- **Repo footprint** — how to vendor a Node/Docker backend in the repo without bloating
  it or breaking the Swift-only CI. Probably a self-contained subdir + its own README.
- **Auth** — none for the demo; note it as a later layer.

**Dependencies / prerequisites.** A real `fetch` story (see Cross-cutting #1); CORS on
the backend; pairs naturally with the deferred **background-revalidation** sub-project
(refetch-on-focus / polling are far more compelling against a live API).

---

## Theme B — Pushing the envelope (real-world app capabilities)

### B1 — Web Components interop (DOM side)

Two directions, both valuable:
1. **Consuming** third-party custom elements (`<some-widget>`) inside a Swiflow `body`.
2. **Exposing** a Swiflow component *as* a custom element, so non-Swiflow pages can embed it.

**Grounding / friction.** Swiflow renders by applying patches through the JS driver;
element creation today is attribute-string oriented and the event payload is limited
(`EventInfo` exposes only `targetValue`/`targetChecked` — no target identity). Custom
elements typically need **JS properties** (not just string attributes), **`CustomEvent`
detail** payloads, and they often **manage their own light/shadow DOM children** — which
the diff must not stomp.

**Likely needs.** A `.property(name, value)` modifier (set a JS prop, not an attribute);
richer event payloads (`CustomEvent.detail`); and an **escape hatch that marks a subtree
as "not reconciled by Swiflow"** so the diff leaves an element's self-managed children
alone. (That escape hatch recurs in B2 — see Cross-cutting #2.)

**Open question.** Where's the reconciliation ownership boundary for an element that
populates its own shadow root?

### B2 — Other WASM modules (WASI?) + a WASM-controlled canvas

- **Hosting a second WASM module** alongside the Swiflow app. Swiflow is WASM-in-browser
  via JavaScriptKit; a second module is instantiated through JS glue and its exports are
  called from Swift through JS. Establish the pattern + lifecycle ownership.
- **WASM-controlled `<canvas>`.** Swiflow owns the `<canvas>` element (via a `Ref`) and
  manages its layout/lifecycle; a separate module (Rust/C/Swift → WASM) receives the
  canvas/context and owns the draw loop. Swiflow reconciles *around* the canvas but never
  *inside* it (same non-reconciled-subtree need as B1).
- **WASI 0.2 / Component Model interop** — more speculative (browser support + toolchain
  maturity). Flag as research-grade; the canvas + second-module cases are the pragmatic
  near-term targets.

**Dependencies.** A stable `Ref` → real DOM node handle (Refs exist today); a way to hand
the node/context to another module; the non-reconciled-subtree escape hatch (Cross-cutting #2).

### B3 — UI core `@Component`s (a standard component library)

A first set of ready-to-use components, almost certainly a separate **`SwiflowUI`** module:
- **Layout:** `Stack` / `VStack` / `HStack` / `Grid` — thin, CSS-first wrappers over
  flexbox/grid with spacing + alignment props (fits Swiflow's CSS-first component model).
- **Overlays:** rich **Alert / Prompt** (modal dialogs) and **Toast** notifications
  (transient, queued, auto-dismiss).

**Grounding / dependencies.** Builds on the existing CSS-first primitives and the
dialog/popover/`<details>` work already done. Overlays need a **portal / overlay-root host**
(Cross-cutting #3) and clean dismissal — which runs straight into two known gaps:
`EventInfo` lacks target identity (backdrop-click / click-outside is awkward today), and
View Transitions on top-layer `<dialog>`/popover glitch (we CSS-animate instead). A Toast
**queue** is a small state machine → motivates B4.

**Open questions.** How opinionated/styled vs unstyled-and-themeable (CSS-vars theming)?
Ship in core or a separate `SwiflowUI` module (lean: separate module)?

### B4 — Managed reducers / state machines ("internal pipes")

A reducer/store primitive — `(state, action) -> state` and/or typed finite state machines —
wired into the scheduler (`markDirty`) so transitions trigger re-renders. Complements
per-component `@State` (local UI state) and the SwiflowQuery cache (server state) for the
gap in between: shared/app-level client state and complex flows (wizards, multi-step async
status, the Toast queue from B3).

**Open questions.**
- **Scope** — a local per-component machine, a shared/global store, or both?
- **Relationship to `@State`** — sugar over it, or its own cell type? Server state stays in
  the query cache; this is explicitly *client* state.
- **API shape** — Elm/Redux-style actions, or Swift enums + a `transition` function
  (TCA-flavored)? Does the reducer own side effects (dispatch async, à la TCA `Effect`),
  or stay pure with effects at the call site (mirroring the mutation design)?

---

## Cross-cutting prerequisites (these keep recurring)

Several roadmap items converge on the same few primitives. Building these well unblocks
multiple themes at once:

1. **A real `fetch` / JSON story** — `JSObject.global.fetch` bridging + `Decodable` decode.
   Needed by Theme A; useful everywhere. Decide: documented pattern vs a `SwiflowHTTP` helper.
2. **A richer element model** — set JS *properties* (not just attributes), `CustomEvent`
   detail payloads, and a **"Swiflow does not reconcile inside this node" escape hatch**.
   Serves B1 (web components), B2 (canvas / foreign WASM), and any third-party-DOM integration.
3. **A portal / overlay-root host** — render a subtree outside the normal parent (top layer /
   document end). Serves B3 (Alert/Prompt/Toast) and any future tooltip/menu work.
4. **`EventInfo` target identity** — backdrop-click / click-outside / delegated handlers need
   to know *which* element fired. A known gap that B1 and B3 both hit.

## Suggested sequencing (rough)

- **Theme A** first — it's the most contained, proves the data layer for real apps, and
  forces the Cross-cutting #1 decision. Pairs with the deferred background-revalidation work.
- **Cross-cutting #2 + #3 + #4** as the enabling layer before the heavier UI/DOM items.
- **B3** (UI core) and **B4** (reducers/state machines) reinforce each other — the Toast
  queue is the natural first consumer of a state-machine primitive; consider them together.
- **B1 / B2** as the integration/interop track once the element-model escape hatch exists;
  WASI/Component-Model stays research-grade until browser + toolchain support firms up.

## Triggers to revisit

Promote an item to a real spec when: a concrete app needs it; a cross-cutting prerequisite
is about to be built anyway (do the dependent item alongside it); or the simulated examples
stop being convincing for the story we want to tell.
