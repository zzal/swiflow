# Swiflow Phase 13.0 — `swiflow init` outside-repo fix

## Goal

Make `swiflow init` work from any directory. Remove the hardcoded `"../.."` default from `--swiflow-source`; make the flag required with an actionable error message so users who don't pass it get a clear explanation rather than a cryptic SPM failure later.

---

## Root Cause

`InitCommand.swiflowSource` defaults to `"../.."`. That relative path is evaluated at `swiflow dev`/`swiflow build` time by SPM, not by the CLI. It resolves correctly only when the generated project sits inside the Swiflow repo tree (e.g., `examples/MyApp/../../` → Swiflow root). Anywhere else it points at an unrelated directory, and SPM names whatever package it finds there instead — producing:

```
'my-swiflow': unknown package 'Swiflow' in dependencies of target 'App'; valid packages are: 'private'
```

Swiflow has no public release yet, so there is no git URL to fall back on. The right fix is to make `--swiflow-source` required and fail fast with a helpful message instead of silently generating a broken project.

---

## Design

### Scope

Two files change. Everything else stays untouched.

| File | Change |
|---|---|
| `Sources/SwiflowCLI/Commands/InitCommand.swift` | Make `--swiflow-source` required; add `validate()`; update help text |
| `Tests/SwiflowCLITests/InitCommandTests.swift` | Update 2 existing tests; add 1 new test |

`ProjectWriter`, `Templates`, and the E2E tests (`DevCommandTests`, `BuildCommandTests`) are unaffected — they already pass `swiflowSource` as an explicit concrete value.

---

## `InitCommand.swift` changes

### 1 — Change the option type

```swift
// Before
var swiflowSource: String = "../.."

// After
var swiflowSource: String?
```

### 2 — Update help text

Remove the stale "After Phase 4 publishes Swiflow…" discussion. Replace with:

```swift
@Option(
    name: .customLong("swiflow-source"),
    help: ArgumentHelp(
        "Path the generated project uses for its Swiflow dependency.",
        discussion: """
            Required until Swiflow has a public release. Pass the absolute or \
            relative path to your local Swiflow clone.
            Example: --swiflow-source /path/to/swiflow
            """
    )
)
var swiflowSource: String?
```

### 3 — Add `validate()`

ArgumentParser calls `validate()` after parsing and before `run()`. This is the right hook for domain-specific required-field checks because it integrates with ArgumentParser's error pipeline (exit code 64, usage hint printed automatically).

```swift
mutating func validate() throws {
    if swiflowSource == nil {
        throw ValidationError("""
            --swiflow-source is required. Swiflow has no public release yet.
            Pass the path to your local Swiflow clone:
              swiflow init \(name) --swiflow-source /path/to/swiflow
            """)
    }
}
```

### 4 — Unwrap in `run()`

`validate()` guarantees `swiflowSource` is non-nil when `run()` is called:

```swift
swiflowSource: swiflowSource!,   // safe: validate() guards this
```

---

## Test changes

### Update: "Defaults: --path is ."

The test currently parses `["demo"]` and asserts `swiflowSource == "../.."`. After the change, parsing `["demo"]` with no `--swiflow-source` is still valid at parse time (the field is `String?`) — `validate()` is called by `parse(_:)`, so it now throws `ValidationError`.

Split into two targeted tests:

```swift
@Test("Default: --path is .")
func defaultPath() throws {
    let parsed = try InitCommand.parse(["demo", "--swiflow-source", "/some/path"])
    #expect(parsed.name == "demo")
    #expect(parsed.path == ".")
}

@Test("Missing --swiflow-source surfaces a ValidationError")
func missingSwiflowSource() {
    #expect(throws: ValidationError.self) {
        try InitCommand.parse(["demo"])
    }
}
```

### Update: "--path that doesn't exist surfaces a ValidationError"

This test omits `--swiflow-source`, so after the change `validate()` throws for the missing flag before `run()` even checks the path. Add `--swiflow-source` so the test exercises what it says it exercises:

```swift
@Test("--path that doesn't exist surfaces a ValidationError")
func refusesMissingPath() async throws {
    let cmd = try InitCommand.parse([
        "Demo",
        "--path", "/does/not/exist/swiflow-test-\(UUID().uuidString)",
        "--swiflow-source", "/abs/path/to/swiflow",
    ])
    await #expect(throws: ValidationError.self) {
        try await cmd.run()
    }
}
```

### No other test changes

All other `InitCommandTests` call `ProjectWriter.writeProject(swiflowSource: ...)` directly (bypassing the CLI) or already supply `--swiflow-source` explicitly. They pass unchanged.

---

## Error message rationale

The message includes:

1. **The flag name** — so users know exactly what to add
2. **The reason it's required** — "no public release yet" prevents confusion (they'd otherwise search for a release or a default URL)
3. **A concrete example** — copy-pasteable with just a path substitution

---

## Testing strategy

**Unit (no WASM build required):**
- Parse `["demo"]` without `--swiflow-source` → `ValidationError` ✓
- Parse `["demo", "--swiflow-source", "/x"]` → `swiflowSource == "/x"` ✓
- Parse with bad `--path` + valid `--swiflow-source` → `ValidationError` from `run()` ✓

**End-to-end (existing, no changes):**
- `DevCommandTests` and `BuildCommandTests` already pass `swiflowSource: swiflowRepoRoot.path` — continue to pass unchanged ✓

---

## Out of scope

- Publishing Swiflow or switching to a git URL default — deferred until there is a public release to point at
- `swiflow build` and `swiflow dev` — the `--path` flag on those commands points at the generated *project*, not the Swiflow source; they are unaffected
