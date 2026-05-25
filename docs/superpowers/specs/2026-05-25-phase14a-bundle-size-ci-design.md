# Phase 14a — Bundle Size CI

**Goal:** Enforce a bundle-size budget in CI so the README's "~59 MB" claim becomes a tracked, measured number rather than an aspirational one. Catch unjustified growth on every PR before it lands.

**Scope:** Measurement script + committed baseline + new CI job + PR comment. Nothing about *shrinking* the bundle — that's Phase 14b (lazy components).

---

## What we measure

The canonical artifact is **the Counter example** (`examples/HelloWorld`) built with `swiflow build` in release mode. That's what the README quotes and what users see on first run.

For each release build we record four numbers:

| Field | Source | Why |
|---|---|---|
| `wasm_bytes` | `App.wasm` raw size | Headline number; what `Content-Length` reports |
| `wasm_gzip_bytes` | `App.wasm` after `gzip -9` | What clients actually pay on the wire |
| `js_bytes` | `index.js` raw size | PackageToJS runtime — small but non-zero |
| `js_gzip_bytes` | `index.js` after `gzip -9` | Wire cost of the JS runtime |

We compute `total_gzip = wasm_gzip_bytes + js_gzip_bytes` as the single number the CI gate compares.

**Why gzipped totals as the gate:** Raw `.wasm` numbers fluctuate with compiler version and debug-info choices; gzipped wire size is what end-users feel and is more stable across Swift toolchain bumps.

**Out of scope for the baseline:** The dev-only JS driver (`swiflow-driver.js`, ~6 KB) and `index.html`. They're shipped separately, change rarely, and aren't where bundle bloat hides.

## Baseline storage

A single committed file at `docs/perf/bundle-baseline.json`:

```json
{
  "example": "examples/HelloWorld",
  "swift_version": "6.3.0",
  "wasm_sdk_version": "6.3-RELEASE",
  "measured_at": "2026-05-25",
  "wasm_bytes": 61902848,
  "wasm_gzip_bytes": 14523904,
  "js_bytes": 27648,
  "js_gzip_bytes": 8192,
  "total_gzip_bytes": 14532096
}
```

Updating the baseline is a deliberate, reviewed action — a one-line PR that bumps the numbers with a commit message explaining *why* the budget moves. There is no "auto-update baseline" mode; that defeats the purpose of having a budget.

## Measurement script

`Scripts/measure-bundle.sh` (POSIX `sh`, no Bash-isms — runs on the CI Linux runner and on local macOS).

Behavior:

1. From repo root, `swift build -c release --product swiflow` (only if `.build/release/swiflow` is missing).
2. `cd examples/HelloWorld && swift package clean`.
3. Resolve the WASM SDK name via `swift sdk list | grep wasm` (same probe path the existing E2E tests use).
4. Run `../../.build/release/swiflow build` (which wraps `swift package --swift-sdk … js -c release`).
5. Locate `.build/plugins/PackageToJS/outputs/Package/App.wasm` and `index.js`.
6. Print a Markdown table to stdout:

   ```
   | Artifact          | Bytes      | Gzipped    |
   | ----------------- | ---------- | ---------- |
   | App.wasm          | 61,902,848 | 14,523,904 |
   | index.js          |     27,648 |      8,192 |
   | **Total (gzip)**  |            | 14,532,096 |
   ```

7. Write a fresh `current-bundle.json` (same shape as baseline) to a path the workflow can pick up.
8. Exit 0 always. The compare step is separate.

Local devs run `Scripts/measure-bundle.sh` to reproduce the CI number on their machine. The CI job adds a comparison step on top.

**Why a shell script and not Swift:** zero compile cost; the work is `du`, `gzip -c | wc -c`, and `printf`. A Swift target would add 30s of compile time to a job whose whole point is measuring something else.

## CI job

A new job `bundle-size` in `.github/workflows/ci.yml`, modeled on the existing `playwright-e2e` job (same Swift install, same WASM SDK cache, same PR-only gate).

```yaml
bundle-size:
  name: Bundle size
  runs-on: ubuntu-22.04
  if: github.event_name == 'pull_request'
  steps:
    - uses: actions/checkout@v4
    - <Swift 6.3 + WASM SDK setup, copied from playwright-e2e>
    - name: Build swiflow CLI
      run: swift build -c release --product swiflow
    - name: Measure bundle
      run: Scripts/measure-bundle.sh
    - name: Compare against baseline
      id: compare
      run: Scripts/compare-bundle.sh
    - name: Comment on PR
      if: always()
      uses: marocchino/sticky-pull-request-comment@v2
      with:
        header: bundle-size
        message: |
          ${{ steps.compare.outputs.report }}
```

The compare step:

- Reads `docs/perf/bundle-baseline.json` and `current-bundle.json`.
- Computes `delta_pct = (current.total_gzip_bytes - baseline.total_gzip_bytes) / baseline.total_gzip_bytes * 100`.
- Builds a Markdown report with three rows (baseline, current, delta) and an emoji status.
- Exits **0** if `delta_pct <= 5%`.
- Exits **1** (fail the job) if `delta_pct > 5%` AND the PR doesn't carry the `bundle-size-skip` label.
- Exits **1** unconditionally if `delta_pct > 20%` (no label override at that magnitude — that's a Phase-level event that needs a baseline bump).

**Why 5% / 20%:** 5% is the noise floor — a single dependency bump or a stdlib change can move things that much. 20% is "you probably linked in a feature; this needs a separate decision."

**The `bundle-size-skip` label** is the escape valve when a PR legitimately grows the bundle (e.g., shipping a router upgrade). The reviewer applies it after seeing the comment, the job re-runs, passes, and the baseline gets bumped in a follow-up commit.

## PR comment shape

```markdown
### 📦 Bundle size

| Artifact          | Baseline   | This PR    | Δ          |
| ----------------- | ---------: | ---------: | ---------: |
| App.wasm          | 61.9 MB    | 62.1 MB    | +0.3%      |
| index.js          | 27.6 KB    | 27.6 KB    | 0.0%       |
| **Total (gzip)**  | 13.86 MB   | 13.92 MB   | **+0.4%**  |

✅ Within budget (≤5% growth allowed).
```

When over budget:

```markdown
### 📦 Bundle size

| Artifact          | Baseline   | This PR    | Δ          |
| ----------------- | ---------: | ---------: | ---------: |
| **Total (gzip)**  | 13.86 MB   | 14.92 MB   | **+7.6%**  |

❌ Growth exceeds 5% budget.

If this growth is intentional, apply the `bundle-size-skip` label and update `docs/perf/bundle-baseline.json` in this PR.
```

## README integration

Replace the hand-written "~59 MB" line in `README.md` with a section that links to the latest baseline file:

```markdown
**WASM bundle (Counter example, release):** see [docs/perf/bundle-baseline.json](docs/perf/bundle-baseline.json).
Every PR runs `Scripts/measure-bundle.sh` in CI and comments the diff.
```

That way the README never drifts from reality; the JSON is the source of truth and the CI keeps it honest.

## Non-goals

- Measuring `MiniRouter` or `RouterDemo` — Counter is the canonical bundle and adding more examples doubles the CI cost for little signal.
- Tracking dev-mode (`-c debug`) sizes — debug is not what users pay for and doubles build time.
- Per-symbol breakdown — `twiggy`-style analysis is a Phase 14b concern once we have lazy components to attribute to.
- Cold-build *time* tracking — that's the perf doc's job, not this gate.

## Open questions

None. The shape above is deliberately minimal: one script, one JSON, one CI job, one PR label. If anything wants generalizing (multiple examples, multiple artifacts, historical charts) it can come after lazy components land and there's actually a story worth charting.
