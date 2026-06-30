# Harden Theme A — Property/Fuzz Suite + Opt-in Real-Backend E2E — Design

**Goal:** Battle-test the SwiflowQuery data layer and the `TodoCRUD` real-API example *in the development process* — not by manufacturing scale, but by manufacturing, deterministically and repeatably, the adversarial conditions scale eventually exposes (latency, errors, races, time passing, network failure).

Two independent deliverables:
- **Part A** — a deterministic, model-based property/fuzz suite over the cache state machine (cache / SWR / dedup / optimistic / invalidation / **generation** / rollback / retry).
- **Part B** — an opt-in, CI-label-gated end-to-end test of `TodoCRUD` against its real Bun + SQLite backend.

**Context.** Theme A (a real read+write SwiflowQuery example) already ships as `examples/TodoCRUD` (real Bun+SQLite CRUD: read via `query(TodoList())`, write via `@MutationState` with optimistic edits + `.exact(["todos"])` invalidation + 5s polling + focus-refetch) and `examples/MissionControl` (read-heavy real APIs). The gap is **coverage**: the query/mutation/optimistic machinery these exercise has no fuzz coverage, and the examples have no e2e/CI gate (CI skips example builds), so they can silently rot. This spec closes that gap.

---

## Existing seams this builds on (verified)

- `QueryClient(clock: any QueryClock = SystemQueryClock())` — clock is injectable; `ManualClock` exists for deterministic time (used in `Tests/SwiflowQueryTests/QueryClientFetchTests.swift`).
- `QueryEntry.boxedFetch = { … }` — per-entry fetch closure; tests set it to return / throw / delay arbitrary results.
- `SyncScheduler { _ in … }` — synchronous scheduler; render-marks are observable; `flush()` runs queued callbacks.
- `client.inFlightTasks()` — returns in-flight fetch + mutation tasks to `await` for deterministic settling.
- `MutationRuntime<M>.wire(owner:scheduler:client:)`, `.beginOptimistic(_:_:)` (synchronous optimistic + `.pending`, returns a rollback stack of `(key, prior, gen)`), `.finish(_:_:_:)` (async perform → success: set data + invalidate; failure: generation-guarded rollback).
- `QueryClient.generation(of:)`, `.setQueryData(_:_:)`, `.getQueryDataErased(_:)`, `.invalidate(_:exact:)`, `.invalidate(tag:)`, `.startFetch(for:entry:)`; `forceStaleAndRefetch` bumps generation + cancels in-flight + refetches live subscribers; `commitFetch` commits only if `entry.generation == capturedGeneration`.
- Retry/backoff is clock-driven: `entry.failureCount`, `entry.nextRetryDue = clock.now() + entry.retry.delay(forAttempt:)`, `entry.retry.maxRetries`.
- **CI pattern (verified):** `ci.yml` has a `playwright-e2e` job gated `if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'run-e2e')`; the workflow triggers on `labeled` events. `playwright.swiflowui.config.ts` shows the in-place `swiflow dev --path <example> --port <p>` webServer pattern; `harness.ts` exposes `SWIFLOW` (release CLI path) and `ensureCli()`.

---

## Part A — Property/Fuzz suite

### File
- Create: `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift` (host, swift-testing).
- Possibly: a tiny seeded-PRNG helper inline in that file (no new dependency).

### Determinism & reproducibility
- A seeded **SplitMix64** PRNG (≈10 lines, inline). No external dependency, deterministic, good distribution.
- The suite runs many independent sequences (target: ~200 sequences × ~50 ops each — tune so the suite stays well under a second). Each sequence seeds the PRNG from a base seed + sequence index.
- **No shrinking framework** (Swift has none). Instead: on the first failing assertion, the harness prints the **base seed, sequence index, and the op trace executed so far**, so the exact sequence reproduces by pinning that seed — and a focused regression `@Test` can hard-code the trace.

### Harness
A `Model` (oracle) + a real `QueryClient` driven in lockstep:
- **Domain:** a small fixed set of test types so the oracle is tractable — a list query keyed by an integer "list id" whose `Value` is `[Int]`, plus mutations `Append(listID, value)`, `RemoveLast(listID)`, and `FailingAppend(listID, value)` (its `perform` throws). 2–3 distinct list keys so prefix/tag invalidation has something to fan across.
- **Real side:** `QueryClient(clock: ManualClock())`, a `SyncScheduler`, a `Dummy` subscriber `Component` (as in `QueryClientFetchTests`), `MutationRuntime`s wired via `wire(owner:scheduler:client:)`. Each query entry's `boxedFetch` returns the **server-truth model value** for its key (so a refetch reconciles to truth); a mutation's `perform` mutates the server-truth model then returns.
- **Oracle (`Model`):** per key, tracks `serverTruth: [Int]`, `generation: Int` (mirrors bump-on-invalidate / bump-on-supersede), and the set of in-flight mutations' optimistic layers. After each op the harness computes the **expected committed cache value** and asserts equality with the real client (after advancing the clock and draining `inFlightTasks()` where the op implies settling).

### Op alphabet (chosen per step by the PRNG)
1. **Subscribe** a (possibly new) list key (creates the entry + initial fetch).
2. **Mutate** — `Append` / `RemoveLast` (succeeds) or `FailingAppend` (its `perform` throws). Resolution order across overlapping mutations is PRNG-controlled to force races.
3. **Invalidate** — `.exact(key)`, `.prefix(key)`, or `.tag(t)`.
4. **Advance clock** past `staleTime` and/or `refetchInterval` (drives SWR staleness + polling).
5. **Focus** (triggers refetch-on-focus for live, stale entries).
6. **Drain** — `await inFlightTasks()` + `scheduler.flush()` to settle, then assert invariants.

### Invariants (asserted continuously)
1. **Convergence** — after all in-flight settle with no pending mutation, every key's cached value equals the model's `serverTruth` (no optimistic residue; no leaked sentinel/temp values).
2. **Generation monotonic-wins** — no stale fetch/result ever commits over a newer generation (assert via the generation guard: an op trace that supersedes an in-flight fetch never resurfaces the old value).
3. **Rollback exactness** — a `FailingAppend` whose key was **not** superseded restores exactly the pre-mutation value; a superseded failing mutation does **not** clobber the newer writer (its rollback is skipped).
4. **Notification** — a committed value change marks the subscribing component dirty (observed via the `SyncScheduler` mark count).

### Scope
- Targets `QueryClient` + `MutationRuntime` (the generation/rollback/invalidation/SWR core). Uses only the existing package/internal test seams.
- Not in scope: the WASM `Renderer`, real network, `SwiflowFetcher` (covered by its own tests + Part B).

---

## Part B — Opt-in real-backend E2E

### Files
- Create: `Tests/playwright/playwright.todocrud.config.ts`
- Create: `Tests/playwright/todocrud.spec.ts`
- Modify: `Tests/playwright/package.json` (add `test:todocrud` script)
- Modify: `.github/workflows/ci.yml` (new label-gated job; `labeled` trigger already present)

### Config (`playwright.todocrud.config.ts`)
Mirror `playwright.swiflowui.config.ts`, but with a **two-process `webServer`**:
1. **Backend:** `bun run examples/TodoCRUD/backend/server.ts`, `url: http://127.0.0.1:8080/todos` (Bun's `GET /todos` is the readiness probe), `reuseExistingServer: false`.
2. **Frontend:** `'${SWIFLOW}' dev --path examples/TodoCRUD --port 3002`, `url: http://127.0.0.1:3002`, `reuseExistingServer: false`, `timeout: 300_000`.

`baseURL: http://127.0.0.1:3002`, `testDir: '.'`, `testMatch: ['todocrud.spec.ts']`, `fullyParallel: false`, single chromium project. `ensureCli()` at top (as the other configs do).

**Backend orchestration = Bun directly** (zero-npm Bun script, light in CI). The existing `Dockerfile`/`docker-compose.yml` stay for local `docker compose up`; the e2e does not use them.

### Spec (`todocrud.spec.ts`)
Against the real backend + real `fetch`/CORS/`JSValueDecoder`:
1. **Read:** after a brief `Loading…`, the three seeded todos render (first checked).
2. **Optimistic add → reconcile:** type a title + **Add** → the row appears **immediately**; then the list reconciles (the optimistic negative temp-id row is replaced by the server row). Assert the row is present and stable after the post-mutation `GET /todos` settles (poll for the reconciled state).
3. **Toggle persists:** toggle a checkbox → `done` flips; reload the page → still flipped (the in-memory DB persists for the backend process's life).
4. **Delete:** ✕ removes the row; it stays gone after revalidation.
5. **Forced-failure rollback (no backend change):** `page.route('**/todos', route => route.abort())` (or scoped to the next POST), fire **Add**, assert the optimistic row appears **then disappears** (rollback) and the "Add failed." error shows. Then unroute and confirm normal adds work again.
6. **(Optional) polling:** from the test, `POST` a todo straight to `http://127.0.0.1:8080/todos`, then assert the UI list shows it within ~6s (the 5s `refetchInterval`).

### Local run
`Tests/playwright/package.json` → `"test:todocrud": "playwright test --config=playwright.todocrud.config.ts"`. Requires Bun on PATH locally (documented in the spec/README); the config invokes `bun run` directly.

### CI (`ci.yml`)
Add a `playwright-e2e-backend` job mirroring `playwright-e2e` (checkout, swiftly/Swift toolchain, WASM SDK download+install, release `swiflow` build, Playwright deps + chromium install, browser cache) **plus**:
- a Bun setup step (`oven-sh/setup-bun@v2`);
- gate: `if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'run-e2e-backend')`;
- run step: `npx playwright test --config=playwright.todocrud.config.ts` in `Tests/playwright`.

A **distinct `run-e2e-backend` label** (separate from `run-e2e`) keeps the heavier backend run opt-in on its own. The workflow's existing `pull_request: types: [..., labeled]` trigger already covers it; confirm `labeled` is present (it is).

---

## Testing / verification of this work

- **Part A:** `swift test --filter QueryStateMachineFuzzTests` is green and runs in well under a second; deliberately introducing a bug (e.g. removing the generation guard in `commitFetch`) makes it fail with a printed seed+trace (sanity-check the oracle actually bites — do this manually once, do not commit the break).
- **Part B:** locally, `cd Tests/playwright && npm run test:todocrud` (with Bun installed) is green; the forced-failure case demonstrably exercises rollback. In CI, adding the `run-e2e-backend` label to a PR triggers the job and it passes.
- Full host suite (`swift test`) stays green; existing `playwright-e2e` (`run-e2e`) unaffected.

## Acceptance criteria
1. A deterministic, seeded property/fuzz suite drives randomized op sequences against a real `QueryClient`/`MutationRuntime` and asserts the four invariants; failures print a reproducible seed + trace.
2. Removing the `commitFetch` generation guard (a real regression) is caught by Part A (verified once, manually).
3. An opt-in `todocrud.spec.ts` runs the real Bun backend + the WASM app and asserts read, optimistic-add→reconcile, toggle-persist, delete, and forced-failure rollback over real HTTP.
4. The backend e2e is gated behind a `run-e2e-backend` CI label and a `test:todocrud` local script; it does not run on normal CI.
5. No change to the existing `run-e2e` Playwright job, the examples' app code, or `SwiflowQuery` production code (test-only + CI + config additions).

## Out of scope
- A backend "chaos mode" (env-flag latency/error injection in `server.ts`) — the forced-failure case uses Playwright route interception instead; chaos mode can be a later add.
- MissionControl e2e (read-only, third-party live APIs — flakier to gate on; revisit separately).
- Shrinking-framework integration; offline/soak/leak harnesses; DEBUG in-cache invariant assertions (Tier 3) — all deferred.
- Any change to `SwiflowQuery`/`SwiflowFetcher` production behavior. If Part A surfaces a real bug, fix it in a separate, focused change.
