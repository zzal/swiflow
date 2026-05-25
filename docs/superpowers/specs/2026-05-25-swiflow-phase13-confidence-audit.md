# Phase 13 — Confidence Audit

**Date:** 2026-05-25  
**Status:** Audit complete — gaps identified, fixes not yet planned  
**Scope:** SwiflowRouter · @Environment · CLI tooling · Public API surface

---

## Methodology

Full static analysis of all four areas: public API review, test coverage mapping, cross-module dependency check, known rough edges from prior specs. No code changes — discovery only.

---

## Area 1: SwiflowRouter

**State:** Feature-complete, undertested.

The module ships `Router`, `RouterContext`, `RouterRoot`, `Link`, `RouteDefinition`, `RouteBuilder`, `RoutePattern`, `RouteMatching`. A `RouterKey` environment key wires the router into `@Environment(\.router)`. `docs/guides/router.md` exists.

### Gaps

| ID | Severity | Description |
|----|----------|-------------|
| R1 | IMPORTANT | No test verifying that `@Environment(\.router)` propagates correctly across `embed { }` component boundaries. The router is injected at the `RouterRoot` level; a deeply nested component reading `@Environment(\.router)` inside `embed {}` is untested. |
| R2 | IMPORTANT | `Router.navigate`, `replace`, and `back` are closures — they're tested in unit isolation but there is no Playwright test verifying that browser history (`window.history.pushState`, `history.back()`) actually changes the URL and triggers a re-render. |
| R3 | MINOR | `Link` reads `AmbientEnvironment.current` during `body`, which means it cannot be used safely in `onAppear`. This limitation is noted in `Link.swift` but is not mentioned in `docs/guides/router.md`. |
| R4 | MINOR | `RouteBuilder` has no tests for conditional/optional routes (`if condition { Route(...) }`). This is a standard use case and could silently produce wrong route trees. |

---

## Area 2: @Environment

**State:** Complete and correctly designed. Infrastructure is sound.

`EnvironmentKey`, `EnvironmentValues`, `Environment<Value>` property wrapper, `withEnvironment` DSL, ambient thread-local (`AmbientEnvironment.current`), `VNode.environmentOverride`, and Diff propagation are all implemented. `docs/guides/environment.md` exists. Three test files cover values, DSL, and threading.

Note: `@Environment` intentionally has no projected value (`$`) — environment values are read-only reads from context, same as SwiftUI's design. This is correct.

### Gaps

| ID | Severity | Description |
|----|----------|-------------|
| E1 | IMPORTANT | No postfix `.environment(keyPath:value:)` VNode modifier. Users must wrap in `withEnvironment(\.key, value) { ... }`. This is inconsistent with the rest of the DSL where all modifiers are postfix on `VNode` (`.on()`, `.value()`, `.checked()`, `.ref()`). |
| E2 | IMPORTANT | `VNode` equality ignores `EnvironmentValues` in `environmentOverride` nodes — only the child subtree is compared. This means the diff re-merges environment on every render pass regardless of whether anything changed. Not incorrect, but means environment changes don't reliably signal re-renders in complex trees. |
| E3 | MINOR | Environment propagation test coverage is shallow: tests cover 2–3 levels of nesting. No stress test for deeply nested trees (>5 component levels) with multiple `withEnvironment` overrides. |
| E4 | MINOR | No test for what happens when a component reads `@Environment` in `onAppear` vs. `body` — the order matters since `AmbientEnvironment.current` is set during `body` evaluation, not during lifecycle hooks. Behavior is correct but undocumented/untested. |

---

## Area 3: CLI Tooling

**State:** Functional for in-repo development only. Not distributable yet.

`swiflow init <name>` works when `--swiflow-source` or `SWIFLOW_SOURCE` is provided. `swiflow dev` and `swiflow build` probe for the WASM SDK automatically. E2E Playwright tests cover `swiflow dev` and `swiflow build`.

### Gaps

| ID | Severity | Description |
|----|----------|-------------|
| C1 | CRITICAL | `swiflow init` requires `--swiflow-source` or `SWIFLOW_SOURCE`. Without it, the command errors: *"Swiflow has no public release yet."* This is the intended pre-release behavior but blocks any future Homebrew/Mint distribution — there's no path to a released version that works out of the box. Fix: once a GitHub release exists, default to a URL-based dependency. |
| C2 | IMPORTANT | Generated `Package.swift` embeds `.package(path: "{{SWIFLOW_SOURCE}}")`. After `swiflow init`, moving or deleting the Swiflow clone breaks the generated project. There is no migration path or documentation for switching to a URL dependency after initial setup. |
| C3 | IMPORTANT | No integration test that runs `swiflow init <name>` end-to-end and then verifies the scaffolded project builds. `InitCommandTests` tests `ProjectWriter` (file correctness) and argument parsing but never invokes the real init flow. |
| C4 | MINOR | `swiflow init` has no atomic write / rollback: if a file write fails partway through (disk full, permission denied), the target directory is left partially written. There is no cleanup on failure. |
| C5 | MINOR | Help text example for `--swiflow-source` shows absolute paths only (`/path/to/swiflow`). Relative paths work (e.g., `../..`) but are not documented. |
| C6 | MINOR | Generated `.gitignore` is minimal. Common entries (`*.swp`, `.DS_Store`, editor caches) are missing. Low-priority but affects project hygiene. |

---

## Area 4: Public API Surface

**State:** Mostly clean. Key issue is internal serialisation types leaking as `public`.

### Gaps

| ID | Severity | Description |
|----|----------|-------------|
| A1 | IMPORTANT | `Patch`, `PatchPayload`, `PatchSerializer` are `public`. These are JS-bridge serialisation details, not user-facing API. They should be `package` (visible to `SwiflowWeb` in the same package, invisible to downstream users). |
| A2 | IMPORTANT | `PropertyValue` is `public` because `TestHarness.properties: [String: PropertyValue]` is a public property on `SwiflowTesting`. Exposing this internal DOM property type forces users to import an abstraction they should never construct. Fix: either make `TestHarness.properties` return `[String: String]` (flattened) or introduce a public `TestPropertyValue` type that doesn't leak the internal representation. |
| A3 | IMPORTANT | `HandleAllocator` and `MountNode` are `public`. They need to cross the `Swiflow` → `SwiflowTesting` module boundary (same package, different targets), so they SHOULD be `package` rather than `public`. They are currently `public` which exposes them to all downstream importers. Changing to `package` is a breaking change in the sense that any downstream code using them directly would break — but no sane user should be using them directly, so this is safe to do pre-1.0. |
| A4 | IMPORTANT | No `SwiflowTesting` user guide in `docs/guides/`. Users must read `TestHarness.swift` inline docs to discover `render()`, `click()`, `input()`, `findAll()`, `find()`, `blur()`. A testing guide would directly improve adoption. |
| A5 | MINOR | `TestHarness` exposes `click()`, `input()`, `blur()` but not `change()`. The `<select>` and `<textarea>` `onChange` patterns (used in Phase 12 forms) can't be exercised without reaching into internals. |
| A6 | MINOR | No declared stable API contract: users cannot distinguish "public and stable" from "public but may change" before 1.0. A simple `// @stable` annotation convention or a `CHANGELOG.md` noting breaking changes would help. |
| A7 | MINOR | Inconsistent error escalation: some programmer errors use `fatalError`, others use `preconditionFailure`. Both trap in release builds; the convention should be uniform. |

---

## Summary

| Area | Critical | Important | Minor |
|------|----------|-----------|-------|
| SwiflowRouter | 0 | 2 | 2 |
| @Environment | 0 | 2 | 2 |
| CLI Tooling | 1 | 2 | 3 |
| Public API | 0 | 4 | 3 |
| **Total** | **1** | **10** | **10** |

### Must fix before any public release (Critical)
- **C1** — `swiflow init` hardcoded source requirement blocks distribution

### Should fix before 1.0 (Important)
- **R1** — Router environment propagation across `embed {}` untested
- **R2** — No Playwright test for actual URL/history interaction
- **E1** — Missing `.environment()` postfix VNode modifier
- **E2** — Environment equality ignored in VNode diff
- **C2** — Generated projects not portable (path dependency)
- **C3** — No `swiflow init` integration test
- **A1** — `Patch`/`PatchPayload`/`PatchSerializer` should be `package`
- **A2** — `PropertyValue` leaks through `TestHarness.properties`
- **A3** — `HandleAllocator`/`MountNode` should be `package`
- **A4** — No SwiflowTesting user guide

### Polish / nice-to-have (Minor)
- R3, R4, E3, E4, C4, C5, C6, A5, A6, A7
