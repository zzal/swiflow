# Test Design Review — swiflow

**Date:** 2026-06-12 · **Farley Index: 8.3 / 10.0 (Excellent)** — up from 8.0 earlier the same day, after applying all four recommendations from the initial review.

The suite is notable for what it *doesn't* have: across the 47-file deterministic sample (~254 test methods), **zero tautology theatre, zero sleeps, zero cryptic names, zero unconditionally skipped tests, and no mocking framework** — test doubles are hand-rolled, dependency-injected fakes (`StubProcessRunner`, `ManualClock`) that always exercise real production code.

## Property Breakdown

| Property | Static | LLM | Blended | Weight | Key Evidence |
|---|---|---|---|---|---|
| Understandable | 9.4 | 9.6 | **9.5** | 1.50x | 100% of 809 tests carry display-name spec strings; 51+ `@Suite` groups; why-comments throughout |
| Maintainable | 7.0 | 8.2 | **7.5** | 1.50x | DI fakes + builders; `URLSanitizer.Configuration` injection; 37/41 sampled files still use `@testable` |
| Repeatable | 8.3 | 9.0 | **8.6** | 1.25x | Virtual time via `ManualClock`; UUID-isolated temp dirs; env-gated wasm E2E |
| Atomic | 9.1 | 9.0 | **9.0** | 1.00x | Zero `.serialized` suites (was 8); isolation explicit and documented per suite |
| Necessary | 4.2 | 8.5 | **5.9** | 1.00x | `@Test(arguments:)` adopted for table-shaped tests; density still low (8/254 sampled methods) |
| Granular | 9.1 | 8.8 | **9.0** | 1.00x | ~1.5–2 assertions/test; parameterized tables fail per-case |
| Fast | 7.3 | 8.5 | **7.8** | 0.75x | Mostly pure computation; file I/O confined to CLI tests; one gated wasm E2E build |
| First (TDD) | 8.5 | 8.2 | **8.4** | 1.00x | Spec-first naming universal; source commits consistently paired with test changes |

## Tautology Theatre Analysis

The defining test: *"Would this test still pass if all production code were deleted?"*

- **Mock Tautologies:** None detected.
- **Mock-Only Tests:** None detected. (No mocking framework; fakes are always paired with a real SUT.)
- **Trivial Tautologies:** None detected.
- **Framework Tests:** None detected.

**Summary: 0 instances across 0 of ~254 sampled test methods.**

## Improvements Applied Since the Initial Review (all 2026-06-12)

1. **`@Test(arguments:)` adopted** for the validator and event-mapping tables — 12 accept/reject pairs collapsed to 6 parameterized tests; per-case failure reporting (`c633111`).
2. **URLSanitizer suite de-serialized via `Configuration` injection** — production gained `sanitize(_:configuration:)`; tests stopped mutating globals, removing a latent cross-suite race (`241479a`).
3. **All remaining `.serialized` suites eliminated** — sync `@MainActor` atomicity, `@MainActor` alignment for HandlerRegistryMultiRoot, and documented per-test `TaskScope` isolation for the task suites (`0fff598`).
4. **Every bare `@Test` named** — 158 display names across 48 files, derived from test bodies, not de-camelized function names (`11fe18a`).

## Remaining Levers (diminishing returns)

1. **Necessary (5.9)** — more table-shaped candidates exist (URL scheme lists, design tokens, diff cross-kind matrices), but remaining ones are judgment calls rather than obvious wins.
2. **Maintainable (7.5)** — suites that only touch public API (Forms, Event, Router) could use plain `import` instead of `@testable` and become refactoring-proof.
3. **Fast (7.8)** — structural: CLI tests do real file I/O by design.

## Methodology Notes

- Static/LLM blend: 60/40 via the plugin CLI calculator; index formula weights sum to 9.0
- LLM model: claude-fable-5
- Files analyzed: 47 of 161 (SHA-256 deterministic 30% sampling, threshold 50 exceeded; identical selection across runs, so scores are directly comparable)
- Test methods analyzed: ~254 of 809 Swift `@Test` methods (plus 31 Playwright, 46 js-driver)
- Language: Swift (primary; Swift Testing 141 files, XCTest 5), TypeScript/JavaScript (Playwright, node:test + jsdom)
- Caveat: Swift is not among the tool's officially supported languages; detection patterns were adapted (`@Test`/`#expect`/`@Suite`, `.serialized`, `@testable`). T (First) leaned on LLM judgment plus git history, as static TDD evidence is indirect.

## Dimensions Not Measured

Predictive, Inspiring, Composable, Writable (Beck's Test Desiderata — require runtime or team context).

## Reference

- Dave Farley, [Properties of Good Tests](https://www.linkedin.com/pulse/tdd-properties-good-tests-dave-farley-iexge/)
- Scoring methodology: [Andrea LaForgia, test-design-reviewer](https://github.com/andlaf-ak/claude-code-agents/tree/main/test-design-reviewer)
