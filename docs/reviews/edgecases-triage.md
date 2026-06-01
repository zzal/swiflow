# EdgeCases stress-harness — triage report

**Date:** 2026-05-30
**Updated:** 2026-05-31 — Trap 12 (controlled-value patch) added on `main` (commit `14490e4`); harness now 12 traps.
**Branch:** `feat/edgecases-stress`
**Harness:** `examples/EdgeCases/` (12 traps) + `Tests/playwright/edgecases.spec.ts` (run: `npm run test:edgecases`, builds in-place on :3003)
**Spec:** `docs/superpowers/specs/2026-05-30-edgecases-reconciliation-stress-harness-design.md`

## Headline

**12/12 traps pass. No reconciler correctness bugs found.** Across an adversarial sweep of nested fragments, loops, conditionals, keyed reorders, component lifecycle, bulk add/remove, and the raw-spread limitation, the stable-child-slots reconciler preserved node identity / sibling state in every case. Traps 1–11 probe the *preserve* path (an uncontrolled node must survive a sibling mutation); **Trap 12 adds the complementary *update* path** — a controlled input bound to `@State` must have its live `.value` patched onto the **same** reused node when state changes. A holistic review confirmed **every trap is genuine** (none vacuously green): each builds the nested shape it claims and each assertion would fail under spurious recreation.

## Per-trap results

| Trap | Edge case | Result | Genuine? |
|---|---|---|---|
| 1 | conditional before a sentinel input | pass | yes — load-bearing dialog-bug regression guard |
| 2 | `for`-of-`if` | pass | yes |
| 3 | `for`-of-`if`-of-`for` (3-level) | pass | yes |
| 4 | loop inside a conditional (`<details open>` sentinel) | pass | yes |
| 5 | keyed reorder with interspersed fragments | pass | yes — keys did not neuter it |
| 6 | two adjacent conditionals (bucketKey path) | pass | yes |
| 7 | component in an emptying fragment + sibling `@State` | pass | yes — strongest signal (lifecycle counts + Keeper state) |
| 8 | empty→full→empty rapid cycle (no leak) | pass | yes |
| 9 | keyed items carrying inner `if`/state across reorder | pass | yes |
| 10 | raw `[VNode]` spread (known limitation) | pass | yes — no-crash / no-cross-container guard |
| 11 | dynamic keyed list: Add +1/+100 front&back, Remove, Swap, Clear | pass | yes — bulk-churn identity preserved |
| 12 | controlled input (`.value($state)`): state-change value patch + two-way typing | pass | yes — only trap on the *update* path; `__tag` proves in-place patch, not recreate |

Detection method: typed value + a stamped `__tag` DOM property (a reused node keeps both; a recreated node loses both), plus `<details open>` (Trap 4) and child-`@State` counters (Trap 7). Trap 12 inverts the value signal — because a controlled input's value is restored from `@State` on recreation, the typed value *can't* prove reuse there, so the stamped `__tag` is the sole identity signal while the value asserts the state→DOM patch landed.

## Findings (non-correctness)

1. **Detection methodology fix (in the harness, not the framework).** The initial Trap 1 test asserted `toBeFocused()` after clicking the toggle *button* — but a button click steals focus, so it failed regardless of node identity (a false "bug"). Corrected to value + tagged-node identity (`seedSentinel`/`expectSurvived`). All sentinel checks now use this; focus is never asserted after a control click.

2. **Mixed keyed/unkeyed children → hard `preconditionFailure` (DEBUG-only).** `Sources/Swiflow/Diff/Diff.swift` fires the diagnostic (→ `Diagnostics.swift` crash) when a container's element/component children mix keyed and unkeyed. Fragments (`if`/`for`) are exempt. This forced explicit `.key(...)` on the keyable siblings in Traps 5 & 6 (intent preserved). **Ergonomics note:** a hard crash is defensible (the alternative is silent per-render re-mounting of unkeyed children), but it's harsh; a future option is a release-mode one-shot `console.error` + auto index-key fallback (the `__index_<i>` plan already noted in `KeyedChildrenDiff.swift`). Not a bug; logged for consideration.

3. **Raw `[VNode]` spread footgun (Trap 10).** An unwrapped `[VNode]` spliced into a builder is flattened (documented in `ResultBuilder.swift`), so changing its length shifts following siblings *within that element*. Confirmed it degrades gracefully — no crash, and a sentinel in a *separate* element is unaffected. Behaves as documented.

4. **`$0` shorthand collides with nested result-builder closures.** `.map { span { text("s\($0)") } }` fails to compile — `$0` binds to the inner `span`'s `@ChildrenBuilder` closure, not the `.map` closure. A named loop variable is *required* (`.map { i in span { text("s\(i)") } }`). Inherent to Swift shorthand-argument scoping; worth a one-line DSL-docs note ("name your loop variable when mapping element builders").

## Follow-ups (not done — future improvements)

- **Trap 11 perf assertion.** Currently identity-only. Add a `window.__swiflow.perf().lastPatchCount` bound after `+100 front` so a correct-but-O(n²) diff regression (existing rows needlessly re-placed) can't pass silently. (`DevAPI` exposes it.)
- **Trap 5 fragment-position assertion.** The keyed-input reuse is checked; "fragments hold their positions" is only implicit — add a sibling-order assertion.
- **Highest-value missing traps:** (a) a fragment as the FIRST child (worst case for `nextDOMAnchor` append-vs-insert); (b) simultaneous toggle of two adjacent fragments in one render (the real `bucketKey`-collision stress; one-at-a-time mostly hits the prefix scan); (c) moving a keyed item that itself contains a non-empty fragment across a reorder (multi-root `placeRoots` under LIS); (d) text-node interleaving with keyed siblings; (e) cross-kind replace at a keyed slot (same key, tag change) — has subtle reattach logic and no trap.
- **Cosmetic:** `Trap11DynamicList.add` mutates `nextId` inside `.map` (side-effecting map); `let ids = Array(nextId ..< nextId + count); nextId += count` is clearer.

## Embedded as a template (fulfills spec §6)

EdgeCases is embedded as `swiflow init --template EdgeCases` — `swiflow init --help` lists `EdgeCases, HelloWorld, MiniRouter`, and scaffolding substitutes the project name (`name: "EdgeCases"` → the user's name). `EmbeddedTemplates.swift` was regenerated (`swift scripts/embed-templates.swift`); the bit-for-bit freshness gate passes. The Playwright e2e still builds the source **in-place** (`swiflow dev --path examples/EdgeCases`, see `playwright.edgecases.config.ts`) so it tests the real example directly, independent of the embedded copy. Maintenance note: editing a trap now requires re-running the embed script before the freshness test will pass.
