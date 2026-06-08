# CI Build Cache — why every run was cold, and the ~9-minute fix (2026-06-07)

> **Status:** Fixed and verified on `origin/main`. The Linux `Test` job
> dropped from **~13m10s → ~4m08s** once the SwiftPM `.build` cache started
> being saved and restored. Numbers below are from real runs (cold:
> `27107321416`, warm: `27109584472`).

## Symptom

Every CI run on Swift 6.3.2 paid a full cold build — ~636s for
`Build library + WebTarget` and ~290s for `Test` (almost all of which is
*compiling* the test bundle, not running it) — even though the workflow has
an `actions/cache@v4` step keyed to restore `.build/`. The cache appeared to
never help.

## Root causes (two, compounding)

### 1. A perpetually-red job can never warm its own cache

`actions/cache@v4` writes the cache in a **post-step**, and only when:

- the primary key was a **miss** during restore, **and**
- the job actually **reaches its post-step** — a job that fails mid-way
  skips it (the `- Post Cache SwiftPM build` dash in the run UI).

Every 6.3.2 run had been failing at the `Test` step (see the unrelated
recursion bug below), so the post-save never ran and `.build` was never
written. The very first run to go **green** finally saved the ~861 MB cache;
the next run restored it. The cache was correct all along — it just had
nothing to restore until a run succeeded.

### 2. The cache key hashed a gitignored file

```yaml
key: ${{ runner.os }}-swift6.3.2-wasm6.3.2-${{ hashFiles('Package.resolved') }}
```

`Package.resolved` is **gitignored**, so it doesn't exist at checkout when the
key is evaluated (`swift build` generates it later, during dependency
resolution). `hashFiles()` on a missing file returns an empty string, so the
key silently collapsed to the constant `Linux-swift6.3.2-wasm6.3.2-`. That
"works" (a constant key always hits once saved) but it **never invalidates on
a dependency bump**. Fixed by hashing the tracked `Package.swift`:

```yaml
key: ${{ runner.os }}-swift6.3.2-wasm6.3.2-${{ hashFiles('Package.swift') }}
```

The `restore-keys` prefix (`Linux-swift6.3.2-wasm6.3.2-`) is unchanged, so the
switchover seamlessly restored the cache the first green run had saved, then
re-saved under the real hashed key.

## Results

`Test (ubuntu-22.04)` job, cold vs. warm cache:

| Step | Cold (run …321416) | Warm (run …584472) | Δ |
| --- | ---: | ---: | ---: |
| Build library + WebTarget | 636s | 52s | −584s |
| Test (mostly test-bundle compile) | 290s | 86s | −204s |
| Build CLI | 16s | 15s | — |
| Cache restore | (miss) | 16s | +16s |
| **Test job total** | **~13m10s** | **~4m08s** | **≈ −9 min** |

Restore confirmed in the warm run's log:

```
Cache restored from key: Linux-swift6.3.2-wasm6.3.2-   (~861 MB)
```

## Note: parallelism is not the lever here

The remaining ~86s `Test` step is dominated by **compiling** the test bundle
(macro expansion); actual test *execution* is ~1–2s (each `@Test` ran in
0.001s). So `swift test --no-parallel` vs. parallel changes the total by
~1–2s. `--no-parallel` is kept deliberately — it keeps the process-global
`OnChangeStorage` table (keyed by recycled object addresses) deterministic
across suites. The build cache, not the test runner, is the real lever.

## The bug that kept CI red (and hid the cache problem)

The recurring `SwiflowPackageTests.xctest ... exited with unexpected signal
code 11` was **not** an upstream Swift 6.3.2 toolchain segfault, despite
looking like one. The actual cause was an infinite recursion introduced in a
test helper:

```swift
private func makeCleanHolder() -> OnChange_Holder {
    let c = makeCleanHolder()   // calls itself → stack overflow → SIGSEGV
    ...
}
```

Deterministic under `--no-parallel` (it died at the first `onChange(of:)`
test); "random location" under the parallel runner (many threads overflowing
at once), which is what sold the false toolchain theory. It never reproduced
locally because this machine has no XCTest, so the test bundle never runs
here — only CI exercises it. Fixed in commit `6391eaa`; the cache fix is
`5157906`.

## Reproduction

Push any source change and compare the `Test` job's `Build library +
WebTarget` and `Test` step durations against a run where the cache key
prefix has an entry. A cold build recurs only after a toolchain/SDK bump
(which rotates the `swift6.3.2-wasm6.3.2` key segment) or a `Package.swift`
change with no prior cache under the prefix.
