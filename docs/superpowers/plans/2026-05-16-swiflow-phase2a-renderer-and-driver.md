# Swiflow Phase 2a — Renderer + JS Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the WASM-side renderer and the JavaScript driver so that a hand-crafted example app — `examples/HelloWorld/` — can be compiled to WebAssembly, served by any static HTTP server, and rendered into a real DOM in a browser, including responding to a button click that triggers a Swift closure and a full re-render via `Swiflow.rerender()`.

**Architecture:** Phase 1's Swift core (VDOM + diff + DSL) is platform-independent. This phase adds a second SPM library target, `SwiflowWeb`, that imports JavaScriptKit and lives behind a WASM-only build condition. `SwiflowWeb` provides `Swiflow.render(_:into:)` and `Swiflow.rerender()`, owns the `Renderer` state (mount tree + allocator + registry + view producer), serializes patches to `JSValue`, and registers the single Swift dispatcher that the JS driver calls when a DOM event fires. The driver itself is a ~150-line vanilla-JS file that owns a `Map<int, Node>` and a `switch` over patch opcodes.

**Tech Stack:** Swift 6.0+, JavaScriptKit 0.21+, SwiftPM, vanilla JavaScript (no TypeScript, no bundler). The `swift sdk install` toolchain for WASI is required to build the example; the macOS test target does NOT require it.

**Reference spec:** `~/.claude/plans/i-want-you-to-dynamic-pancake.md` (the approved refined spec). Phase 2 deliverables live in § 5. This plan covers a strict subset: § 5.2 (JS driver), § 5.3 (Hello World template — but hand-crafted, not yet via `swiflow init`), and the Renderer portion of § 5.1. The CLI (§ 5.1) and dev server are deferred to Phases 2b/2c.

**Repo state at start:** Phase 1 complete. 103 tests passing across 20 suites. `main` is at `1443f63`. The `Swiflow` library is pure Swift with zero external dependencies.

---

## Phase 2a is split for prompt-length reasons

The 8 tasks below are detailed in `2026-05-16-swiflow-phase2a-tasks.md` (created alongside this file). This top-level plan holds the architecture, file map, and completion checklist; the task-by-task TDD steps with full code listings live in the companion file because the JS driver contains `innerHTML` references (a deliberate Phase 1 escape-hatch design) that triggered a security-reminder hook on the combined write.

---

## File map (Phase 2a deliverables)

| Path | Responsibility |
|---|---|
| `Package.swift` | Add `JavaScriptKit` dependency. Split `Swiflow` library into two products: `Swiflow` (existing, platform-agnostic) and `SwiflowWeb` (new, WASM-only). |
| `Sources/Swiflow/PatchSerializer.swift` | Encodes a `Patch` into a `PatchPayload` value — pure Swift, fully testable on macOS. |
| `Sources/Swiflow/PatchPayload.swift` | Intermediate dict-like representation of an encoded patch. |
| `Sources/SwiflowWeb/SwiflowWeb.swift` | Module root. `@_exported import Swiflow` so users only need one import. Declares the `Swiflow` namespace's renderer-facing static API. |
| `Sources/SwiflowWeb/Renderer.swift` | The `Renderer` class — owns mount tree, allocator, registry, view producer. Public surface: `Swiflow.render(_:into:)` + `Swiflow.rerender()`. |
| `Sources/SwiflowWeb/JSAdapter.swift` | Maps `PatchPayload` → `JSObject`. WASM-only; one function per concrete case via switch. |
| `Sources/SwiflowWeb/DispatcherBridge.swift` | Registers a single Swift function as `window.__swiflowDispatch` via `JSClosure`. The JS driver calls it when an event fires. |
| `Tests/SwiflowTests/PatchSerializerTests.swift` | One test per opcode, asserting `Patch` → `PatchPayload` mapping. |
| `Tests/SwiflowTests/PatchPayloadTests.swift` | Equality semantics on the encoded payload type. |
| `js-driver/swiflow-driver.js` | Vanilla JS, ~150 lines: node map, dispatcher hookup, patch interpreter (switch over `payload.op`), `window.swiflow` API. |
| `js-driver/README.md` | One-page authoring guide for the driver. |
| `examples/HelloWorld/Package.swift` | Local-path dependency on the parent `Swiflow` package. |
| `examples/HelloWorld/Sources/App/App.swift` | Hand-crafted demo: a counter with `Swiflow.render` + `Swiflow.rerender` per § 5.3. |
| `examples/HelloWorld/public/index.html` | Hosts the WASM module + the JS driver. |
| `examples/HelloWorld/README.md` | Step-by-step "how to build and serve this by hand" — no CLI required. |
| `README.md` | Updated status: "Phase 2a in progress: renderer + JS driver shipped, CLI pending." |

---

## Architectural decisions

These derive from the spec but get nailed down here so they don't shift mid-implementation.

1. **Two library products, one repo.** `Swiflow` stays pure (no platform deps). `SwiflowWeb` adds `JavaScriptKit`. The example imports `SwiflowWeb`, which `@_exported import`s `Swiflow`, so user code reads `import SwiflowWeb` and gets the whole DSL + the renderer in one shot.

2. **`SwiflowWeb` builds WASM-only via `#if canImport(JavaScriptKit)`.** macOS / Linux compile to an empty module (the only public symbols sit inside the conditional). Tests stay platform-agnostic and depend only on `Swiflow`.

3. **Patch encoding splits at the JSValue boundary.** `PatchSerializer.encode(Patch) -> PatchPayload` lives in `Swiflow` core and is fully testable on macOS. `JSAdapter.toJSValue(PatchPayload) -> JSObject` lives in `SwiflowWeb` and is exercised only by manual browser runs in Phase 2a. This keeps the serialization logic — where every bug will hide — under the test microscope.

4. **`Renderer` is a class, not a singleton.** The library doesn't impose a global instance; the user calls `Swiflow.render(_:into:)` once and the `Renderer` lives as a strong reference inside `SwiflowWeb`'s module-private ambient state. `Swiflow.rerender()` looks up that ambient state. Multiple roots are not supported in Phase 2a (out of scope).

5. **Handler dispatch is one Swift function, one JS function.** At boot, `Renderer` registers `JSClosure { args -> JSValue in HandlerRegistry.dispatch(...) }` as `window.__swiflowDispatch`. The JS driver's per-listener wrapper calls `window.__swiflowDispatch(handlerId, eventPayload)`. No matter how many handlers a user attaches, only one Swift function ever crosses the bridge — matching spec § Branch 9.

6. **Patch wire format is `JSArray<JSObject>` per § 8a.** Each `JSObject` has an `op: String` discriminator and named fields. The TypedArray binary format is explicitly out of scope (Phase 4).

7. **No browser E2E test runner in Phase 2a.** Per spec § 5.4 + § 15. Verification is by hand: build the example, serve it, click the button, see the count increment. Phase 4 adds Playwright.

8. **`HandlerRegistry` stays in `Swiflow` core.** It has zero JS dependencies. The reviewer's loose-end #1 ("decide where it lives") is resolved by **not moving it**: `Swiflow` owns the registry; `SwiflowWeb` adds a bridge file that connects it to JavaScriptKit's `JSClosure`.

---

## Tasks

The 8 tasks below are independent commits, ordered by dependency. Each follows the same TDD discipline as Phase 1: failing test, run to confirm red, implementation, run to confirm green, commit.

- **T1**: Restructure `Package.swift` — add `SwiflowWeb` target with `JavaScriptKit` dependency. Skeleton `SwiflowWeb.swift` so the target compiles to an empty module on macOS.
- **T2**: `PatchPayload` intermediate encoding type with `Field` enum cases for int / string / property. Equality tests.
- **T3**: `PatchSerializer.encode(Patch) -> PatchPayload` — switch over all 16 opcodes. One test per opcode (16 tests).
- **T4**: `JSAdapter.toJSValue(PatchPayload) -> JSValue` in `SwiflowWeb`. WASM-only, no tests (defer to manual verification in T8).
- **T5**: `Renderer` class + `Swiflow.render(_:into:)` + `Swiflow.rerender()` in `SwiflowWeb`. Module-private ambient renderer storage with `nonisolated(unsafe)` per Phase 1's Sendable-deferral pattern.
- **T6**: `DispatcherBridge` — register `window.__swiflowDispatch` as a `JSClosure` that calls `HandlerRegistry.dispatch(id:event:)`. Idempotent.
- **T7**: `js-driver/swiflow-driver.js` — vanilla JS, ~150 lines. Implements `window.swiflow.{applyPatches, mount, registerDispatcher}` and per-listener event wrappers. Driver-authoring README.
- **T8**: `examples/HelloWorld/` — hand-crafted demo (Package.swift, App.swift, index.html, copy of the driver). Manual verification instructions in the example README. Top-level README updated to "Phase 2a in progress."

For each task's full TDD steps + code listings, see the companion file `2026-05-16-swiflow-phase2a-tasks.md` (created in the same commit as this plan).

---

## Phase 2a Completion Checklist

After Task 8, verify:

- [ ] `swift build` succeeds with no warnings on macOS.
- [ ] `swift test` reports 119 tests in 21 suites passing (16 new `PatchSerializerTests` + 4 new `PatchPayloadTests` on top of Phase 1's 103 across 20 suites).
- [ ] `Package.resolved` shows the JavaScriptKit dependency resolved.
- [ ] `examples/HelloWorld/` exists and is self-contained (its `Package.swift` resolves via the local path dep).
- [ ] The driver file at `js-driver/swiflow-driver.js` and the example's `public/swiflow-driver.js` are byte-identical (until Phase 2b automates embedding).
- [ ] **(If WASM SDK present)** the Hello World example renders in a browser and the click handler triggers the rerender. This is the load-bearing verification for Phase 2a's success.
- [ ] CI on macOS + Linux still passes (`swift test` runs the same 119 tests; neither runner needs the WASM SDK for the meta-package's test target).

When all boxes are checked, Phase 2a is done. Phase 2b begins with its own plan, which will:
- Add the `SwiflowCLI` executable target.
- Embed the `js-driver/swiflow-driver.js` content as a Swift `String` resource in the CLI binary.
- Implement `swiflow init <name>` and `swiflow build` to automate what the example README currently asks the user to do by hand.

---

## Out of Scope for This Plan

Explicit non-goals for Phase 2a (deferred to Phase 2b, 2c, or later):

- The `swiflow` CLI binary, `init` / `build` / `dev` commands, ArgumentParser wiring, templates (Phase 2b).
- Dev HTTP server, file watcher, WebSocket `/reload` (Phase 2c).
- Browser-side automated tests with Playwright (Phase 4 per spec § 5.4 + § 15).
- Component lifecycle hooks, `@State` property wrapper, scheduler (Phase 3).
- TypedArray binary patch buffer replacing `JSArray<JSObject>` (Phase 4).
- Source maps as separate `.map` files (Phase 4 — DWARF in dev builds is the Phase 2c substitute).
- Cleanup of prior `Renderer` state when `Swiflow.render` is called a second time on the same page. Phase 2a leaks the old renderer (no second-call use case in Phase 2a; Phase 3's component lifecycle will fix this naturally).
- The double-registry problem (user closures registered into a private `HandlerRegistry` that the Renderer can't dispatch through) is **solved**, not deferred: Phase 2a exposes the Renderer's registry as `Swiflow.handlers`, and user `view()` code uses `.on("click", Swiflow.handlers.register { ... })`. Phase 3's `@State` redesign will replace this manual pattern with an implicit per-component registration site.
