# `swiflow init` — Templates Sourced From `examples/`

**Status:** Draft
**Date:** 2026-05-28
**Predecessor:** Phase 13 (`swiflow init` rough edges)

## Problem

`Sources/SwiflowCLI/Templates/Templates.swift` carries ~200 lines of inline
string constants — `rawPackageSwift`, `rawAppSwift`, `rawIndexHTML`,
`rawGitignore`, `rawReadme` — that duplicate the contents of
`examples/HelloWorld/`. `Tests/SwiflowCLITests/TemplatesTests.swift` already
asserts each constant is byte-equal to its on-disk counterpart, so the
duplication is forced in-sync by tests — but a contributor editing the
example still has to mirror the change into the string literal (and the
test only flags it after the fact).

A second gap rides on the same surface: `swiflow init` can only scaffold
the HelloWorld example. `examples/MiniRouter/` and `examples/RouterDemo/`
exist as fully working projects but cannot be selected. The Playwright
router config (`Tests/playwright/playwright.router.config.ts:12-15`) calls
this out explicitly:

> Unlike Counter, RouterDemo lives in the tree (examples/RouterDemo/)
> rather than being scaffolded fresh each run.

That checked-in tree is a workaround for the missing `--template` flag.

Both problems are closed by treating `examples/*` as the single source of
truth and generating an embedded template carrier at build time — the
exact pattern `EmbeddedDriver` already uses for the JS driver.

## Goals

1. Delete the raw template string constants from `Templates.swift`. The
   on-disk `examples/<name>/` directories become the only place template
   contents live.
2. Make every directory under `examples/` available as a template via
   `swiflow init <name> --template <template>` (default `HelloWorld`).
3. Keep `swiflow` as a single self-contained binary — no runtime
   filesystem dependency on the repo tree.
4. Preserve the drift-detection guarantee the current `TemplatesTests`
   provides, in the same shape as `DriverEmbedderTests`.

## Non-Goals

- Migrating `Tests/playwright/playwright.router.config.ts` to scaffold
  RouterDemo via `swiflow init --template RouterDemo`. Natural follow-on,
  separate PR.
- A general-purpose templating engine. The substitution model stays at
  two tokens (`{{NAME}}` and a swiflow-dep placeholder). The placeholder
  name changes from today's `{{SWIFLOW_SOURCE}}` to `{{SWIFLOW_DEP}}`
  because codegen now normalizes the whole `.package(...)` line, not
  just the path string inside it. Token rename is an internal detail —
  no user-facing impact.
- Inheriting files across templates (e.g. "use HelloWorld's README if
  the example lacks one"). Each template ships exactly what its
  directory contains; missing files are added to the example, not
  synthesized at scaffold time.
- SwiftPM resources or `Bundle.module` access. Codegen produces a flat
  Swift file, same as `EmbeddedDriver`.

## Approach: Build-Time Codegen

Mirror the `EmbeddedDriver` pattern. A standalone script
(`scripts/embed-templates.swift`) walks `examples/`, normalizes
per-example tokens, and emits a generated
`Sources/SwiflowCLI/EmbeddedTemplates.swift`. A freshness test re-runs
the codegen logic in-process and asserts the generated file matches what
the script would emit right now.

### Why not SwiftPM resources

- SPM resources must live under the target's source path, or the target
  has to be repointed via `path:`. Today `path: "Sources/SwiflowCLI"` —
  adopting resources means either symlinking `examples/` into
  `Sources/SwiflowCLI/`, widening the target path, or splitting a
  resource bundle target. All add structure for no win over codegen.
- `Bundle.module` works in tests but distributing a flat binary becomes
  fiddlier than the current `swift build -c release --product swiflow`.
- The freshness-check pattern is already in the codebase; introducing a
  second mechanism (resources) for the same kind of asset costs
  consistency.

### Why not runtime filesystem lookup

Not viable: end users install a single binary and don't have the repo
tree to read from.

## Source-of-Truth Conventions

Every directory directly under `examples/` is a template. The template
name is the directory name (`HelloWorld`, `MiniRouter`, `RouterDemo`).

A file under `examples/<name>/` ships as part of the template unless it
matches the **blacklist**:

- `.build/` (any depth)
- `.DS_Store`
- `Package.resolved`
- `swiflow-driver.js`
- `swiflow-sw.js`
- `swiflow-manifest.json`

The JS driver and service worker are blacklisted because they keep
coming from `EmbeddedDriver` (which is itself codegen'd from
`js-driver/`). This avoids two paths for the same canonical bytes.
`TemplatesTests.exampleDriverMatchesCanonical` and
`exampleServiceWorkerMatchesCanonical` are preserved — they continue to
assert that the example's checked-in JS copies match `js-driver/`.

### Token Normalization (Codegen Time)

For each file kept after blacklisting:

1. **Project name:** every literal occurrence of the example's directory
   name in the file's text contents is replaced with `{{NAME}}`. This is
   a global substring replace per file; the example directory name acts
   as the search key. (e.g. `name: "HelloWorld"` →
   `name: "{{NAME}}"`; `<title>MiniRouter</title>` →
   `<title>{{NAME}}</title>`.)
2. **Swiflow dependency:** in `Package.swift` only, the literal line
   matching `.package(path: "../..")` is replaced with the token
   `{{SWIFLOW_DEP}}`. This is a strict, single-line literal match — not
   a regex — so codegen will fail loudly if any example's `Package.swift`
   diverges from that exact form. (Asserting one canonical shape is
   intentional; it keeps the substitution dumb.)

After normalization, the file's contents are emitted into the generated
Swift file as a raw-string literal under the example's name.

### Generated File Shape

`Sources/SwiflowCLI/EmbeddedTemplates.swift`:

```swift
// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-templates.swift
//
// Source: examples/*/

enum EmbeddedTemplates {
    struct Template {
        let name: String
        /// Map of relative file path → raw (un-substituted) contents.
        let files: [String: String]
    }

    static let all: [Template] = [
        Template(name: "HelloWorld", files: [ /* … */ ]),
        Template(name: "MiniRouter", files: [ /* … */ ]),
        Template(name: "RouterDemo", files: [ /* … */ ]),
    ]

    static func lookup(_ name: String) -> Template? {
        return all.first(where: { $0.name == name })
    }

    static var availableNames: [String] {
        return all.map(\.name)
    }
}
```

`all` is an array (not a dictionary) so iteration order stays deterministic —
templates are sorted alphabetically by name at codegen time, which drives the
`--help` listing and the unknown-template error message. Each `Template`
carries its own `name`, so `lookup` and `availableNames` are one-liners.

## CLI Surface

```
swiflow init <name>
    [--path <parent>]
    [--template <template>]        NEW. Default: HelloWorld
    [--swiflow-source <path>]
    [--swiflow-version <version>]
```

- `--template` accepts the directory name of any example. Match is
  case-sensitive (matches the directory name on disk).
- Unknown template name → `ValidationError` with message
  `unknown template "Foo" — available: HelloWorld, MiniRouter, RouterDemo`
  (list generated from `EmbeddedTemplates.byName`).
- `swiflow init --help` lists the available templates inline (composed
  from `byName`) so users discover them without a separate flag.

No `--list-templates`. `--help` covers it.

## Templates.swift After

The file collapses to:

- `SwiflowDep` enum (unchanged; resolves to a `.package(...)` fragment).
- A small `render(_:name:swiflowDep:)` helper that applies the two
  token substitutions to any file's raw contents. Used by
  `ProjectWriter`.

Public-surface change: `Templates.packageSwift(name:swiflowDep:)`,
`Templates.appSwift(name:)`, etc. are removed. Their callers
(`ProjectWriter`) move to the generic `render` helper.

```swift
enum Templates {
    /// Applies the two scaffold-time substitutions to a raw template
    /// file's contents. Used for every file in a Template.
    static func render(_ raw: String, name: String, swiflowDep: SwiflowDep) -> String {
        return raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_DEP}}", with: swiflowDep.packageFragment)
    }
}
```

`SwiflowDep.packageFragment` already returns the exact
`.package(path: "...")` / `.package(url: "...", exact: "...")` fragment —
no change.

## ProjectWriter Changes

`ProjectWriter.writeProject` today hardcodes seven file writes. It
becomes a walk over the chosen template's `files` map:

```swift
static func writeProject(
    name: String,
    template: EmbeddedTemplates.Template,
    into parent: URL,
    swiflowDep: SwiflowDep,
    jsDriverSource: String,
    jsServiceWorkerSource: String,
    _testFailDuringWrites: Bool = false
) throws {
    // … existing precondition checks (parent exists, target doesn't) …

    // Create the target directory.
    let project = parent.appendingPathComponent(name, isDirectory: false)
    try fm.createDirectory(at: project, withIntermediateDirectories: true)

    do {
        // Walk the template's file map. Intermediate directories are
        // created on demand so nested paths like Sources/App/Pages/Foo.swift
        // (MiniRouter) work without per-template scaffolding logic.
        for (relativePath, raw) in template.files {
            let dest = project.appendingPathComponent(relativePath)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let rendered = Templates.render(raw, name: name, swiflowDep: swiflowDep)
            try rendered.write(to: dest, atomically: true, encoding: .utf8)
        }

        // JS driver + service worker come from EmbeddedDriver, not the
        // template. This keeps the canonical js-driver/ source as the
        // single source of truth for driver bytes.
        try jsDriverSource.write(
            to: project.appendingPathComponent("swiflow-driver.js"),
            atomically: true, encoding: .utf8
        )
        try jsServiceWorkerSource.write(
            to: project.appendingPathComponent("swiflow-sw.js"),
            atomically: true, encoding: .utf8
        )
    } catch {
        try? fm.removeItem(at: project)
        throw error
    }
}
```

Iteration order over a `[String: String]` is undefined. For scaffold
correctness it doesn't matter — `createDirectory(...withIntermediateDirectories: true)`
is idempotent. Test output (golden trees) compares filesystem state,
not write order.

`InitCommand` resolves `--template` to a `Template` (via
`EmbeddedTemplates.byName`) before calling `writeProject`. Unknown
template name surfaces as a `ValidationError` before any I/O.

## Tests

### New: `TemplateEmbedderTests`

Same shape as `DriverEmbedderTests`. Re-runs the codegen logic
**in-process** (importing the same helper the script uses — see below),
diffs against the on-disk `EmbeddedTemplates.swift`, and fails with the
regen command in the message if they diverge.

To make this work without duplicating logic between the script and the
test, the codegen logic moves into a pure helper inside `SwiflowCLI`:

```swift
// Sources/SwiflowCLI/TemplateEmbedder.swift
enum TemplateEmbedder {
    /// Walks `examplesRoot` and produces the Swift source for
    /// EmbeddedTemplates.swift. Pure: no filesystem writes.
    static func swiftSource(examplesRoot: URL) throws -> String { … }

    /// Per-example token normalization. Exposed for tests.
    static func normalize(_ raw: String, exampleName: String, isPackageSwift: Bool) -> String { … }
}
```

`scripts/embed-templates.swift` is then a thin shell — same role as
`scripts/embed-driver.swift`. It re-implements the normalization inline
(can't import `SwiflowCLI` standalone), and the freshness test catches
any drift between the script and `TemplateEmbedder`.

### Replaced: per-file byte-equality tests in `TemplatesTests`

Today's tests assert each raw string equals a specific file in
`examples/HelloWorld/`. After the refactor those assertions move to a
single **round-trip** test:

```swift
@Test("HelloWorld template scaffolds byte-identical to examples/HelloWorld/")
func helloWorldRoundTrip() throws {
    let template = EmbeddedTemplates.helloWorld
    for (relativePath, raw) in template.files {
        let rendered = Templates.render(
            raw, name: "HelloWorld", swiflowDep: .path("../..")
        )
        let onDisk = try String(
            contentsOf: helloWorldDir.appendingPathComponent(relativePath),
            encoding: .utf8
        )
        #expect(rendered == onDisk, "drift in \(relativePath)")
    }
}
```

Analogous round-trips for `MiniRouter` and `RouterDemo`.

The blacklist gets its own assertion: every non-blacklisted file under
`examples/<name>/` appears in the corresponding `Template.files` map
(catches "added a file to MiniRouter but forgot to regen").

### Preserved

- `TemplatesTests.exampleDriverMatchesCanonical` and
  `exampleServiceWorkerMatchesCanonical` — still assert
  `examples/HelloWorld/swiflow-driver.js` byte-equals
  `js-driver/swiflow-driver.js`. Unchanged.

### `InitCommandTests`

Parametric case: `swiflow init demo --template MiniRouter` produces a
project with `SwiflowRouter` in its `Package.swift` target deps.
Unknown-template case: `swiflow init demo --template Bogus` exits with
the validation error and lists available templates.

## Example Readiness

`MiniRouter` ships no `README.md` or `.gitignore`; `RouterDemo` ships no
`README.md`. Today that's fine because they aren't scaffolded; after this
change a `swiflow init demo --template MiniRouter` would produce a
scaffold without those files.

Fix: add minimal `README.md` and `.gitignore` to `examples/MiniRouter/`
and `README.md` to `examples/RouterDemo/` **in the same change**. They
mirror HelloWorld's structure but reflect the example's content (Router
intro instead of Counter intro). This is example-source-of-truth work,
not template work — adding files to the examples *is* how you add files
to the template.

## File Layout After

```
scripts/
  embed-driver.swift           (unchanged)
  embed-templates.swift        NEW
Sources/SwiflowCLI/
  Commands/
    InitCommand.swift          changed: --template flag, lookup
  Project/
    ProjectWriter.swift        changed: walks template.files
  Templates/
    Templates.swift            changed: thinned to SwiflowDep + render()
  TemplateEmbedder.swift       NEW (pure codegen helper)
  EmbeddedDriver.swift         (unchanged; still generated)
  EmbeddedTemplates.swift      NEW (generated by embed-templates.swift)
Tests/SwiflowCLITests/
  TemplatesTests.swift         changed: round-trip per template + blacklist coverage
  TemplateEmbedderTests.swift  NEW (freshness test for EmbeddedTemplates.swift)
  InitCommandTests.swift       changed: --template parametric cases
examples/
  HelloWorld/                  (unchanged)
  MiniRouter/
    README.md                  NEW
    .gitignore                 NEW
  RouterDemo/
    README.md                  NEW
```

## Build / Workflow

Regen flow for a contributor editing an example:

```bash
# Edit examples/HelloWorld/Sources/App/App.swift (or any template file).
$ swift scripts/embed-templates.swift
wrote Sources/SwiflowCLI/EmbeddedTemplates.swift (xxxx bytes)
$ swift test --filter SwiflowCLITests
```

CI runs `TemplateEmbedderTests` like it runs `DriverEmbedderTests`;
forgetting to rerun the script surfaces as a clear "regenerate by
running …" failure.

## Risks / Trade-offs

- **Extra codegen step.** Already accepted for `EmbeddedDriver`. Same
  ergonomics, same failure mode.
- **Token collision.** Replacing every occurrence of an example's name
  with `{{NAME}}` means an example must not contain its own name as
  unrelated content (e.g. a doc string that mentions "HelloWorld" in
  prose). HelloWorld currently doesn't. If a future example needs the
  literal name preserved, the convention is "rename the prose
  reference" — keep the substitution dumb.
- **Strict `.package(path: "../..")` match.** If a future example wants
  a different relative path to the repo root (e.g. a deeper nesting),
  the codegen rejects it. Forcing one canonical shape is the price of
  literal-string substitution; the alternative (regex on `.package(path:`)
  is more code for no concrete benefit today.
- **Iteration order in `template.files`.** Undefined for `[String: String]`.
  `ProjectWriter` doesn't depend on order, but tests should compare
  filesystem state (sets of files), not iteration output.
