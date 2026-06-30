# Harden Theme A — Fuzz Suite + Opt-in Backend E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battle-test the SwiflowQuery cache state machine with a deterministic property/fuzz suite (Part A), and add an opt-in, CI-label-gated real-backend e2e for `TodoCRUD` (Part B).

**Architecture:** Part A drives a real `QueryClient` (+ `ManualClock`, `SyncScheduler`, model-backed `boxedFetch`, real `MutationRuntime`s) through randomized op sequences and asserts the cache **converges to a server-truth oracle** at quiescence (plus targeted rollback/supersede regressions). Part B adds a Playwright config that boots the real Bun backend + `swiflow dev`, a spec that asserts read/optimistic-reconcile/toggle/delete/forced-rollback, and a label-gated CI job mirroring the existing `playwright-e2e`.

**Tech Stack:** Swift 6.3 + swift-testing (Part A, host). Playwright + Bun + GitHub Actions (Part B). Spec: `docs/superpowers/specs/2026-06-30-harden-theme-a-fuzz-and-e2e-design.md`.

**Critical context — verified seams:**
- `QueryClient(clock: ManualClock())`; `client.reconcile(owner:scheduler:observations:)` registers live queries; `QueryClient.QueryObservation(key:tags:staleTime:refetchInterval:refetchOnFocus:retry:boxedFetch:valuesEqual:)` (field order per `Tests/SwiflowQueryTests/BackgroundSupport.swift`).
- `client.tick(now:)` (poll), `client.focusChanged(visible:)` (focus), `client.inFlightTasks()` (settle), `client.getQueryDataErased(_:) -> Any?`, `client.invalidate(_:exact:)`, `client.invalidate(tag:)`.
- `ManualClock()` → `.advance(by:)`, `.now()`. `SyncScheduler { (c: AnyComponent) in … }`. `AnyComponent(SomeComponent())`.
- Mutations: `MutationRuntime<M>()`, `.wire(owner:scheduler:client:)`; `MutationHandle(runtime:mutation:)`, `.mutate(_ input:)` (synchronous optimistic + registers the async finish on `client.inFlightMutations`, which `inFlightTasks()` includes).
- `OptimisticEdit.update(_ query: Q) { (Q.Value) -> Q.Value }` keys off `query.queryKey`. `Invalidation` cases: `.exact(QueryKey)`, `.prefix(QueryKey)`, `.tag(QueryTag)`. `QueryKey` is `[String]` (ExpressibleByArrayLiteral); `QueryTag` is a string-literal tag.
- `Query`/`Mutation` are `@MainActor` protocols; you can write **plain conformances** (no `@Query`/`@Mutation` macro needed) — supply `queryKey`/`fetch` (and `optimistic`/`invalidations`) by hand.
- Test harness style: `import Testing; import Swiflow; @testable import SwiflowQuery`. See `BackgroundSupport.swift` + `QueryClientFetchTests.swift`.
- CI: `playwright-e2e` job in `.github/workflows/ci.yml` (lines ~241-312) gated `if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'run-e2e')`; `pull_request` triggers include `labeled`. Playwright configs live in `Tests/playwright/`; `harness.ts` exports `SWIFLOW` (release CLI path) + `ensureCli()`. `package.json` has `test:counter` etc.

**Branch:** `harden/theme-a-fuzz-and-e2e` (created off `origin/main`; spec committed there).

---

## Task 1: Fuzz harness + scripted smoke test (Part A foundation)

**Files:**
- Create: `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift`

- [ ] **Step 1: Write the harness + a scripted (non-random) smoke test that drives a few ops and asserts convergence.**

Create `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift`:

```swift
// Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
//
// Deterministic property/fuzz suite for the SwiflowQuery cache state machine.
// Drives a real QueryClient + MutationRuntime through op sequences and asserts
// the cache converges to a server-truth oracle at quiescence. See
// docs/superpowers/specs/2026-06-30-harden-theme-a-fuzz-and-e2e-design.md.
import Testing
import Swiflow
@testable import SwiflowQuery

// MARK: - Seeded PRNG (SplitMix64) — reproducible; Swift has no shrinking, so
// failures print seed + trace and a regression test pins the trace.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor private final class FuzzSubscriber: Component { var body: VNode { .text("") } }

// MARK: - Server-truth oracle. The cache must converge to `lists` at quiescence.
@MainActor private final class ServerModel {
    var lists: [Int: [Int]] = [:]
    func value(_ id: Int) -> [Int] { lists[id] ?? [] }
    static func key(_ id: Int) -> QueryKey { ["list", String(id)] }
}

// MARK: - Test query/mutations (plain conformances; no macros).
private struct ListQuery: Query {
    let id: Int
    let model: ServerModel
    var queryKey: QueryKey { ServerModel.key(id) }
    var tags: Set<QueryTag> { ["lists"] }
    func fetch() async throws -> [Int] { model.value(id) }
}

private struct AppendMut: Mutation {
    let id: Int; let model: ServerModel
    func perform(_ v: Int) async throws -> Int { model.lists[id, default: []].append(v); return v }
    func optimistic(_ v: Int) -> [OptimisticEdit] { [.update(ListQuery(id: id, model: model)) { $0 + [v] }] }
    func invalidations(input: Int, output: Int) -> [Invalidation] { [.exact(ServerModel.key(id))] }
}

private struct RemoveLastMut: Mutation {
    let id: Int; let model: ServerModel
    func perform(_ ignored: Int) async throws -> Int {
        if !(model.lists[id]?.isEmpty ?? true) { model.lists[id]!.removeLast() }
        return 0
    }
    func optimistic(_ ignored: Int) -> [OptimisticEdit] {
        [.update(ListQuery(id: id, model: model)) { $0.isEmpty ? $0 : Array($0.dropLast()) }]
    }
    func invalidations(input: Int, output: Int) -> [Invalidation] { [.exact(ServerModel.key(id))] }
}

private struct FailAppendMut: Mutation {
    struct Boom: Error {}
    let id: Int; let model: ServerModel
    func perform(_ v: Int) async throws -> Int { throw Boom() }   // never mutates truth
    func optimistic(_ v: Int) -> [OptimisticEdit] { [.update(ListQuery(id: id, model: model)) { $0 + [v] }] }
    // no invalidations — it fails
}

// MARK: - The world: a QueryClient + clock + model + helpers.
@MainActor private final class MarkCounter { var n = 0 }

@MainActor private final class FuzzWorld {
    let model = ServerModel()
    let clock = ManualClock()
    let client: QueryClient
    let scheduler: SyncScheduler
    let owner = AnyComponent(FuzzSubscriber())
    private let markCounter = MarkCounter()
    private(set) var subscribed: Set<Int> = []

    init() {
        let counter = markCounter
        self.scheduler = SyncScheduler { _ in counter.n += 1 }
        self.client = QueryClient(clock: clock)
    }
    func currentMarks() -> Int { markCounter.n }

    // Accumulated observations: reconcile() REPLACES an owner's observation set
    // (dropped keys are unsubscribed), so every subscribe re-sends the FULL set.
    private var observations: [Int: QueryClient.QueryObservation] = [:]
    func subscribe(_ id: Int) {
        guard observations[id] == nil else { return }
        let model = self.model
        observations[id] = QueryClient.QueryObservation(
            key: ServerModel.key(id), tags: ["lists"], staleTime: .zero,
            refetchInterval: .seconds(5), refetchOnFocus: true, retry: .none,
            boxedFetch: { model.value(id) },
            valuesEqual: { ($0 as? [Int]) == ($1 as? [Int]) })
        subscribed.insert(id)
        client.reconcile(owner: owner, scheduler: scheduler, observations: Array(observations.values))
    }

    func mutate<M: Mutation>(_ m: M, _ input: M.Input) {
        let rt = MutationRuntime<M>()
        rt.wire(owner: owner, scheduler: scheduler, client: client)
        MutationHandle(runtime: rt, mutation: m).mutate(input)
    }

    /// Drain every in-flight fetch + mutation, repeatedly (a mutation's success
    /// fires an invalidation → a refetch → a new in-flight task). Bounded.
    func settle() async {
        for _ in 0..<200 {
            let tasks = client.inFlightTasks()
            if tasks.isEmpty {
                scheduler.flush()   // run queued markDirty callbacks so currentMarks() is meaningful
                return
            }
            for t in tasks { await t.value }
        }
        Issue.record("settle() did not quiesce within 200 drains")
    }

    /// Assert every subscribed key's cached value equals the server truth.
    func assertConverged(_ ctx: @autoclosure () -> String) {
        for id in subscribed {
            let cached = client.getQueryDataErased(ServerModel.key(id)) as? [Int]
            #expect(cached == model.value(id), "convergence failed for list \(id): cache=\(cached ?? []) truth=\(model.value(id)) — \(ctx())")
        }
    }
}

@Suite("Query state machine — fuzz")
@MainActor
struct QueryStateMachineFuzzTests {

    @Test("scripted sequence converges (harness smoke test)")
    func scriptedConverges() async {
        let w = FuzzWorld()
        w.subscribe(1); await w.settle()
        let marksBefore = w.currentMarks()
        w.mutate(AppendMut(id: 1, model: w.model), 10); await w.settle()
        #expect(w.currentMarks() > marksBefore)   // notification invariant: a commit marked the subscriber dirty
        w.mutate(AppendMut(id: 1, model: w.model), 20); await w.settle()
        w.mutate(FailAppendMut(id: 1, model: w.model), 99); await w.settle()   // optimistic then rollback
        w.mutate(RemoveLastMut(id: 1, model: w.model), 0); await w.settle()
        w.client.invalidate(["list"], exact: false); await w.settle()
        w.assertConverged("scripted")
        #expect(w.model.value(1) == [10])   // 10,20 appended; 99 rolled back; 20 removed
    }
}
```

- [ ] **Step 2: Run it to verify it compiles and passes.**

Run: `swift test --filter QueryStateMachineFuzzTests`
Expected: PASS (1 test). If the `marks` capture pattern doesn't compile cleanly, simplify: make `SyncScheduler`'s closure increment a `final class Counter { var n = 0 }` held by `FuzzWorld`, and `currentMarks()` returns `counter.n` (avoid the closure-capture-back dance). Keep the behavior: `currentMarks()` reflects scheduler mark count.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
git commit -m "test(query): fuzz harness + scripted convergence smoke test (#theme-a-harden)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Randomized fuzz loop

**Files:**
- Modify: `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift` (append a test)

- [ ] **Step 1: Write the randomized fuzz test.** Append inside `struct QueryStateMachineFuzzTests`:

```swift
    @Test("randomized op sequences converge to server truth")
    func randomizedConverges() async {
        let baseSeed: UInt64 = 0xDEAD_BEEF_CAFE_F00D
        let sequences = 200
        let opsPerSequence = 40
        let listIDs = [1, 2, 3]   // enough for prefix/tag fan-out

        for seq in 0..<sequences {
            var rng = SplitMix64(seed: baseSeed &+ UInt64(seq))
            let w = FuzzWorld()
            var trace: [String] = []
            // Always start with at least one subscription.
            w.subscribe(listIDs[0]); trace.append("subscribe \(listIDs[0])"); await w.settle()

            for _ in 0..<opsPerSequence {
                let id = listIDs.randomElement(using: &rng)!
                let pick = Int.random(in: 0..<7, using: &rng)
                switch pick {
                case 0:
                    w.subscribe(id); trace.append("subscribe \(id)")
                case 1:
                    let v = Int.random(in: 1...999, using: &rng)
                    w.mutate(AppendMut(id: id, model: w.model), v); trace.append("append \(id) \(v)")
                case 2:
                    w.mutate(RemoveLastMut(id: id, model: w.model), 0); trace.append("removeLast \(id)")
                case 3:
                    let v = Int.random(in: 1...999, using: &rng)
                    w.mutate(FailAppendMut(id: id, model: w.model), v); trace.append("failAppend \(id) \(v)")
                case 4:
                    let exact = Bool.random(using: &rng)
                    if exact { w.client.invalidate(ServerModel.key(id), exact: true); trace.append("invalidate.exact \(id)") }
                    else { w.client.invalidate(["list"], exact: false); trace.append("invalidate.prefix") }
                case 5:
                    w.client.invalidate(tag: "lists"); trace.append("invalidate.tag lists")
                case 6:
                    w.clock.advance(by: .seconds(6)); w.client.tick(now: w.clock.now()); trace.append("tick +6s")
                default: break
                }
                await w.settle()
                // Convergence holds at every quiescent point (no pending mutation
                // is in flight after settle()).
                w.assertConverged("seq=\(seq) seed=\(baseSeed &+ UInt64(seq)) trace=\(trace)")
            }
        }
    }
```

- [ ] **Step 2: Run it.** `swift test --filter QueryStateMachineFuzzTests` → expect PASS (2 tests), completing in well under a second. If it's slow, lower `sequences`/`opsPerSequence` until it's snappy (keep ≥100×30).

If convergence FAILS, that is a genuine finding: the printed `seed=` + `trace=` reproduces it. **Do not weaken the assertion.** Report it (DONE_WITH_CONCERNS) with the seed+trace — per the spec, a real `SwiflowQuery` bug is fixed in a separate focused change, not here.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
git commit -m "test(query): randomized convergence fuzz loop with seed+trace repro (#theme-a-harden)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Targeted invariant regressions (rollback + supersede)

**Files:**
- Modify: `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift` (append two tests)

These pin the two subtle invariants deterministically (convergence covers them broadly; these make the intent explicit and catch them precisely).

- [ ] **Step 1: Write the tests.** Append inside `struct QueryStateMachineFuzzTests`:

```swift
    @Test("a failed, non-superseded mutation rolls back to the exact prior value")
    func rollbackExactness() async {
        let w = FuzzWorld()
        w.subscribe(1); await w.settle()
        w.mutate(AppendMut(id: 1, model: w.model), 7); await w.settle()
        let before = w.client.getQueryDataErased(ServerModel.key(1)) as? [Int]
        #expect(before == [7])

        w.mutate(FailAppendMut(id: 1, model: w.model), 999); await w.settle()
        let after = w.client.getQueryDataErased(ServerModel.key(1)) as? [Int]
        #expect(after == [7], "failed mutation must restore the exact prior value")
        #expect(w.model.value(1) == [7])   // truth never changed
    }

    @Test("invalidate supersedes the prior generation; the refetched truth wins")
    func generationSupersedeWins() async {
        let w = FuzzWorld()
        w.model.lists[1] = [1]
        w.subscribe(1); await w.settle()
        #expect(w.client.getQueryDataErased(ServerModel.key(1)) as? [Int] == [1])
        // Truth moves on, then an exact invalidate bumps the generation and
        // refetches; the newer truth must win (and any prior in-flight result is
        // dropped by commitFetch's generation guard).
        w.model.lists[1] = [1, 2]
        w.client.invalidate(ServerModel.key(1), exact: true)
        await w.settle()
        #expect(w.client.getQueryDataErased(ServerModel.key(1)) as? [Int] == [1, 2])
    }
```

This deterministic version proves invalidate→refetch→newer-truth-wins without timing gymnastics. The subtle "a parked stale fetch is dropped mid-flight" case is exercised by the randomized loop in Task 2 (which interleaves `invalidate`/`tick` with mutations' in-flight refetches) — and Step 4 below confirms the generation guard is what makes that loop pass.

- [ ] **Step 2: Run it + the whole suite.** `swift test --filter QueryStateMachineFuzzTests` → 4 tests pass. Then `swift test` (full host suite) → green, no regressions.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
git commit -m "test(query): targeted rollback-exactness + generation-supersede regressions (#theme-a-harden)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify the oracle bites (manual, DO NOT COMMIT the break).** Temporarily weaken `commitFetch` in `Sources/SwiflowQuery/QueryClient.swift` — change `guard entry.generation == generation else { return }` to `guard true else { return }` (drop the generation guard). Run `swift test --filter QueryStateMachineFuzzTests` and confirm **`randomizedConverges` fails** with a printed `seed=`/`trace=` (it interleaves invalidate/tick with in-flight refetches, so a dropped guard lets a stale fetch clobber newer truth → convergence breaks). Then `git checkout -- Sources/SwiflowQuery/QueryClient.swift` to restore and re-run to confirm green. Record the failing seed in the task report. (This proves the suite catches a real regression — acceptance criterion #2.) If `randomizedConverges` does NOT fail with the guard dropped, the fuzz coverage is too weak — increase sequence/op counts or add an explicit "invalidate while a slow refetch is in flight" op until it does.

---

## Task 4: Opt-in backend e2e — config + spec + local script (Part B)

**Files:**
- Create: `Tests/playwright/playwright.todocrud.config.ts`
- Create: `Tests/playwright/todocrud.spec.ts`
- Modify: `Tests/playwright/package.json` (add `test:todocrud`)

This task is **controller-run** for verification (the e2e needs Bun + the real backend + a browser; run it inline, never in a subagent). An implementer may write the files; verification happens by running it locally.

- [ ] **Step 1: Create the Playwright config.** `Tests/playwright/playwright.todocrud.config.ts`:

```ts
// Tests/playwright/playwright.todocrud.config.ts
//
// Opt-in real-backend e2e for examples/TodoCRUD: boots the actual Bun + SQLite
// backend AND `swiflow dev`, then runs todocrud.spec.ts against real HTTP/CORS.
// Gated in CI behind the `run-e2e-backend` label; locally: `npm run test:todocrud`
// (requires Bun on PATH).
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "TodoCRUD");
const BACKEND = join(EXAMPLE_DIR, "backend", "server.ts");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["todocrud.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3002", trace: "on-first-retry" },
  webServer: [
    {
      command: `bun run '${BACKEND}'`,
      url: "http://127.0.0.1:8080/todos",   // GET /todos is the readiness probe
      reuseExistingServer: false,
      timeout: 60_000,
    },
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3002`,
      url: "http://127.0.0.1:3002",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
```

Confirm `REPO_ROOT` is exported by `harness.ts` (it is — `playwright.swiflowui.config.ts` imports it). If not, derive it the same way that config does.

- [ ] **Step 2: Create the spec.** `Tests/playwright/todocrud.spec.ts`:

```ts
import { test, expect } from "@playwright/test";

// Against the REAL Bun + SQLite backend (seeded with 3 todos, first done).
test.describe("TodoCRUD (real backend)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await expect(page.getByText("Read the SwiflowQuery guide")).toBeVisible();
  });

  test("reads the seeded list", async ({ page }) => {
    await expect(page.getByText("Wire a real CRUD API")).toBeVisible();
    await expect(page.getByText("Watch optimistic updates reconcile")).toBeVisible();
  });

  test("optimistic add appears instantly and reconciles to the server row", async ({ page }) => {
    const title = `Buy milk ${Date.now()}`;
    await page.getByPlaceholder("What needs doing?").fill(title);
    await page.getByRole("button", { name: "Add" }).click();
    // Optimistic: visible immediately (before the POST/refetch settles).
    await expect(page.getByText(title)).toBeVisible();
    // Reconciles and stays after the post-mutation GET /todos.
    await expect.poll(async () => page.getByText(title).isVisible()).toBe(true);
    // Survives a reload (it really persisted server-side for the process life).
    await page.reload();
    await expect(page.getByText(title)).toBeVisible();
  });

  test("toggle persists across reload", async ({ page }) => {
    const row = page.getByText("Wire a real CRUD API");
    const checkbox = row.locator("xpath=preceding-sibling::input | ../input[@type='checkbox']").first();
    // The checkbox label carries the title; click the labeled checkbox.
    await page.getByRole("checkbox", { name: "Wire a real CRUD API" }).check();
    await page.reload();
    await expect(page.getByRole("checkbox", { name: "Wire a real CRUD API" })).toBeChecked();
  });

  test("delete removes the row", async ({ page }) => {
    await page.getByRole("button", { name: "Delete Watch optimistic updates reconcile" }).click();
    await expect(page.getByText("Watch optimistic updates reconcile")).toHaveCount(0);
  });

  test("forced network failure rolls the optimistic add back", async ({ page }) => {
    // Abort the POST so perform() fails → optimistic row must roll back + error shows.
    await page.route("**/todos", (route) =>
      route.request().method() === "POST" ? route.abort() : route.continue());
    const title = `Will fail ${Date.now()}`;
    await page.getByPlaceholder("What needs doing?").fill(title);
    await page.getByRole("button", { name: "Add" }).click();
    await expect(page.getByText(title)).toBeVisible();          // optimistic
    await expect(page.getByText(title)).toHaveCount(0);          // rolled back
    await expect(page.getByText("Add failed.")).toBeVisible();
    await page.unroute("**/todos");
  });
});
```

Note: the exact selectors depend on the SwiflowUI `Checkbox`/`Button` DOM. Before finalizing, open the running demo (Step 4) and confirm the accessible names — `Checkbox(todo.title, …)` should expose `getByRole("checkbox", { name: title })`, and `Button("✕", … .attr("aria-label", "Delete \(title)"))` exposes `getByRole("button", { name: "Delete <title>" })`. Adjust selectors to the real a11y tree; keep each test's intent.

- [ ] **Step 3: Add the local script.** In `Tests/playwright/package.json` `scripts`, add:

```json
    "test:todocrud": "playwright test --config=playwright.todocrud.config.ts",
```

- [ ] **Step 4: Run it locally (controller; requires Bun on PATH).** First build the release CLI so the harness uses fresh bytes: `swift build -c release --product swiflow`. Then `cd Tests/playwright && npm run test:todocrud`. Expected: all specs pass against the real backend; the forced-failure test demonstrably shows the optimistic row appear then roll back. Adjust selectors per Step 2's note as needed.

- [ ] **Step 5: Commit.**

```bash
git add Tests/playwright/playwright.todocrud.config.ts Tests/playwright/todocrud.spec.ts Tests/playwright/package.json
git commit -m "test(e2e): real-backend TodoCRUD Playwright suite (Bun + swiflow dev)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: CI job + label gate

**Files:**
- Modify: `.github/workflows/ci.yml` (add a `playwright-e2e-backend` job)

CI-only; cannot be verified locally beyond YAML validity — verified by pushing + adding the label.

- [ ] **Step 1: Add the job.** Append a new job to `.github/workflows/ci.yml`, mirroring `playwright-e2e` but gated on `run-e2e-backend` and adding a Bun setup step + the todocrud config:

```yaml
  playwright-e2e-backend:
    name: Playwright E2E (real backend)
    runs-on: ubuntu-22.04
    # Opt-in (separate from `run-e2e`): boots the real Bun + SQLite backend and
    # runs examples/TodoCRUD end-to-end. Heavier, so its own label.
    if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'run-e2e-backend')
    steps:
      - uses: actions/checkout@v7

      - name: Set up Swift 6.3.2
        uses: vapor/swiftly-action@bedb227456c5f495afbef80baebee17a8a02cef4 # v0.2.1
        with:
          toolchain: "6.3.2"

      - name: Cache SwiftPM build + WASM SDK
        uses: actions/cache@v6
        with:
          path: |
            .build
            ~/.cache/org.swift.swiftpm
            ~/.config/swiftpm/swift-sdks
          key: ${{ runner.os }}-swift6.3.2-wasm6.3.2-${{ hashFiles('Package.swift') }}
          restore-keys: |
            ${{ runner.os }}-swift6.3.2-wasm6.3.2-

      - name: Install WASM SDK (if not cached)
        run: |
          if swift sdk list 2>/dev/null | grep -q "swift-6.3.2-RELEASE_wasm$"; then
            echo "WASM SDK already installed (cache hit)."
          else
            swift sdk install \
              https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz \
              --checksum a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c
          fi

      - name: Build swiflow CLI
        run: swift build -c release --product swiflow

      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Set up Node 20
        uses: actions/setup-node@v6
        with:
          node-version: "20"
          cache: npm
          cache-dependency-path: Tests/playwright/package-lock.json

      - name: Cache Playwright browsers
        uses: actions/cache@v6
        with:
          path: ~/.cache/ms-playwright
          key: ${{ runner.os }}-playwright-${{ hashFiles('Tests/playwright/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-playwright-

      - name: Install Playwright deps
        working-directory: Tests/playwright
        run: npm ci

      - name: Install Playwright browsers
        working-directory: Tests/playwright
        run: npx playwright install --with-deps chromium

      - name: Run TodoCRUD e2e
        working-directory: Tests/playwright
        run: npx playwright test --config=playwright.todocrud.config.ts
```

The `pull_request` trigger already includes `labeled` (no trigger change needed). The `paths-ignore` only filters `**/*.md`/`docs/**`/`LICENSE`, so these `Tests/`/`.github/` changes trigger CI normally.

- [ ] **Step 2: Validate YAML.** Run a YAML lint / `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` (or `actionlint` if available) to confirm the file parses. Expected: no errors.

- [ ] **Step 3: Commit.**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: opt-in real-backend TodoCRUD e2e job (run-e2e-backend label)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `swift test` — full host suite green, including the 4 fuzz/regression tests; suite stays fast.
- [ ] Oracle-bites check performed once (Task 3 Step 4) and reverted — recorded in the report.
- [ ] `cd Tests/playwright && npm run test:todocrud` green locally (Bun installed); forced-failure rollback demonstrated.
- [ ] `ci.yml` parses; existing `playwright-e2e` (`run-e2e`) untouched.
- [ ] Open a PR from `harden/theme-a-fuzz-and-e2e` → `main`. In the PR description, note that adding the **`run-e2e-backend`** label exercises the new job (and create that label on the repo if it doesn't exist). **Do not merge** until the user says "merge it -- CI is green" (`gh pr merge <n> --admin --rebase`). Revert any build-regenerated `examples/**/swiflow-driver.js` / `swiflow-service-worker.js` before opening the PR.

## Spec coverage check

- Deterministic seeded fuzz + reproducible seed/trace → Tasks 1–2.
- Convergence / rollback / generation-supersede / notification invariants → Tasks 1 (convergence+notification via marks), 2 (convergence), 3 (rollback + supersede).
- "Oracle bites" (catches a real regression) → Task 3 Step 4.
- Opt-in real-backend e2e (read/optimistic-reconcile/toggle/delete/forced-rollback) → Task 4.
- Bun-direct orchestration; `test:todocrud` local script → Task 4.
- `run-e2e-backend` label-gated CI job mirroring `playwright-e2e` → Task 5.
- No change to SwiflowQuery/SwiflowFetcher production code or example app code → all tasks are test/CI/config only.
