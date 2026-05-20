# Swiflow Phase 6 — Trust & Polish (Design)

**Date:** 2026-05-20
**Status:** Approved, ready for implementation.
**Parent roadmap:** [`docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md`](../plans/2026-05-20-swiflow-dx-uplift-master-plan.md)
**Motto:** *Save → pixels feel instant.* (Phase 6 sweeps the credibility-erosion list so Phase 8's HMR lands on a clean surface.)

---

## Goal

Eliminate every "this code has not been read by a frontend dev" smell from the post-Phase-5 public API so a new visitor's first 30 seconds with Swiflow are uniformly positive. **No new public capabilities ship in this phase** — that's intentional. Phase 6 is the cheap, fast credibility multiplier before the big swings.

## Scope (six small surfaces)

### 1. Fix `.attr(_:_:Bool)` to omit the attribute when `false`

**Current state** (verified):

```swift
// Sources/Swiflow/DSL/Modifiers.swift:41-43
public static func attr(_ name: String, _ value: Bool) -> Attribute {
    .attribute(name: name, value: value ? "" : "")
}
```

Both branches emit the empty string; the doc-comment (lines 34-40) admits the bug and tells the caller to gate at the call site. **This is an API bug, not a doc problem.**

**New behavior:** when `value == true`, emit `attribute(name, value: "")` (matches HTML boolean-attribute semantics: presence = truthy). When `value == false`, return `Attribute.attribute(name: name, value: nil)`-equivalent → a marker that the fold step drops, so `disabled` never appears in `ElementData.attributes`.

**Implementation shape:**

- Introduce a private `Attribute.skip` case (or equivalent) that `applyAttributes(...)` filters out. Alternative: return an `Optional<Attribute>` from the Bool overload and update the variadic factories to compact `nil`. Pick the path that doesn't break the `[Attribute]` variadic ergonomics — most likely the `.skip` case, gated to internal use.
- Mirror the same fix in `Sources/Swiflow/DSL/VNodeModifiers.swift:42-44` (postfix path). Postfix returns `VNode` not `Attribute`, so the fix there is simpler: branch on `value` and short-circuit to `self` when `false`.
- Update both doc-comments to drop the "caller should gate" warning. New wording: *"Emits a presence-only HTML boolean attribute when `true`; omits the attribute entirely when `false`."*
- Tests covering: `attr("disabled", true)` writes `disabled=""`; `attr("disabled", false)` writes nothing; postfix shape matches.

**Why this matters:** the assessment cites this as one of two bugs that "erode trust the first time someone reads it." It is literally `value ? "" : ""` and a frontend dev will spot it in five seconds.

---

### 2. Hide `Binding<Value>` from discovery until Phase 7

**Current state** (verified):

```swift
// Sources/Swiflow/Reactivity/State.swift:108-116
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void
    ...
}
```

The type ships **without a DSL consumer**. The doc-comment (lines 105-107) admits this:

> Phase 3 v1 doesn't yet have any DSL bindings that consume `Binding`; it's surfaced now so the API is set in stone before Phase 4's form helpers land.

A frontend dev who reaches for `input(.value($text))` hits a compile error. We need the symbol present for ABI stability and Phase 7 wiring, but we want it **invisible to Xcode autocomplete and DocC** until Phase 7 ships the consumer.

**New behavior:**

- Apply `@_documentation(visibility: internal)` to `public struct Binding<Value>` and to `public var projectedValue: Binding<Value>` on `State`.
- Update the doc-comment to point at the Phase 7 plan: *"Type reserved for Phase 7 form bindings. Use `@State`'s `wrappedValue` for now; `$text`-style projected bindings start working when Phase 7's `.value(_:)` modifier ships."*

**Why this matters:** removes a footgun without removing the symbol (which Phase 7 will need). Zero behavior change; pure discoverability.

---

### 3. Add `final class` explainer comment to template + example

**Current state:**

```swift
// Sources/SwiflowCLI/Templates/Templates.swift:105 (and examples/HelloWorld/Sources/App/App.swift:13)
final class Counter: Component {
```

A React/SwiftUI dev's first instinct is `struct Counter: Component`. They will try it. The protocol-conformance error is unhelpful — it doesn't say "Components must be classes because @State reactivity needs reference semantics."

**New behavior:** add one comment line immediately above `final class Counter: Component` in both files:

```swift
// `final class` (not `struct`) — @State reactivity needs reference
// semantics so the framework can wire the owner via Mirror after init.
// See Sources/Swiflow/Reactivity/Component.swift for details.
final class Counter: Component { ... }
```

Constraints:
- Template and example must stay byte-equal (the `TemplatesTests.appSwiftMatchesExample` test asserts this).
- Comment is *information* not a TODO; no emoji; one wrapped sentence.

**Why this matters:** the comment saves every first-time user ten minutes of confusion, costs zero runtime, and signals that the framework has been thought through.

---

### 4. Loudify the `embed { }` factory contract + add a DEBUG diagnostic

**Current state:**

```swift
// Sources/Swiflow/DSL/ComponentDSL.swift:19-24
/// - Warning: The factory closure must allocate a **fresh** instance every
///   call — `{ Counter() }`, not `{ self.existingCounter }`. Passing an
///   existing instance defeats the per-position reuse logic and produces
///   undefined `@State` lifecycle behaviour: ...
```

The warning exists but lives mid-paragraph in a doc block. The assessment calls this a "sharp edge React doesn't have" — JSX `<Counter/>` is constructively safe; `embed { factory }` requires user discipline.

**New behavior:**

- Promote the warning to a leading `> ⚠️ **Factory contract**` block at the top of the doc-comment, not buried in a `Warning:` field. Use the same wording, but visually first.
- Add a **DEBUG-only** mechanism in the Diff layer that detects when a Component instance returned by a factory has been seen before. Implementation sketch:
  - Renderer maintains a `Set<ObjectIdentifier>` of currently-mounted Component instances (DEBUG only, compiled out in release).
  - On first-mount of a new Component (in `Diff.mount(...)`-equivalent), check if the new instance's `ObjectIdentifier` is already in the set.
  - If yes → call `swiflowDiagnostic("embed { } factory returned an already-mounted Component instance. Factories must allocate a fresh instance per call — `{ Counter() }`, not `{ self.existingCounter }`. See Sources/Swiflow/DSL/ComponentDSL.swift.")`. In DEBUG this traps; in release it is compiled to nothing.
  - On unmount, remove from set.
- Test: a Diff/mount test that constructs a parent which reuses a child instance across mounts and asserts the diagnostic fires.

**Why this matters:** the doc warning catches careful readers; the diagnostic catches the rest. Per the project's XSS posture (per `project_swiflow_xss_posture` memory pattern), DEBUG-only diagnostics are the framework's accepted way to surface programmer footguns.

---

### 5. README "Current State" section + status line bump

**Current state:** README's intro is upbeat ("Frontend ecosystem for Swift on the web") with a *Status:* line at line 10 that names the latest completed phase. There is **no honest section about WASM bundle size, cold-build time, hot-build time, or what's missing.**

**New behavior:** insert a new section, **"Current State"**, immediately after the intro paragraph (between the current line 8 and the "Quick start" heading). Contents:

- **Measured WASM bundle size** for the Counter template (post-`-c release` `.wasm` + JS runtime, in KB). Measurement command documented inline so anyone can reproduce.
- **Cold-build time** on a typical M-series Mac (run `time swift package --swift-sdk <wasm-sdk> js -c release` after `swift package clean` from a fresh `swiflow init` project). Document the command.
- **Hot-build time** (same command, no clean). Document the command.
- **What works today** (bulleted, 3-5 items): Component + `@State` reactivity, postfix VNode modifiers, typed `.on(.click)` events, `URLSanitizer`-protected DSL fold, dev server with full-page reload on save.
- **What's not ready yet** (bulleted, points at master plan): HMR (Phase 8 — *"save → pixels feel instant"* is not yet true), devtools (Phase 9), router (Phase 11), two-way input binding (Phase 7), refs (Phase 7), forms (Phase 12), multi-root rendering (Phase 13).
- One-line pointer to `docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md`.

Also: update the **Status** line at line 10 from "Phase 5 (API Polish) complete" → "Phase 6 (Trust & Polish) complete" at the end of Phase 6.

**Why this matters:** the assessment specifically calls out "the order-of-magnitude difference matters for 'side project deployed to a static host'" and "Owning it ('our cold build is 30 seconds; here's why, here's the cache') is more durable than hiding it." Honesty calibrates first-time users; hiding the cost makes them quit.

---

### 6. Garbage-collect superseded plan drafts

**Current state:** four untracked plan files in `docs/superpowers/plans/`:

- `2026-05-17-swiflow-phase2b-cli.md` — Phase 2b CLI work; already shipped in `f422241..ac0f88b` and Phase 5 commits.
- `2026-05-18-swiflow-phase2b3-cosmetics-cleanup.md` — already shipped as commit `4b962b3` + `f3ce9ca`.
- `2026-05-18-swiflow-phase2c-dev-server.md` — already shipped (dev server is live; HMR upgrade comes in Phase 8).
- `2026-05-18-swiflow-phase3-reactivity.md` — already shipped (Phase 3 reactivity is the post-Phase-5 baseline).

These are archived drafts that were never committed. **Decision:** commit them as-is for the audit trail (per `reference_swiflow_phase_doc_layout` memory — plans live in `docs/superpowers/plans/`). Do not edit content; just `git add` and commit with a chore message.

**Why this matters:** untracked files in `git status` add noise to every future session. Committing them once preserves history and clears the working tree.

---

## Non-Goals (deferred to later phases)

- **HMR / module hot-swap** → Phase 8.
- **Binding consumer (`.value($text)`) actually works** → Phase 7. Phase 6 only hides it; Phase 7 ships it.
- **`Ref<Element>`** → Phase 7.
- **Component inspector** → Phase 9.
- **Removing `Swiflow.render(into:)` single-root precondition** → fully lifted in Phase 13 (dev-mode relaxation lands in Phase 8).
- **Macro-driven `@ChildrenBuilder` error messages** → Phase 13.

## Cross-cutting constraints (project conventions)

- Cross-module visibility uses `package`, not `internal` — per `project_two_module_package_access` memory. No symbol Phase 6 touches needs to cross module boundaries, so this doesn't bite here, but apply if it comes up.
- `js-driver/swiflow-driver.js` and `Sources/SwiflowCLI/EmbeddedDriver.swift` must stay bit-for-bit identical — per `project_js_driver_embedded_sync` memory. Phase 6 doesn't touch either, but Task E (README) will reference Phase 8 plans that touch both.
- SourceKit IDE diagnostics in this workspace lag the on-disk truth — per `feedback_sourcekit_diagnostics_are_stale` memory. Always verify with `swift build` before acting on a `<new-diagnostics>` reminder.

## Verification

Phase 6 is shipped when:

1. All five scope items above are implemented and tested.
2. `swift test` passes the full suite with the new tests added (Phase 5 baseline: 281 tests / 59 suites; Phase 6 target: +5 to +8 tests, no regressions).
3. The Counter template still builds via `swiflow init` and renders correctly via `swiflow dev`.
4. README "Current State" section is populated with **actually measured numbers**, not estimates.
5. `git status` is clean: no untracked plan files remaining; the four superseded drafts are committed.
6. README Status line names "Phase 6 (Trust & Polish)".

## Execution plan

Bite-sized task plan lives at `docs/superpowers/plans/2026-05-20-swiflow-phase6-trust-and-polish.md`. Execution via `superpowers:subagent-driven-development` — same flow as Phase 5.
