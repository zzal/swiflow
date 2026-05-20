# Why Swiflow exists — explained for a junior frontend dev

## The big picture

Imagine you love React, but you don't want to write JavaScript or TypeScript.
You want to write **Swift** — the same language Apple uses for iPhone apps.
Why? Maybe because Swift has a stronger type system, fast performance, and you
already know it from iOS work.

To run Swift in a browser, there's a trick called **WebAssembly (WASM)** —
basically, the browser can run compiled code that isn't JavaScript. So you
compile your Swift app to a `.wasm` file, the browser loads it, and now Swift
code runs in the page.

But there's a catch. The browser's DOM (the live HTML — buttons, divs, all
of it) lives in JavaScript-land. Swift-WASM lives in WASM-land. **Every time
your Swift code wants to change a button's text, it has to "talk" across a
bridge to JavaScript.** Every crossing of that bridge has overhead. If your
app makes 1000 little DOM changes per frame, you pay that overhead 1000 times
— and your app feels slow.

That's the problem Swiflow is built to fix.

## The two specific gaps Swiflow attacks

From [docs/brainstorm/swift-flow-prd.md](docs/brainstorm/swift-flow-prd.md):

| The Problem | What you hit today | What Swiflow does |
|---|---|---|
| **The "Bridge Tax"** | Frequent, small JS calls (slow) | Batches *all* DOM mutations from one render into a single list, sends it across the bridge in ONE leap |
| **Toolchain Friction** | Manual `Package.swift`, JS glue, WASM SDK install, dev server config… | One CLI binary (`swiflow`) that scaffolds, builds, and serves |

The pitch in one sentence: **Swiflow is "Vite for Swift on the web."** Vite
gave JS devs a one-command dev loop with instant feedback. Swift-on-the-web
didn't have that. Swiflow does.

## How is this different from Carton (and friends)?

This is the part that confuses people. They sound similar. They are not.

**Carton** (and its modern replacement, `swift package js` / PackageToJS) is
a **build tool**. It knows how to compile Swift to WASM, install the right
toolchain, and serve the output on `localhost`. That's it. It doesn't care
*what* you're building — a game, a UI app, a number cruncher. It just
compiles.

**Tokamak / ElementaryUI** are **UI libraries**. They give you SwiftUI-style
components that render to HTML. But they don't ship a dev server or a CLI.
You still wire up Carton (or whatever) yourself. And — critically — they
don't solve the bridge tax: each component change is its own little JS call.

**Swiflow** is both **a UI library AND the orchestrator around it**, designed
together as one product:

```
┌─────────────────────────────────────────────────────────────────┐
│                          What you get                            │
├──────────────────┬──────────────────┬───────────────────────────┤
│   Carton         │  Tokamak / Elem  │      Swiflow              │
├──────────────────┼──────────────────┼───────────────────────────┤
│ Build + serve    │ UI components    │ Build + serve             │
│ (no UI lib)      │ (no dev tools)   │   + UI components         │
│                  │                  │   + batched bridge        │
│                  │                  │   + @State reactivity     │
│                  │                  │   + diagnostics + security│
└──────────────────┴──────────────────┴───────────────────────────┘
```

**The killer feature that nobody else has: batched patches.** When state
changes in Swiflow, the framework figures out *every* DOM mutation that needs
to happen (add this node, change that text, remove that handler) into a list
called `Patch`. Then it ships that entire list across the bridge once per
frame. The JS driver replays the list in a tight loop. One bridge crossing
per frame, no matter how many things changed.

That's the React-style trick (React calls it "reconciliation"), but adapted
specifically to be cheap across the WASM↔JS boundary.

## The four priorities (the manifesto)

[docs/brainstorm/swift-flow-Developer-Manifesto.md](docs/brainstorm/swift-flow-Developer-Manifesto.md)
locks the priorities, in order:

1. **Growth** — make it easy for strangers to contribute
2. **Performance** — actually win on speed vs. Tokamak
3. **Observability** — when something breaks, the dev knows *why* immediately
4. **Usability** — `swiflow init demo && swiflow dev` and you see Hello World in 60 seconds

Every architectural decision has been filtered through those four pillars in
that order. That's why we shipped a CLI before reactivity, and DWARF
debugging before fancier diffing.

## Where we are right now

From [README.md](README.md):

> **Status:** Phase 4 (Hardening) complete. The framework is feature-complete
> through Phase 3 (Component + `@State` reactivity + RAFScheduler) and
> hardened in Phase 4 with the URL sanitizer, debug-only diagnostics, DWARF
> debugging guide, JS-driver unit tests, and a Playwright happy-path e2e.

So today you can:

- `swiflow init my-app` → real scaffolded project
- `swiflow dev` → builds your Swift to WASM, serves on `:3000`, full-reloads on save
- Write a `Counter: Component` with `@State var count = 0` and a click handler — it just works
- Click around in a real browser, watch the counter increment, with Swift DWARF symbols so traps point to your `.swift` files in DevTools

**TL;DR:** Carton compiles. Tokamak draws UIs. Swiflow does both *and* solves
the bridge tax that makes the others feel slow — wrapped in a one-command dev
loop so a junior dev can ship Hello World in under a minute.
