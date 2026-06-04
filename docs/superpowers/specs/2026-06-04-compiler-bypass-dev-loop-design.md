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
2. **App source-file-set changes self-heal.** Editing the *contents* of an existing app `.swift`
   file is the fast replay path. Adding / removing / renaming an app `.swift` file invalidates the
   captured command's source list, so it triggers one full `swift build --product App` that also
   re-captures the commands, then the fast path resumes. No restart, no silent miscompile.
3. **Capture is lazy.** Startup is unchanged. The *first* save after launch runs the capturing
   build (~12 s, same as today); every save after that is ~1.6 s. No wasted work if the user
   launches and never edits.

## Architecture

A staleness-aware orchestrator, `BypassRebuilder`, replaces `FastRebuilder` in the dev loop. On
each save it makes a cheap decision:

- **Replay** the two cached commands (~1.6 s) when the app source-file set and `Package.swift` are
  unchanged since capture.
- **Capture-build** — one full `swift build --product App -v` (~12 s) that both produces the wasm
  *and* yields the commands to parse — on the first save, on an app file-set change, or on a
  `Package.swift` change.

The existing `RawWasmBuildInvocation` / `WasmArtifactCopier` are reused as-is. Nothing from Lever 1
is discarded; the bypass is layered on top, and `RawWasmBuildInvocation` remains the permanent
fallback if command capture ever fails to parse.

All new code lives in a new file, `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`, so
`FastRebuild.swift` stays focused.

## Components

### `CapturedBuildCommands` (Sendable value type)

```
struct CapturedBuildCommands: Sendable, Equatable {
    let compile: ResolvedCommand   // App-module swiftc (executable + argv)
    let link: ResolvedCommand      // clang→wasm-ld driver (executable + argv)
    let sourceSet: Set<String>     // app .swift file paths at capture time (staleness key)
    let manifestMTime: Date?       // Package.swift mtime at capture time (staleness key)
}

struct ResolvedCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}
```

### `BuildCommandParser` (pure — the testable heart)

```
enum BuildCommandParser {
    /// Parse verbose `swift build --product App -v` stdout into the two commands.
    /// Returns nil if either anchor line is absent (caller falls back to Lever 1).
    static func parse(verboseOutput: String, appModule: String) -> (compile: ResolvedCommand, link: ResolvedCommand)?
}
```

**Anchors** (each is a single shell-command line in the verbose output):
- **Compile:** the line invoking `…/swiftc` that contains both `-module-name <appModule>` and
  `-target wasm32` (the app executable module's WASM compile). Host-side macro-plugin builds use an
  `arm64-apple-macosx` / Linux host triple and are filtered out by the `wasm32` requirement.
- **Link:** the line invoking `…/clang` with `-o <path>/App.wasm` (the link driver that constructs
  the full `wasm-ld` invocation, including the `@…/Objects.LinkFileList` object list). The bare
  nested `wasm-ld` line is clang's internal spawn and is **not** what we replay.

Lines are split into argv with shell-aware tokenization (handles the quoted paths SwiftPM emits).

### `AppSourceFingerprint`

```
enum AppSourceFingerprint {
    /// Recursively collect *.swift paths under the app source dir, as a set.
    /// Content changes don't alter the set (those are safe to replay); only
    /// add/remove/rename do — exactly the events that invalidate the captured
    /// command's source list.
    static func compute(appSourcesDir: URL) -> Set<String>
}
```

### `CommandReplayer`

```
enum CommandReplayer {
    /// Run compile then link via the ProcessRunner, streaming output to the
    /// user (captureOutput: false). A non-zero exit throws — for a compile
    /// error this surfaces the diagnostics and the loop skips the HMR
    /// broadcast (identical to today's failed-rebuild behavior). Not a
    /// fallback trigger: a full build would fail identically.
    static func replay(_ commands: CapturedBuildCommands, using runner: ProcessRunner) throws
}
```

### `BypassRebuilder` (Sendable struct; per-save state held `inout` by the loop)

```
struct BypassRebuilder: Sendable {
    let capturingBuild: VerboseWasmBuildInvocation   // swift build --product App -v (captureOutput: true)
    let fallback: RawWasmBuildInvocation             // Lever 1 path, used if parsing fails
    let appModule: String                            // "App"
    let appSourcesDir: URL                           // <project>/Sources/App
    let manifestURL: URL                             // <project>/Package.swift
    let artifactURL: URL                             // .build/.../App.wasm (raw build output)
    let outputWasmURL: URL                           // served PackageToJS App.wasm

    /// Decide → build-or-replay → copy. `captured` persists across saves
    /// (owned by the watcher loop); `bypassDisabled` latches on a parse
    /// failure so we don't re-run the slow -v build every save forever.
    func rebuild(
        using runner: ProcessRunner,
        captured: inout CapturedBuildCommands?,
        bypassDisabled: inout Bool
    ) throws
}
```

`VerboseWasmBuildInvocation` is a sibling of `RawWasmBuildInvocation` whose `composeArguments()`
appends `-v` and which runs with `captureOutput: true`, returning stdout for the parser. (Both
could share a small base, but YAGNI — two tiny structs is fine.)

## Data flow (per save)

```
rebuild():
  if bypassDisabled:
      fallback.run(); copy; return                       # permanent Lever-1 path

  fingerprint = AppSourceFingerprint.compute(appSourcesDir)
  manifestMTime = mtime(manifestURL)
  stale = captured == nil
        || captured.sourceSet != fingerprint
        || captured.manifestMTime != manifestMTime

  if stale:
      print reason ("first rebuild — capturing…", "app file set changed — re-capturing…",
                    or "Package.swift changed — re-capturing… (restart if deps changed the JS glue)")
      stdout = capturingBuild.run(using: runner)          # builds AND yields commands (~12s)
      if let cmds = BuildCommandParser.parse(stdout, appModule):
          captured = CapturedBuildCommands(cmds, sourceSet: fingerprint, manifestMTime: manifestMTime)
      else:
          bypassDisabled = true
          log "swiflow: could not capture compile commands; using full builds this session."
      copy(artifactURL → outputWasmURL)
  else:
      CommandReplayer.replay(captured!, using: runner)     # ~1.6s; throws on compile error
      copy(artifactURL → outputWasmURL)
```

The capture-build and the command capture are the **same** invocation — no double build. The
`Package.swift`-changed branch rebuilds + re-captures (handling target-setting / source-dep
changes correctly) and prints the one honest caveat: a dependency change that alters the low-level
JS import surface (`wasm-imports.json`) needs a restart, because `swift build --product App` does
not regenerate the PackageToJS glue. This is rare and consistent with the "framework immutable"
scope.

## DevCommand integration

In the watcher task, replace the `fastRebuilder`/full-build branch with a `BypassRebuilder` plus
loop-owned state:

```
let bypassRebuilder: BypassRebuilder? = WasmArtifactLocator.resolve(...).map { artifactURL in
    BypassRebuilder(
        capturingBuild: VerboseWasmBuildInvocation(...),
        fallback: RawWasmBuildInvocation(...),
        appModule: "App",
        appSourcesDir: projectURL.appendingPathComponent("Sources/App"),
        manifestURL: projectURL.appendingPathComponent("Package.swift"),
        artifactURL: artifactURL,
        outputWasmURL: outputWasmURL
    )
}
// (unchanged) if nil → print the existing "fast rebuild unavailable" notice; loop uses full
//             `invocation.run` per save.

group.addTask {
    let rebuildRunner = SystemProcessRunner()
    var captured: CapturedBuildCommands? = nil      // persists across saves
    var bypassDisabled = false
    for await changed in watcher.changes() {
        print("swiflow: rebuilding (\(changed.count) file…)…")
        do {
            if let bypassRebuilder {
                try bypassRebuilder.rebuild(using: rebuildRunner, captured: &captured, bypassDisabled: &bypassDisabled)
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
matching the existing idiom (and the `rebuildRunner` task-local comment).

## Error handling & fallback hierarchy

| Situation | Behavior |
|---|---|
| App content edit, set + manifest unchanged | Replay (~1.6 s). |
| Replay → `swiftc` compile error (non-zero) | Surface diagnostics, no HMR broadcast (today's behavior). Not a fallback. |
| App file added/removed/renamed | Full `swift build --product App -v` + re-capture, then resume. |
| `Package.swift` mtime changed | Full build + re-capture + one-line "restart if deps changed the JS glue" note. |
| Parser can't find a command line | Latch `bypassDisabled`; use `RawWasmBuildInvocation` for the rest of the session; log once. |
| Bin-path resolution fails at startup | `bypassRebuilder == nil` → existing full `swift package js` per save (unchanged Lever 1 fallback). |

## Testing

**Unit — pure:**
- `BuildCommandParser.parse` against a checked-in sample of real `swift build -v` output
  (`Tests/SwiflowCLITests/Fixtures/`): finds the wasm App compile line (not the host macro-plugin
  line), finds the `App.wasm` link line; returns nil when either is absent; tokenizes quoted paths.
- `AppSourceFingerprint.compute` against temp dirs: stable across content edits; differs on
  add/remove/rename; recurses subdirectories.

**Unit — stubbed `ProcessRunner`:** drive `BypassRebuilder.rebuild` and assert the decision via the
recorded calls + `inout` state:
- First save → runs the `-v` capturing build, sets `captured`, copies.
- Second save, set+manifest unchanged → replays exactly the two captured argvs (assert the
  `StubProcessRunner.calls` match), does NOT run `swift build`.
- File-set change → runs `-v` build again, updates `captured.sourceSet`.
- `Package.swift` mtime change → runs `-v` build again.
- Parse-fail stub → latches `bypassDisabled`, subsequent save runs `fallback` argv.
- Replay non-zero exit → `rebuild` throws (loop would skip broadcast).

**Gated integration** (mirror `FastRebuilderIntegrationTests`, same enablement gate): scaffold a
HelloWorld example, initial `.dev` build, then:
1. First save (content edit) → captures; served wasm reflects the edit.
2. Second save (different content edit) → served wasm reflects it; assert no `swift build` ran
   (e.g. via a marker / timing or a spy runner) — i.e. the replay path executed.
3. Add a new `.swift` file referenced by `App.swift` → fallback re-capture compiles it; served wasm
   contains the new symbol.

## Risks / notes

- **App target naming.** Anchors assume the app module/target is `App` (matches `swiflow init`
  scaffold and the hardcoded `--product App`). A non-conforming project → parser returns nil →
  safe Lever-1 fallback. Acceptable pre-1.0.
- **App sources at `Sources/App`.** Fingerprint assumes the conventional layout. An unconventional
  layout could miss a file-set change → at worst a stale replay until restart. Documented; matches
  existing conventions.
- **`Objects.LinkFileList` reuse.** Replay relies on the link file list written by the capture
  build; it's invariant while the object set is invariant, which is exactly the set we re-capture
  on. Consistent by construction.
- **Capture build output is captured, not streamed.** During a capturing build the user sees a
  one-line "capturing…" message instead of live `swift build` progress. Acceptable (only the slow
  builds; replay builds stream normally).
- **Out of scope:** framework-source hot rebuild (needs per-module replay — explicitly declined),
  multi-target apps, regenerating the PackageToJS glue on dependency changes, Windows/Linux dev
  hosts (dev loop is macOS today). The js-driver/`EmbeddedDriver` are untouched (no driver change).

## Files

- **Create:** `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- **Create:** `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`
- **Create:** `Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt`
- **Modify:** `Sources/SwiflowCLI/Commands/DevCommand.swift` (swap `FastRebuilder` → `BypassRebuilder`
  + loop-owned `captured`/`bypassDisabled` state)
- **Unchanged:** `FastRebuild.swift` (`RawWasmBuildInvocation`, `WasmArtifactLocator`,
  `WasmArtifactCopier` reused as-is)
```
