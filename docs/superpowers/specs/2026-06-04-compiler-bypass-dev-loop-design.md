# Compiler-Bypass Dev Loop (Lever 2) — Design

**Date:** 2026-06-04
**Status:** Approved for planning
**Supersedes:** the "direct swiftc/wasm-ld bypass = NO" verdict in
`docs/perf/2026-06-04-warm-build-spike.md` §3(a) (it rested on an unmeasured 5–8 s link figure).
**Evidence:** `docs/perf/2026-06-04-wasm-hotswap-spike.md`.

## Goal

Cut the `swiflow dev` hot-loop rebuild from ~12 s to ~1.6 s by replaying SwiftPM's own
`swiftc` + `wasm-ld` commands on each save, skipping the ~9 s SwiftPM orchestration overhead
(manifest load, graph resolution, build planning, llbuild stat sweep) that is paid on every
`swift build` invocation even when nothing changed.

## Context

Lever 1 (shipped, `Sources/SwiflowCLI/DevServer/FastRebuild.swift`) already removed the ~17 s
PackageToJS packaging by running `swift build --product App` + an atomic wasm copy over the served
output, reusing the invariant JS glue. The remaining ~12 s is dominated by SwiftPM's per-invocation
overhead, **not** compilation (~2 s) or linking (~0.3 s, measured in isolation).

The spike established that running SwiftPM's *emitted* `swiftc` (App-module compile, carrying
`-load-plugin-executable` so macros expand) and the `clang`→`wasm-ld` link command directly —
with no `swift build` wrapper — rebuilds a real content edit in **~1.6 s** and produces a
byte-faithful, correct `App.wasm`. Lever 2 productionizes that capture-and-replay.

## Scope decisions (locked with the user)

1. **Audience = app developers.** The bypass treats the framework + dependencies as immutable.
   Editing Swiflow's own sources (a path dependency) or anything outside the app target is **not**
   reflected by the fast loop — that needs a `swiflow dev` restart. This is the explicit,
   accepted trade-off; it is what makes single-module replay correct.
2. **App source-file-set *and import-set* changes self-heal.** Editing the *body* of an existing
   app `.swift` file is the fast replay path. Two kinds of change invalidate the captured command
   and trigger a full `swift build --product App` re-capture (then the fast path resumes, no
   restart, no silent miscompile): (a) adding / removing / renaming an app `.swift` file (changes
   the captured source list); (b) changing the **set of `import` lines** across the app sources —
   e.g. adding `import SwiflowQuery` to an existing file. (b) is subtle: the file set is unchanged,
   yet a new import of an already-declared dependency can make the frozen `swiftc` argv's module
   search/load flags wrong, which would surface as a confusing "no such module" on a line the user
   wrote correctly, or (rarer) a stale `.swiftmodule` pickup. The hot-swap spike listed
   "import surface changed" as a re-capture trigger; this design honors that by folding an
   import-line hash into the staleness key.
3. **Capture is lazy.** Startup is unchanged. The *first* save after launch runs the capturing
   build (~12 s, same as today); every save after that is ~1.6 s. No wasted work if the user
   launches and never edits.

## Architecture

A staleness-aware orchestrator, `BypassRebuilder`, replaces `FastRebuilder` in the dev loop. On
each save it makes a cheap decision:

- **Replay** the two cached commands (~1.6 s) when the **staleness key** is unchanged since capture
  (see `StalenessKey` below — app source-file set, import-line hash, `Package.swift` and
  `Package.resolved` mtimes).
- **Capture-build** — one full `swift build --product App -v` (~12 s) that both produces the wasm
  *and* yields the commands to parse — on the first save, or whenever the staleness key differs.

The existing `RawWasmBuildInvocation` / `WasmArtifactCopier` are reused as-is. Nothing from Lever 1
is discarded; the bypass is layered on top, and `RawWasmBuildInvocation` remains the permanent
fallback if command capture ever fails to parse.

All new code lives in a new file, `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`, so
`FastRebuild.swift` stays focused.

### Prerequisite: `ProcessRunner` concurrent pipe drain

The capturing build runs `swift build -v` with `captureOutput: true`. Today `SystemProcessRunner`
drains stdout *then* stderr sequentially (`ProcessRunner.swift:91-92`), and its own comment notes
this can deadlock when a child writes >64 KiB to the not-yet-drained stream — because
`readDataToEndOfFile()` on the first pipe blocks until child exit, while the child blocks on a full
second pipe and never exits. A verbose `swift build` emits ~MBs across stdout **and** stderr, so it
hits this exactly. **First task of the plan: make the `captureOutput: true` path drain both pipes
concurrently** (one reader per pipe — a `DispatchQueue.global().async` reader or a thread, joined
before `waitUntilExit()`). This is a localized fix to `SystemProcessRunner` that benefits all
callers; the existing small-output call sites are unaffected. Because SwiftPM's `-v` lines may land
on stdout or stderr (and this varies by version), the parser consumes the **concatenation of both**
captured streams.

## Components

### `StalenessKey` (Sendable value type — the "safe to replay?" key)

```
struct StalenessKey: Sendable, Equatable {
    let sourceSet: Set<String>   // app .swift file paths (catches add/remove/rename)
    let importHash: Int          // hash of the sorted, de-duped `import` lines across app sources
    let manifestMTime: Date?     // Package.swift mtime
    let resolvedMTime: Date?     // Package.resolved mtime (catches `swift package update` drift)

    /// Walk the app sources once: collect *.swift paths and scan each file's
    /// top-of-file `import` lines, then stat the two manifest files.
    static func compute(appSourcesDir: URL, manifestURL: URL, resolvedURL: URL) -> StalenessKey
}
```

The key's theory: a replay is safe iff the frozen `swiftc`/link argv is still the *correct* argv.
File-body edits don't change the argv (swiftc's own incremental machinery + the stable
`Objects.LinkFileList` handle those). What *does* change the correct argv — a different source list,
a different import surface, or a dependency/manifest change — is exactly what these four fields
detect. Equality of the whole key ⇒ replay; any difference ⇒ capture-build + re-key.

### `CapturedBuildCommands` (Sendable value type)

```
struct CapturedBuildCommands: Sendable, Equatable {
    let compile: ResolvedCommand   // App-module swiftc, the -c (object-emitting) job
    let link: ResolvedCommand      // clang→wasm-ld driver
    let key: StalenessKey          // the key these commands were captured against
}

struct ResolvedCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}
```

### `BuildCommandParser` (pure — the testable heart)

```
enum BuildCommandParser {
    /// Parse combined `swift build --product App -v` output (stdout+stderr) into the two
    /// commands. Returns nil if either anchor is absent OR the compile job is ambiguous —
    /// the caller then falls back to Lever 1.
    static func parse(verboseOutput: String, appModule: String) -> (compile: ResolvedCommand, link: ResolvedCommand)?
}
```

**Anchors** (each is one shell-command line in the verbose output):
- **Compile:** the `…/swiftc` line containing `-module-name <appModule>`, the substring `wasm32`
  (keep it a substring — forward-compatible across `wasip1`/`wasip2`; host macro-plugin builds use
  an `arm64-apple-macosx`/Linux triple and are filtered out), **and an object-emission flag (`-c`)**.
  A real verbose build emits *two* `-module-name App … wasm32` swiftc jobs — an `-emit-module`-only
  job and the `-c` compile job (verified: lines 456 & 464 of a captured QueryDemo build). We replay
  the **`-c` object-emitting** job (the `.swiftmodule` emit job is unneeded — nothing imports the
  executable module). If zero or ≥2 object-emitting candidates match, `parse` returns nil rather
  than guessing.
- **Link:** the `…/clang` line with `-o <path>/App.wasm` (the link driver that constructs the full
  `wasm-ld` invocation, including the `@…/Objects.LinkFileList` object list). The bare nested
  `wasm-ld` line is clang's internal spawn and is **not** what we replay.

Lines are split into argv with shell-aware tokenization (handles the quoted paths SwiftPM emits).

### `CommandReplayer`

```
enum CommandReplayer {
    /// Run compile then link via the ProcessRunner, streaming output to the
    /// user (captureOutput: false). A non-zero exit throws — for a compile
    /// error this surfaces the diagnostics and the loop skips the HMR
    /// broadcast (identical to today's failed-rebuild behavior). Not a
    /// fallback trigger: a full build would fail identically. (Stale-replay
    /// "no such module" errors are prevented up front by the importHash in
    /// StalenessKey, not papered over with a costly auto-recapture-on-failure
    /// — fast failure feedback during normal mid-edit saves is worth more.)
    static func replay(_ commands: CapturedBuildCommands, using runner: ProcessRunner) throws
}
```

### `BypassRebuilder` (Sendable struct; per-save state held `inout` by the loop)

```
/// Loop-owned, single-task state. One `inout` parameter keeps the call
/// signature stable as the staleness key grows.
struct BypassState: Sendable {
    var captured: CapturedBuildCommands?   // nil until first save
    var bypassDisabled = false             // latches true if parsing ever fails
}

struct BypassRebuilder: Sendable {
    let capturingBuild: CapturingWasmBuildInvocation  // swift build --product App -v (captureOutput: true)
    let fallback: RawWasmBuildInvocation              // Lever 1 path, used if parsing fails
    let appModule: String                             // "App"
    let appSourcesDir: URL                            // <project>/Sources/App
    let manifestURL: URL                              // <project>/Package.swift
    let resolvedURL: URL                              // <project>/Package.resolved
    let artifactURL: URL                              // .build/.../App.wasm (raw build output)
    let outputWasmURL: URL                            // served PackageToJS App.wasm

    /// Decide → build-or-replay → copy. `state` persists across saves (owned
    /// by the watcher loop, never shared across tasks — so this stays a
    /// Sendable value type with a non-Sendable runner passed per call).
    func rebuild(using runner: ProcessRunner, state: inout BypassState) throws
}
```

`CapturingWasmBuildInvocation` is a sibling of `RawWasmBuildInvocation` whose `composeArguments()`
appends `-v` and which runs with `captureOutput: true`, returning the combined captured output for
the parser. (Both could share a small base, but YAGNI — two tiny structs is fine.) The name signals
intent: capturing the commands is the purpose; `-v` is the means.

## Data flow (per save)

```
rebuild():
  if bypassDisabled:
      fallback.run(); copy; return                       # permanent Lever-1 path

  key = StalenessKey.compute(appSourcesDir, manifestURL, resolvedURL)
  stale = state.captured == nil || state.captured.key != key

  if stale:
      print reason (first save → "capturing compile commands (one-time ~Ns)…";
                    sourceSet differs → "app file set changed — re-capturing…";
                    importHash differs → "imports changed — re-capturing…";
                    manifest/resolved differs → "Package.swift changed — re-capturing…
                       (if you added/changed a dependency, restart swiflow dev to refresh the JS glue)")
      output = capturingBuild.run(using: runner)          # builds AND yields commands (~12s)
      if let cmds = BuildCommandParser.parse(output, appModule):
          state.captured = CapturedBuildCommands(compile: cmds.compile, link: cmds.link, key: key)
      else:
          state.bypassDisabled = true
          log "swiflow: could not capture compile commands; using full builds this session."
      copy(artifactURL → outputWasmURL)
  else:
      CommandReplayer.replay(state.captured!, using: runner)   # ~1.6s; throws on compile error
      copy(artifactURL → outputWasmURL)
```

The capture-build and the command capture are the **same** invocation — no double build. The
manifest-changed branch rebuilds + re-captures (handling target-setting / source-dep changes
correctly) and prints the one honest caveat, phrased actionably: if the edit added or changed a
*dependency*, the low-level JS import surface (`wasm-imports.json`) may have changed and a
`swiflow dev` restart is needed, because `swift build --product App` does not regenerate the
PackageToJS glue. This is rare and consistent with the "framework immutable" scope.

## DevCommand integration

In the watcher task, replace the `fastRebuilder`/full-build branch with a `BypassRebuilder` plus
loop-owned state:

```
let bypassRebuilder: BypassRebuilder? = WasmArtifactLocator.resolve(...).map { artifactURL in
    BypassRebuilder(
        capturingBuild: CapturingWasmBuildInvocation(...),
        fallback: RawWasmBuildInvocation(...),
        appModule: "App",
        appSourcesDir: projectURL.appendingPathComponent("Sources/App"),
        manifestURL: projectURL.appendingPathComponent("Package.swift"),
        resolvedURL: projectURL.appendingPathComponent("Package.resolved"),
        artifactURL: artifactURL,
        outputWasmURL: outputWasmURL
    )
}
// (unchanged) if nil → print the existing "fast rebuild unavailable" notice; loop uses full
//             `invocation.run` per save.

group.addTask {
    let rebuildRunner = SystemProcessRunner()
    var state = BypassState()      // persists across saves
    for await changed in watcher.changes() {
        print("swiflow: rebuilding (\(changed.count) file…)…")
        do {
            if let bypassRebuilder {
                try bypassRebuilder.rebuild(using: rebuildRunner, state: &state)
            } else {
                _ = try invocation.run(using: rebuildRunner)
            }
            // …existing cache-buster + broadcastHMRSwap + "HMR broadcast"…
        } catch {
            print("swiflow: rebuild failed — \(error). Browser unchanged; fix and save to retry.")
        }
    }
}
```

The `inout` state lives in the single watcher task — one task context, never shared across actors —
so `BypassRebuilder` stays a `Sendable` value type and `ProcessRunner` stays non-`Sendable`,
matching the existing idiom (and the `rebuildRunner` task-local comment). **Invariant:** the loop's
serial `for await` guarantees a rebuild never overlaps the next one — so the replayed `swiftc` never
runs concurrently with itself or a capture build (which would corrupt shared incremental state in
`.build`). Do not parallelize this loop.

## Error handling & fallback hierarchy

| Situation | Behavior |
|---|---|
| App body edit, staleness key unchanged | Replay (~1.6 s). |
| Replay → `swiftc` compile error (non-zero) | Surface diagnostics, no HMR broadcast (today's behavior). Not a fallback. |
| App file added/removed/renamed (`sourceSet` differs) | Full `swift build --product App -v` + re-capture, then resume. |
| Import added/removed (`importHash` differs) | Full build + re-capture, then resume — prevents the stale "no such module" footgun. |
| `Package.swift`/`Package.resolved` mtime changed | Full build + re-capture + one-line actionable "restart if you added/changed a dependency" note. |
| Parser absent/ambiguous command line | Latch `bypassDisabled`; use `RawWasmBuildInvocation` for the rest of the session; log once. |
| Bin-path resolution fails at startup | `bypassRebuilder == nil` → existing full `swift package js` per save (unchanged Lever 1 fallback). |
| Watcher fires mid-rebuild | Serial `for await` queues it; no overlap (see invariant above). |

## Testing

**Unit — pure:**
- `ProcessRunner` concurrent drain: a test child that writes >64 KiB to **both** stdout and stderr
  returns both captures without hanging (guards the prerequisite fix against regression).
- `BuildCommandParser.parse` against a checked-in sample of real `swift build -v` output
  (`Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt`, containing **both** the
  `-emit-module` job and the `-c` job): selects the `-c` object-emitting App compile line (not the
  emit-module job, not the host macro-plugin line); finds the `App.wasm` link line; returns nil when
  an anchor is absent **or** when ≥2 object-emitting candidates match; tokenizes quoted paths.
- `StalenessKey.compute` against temp dirs: stable across file-*body* edits; `sourceSet` differs on
  add/remove/rename; `importHash` differs when an `import` line is added/removed; recurses
  subdirectories; tolerant of a missing `Package.resolved`.

**Unit — stubbed `ProcessRunner`:** drive `BypassRebuilder.rebuild` and assert the decision via the
recorded calls + `inout BypassState`:
- First save → runs the `-v` capturing build, sets `state.captured`, copies.
- Second save, key unchanged → replays exactly the two captured argvs (assert the
  `StubProcessRunner.calls` match), does NOT run `swift build`.
- File-set change / import change / manifest mtime change → each runs the `-v` build again and
  re-keys.
- Parse-fail stub → latches `state.bypassDisabled`; subsequent save runs the `fallback` argv.
- Replay non-zero exit → `rebuild` throws (loop would skip broadcast).

**Gated integration** (mirror `FastRebuilderIntegrationTests`, same enablement gate): scaffold a
HelloWorld example, initial `.dev` build, then:
1. First save (body edit) → captures; served wasm reflects the edit.
2. Second save (different body edit) → served wasm reflects it; assert the replay path executed and
   no `swift build` ran (spy runner / marker).
3. **Coherence after alternation** (closes the incremental-state risk): add a new `.swift` file
   referenced by `App.swift` → fallback re-capture compiles it (served wasm has the new symbol) →
   **then a further body edit replays correctly** and lands in the served wasm. This exercises
   replay → capture → replay, proving the shared `.build` incremental state stays coherent across
   the alternation.

## Risks / notes

- **App target naming.** Anchors assume the app module/target is `App` (matches `swiflow init`
  scaffold and the hardcoded `--product App`). A non-conforming project → parser returns nil →
  safe Lever-1 fallback. Acceptable pre-1.0.
- **App sources at `Sources/App`.** `StalenessKey` assumes the conventional layout. An unconventional
  layout could miss a file-set change → at worst a stale replay until restart. Documented; matches
  existing conventions.
- **`Objects.LinkFileList` reuse.** Replay relies on the link file list written by the capture
  build; it's invariant while the object set is invariant, which is exactly the set we re-capture
  on. Consistent by construction.
- **Capture build output is captured, not streamed.** During a capturing build the user sees a
  one-line "capturing…" message instead of live `swift build` progress. Acceptable (only the slow
  builds; replay builds stream normally). A capture build that *hangs* (e.g. a network dep
  resolution) would show nothing — but that's a startup-class event, not the hot loop.
- **Save-storms / partial writes.** An editor that truncates-then-rewrites can fire the watcher mid
  write; the replayed `swiftc` then errors (surfaced, self-corrects on the next save) or compiles an
  incomplete-but-valid intermediate. This exposure already exists in Lever 1; Lever 2 only makes it
  more visible by being faster. The 250 ms `FileWatcher` debounce is the mitigation; no new handling.
- **Out of scope:** framework-source hot rebuild (needs per-module replay — explicitly declined),
  multi-target apps, regenerating the PackageToJS glue on dependency changes, Windows/Linux dev
  hosts (dev loop is macOS today). The js-driver/`EmbeddedDriver` are untouched (no driver change).

## Files

- **Modify (prerequisite):** `Sources/SwiflowCLI/Process/ProcessRunner.swift` — make the
  `captureOutput: true` path drain stdout + stderr concurrently (one reader per pipe), removing the
  documented >64 KiB dual-stream deadlock that a verbose `swift build` would otherwise hit.
- **Create:** `Sources/SwiflowCLI/DevServer/CompilerBypass.swift` (`StalenessKey`,
  `CapturedBuildCommands`/`ResolvedCommand`, `BuildCommandParser`, `CommandReplayer`,
  `CapturingWasmBuildInvocation`, `BypassState`, `BypassRebuilder`).
- **Create:** `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`
- **Create:** `Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt` (must contain both the
  `-emit-module` and the `-c` App jobs + a host macro-plugin swiftc line, to exercise disambiguation).
- **Modify:** `Sources/SwiflowCLI/Commands/DevCommand.swift` (swap `FastRebuilder` → `BypassRebuilder`
  + loop-owned `var state: BypassState`).
- **Unchanged:** `FastRebuild.swift` (`RawWasmBuildInvocation`, `WasmArtifactLocator`,
  `WasmArtifactCopier` reused as-is).
```
