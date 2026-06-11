# Swiflow Phase 2b — CLI (`swiflow init` + `swiflow build`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-crafted `examples/HelloWorld/` workflow with a single binary, `swiflow`, that scaffolds a working Swift-WASM project (`swiflow init <name>`) and builds it to a browser-loadable bundle (`swiflow build`) — turning the README's "follow these 12 manual steps" into "run these two commands."

**Architecture:** Add a third SPM target — `SwiflowCLI` (executable, name `swiflow`) — alongside the existing `Swiflow` (pure core) and `SwiflowWeb` (WASM-only renderer). The CLI depends on `swift-argument-parser` and contains no JavaScriptKit imports (it runs on macOS/Linux, never in WASM). Init templates ship as Swift `String` constants; the JS driver ships as an auto-generated `EmbeddedDriver.swift` constant produced from the single source of truth at `js-driver/swiflow-driver.js`. `swiflow build` shells out to `swift package js --use-cdn --product App -c release` after probing for an installed WASM SDK and (on macOS) setting `TOOLCHAINS` to a Swift.org toolchain that has a WASM-aware clang.

**Tech Stack:** Swift 6.0+, `swift-argument-parser` 1.3+, Foundation's `Process`/`FileManager`. The CLI does NOT require the WASM SDK to build — only to *invoke* `swiflow build` against a generated project. Tests that need the WASM SDK end-to-end are gated and skipped when absent.

**Reference spec:** `~/.claude/plans/i-want-you-to-dynamic-pancake.md` §§ 5.1, 5.3, 5.5. Phase 2c (the `swiflow dev` server + file watcher + WebSocket reload) is explicitly out of scope and gets its own plan.

**Repo state at start:** Phase 2a complete. 123 tests passing. `main` is at `ebc4d3a`. The verified-working `examples/HelloWorld/` will become the baseline that `swiflow init` must reproduce byte-for-byte.

---

## Spec deviations (read before starting)

These intentional departures from § 5.1's project layout reflect what was learned during Phase 2a:

1. **No `public/` subdirectory.** The spec shows `<name>/public/{index.html, swiflow-driver.js, app.wasm}`. We put `index.html` and `swiflow-driver.js` at the project root because JavaScriptKit 0.53's PackageToJS plugin emits its bootstrap at `.build/plugins/PackageToJS/outputs/Package/index.js`, which `index.html` imports via a relative path. Moving `index.html` into `public/` would require either copying the PackageToJS output into `public/` on every build (extra step, easy to get stale) or rewriting the import path (fragile). The reality-aligned layout matches the verified Phase 2a example.

2. **No `swiflow build` artifact copy step.** The spec says `build` "copies the produced `.wasm` to `public/app.wasm`." With PackageToJS we don't need to: the plugin emits everything ready-to-serve under `.build/plugins/PackageToJS/outputs/Package/`. `swiflow build` is a thin wrapper around `swift package ... js` that picks the right SDK + toolchain and forwards `--use-cdn`.

3. **No `--production` flag in Phase 2b.** Per spec § 10 and Phase 4 sketch, `wasm-opt`, gzip, and DWARF stripping are Phase 4. `swiflow build` always uses `-c release` for now (no compile-time DCE flag exposure). A future Phase 4 task adds the flag once we have the optimizers wired up — adding it now as a no-op stub would be YAGNI.

4. **No dev-server in Phase 2b.** The spec § 5.1 lists three subcommands (init, build, dev). Phase 2b ships init + build only. `swiflow dev` (swift-nio HTTP server, FSEvents/inotify file watcher, WebSocket reload) lands in Phase 2c.

5. **Init template's Swiflow dependency defaults to a local path.** Until Swiflow is published (Phase 4: homebrew + a tagged release), the only way a generated project can resolve `import SwiflowWeb` is via a local-path dep back to the swiflow checkout. The template's `Package.swift` uses `.package(path: ...)` with the path supplied by `--swiflow-source` (defaulting to `../..`, matching how `examples/HelloWorld/` is wired today). A future Phase 4 task flips the default to `.package(url: "https://github.com/.../swiflow.git", from: "0.1.0")`.

---

## File map (Phase 2b deliverables)

| Path | Responsibility |
|---|---|
| `Package.swift` | Add `swift-argument-parser` dep. Add `SwiflowCLI` executable target (product name `swiflow`). Add `SwiflowCLITests` test target. |
| `Sources/SwiflowCLI/main.swift` | `@main` `Swiflow` `AsyncParsableCommand` with subcommands `init` + `build`. |
| `Sources/SwiflowCLI/Commands/InitCommand.swift` | `swiflow init <name> [--swiflow-source <path>]` — creates project tree from templates + embedded driver. |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | `swiflow build [--swift-sdk <id>] [--path <project-dir>]` — probes SDK, sets TOOLCHAINS on macOS, runs `swift package ... js --use-cdn --product App -c release`. |
| `Sources/SwiflowCLI/Templates/Templates.swift` | Plain-Swift namespaced `enum Templates` with one static property per file (Package.swift, App.swift, index.html, .gitignore, README.md). |
| `Sources/SwiflowCLI/EmbeddedDriver.swift` | **Generated.** `enum EmbeddedDriver { static let javascriptSource: String = ... }`. Source of truth: `js-driver/swiflow-driver.js`. |
| `Sources/SwiflowCLI/DriverEmbedder.swift` | Pure function `DriverEmbedder.swiftSource(forJSSource: String) -> String` — formats the embedded constant. Used by both the codegen script and the freshness test. |
| `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift` | `WasmSDKProbe.list()` + `WasmSDKProbe.pickDefault()` — wraps `swift sdk list`, returns a list of installed WASM SDK IDs. |
| `Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift` | `MacToolchainProbe.swiftLatestBundleIdentifier()` — reads `~/Library/Developer/Toolchains/swift-latest.xctoolchain/Info.plist` and returns the `CFBundleIdentifier`. Returns nil on Linux. |
| `Sources/SwiflowCLI/Process/ProcessRunner.swift` | Thin testable wrapper over `Foundation.Process` — streams stdout/stderr through to the parent's standard streams, returns exit code. Protocol-based so BuildCommand tests can stub it. |
| `scripts/embed-driver.swift` | Swift script (`swift run --package-path scripts ...` or shebang-style) that reads `js-driver/swiflow-driver.js` and writes `Sources/SwiflowCLI/EmbeddedDriver.swift`. |
| `Tests/SwiflowCLITests/DriverEmbedderTests.swift` | Asserts (a) `DriverEmbedder.swiftSource(...)` round-trips one obvious case, (b) `EmbeddedDriver.javascriptSource` equals the content of `js-driver/swiflow-driver.js` (freshness check). |
| `Tests/SwiflowCLITests/TemplatesTests.swift` | Asserts the generated `Package.swift` template, when rendered with `swiflowSource: "../.."` and `name: "HelloWorld"`, equals the contents of `examples/HelloWorld/Package.swift`. Same for `App.swift`, `index.html`, `.gitignore`. This is the load-bearing guarantee that "init regenerates the verified example." |
| `Tests/SwiflowCLITests/InitCommandTests.swift` | Runs InitCommand against a temp directory; asserts file tree exists with the right contents. |
| `Tests/SwiflowCLITests/WasmSDKProbeTests.swift` | Asserts the parser correctly extracts SDK IDs from a captured `swift sdk list` output fixture. |
| `Tests/SwiflowCLITests/BuildCommandTests.swift` | Two test classes: (1) argv-construction tests with a stub runner — assert the right `swift package ... js` invocation gets built; (2) end-to-end integration test gated on WASM SDK presence — invokes `swiflow init` + `swiflow build` against a temp dir, asserts the WASM artifact exists. |
| `examples/HelloWorld/` | Regenerated via `swiflow init HelloWorld --swiflow-source ../..` in T11; should be byte-identical to the current committed version (any diff is a template bug, not an intentional change). |
| `README.md` | Status update: "Phase 2b complete: `swiflow init` + `swiflow build` ship; dev server is Phase 2c." Updated quick-start. |
| `CONTRIBUTING.md` | Add a note that modifying `js-driver/swiflow-driver.js` requires re-running `swift run --package-path scripts embed-driver` (or just `swift test` — the freshness test will tell you). |
| `.github/workflows/ci.yml` | Add `swift build --product swiflow` to CI so the CLI compiles on both runners. |
| `.gitignore` | No change. |

---

## Architectural decisions

These derive from the spec and the Phase 2a verified reality, locked here so they don't shift mid-implementation.

1. **CLI is a plain executable target, not a SwiftPM plugin.** SwiftPM plugins run in a sandbox, can't easily spawn `Process`, and bind their lifecycle to a host package. A standalone executable installed as `swift run -c release swiflow ...` (and, post-Phase-4, as a Homebrew formula) is what end-users will reach for.

2. **`ArgumentParser`'s `AsyncParsableCommand`.** All commands use `async throws run()`. We don't need async per se for Phase 2b (Process is synchronous), but `AsyncParsableCommand` plays nicer with Swift 6 strict concurrency and is the path forward when Phase 2c's dev server needs `await` on file-watcher events.

3. **Templates are Swift String constants, not files in `Resources/`.** SwiftPM resources require process-relative bundle access (`Bundle.module`), which adds friction in tests and breaks if the binary is moved. Inline `String` constants are zero-friction, testable, and trivially substitutable.

4. **JS driver is embedded via codegen, not via `Resources/`.** Same reason as templates, plus: the codegen step is also our freshness guarantee — `DriverEmbedderTests` re-reads `js-driver/swiflow-driver.js` on every `swift test` and asserts the embedded copy is current. Forgetting to regenerate fails CI.

5. **`Templates.render(_:variables:)` does dumb `{{KEY}}` substitution.** Mustache-style templating is overkill. Phase 2b has two variables: `{{NAME}}` and `{{SWIFLOW_SOURCE}}`. A `replacingOccurrences(of:with:)` loop is plenty.

6. **`ProcessRunner` is a protocol.** `BuildCommand` takes a `ProcessRunner` (default `SystemProcessRunner`). Tests inject a `StubProcessRunner` to assert the exact argv passed to `swift package ... js` without actually running it. The end-to-end integration test uses the real `SystemProcessRunner`.

7. **WASM SDK probe is non-fatal.** If `swift sdk list` returns nothing wasm-flavored, `swiflow build` prints a helpful message ("install with: `swift sdk install <URL>`; see https://swift.org/install") and exits 1. This is the first thing a new contributor will hit; a clear error matters more than fancy auto-install.

8. **macOS `TOOLCHAINS` is auto-set when needed, never overwritten.** If the user already has `TOOLCHAINS` set, we leave it alone. If not, we read the swift-latest bundle ID and pass it to the child process via the environment dict (NOT `setenv` — we don't want to mutate the parent's env). Linux skips this step entirely.

9. **Init does NOT run `swift package resolve` automatically.** The spec § 17 calls for `Package.resolved` to be checked in by `init`. But running `resolve` requires network access (to fetch JavaScriptKit + swift-syntax), which makes `init` slow and fragile (no network → init fails). Phase 2b's `init` writes the source tree only; the first `swiflow build` invocation will generate `Package.resolved` as a side effect of SwiftPM's normal resolve step. We document that the user should commit it after the first build. Phase 4 may revisit this if a "fully sealed dependencies" story becomes a real-world ask.

10. **All CLI binary lookups are PATH-relative.** `swiflow build` calls `swift package ...` via `Process` with `executableURL` set to the result of `which swift` (or `/usr/bin/env swift` fallback). We do NOT try to auto-detect the Swift install path; if `swift` isn't on PATH, error out clearly.

---

## Tasks

Twelve tasks, ordered by dependency. Each is one commit. Each follows the TDD discipline of Phase 1+2a: failing test → run-red → minimal implementation → run-green → commit.

---

### Task 1: Add `SwiflowCLI` executable target + `swift-argument-parser` dependency

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowCLI/main.swift`
- Create: `Tests/SwiflowCLITests/PackageSmokeTest.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/PackageSmokeTest.swift`:

```swift
// Tests/SwiflowCLITests/PackageSmokeTest.swift
import Testing
@testable import SwiflowCLI

@Suite("Package smoke test")
struct PackageSmokeTest {
    @Test("SwiflowCLI module can be imported and contains the Swiflow root command")
    func canImport() {
        // The root command's name is the CLI binary name.
        #expect(Swiflow.configuration.commandName == "swiflow")
    }
}
```

- [ ] **Step 2: Run test to verify it fails (no SwiflowCLI module yet)**

Run: `swift test --filter PackageSmokeTest`
Expected: FAIL — `no such module 'SwiflowCLI'`.

- [ ] **Step 3: Add dependency + target to Package.swift**

Edit `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
        .executable(name: "swiflow", targets: ["SwiflowCLI"]),
    ],
    dependencies: [
        // Pinned to minor range. JavaScriptKit's 0.x cadence has shipped
        // breaking changes across minor bumps (e.g. JSValue.function was
        // deprecated 0.21 → 0.53). Bumping the minor requires intentional
        // review of the renderer + dispatcher bridge.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
        // ArgumentParser drives the swiflow CLI. Use a major-bump range —
        // 1.x has been API-stable since 2021.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "Swiflow",
            path: "Sources/Swiflow",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SwiflowCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwiflowCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowCLITests",
            dependencies: ["SwiflowCLI"],
            path: "Tests/SwiflowCLITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

- [ ] **Step 4: Create the CLI entry point skeleton**

Create `Sources/SwiflowCLI/main.swift`:

```swift
// Sources/SwiflowCLI/main.swift
//
// Entry point for the `swiflow` CLI binary. The `Swiflow` async root
// command holds the subcommand table; each subcommand lives in its own
// file under Commands/.

import ArgumentParser

@main
public struct Swiflow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiflow",
        abstract: "Swift-WASM developer ecosystem — scaffold and build Swiflow projects.",
        version: "0.1.0",
        subcommands: [],
        defaultSubcommand: nil
    )

    public init() {}
}
```

(Subcommands are registered in T3; for now the smoke test only checks the module loads and the command name is set.)

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter PackageSmokeTest`
Expected: PASS.

- [ ] **Step 6: Run the full test suite to make sure nothing else broke**

Run: `swift test`
Expected: All 123 Phase 2a tests + the 1 new test pass.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/SwiflowCLI Tests/SwiflowCLITests
git commit -m "$(cat <<'EOF'
feat: add SwiflowCLI executable target with ArgumentParser dep

Skeleton 'swiflow' binary with no subcommands yet — T3 wires the subcommand
table once init and build exist. ArgumentParser pinned to a major range
(1.3+) since 1.x has been API-stable since 2021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Driver embedding — `DriverEmbedder` + generated `EmbeddedDriver.swift` + freshness test

**Files:**
- Create: `Sources/SwiflowCLI/DriverEmbedder.swift`
- Create: `Sources/SwiflowCLI/EmbeddedDriver.swift` (will be overwritten by the codegen script)
- Create: `scripts/embed-driver.swift`
- Create: `Tests/SwiflowCLITests/DriverEmbedderTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/DriverEmbedderTests.swift`:

```swift
// Tests/SwiflowCLITests/DriverEmbedderTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Driver embedding")
struct DriverEmbedderTests {

    @Test("DriverEmbedder.swiftSource wraps the JS source in a Swift String constant")
    func wrapsJSAsSwiftConstant() {
        let js = "console.log('hello');"
        let generated = DriverEmbedder.swiftSource(forJSSource: js)
        #expect(generated.contains("// GENERATED FILE — do not edit."))
        #expect(generated.contains("enum EmbeddedDriver"))
        #expect(generated.contains("static let javascriptSource: String"))
        // The JS source must appear verbatim somewhere in the output.
        #expect(generated.contains(js))
    }

    @Test("EmbeddedDriver.javascriptSource matches js-driver/swiflow-driver.js verbatim")
    func embeddedDriverIsFresh() throws {
        // Resolve js-driver/swiflow-driver.js relative to this test file so
        // the test works from any CWD.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let driverURL = repoRoot.appendingPathComponent("js-driver/swiflow-driver.js")

        let onDiskJS = try String(contentsOf: driverURL, encoding: .utf8)
        #expect(EmbeddedDriver.javascriptSource == onDiskJS, """
            EmbeddedDriver is stale. Regenerate by running:
                swift scripts/embed-driver.swift
            from the repo root, then commit Sources/SwiflowCLI/EmbeddedDriver.swift.
            """)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DriverEmbedderTests`
Expected: FAIL — `DriverEmbedder` and `EmbeddedDriver` don't exist yet.

- [ ] **Step 3: Implement `DriverEmbedder`**

Create `Sources/SwiflowCLI/DriverEmbedder.swift`:

```swift
// Sources/SwiflowCLI/DriverEmbedder.swift
//
// Pure formatting function used by both the codegen script
// (scripts/embed-driver.swift) and the freshness test
// (Tests/SwiflowCLITests/DriverEmbedderTests.swift). Keeping it here means
// the codegen logic is itself under test.

import Foundation

public enum DriverEmbedder {
    /// Produces the Swift source for `EmbeddedDriver.swift` that wraps the
    /// given JS driver source as a raw string literal.
    ///
    /// We use Swift's extended-delimiter raw string (`#"""..."""#`) so that
    /// any quotes, backslashes, or string-interpolation markers in the JS
    /// source pass through untouched. The JS driver currently contains
    /// neither `"""#` nor `#"""`, but defensively bumping to `##"""..."""##`
    /// would be wise if a future JS edit ever introduced one.
    public static func swiftSource(forJSSource js: String) -> String {
        // The trailing newline is preserved so byte-for-byte equality holds
        // against the on-disk file.
        return """
        // GENERATED FILE — do not edit.
        //
        // Regenerate by running, from the repo root:
        //     swift scripts/embed-driver.swift
        //
        // Source: js-driver/swiflow-driver.js

        enum EmbeddedDriver {
            static let javascriptSource: String = #\"\"\"
        \(js)\"\"\"#
        }
        """ + "\n"
    }
}
```

- [ ] **Step 4: Generate `EmbeddedDriver.swift` by hand for this commit**

Create `Sources/SwiflowCLI/EmbeddedDriver.swift` by running the embedder against the current `js-driver/swiflow-driver.js`. The easiest path: write a one-off Swift script (see Step 5), but the very first time you'll commit the file by hand using your editor. Alternatively, write the codegen script first and run it.

Take this path: write the codegen script (Step 5), run it, commit the generated output along with everything else.

- [ ] **Step 5: Write the codegen script**

Create `scripts/embed-driver.swift`:

```swift
#!/usr/bin/env swift
// scripts/embed-driver.swift
//
// One-shot codegen script. Run from the repo root:
//
//     swift scripts/embed-driver.swift
//
// Reads js-driver/swiflow-driver.js and writes
// Sources/SwiflowCLI/EmbeddedDriver.swift using DriverEmbedder.swiftSource.
//
// Why a script and not a SwiftPM plugin: SwiftPM plugins can't write to
// arbitrary paths in the package source tree (they're sandboxed to a
// per-target build dir). For codegen that we want under git, a thin
// scripted approach is simpler.

import Foundation

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

let jsPath = cwd.appendingPathComponent("js-driver/swiflow-driver.js")
let outPath = cwd.appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

guard fm.fileExists(atPath: jsPath.path) else {
    FileHandle.standardError.write(Data("error: \(jsPath.path) not found. Run from repo root.\n".utf8))
    exit(1)
}

let js: String
do {
    js = try String(contentsOf: jsPath, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to read \(jsPath.path): \(error)\n".utf8))
    exit(1)
}

// We re-implement DriverEmbedder.swiftSource inline because this script
// runs standalone (no SPM context, can't `import SwiflowCLI`). The format
// must stay in sync with DriverEmbedder; the freshness test will catch
// any drift between this script and DriverEmbedder.swiftSource.
let output = """
// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-driver.swift
//
// Source: js-driver/swiflow-driver.js

enum EmbeddedDriver {
    static let javascriptSource: String = #\"\"\"
\(js)\"\"\"#
}
""" + "\n"

do {
    try output.write(to: outPath, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outPath.path): \(error)\n".utf8))
    exit(1)
}

print("wrote \(outPath.path) (\(output.utf8.count) bytes)")
```

Make it executable:

```bash
chmod +x scripts/embed-driver.swift
```

- [ ] **Step 6: Run the codegen script**

```bash
cd .
swift scripts/embed-driver.swift
```

Expected output: `wrote ./Sources/SwiflowCLI/EmbeddedDriver.swift (NNNN bytes)`.

Verify the generated file exists and starts with `// GENERATED FILE`:

```bash
head -5 Sources/SwiflowCLI/EmbeddedDriver.swift
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter DriverEmbedderTests`
Expected: PASS — both tests green.

- [ ] **Step 8: Run the full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI/DriverEmbedder.swift Sources/SwiflowCLI/EmbeddedDriver.swift scripts/embed-driver.swift Tests/SwiflowCLITests/DriverEmbedderTests.swift
git commit -m "$(cat <<'EOF'
feat: embed JS driver as a Swift constant generated from js-driver/swiflow-driver.js

The freshness test re-reads the on-disk JS file on every `swift test` and
asserts the embedded copy matches, so forgetting to regenerate fails CI.
Regeneration: `swift scripts/embed-driver.swift` from the repo root.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: ArgumentParser command tree — wire init + build subcommands (shells)

**Files:**
- Create: `Sources/SwiflowCLI/Commands/InitCommand.swift`
- Create: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Modify: `Sources/SwiflowCLI/main.swift`
- Create: `Tests/SwiflowCLITests/CommandTreeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/CommandTreeTests.swift`:

```swift
// Tests/SwiflowCLITests/CommandTreeTests.swift
import Testing
@testable import SwiflowCLI

@Suite("Command tree")
struct CommandTreeTests {
    @Test("Swiflow root command exposes init and build subcommands")
    func subcommandsRegistered() {
        let names = Swiflow.configuration.subcommands.map { $0._commandName }
        #expect(names.contains("init"))
        #expect(names.contains("build"))
    }

    @Test("InitCommand parses a name argument")
    func initParses() throws {
        let cmd = try InitCommand.parse(["my-app"])
        #expect(cmd.name == "my-app")
    }

    @Test("InitCommand parses --swiflow-source")
    func initParsesSwiflowSource() throws {
        let cmd = try InitCommand.parse(["demo", "--swiflow-source", "/tmp/swiflow"])
        #expect(cmd.swiflowSource == "/tmp/swiflow")
    }

    @Test("BuildCommand parses --path and --swift-sdk")
    func buildParses() throws {
        let cmd = try BuildCommand.parse(["--path", "./demo", "--swift-sdk", "swift-6.3-RELEASE_wasm"])
        #expect(cmd.path == "./demo")
        #expect(cmd.swiftSDK == "swift-6.3-RELEASE_wasm")
    }
}
```

Note: `_commandName` is ArgumentParser's internal accessor for the configured `commandName`. If it's not available, use a small helper:

```swift
extension ParsableCommand {
    static var _commandName: String { configuration.commandName ?? "\(self)" }
}
```

Add this in `Tests/SwiflowCLITests/CommandTreeTests.swift` above the suite if needed.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CommandTreeTests`
Expected: FAIL — `InitCommand` and `BuildCommand` don't exist.

- [ ] **Step 3: Implement `InitCommand` shell (action body left for T5)**

Create `Sources/SwiflowCLI/Commands/InitCommand.swift`:

```swift
// Sources/SwiflowCLI/Commands/InitCommand.swift
//
// `swiflow init <name>` — scaffolds a new Swiflow project from the embedded
// templates + driver. The action body lives in T5; this task only locks
// the argument shape.

import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new Swiflow project."
    )

    @Argument(help: "The project name. A directory of this name will be created in the current working directory.")
    var name: String

    @Option(
        name: .customLong("swiflow-source"),
        help: ArgumentHelp(
            "Path or URL the generated project should use for its Swiflow dependency.",
            discussion: """
                Defaults to the relative path '../..', which lets generated projects \
                placed inside this repo's examples/ directory resolve their dependency \
                back to the parent checkout. After Phase 4 publishes Swiflow, this \
                default will flip to the official git URL.
                """
        )
    )
    var swiflowSource: String = "../.."

    func run() async throws {
        // Filled in by T5.
        throw ValidationError("InitCommand.run() not yet implemented (T5).")
    }
}
```

- [ ] **Step 4: Implement `BuildCommand` shell (action body left for T8)**

Create `Sources/SwiflowCLI/Commands/BuildCommand.swift`:

```swift
// Sources/SwiflowCLI/Commands/BuildCommand.swift
//
// `swiflow build` — compiles a Swiflow project to a browser-loadable
// PackageToJS bundle. The action body lives in T8; this task only locks
// the argument shape.

import ArgumentParser
import Foundation

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a Swiflow project to a browser-loadable WASM bundle."
    )

    @Option(
        name: .customLong("path"),
        help: "Path to the Swiflow project directory. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("swift-sdk"),
        help: ArgumentHelp(
            "Override the Swift WASM SDK identifier.",
            discussion: """
                When unset, swiflow runs `swift sdk list` and picks the first installed \
                WASM SDK. Use this flag to pin to a specific SDK across machines.
                """
        )
    )
    var swiftSDK: String?

    func run() async throws {
        // Filled in by T8.
        throw ValidationError("BuildCommand.run() not yet implemented (T8).")
    }
}
```

- [ ] **Step 5: Wire the subcommands into the root**

Edit `Sources/SwiflowCLI/main.swift` — replace `subcommands: []` with the new commands:

```swift
// Sources/SwiflowCLI/main.swift

import ArgumentParser

@main
public struct Swiflow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiflow",
        abstract: "Swift-WASM developer ecosystem — scaffold and build Swiflow projects.",
        version: "0.1.0",
        subcommands: [InitCommand.self, BuildCommand.self],
        defaultSubcommand: nil
    )

    public init() {}
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter CommandTreeTests`
Expected: PASS — all 4 subtests green.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 8: Smoke-test the binary**

```bash
swift run swiflow --help
```

Expected: Help output listing `init` and `build` subcommands.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI Tests/SwiflowCLITests/CommandTreeTests.swift
git commit -m "$(cat <<'EOF'
feat: wire init and build subcommands into the swiflow CLI

Argument shapes only; action bodies land in T5 and T8. Locks the public
flag surface so subsequent tests have stable types to assert against.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Init templates as Swift String constants — must regenerate the verified example

**Files:**
- Create: `Sources/SwiflowCLI/Templates/Templates.swift`
- Create: `Tests/SwiflowCLITests/TemplatesTests.swift`

This is the load-bearing task for "init produces a working project." The templates must, when rendered with `name: "HelloWorld"` and `swiflowSource: "../.."`, equal the bytes of the verified `examples/HelloWorld/` files.

- [ ] **Step 1: Read the existing example to capture the exact bytes**

The test file will embed these as expected strings. To keep them maintainable, the test resolves them from disk via `#filePath` (same pattern as the driver freshness test).

Run these to confirm the current file contents:

```bash
cat examples/HelloWorld/Package.swift
cat examples/HelloWorld/Sources/App/App.swift
cat examples/HelloWorld/index.html
cat examples/HelloWorld/.gitignore
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/SwiflowCLITests/TemplatesTests.swift`:

```swift
// Tests/SwiflowCLITests/TemplatesTests.swift
//
// These tests are the load-bearing guarantee that `swiflow init` will
// produce a project byte-identical to examples/HelloWorld/ (which Phase 2a
// proved works end-to-end). Any drift between templates and the example
// is either an intentional template improvement (then update the example)
// or a regression (then fix the template).

import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Init templates")
struct TemplatesTests {
    /// Repo root resolved relative to this test file's location.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    static func exampleFile(_ relativePath: String) throws -> String {
        let url = repoRoot
            .appendingPathComponent("examples/HelloWorld")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Package.swift renders identically to examples/HelloWorld/Package.swift")
    func packageSwiftMatchesExample() throws {
        let rendered = Templates.packageSwift(name: "HelloWorld", swiflowSource: "../..")
        let expected = try Self.exampleFile("Package.swift")
        #expect(rendered == expected)
    }

    @Test("Sources/App/App.swift renders identically to the example")
    func appSwiftMatchesExample() throws {
        let rendered = Templates.appSwift(name: "HelloWorld")
        let expected = try Self.exampleFile("Sources/App/App.swift")
        #expect(rendered == expected)
    }

    @Test("index.html renders identically to the example")
    func indexHTMLMatchesExample() throws {
        let rendered = Templates.indexHTML(name: "HelloWorld")
        let expected = try Self.exampleFile("index.html")
        #expect(rendered == expected)
    }

    @Test(".gitignore renders identically to the example")
    func gitignoreMatchesExample() throws {
        let rendered = Templates.gitignore()
        let expected = try Self.exampleFile(".gitignore")
        #expect(rendered == expected)
    }

    @Test("README is non-empty and mentions both swiflow build and the static server")
    func readmeMentionsKeyCommands() {
        let rendered = Templates.readme(name: "HelloWorld")
        #expect(rendered.contains("swiflow build"))
        #expect(rendered.contains("python3 -m http.server"))
        #expect(rendered.contains("HelloWorld"))
    }

    @Test("Variable substitution applies {{NAME}} everywhere it appears")
    func substitutesName() {
        let rendered = Templates.packageSwift(name: "MyCoolApp", swiflowSource: "../..")
        #expect(rendered.contains("\"MyCoolApp\""))
        #expect(!rendered.contains("{{NAME}}"))
    }

    @Test("Variable substitution applies {{SWIFLOW_SOURCE}}")
    func substitutesSwiflowSource() {
        let rendered = Templates.packageSwift(name: "Demo", swiflowSource: "/tmp/swiflow-checkout")
        #expect(rendered.contains("/tmp/swiflow-checkout"))
        #expect(!rendered.contains("{{SWIFLOW_SOURCE}}"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TemplatesTests`
Expected: FAIL — `Templates` doesn't exist.

- [ ] **Step 4: Implement `Templates`**

Create `Sources/SwiflowCLI/Templates/Templates.swift`. The template strings below must be byte-identical to the current `examples/HelloWorld/` contents, with `HelloWorld` → `{{NAME}}` and `../..` → `{{SWIFLOW_SOURCE}}` substitutions.

```swift
// Sources/SwiflowCLI/Templates/Templates.swift
//
// Templates that `swiflow init` writes to the new project directory.
// These are plain String constants — no SwiftPM resources — so they
// participate naturally in `swift test` and don't require Bundle access.
//
// Variable substitution is dumb `replacingOccurrences`. Phase 2b has two
// variables: {{NAME}} (project name) and {{SWIFLOW_SOURCE}} (path or URL
// the generated Package.swift uses to depend on Swiflow). If we ever need
// a third, consider promoting to a real templating helper.

import Foundation

enum Templates {

    // MARK: - Public rendering API

    static func packageSwift(name: String, swiflowSource: String) -> String {
        return rawPackageSwift
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_SOURCE}}", with: swiflowSource)
    }

    static func appSwift(name: String) -> String {
        return rawAppSwift
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    static func indexHTML(name: String) -> String {
        return rawIndexHTML
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    static func gitignore() -> String {
        return rawGitignore
    }

    static func readme(name: String) -> String {
        return rawReadme
            .replacingOccurrences(of: "{{NAME}}", with: name)
    }

    // MARK: - Raw template strings
    //
    // These are byte-identical to the current examples/HelloWorld/ files,
    // with `HelloWorld` replaced by `{{NAME}}` and `../..` by
    // `{{SWIFLOW_SOURCE}}`. The TemplatesTests assert the round-trip.

    private static let rawPackageSwift: String = """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: "{{NAME}}",
        products: [
            .executable(name: "App", targets: ["App"]),
        ],
        dependencies: [
            // Local path back to the parent Swiflow package.
            .package(path: "{{SWIFLOW_SOURCE}}"),
            // JavaScriptKit is declared as a direct dependency so SwiftPM
            // exposes the `swift package js` (PackageToJS) plugin to this
            // package. Without it, the plugin only surfaces on the parent
            // package and can't target this example's executable.
            .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
        ],
        targets: [
            .executableTarget(
                name: "App",
                dependencies: [
                    .product(name: "SwiflowWeb", package: "Swiflow"),
                ],
                path: "Sources/App"
            ),
        ]
    )

    """

    private static let rawAppSwift: String = #"""
    // examples/{{NAME}}/Sources/App/App.swift
    import SwiflowWeb

    // Mutable counter shared with the click handler. Phase 3 will replace this
    // with `@State`; for Phase 2a the spec's Hello World uses an explicit
    // `Swiflow.rerender()` call so the bridge path is exercised end-to-end.
    //
    // `@MainActor` keeps Swift 6's strict-concurrency check happy: the browser
    // runs everything on a single thread, so pinning this to MainActor reflects
    // reality and silences `#MutableGlobalVariable`.
    @MainActor
    var count = 0

    @MainActor
    func view() -> VNode {
        div(.class("container")) {
            h1("Hello, Swiflow!")
            p("Count: \(count)")
            button(
                "Increment",
                // `MainActor.assumeIsolated` is safe here: the JS driver invokes
                // every event listener synchronously on the only thread the WASM
                // runtime owns, which the Swift runtime treats as the main actor.
                // Using `Task { @MainActor in ... }` would defer the increment to
                // a later event-loop turn and break the synchronous `rerender()`
                // expectation.
                .on("click", Swiflow.handlers.register { _ in
                    MainActor.assumeIsolated {
                        count += 1
                        Swiflow.rerender()
                    }
                })
            )
        }
    }

    @main
    struct App {
        @MainActor
        static func main() {
            Swiflow.render(view, into: "#app")
        }
    }

    """#

    private static let rawIndexHTML: String = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Swiflow Hello World</title>
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; }
          .container { max-width: 480px; }
          button { padding: 0.4rem 0.9rem; font-size: 1rem; cursor: pointer; }
        </style>
      </head>
      <body>
        <div id="app"></div>

        <!-- Load the Swiflow driver BEFORE the WASM bootstrap so
             `window.swiflow` exists when App.main calls `Swiflow.render`. -->
        <script src="swiflow-driver.js"></script>

        <!--
          JavaScriptKit 0.53's PackageToJS plugin (`swift package js`) emits a
          ready-to-import ES module at .build/plugins/PackageToJS/outputs/Package/
          that handles WASI + Swift runtime initialization. Build first:

              swift package --swift-sdk swift-6.3-RELEASE_wasm js -c release

          then open index.html via a static server rooted at this directory
          (so the relative .build path resolves).
        -->
        <script type="module">
          import { init } from "./.build/plugins/PackageToJS/outputs/Package/index.js";
          await init();
        </script>
      </body>
    </html>

    """

    private static let rawGitignore: String = """
    .DS_Store

    """

    private static let rawReadme: String = """
    # {{NAME}}

    A Swiflow project — Swift-to-WebAssembly with a Vite-inspired dev loop.

    ## Build

    ```bash
    swiflow build
    ```

    This wraps `swift package js --use-cdn --product App -c release` after
    probing for an installed WASM SDK. The output lands at
    `.build/plugins/PackageToJS/outputs/Package/`.

    ## Serve

    Phase 2b doesn't ship a dev server yet (Phase 2c will). Any static HTTP
    server works:

    ```bash
    python3 -m http.server 3000
    ```

    Then open <http://localhost:3000>.

    ## What you should see

    - A heading: **Hello, Swiflow!**
    - A paragraph: **Count: 0**
    - A button: **Increment** that increments the count on each click.

    """
}
```

> **Important formatting note.** Swift multi-line string literals strip a trailing newline by default IF the closing `"""` is on its own line. The `"""` lines above include a blank line before the closing `"""` to preserve the trailing `\n` that the on-disk example files have. If a test fails on a one-byte difference, that's why — adjust the trailing whitespace until it matches.

- [ ] **Step 5: Run tests**

Run: `swift test --filter TemplatesTests`
Expected: PASS — all 7 subtests green.

If the byte-equality tests fail with trailing-newline or whitespace differences, adjust the templates' trailing whitespace until `rendered == expected` holds. The test failure messages will print both strings; diff them by eye.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/Templates Tests/SwiflowCLITests/TemplatesTests.swift
git commit -m "$(cat <<'EOF'
feat: init templates as Swift String constants

Each template, when rendered with the appropriate variables, matches the
verified-working examples/HelloWorld/ files byte-for-byte. The TemplatesTests
are the load-bearing guarantee that `swiflow init` reproduces what Phase 2a
shipped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `InitCommand` implementation — writes the project tree

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/InitCommand.swift`
- Create: `Sources/SwiflowCLI/Project/ProjectWriter.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/InitCommandTests.swift`:

```swift
// Tests/SwiflowCLITests/InitCommandTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("InitCommand")
struct InitCommandTests {
    @Test("Init creates the expected file tree")
    func createsFileTree() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "../..",
            jsDriverSource: "// fake driver\n"
        )

        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: project.path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("swiflow-driver.js").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent(".gitignore").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("README.md").path))
    }

    @Test("Init writes the embedded driver verbatim to swiflow-driver.js")
    func writesDriverVerbatim() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let driver = "// custom driver payload\nconsole.log('hi');\n"
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "../..",
            jsDriverSource: driver
        )

        let url = tmp.appendingPathComponent("Demo/swiflow-driver.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == driver)
    }

    @Test("Init refuses to overwrite an existing directory")
    func refusesOverwrite() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Pre-create the target so the writer collides.
        let collision = tmp.appendingPathComponent("Demo")
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)

        #expect(throws: ProjectWriterError.targetExists(collision)) {
            try ProjectWriter.writeProject(
                name: "Demo",
                into: tmp,
                swiflowSource: "../..",
                jsDriverSource: "// driver\n"
            )
        }
    }

    @Test("Init applies the swiflow-source argument to the generated Package.swift")
    func threadsSwiflowSource() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "/abs/path/to/swiflow",
            jsDriverSource: "// driver\n"
        )

        let pkg = try String(
            contentsOf: tmp.appendingPathComponent("Demo/Package.swift"),
            encoding: .utf8
        )
        #expect(pkg.contains(#".package(path: "/abs/path/to/swiflow")"#))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-init-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InitCommandTests`
Expected: FAIL — `ProjectWriter` doesn't exist.

- [ ] **Step 3: Implement `ProjectWriter`**

Create `Sources/SwiflowCLI/Project/ProjectWriter.swift`:

```swift
// Sources/SwiflowCLI/Project/ProjectWriter.swift
//
// Pure file-tree writer separated from InitCommand so it's trivially
// testable (no CLI invocation, no Process). InitCommand is a thin wrapper
// that resolves arguments + the embedded driver, then delegates here.

import Foundation

enum ProjectWriterError: Error, Equatable, CustomStringConvertible {
    case targetExists(URL)

    var description: String {
        switch self {
        case .targetExists(let url):
            return "target directory already exists: \(url.path)"
        }
    }
}

enum ProjectWriter {

    /// Creates `<into>/<name>/` and writes the full project tree into it.
    ///
    /// - Parameters:
    ///   - name: project name; used as the directory name and `Package.swift` `name:`.
    ///   - into: parent directory (the new project becomes a sibling of existing children here).
    ///   - swiflowSource: value for the generated `Package.swift`'s `.package(path:)`.
    ///   - jsDriverSource: contents to write to `swiflow-driver.js`. Pass `EmbeddedDriver.javascriptSource`
    ///     in production; tests pass a stub string.
    /// - Throws: `ProjectWriterError.targetExists` if `<into>/<name>/` already exists, or
    ///   any `FileManager` error encountered while creating directories / writing files.
    static func writeProject(
        name: String,
        into parent: URL,
        swiflowSource: String,
        jsDriverSource: String
    ) throws {
        let fm = FileManager.default
        let project = parent.appendingPathComponent(name)

        if fm.fileExists(atPath: project.path) {
            throw ProjectWriterError.targetExists(project)
        }

        // Create the directory tree.
        try fm.createDirectory(
            at: project.appendingPathComponent("Sources/App"),
            withIntermediateDirectories: true
        )

        // Write each file.
        try Templates.packageSwift(name: name, swiflowSource: swiflowSource)
            .write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Templates.appSwift(name: name)
            .write(to: project.appendingPathComponent("Sources/App/App.swift"), atomically: true, encoding: .utf8)
        try Templates.indexHTML(name: name)
            .write(to: project.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Templates.gitignore()
            .write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try Templates.readme(name: name)
            .write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try jsDriverSource
            .write(to: project.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Wire `InitCommand.run()` to call `ProjectWriter`**

Replace the body of `Sources/SwiflowCLI/Commands/InitCommand.swift`'s `run()`:

```swift
    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do {
            try ProjectWriter.writeProject(
                name: name,
                into: cwd,
                swiflowSource: swiflowSource,
                jsDriverSource: EmbeddedDriver.javascriptSource
            )
        } catch let error as ProjectWriterError {
            throw ValidationError(String(describing: error))
        }

        print("""
            Created \(name)/
              Next steps:
                cd \(name)
                swiflow build
                python3 -m http.server 3000
                open http://localhost:3000
            """)
    }
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter InitCommandTests`
Expected: PASS — all 4 subtests green.

- [ ] **Step 6: Manual smoke test**

```bash
cd /tmp
rm -rf swiflow-smoke
mkdir swiflow-smoke && cd swiflow-smoke
swift run --package-path . swiflow init demo \
    --swiflow-source .
ls demo
# Expected: Package.swift  README.md  Sources  index.html  swiflow-driver.js  (and .gitignore — use `ls -a`)
cat demo/Package.swift | head -10
# Expected: name "demo", swiflowSource pointed at the absolute path
```

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowCLI/Project Sources/SwiflowCLI/Commands/InitCommand.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "$(cat <<'EOF'
feat: swiflow init writes a complete project tree from templates + embedded driver

ProjectWriter is separated from InitCommand for testability. Refuses to
overwrite an existing target directory.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `ProcessRunner` protocol + `SystemProcessRunner` implementation

Reusable shell-out abstraction. `BuildCommand` will use it; tests will stub it.

**Files:**
- Create: `Sources/SwiflowCLI/Process/ProcessRunner.swift`
- Create: `Tests/SwiflowCLITests/ProcessRunnerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/ProcessRunnerTests.swift`:

```swift
// Tests/SwiflowCLITests/ProcessRunnerTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    @Test("SystemProcessRunner runs /bin/echo and returns exit code 0 + captured stdout")
    func runsEcho() throws {
        let runner = SystemProcessRunner()
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "world"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test("SystemProcessRunner propagates non-zero exit codes")
    func nonZeroExitCode() throws {
        let runner = SystemProcessRunner()
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            workingDirectory: nil,
            environment: nil,
            captureOutput: false
        )
        #expect(result.exitCode == 1)
    }

    @Test("StubProcessRunner records arguments without executing")
    func stubRecords() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        _ = try stub.run(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "js"],
            workingDirectory: URL(fileURLWithPath: "/tmp/proj"),
            environment: ["FOO": "BAR"],
            captureOutput: false
        )
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].arguments == ["package", "js"])
        #expect(stub.calls[0].workingDirectory?.path == "/tmp/proj")
        #expect(stub.calls[0].environment?["FOO"] == "BAR")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessRunnerTests`
Expected: FAIL — `ProcessRunner`, `SystemProcessRunner`, `StubProcessRunner` don't exist.

- [ ] **Step 3: Implement the runner + stub**

Create `Sources/SwiflowCLI/Process/ProcessRunner.swift`:

```swift
// Sources/SwiflowCLI/Process/ProcessRunner.swift
//
// Thin Foundation.Process wrapper. The protocol exists so BuildCommand
// can be tested with a StubProcessRunner that records the argv without
// shelling out.

import Foundation

struct ProcessResult: Equatable {
    let exitCode: Int32
    /// Captured stdout, only populated when `captureOutput == true`. nil otherwise.
    let standardOutput: String?
    /// Captured stderr, only populated when `captureOutput == true`. nil otherwise.
    let standardError: String?
}

protocol ProcessRunner: AnyObject {
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult
}

final class SystemProcessRunner: ProcessRunner {
    init() {}

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        if let environment = environment {
            // Merge with the parent's environment so PATH and friends survive,
            // letting the caller override or extend specific keys.
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let outPipe: Pipe?
        let errPipe: Pipe?
        if captureOutput {
            let o = Pipe()
            let e = Pipe()
            process.standardOutput = o
            process.standardError = e
            outPipe = o
            errPipe = e
        } else {
            // Inherit parent's streams so the user sees swift's progress.
            outPipe = nil
            errPipe = nil
        }

        try process.run()
        process.waitUntilExit()

        let stdout = outPipe.flatMap { pipe -> String? in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }
        let stderr = errPipe.flatMap { pipe -> String? in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr
        )
    }
}

// MARK: - Test stub

/// Records calls without executing. Returns whatever `stubbedExitCode` /
/// `stubbedStandardOutput` were configured with.
final class StubProcessRunner: ProcessRunner {
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
        let workingDirectory: URL?
        let environment: [String: String]?
    }

    var stubbedExitCode: Int32
    var stubbedStandardOutput: String?
    var stubbedStandardError: String?
    private(set) var calls: [Call] = []

    init(stubbedExitCode: Int32 = 0, stubbedStandardOutput: String? = nil, stubbedStandardError: String? = nil) {
        self.stubbedExitCode = stubbedExitCode
        self.stubbedStandardOutput = stubbedStandardOutput
        self.stubbedStandardError = stubbedStandardError
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        ))
        return ProcessResult(
            exitCode: stubbedExitCode,
            standardOutput: stubbedStandardOutput,
            standardError: stubbedStandardError
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessRunnerTests`
Expected: PASS — 3 subtests green.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Process Tests/SwiflowCLITests/ProcessRunnerTests.swift
git commit -m "$(cat <<'EOF'
feat: ProcessRunner protocol + SystemProcessRunner + StubProcessRunner

Lets BuildCommand assert its argv composition against a stub in unit tests
while keeping the real Process shell-out behind the same interface for
production.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: WASM SDK probe — wraps `swift sdk list`

**Files:**
- Create: `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift`
- Create: `Tests/SwiflowCLITests/WasmSDKProbeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/WasmSDKProbeTests.swift`:

```swift
// Tests/SwiflowCLITests/WasmSDKProbeTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("WasmSDKProbe")
struct WasmSDKProbeTests {

    @Test("Picks the first wasm-suffixed SDK from a multi-line listing")
    func picksFirstWasmSDK() {
        let listing = """
        swift-6.3-RELEASE_wasm
        swift-6.3-RELEASE_static-linux-musl
        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == ["swift-6.3-RELEASE_wasm"])
    }

    @Test("Returns multiple wasm SDKs when present, in listing order")
    func picksAllWasm() {
        let listing = """
        swift-6.2-RELEASE_wasm
        swift-6.3-RELEASE_wasm
        swift-DEVELOPMENT-SNAPSHOT-2026-04-01_wasm
        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == [
            "swift-6.2-RELEASE_wasm",
            "swift-6.3-RELEASE_wasm",
            "swift-DEVELOPMENT-SNAPSHOT-2026-04-01_wasm",
        ])
    }

    @Test("Ignores blank lines and trims whitespace")
    func handlesWhitespace() {
        let listing = """

          swift-6.3-RELEASE_wasm  

        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == ["swift-6.3-RELEASE_wasm"])
    }

    @Test("Returns empty for a listing with no wasm SDKs")
    func emptyOnNoWasm() {
        let listing = "swift-6.3-RELEASE_static-linux-musl\n"
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result.isEmpty)
    }

    @Test("pickDefault returns the FIRST wasm SDK from the parsed list")
    func pickDefaultReturnsFirst() {
        let listing = """
        swift-6.2-RELEASE_wasm
        swift-6.3-RELEASE_wasm
        """
        #expect(WasmSDKProbe.pickDefault(from: listing) == "swift-6.2-RELEASE_wasm")
    }

    @Test("pickDefault returns nil for empty listing")
    func pickDefaultEmpty() {
        #expect(WasmSDKProbe.pickDefault(from: "") == nil)
    }

    @Test("list() shells out via the runner and parses the output")
    func listShellsOut() throws {
        let stub = StubProcessRunner(
            stubbedExitCode: 0,
            stubbedStandardOutput: "swift-6.3-RELEASE_wasm\n"
        )
        let probe = WasmSDKProbe(runner: stub, swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"))
        let result = try probe.list()
        #expect(result == ["swift-6.3-RELEASE_wasm"])
        #expect(stub.calls.first?.arguments == ["sdk", "list"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WasmSDKProbeTests`
Expected: FAIL — `WasmSDKProbe` doesn't exist.

- [ ] **Step 3: Implement `WasmSDKProbe`**

Create `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift`:

```swift
// Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift
//
// Wraps `swift sdk list` and filters its output to WASM SDK IDs. Used by
// BuildCommand to pick the right --swift-sdk argument when the user hasn't
// passed one explicitly.

import Foundation

struct WasmSDKProbe {
    let runner: ProcessRunner
    let swiftExecutable: URL

    init(runner: ProcessRunner, swiftExecutable: URL) {
        self.runner = runner
        self.swiftExecutable = swiftExecutable
    }

    /// Runs `swift sdk list` and returns the parsed WASM SDK identifiers.
    func list() throws -> [String] {
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: ["sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard result.exitCode == 0, let stdout = result.standardOutput else {
            return []
        }
        return Self.parseSDKList(stdout)
    }

    /// Filters a `swift sdk list` listing to identifiers ending in `_wasm`.
    /// The suffix convention is what the Swift WASM SDK ships under — both
    /// release SDKs (`swift-6.3-RELEASE_wasm`) and development snapshots
    /// (`swift-DEVELOPMENT-SNAPSHOT-..._wasm`) match.
    static func parseSDKList(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasSuffix("_wasm") }
    }

    /// Convenience: parse + pick the first WASM SDK from a `swift sdk list`
    /// output string. Returns nil if none.
    static func pickDefault(from output: String) -> String? {
        parseSDKList(output).first
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WasmSDKProbeTests`
Expected: PASS — 7 subtests green.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Toolchain Tests/SwiflowCLITests/WasmSDKProbeTests.swift
git commit -m "$(cat <<'EOF'
feat: WasmSDKProbe — wraps swift sdk list and filters to _wasm SDKs

Used by BuildCommand to default --swift-sdk when the user doesn't pin one
explicitly. The list parser is split from the shell-out so it stays under
test without needing the toolchain installed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: macOS `TOOLCHAINS` detection — reads swift-latest.xctoolchain Info.plist

**Files:**
- Create: `Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift`
- Create: `Tests/SwiflowCLITests/MacToolchainProbeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/MacToolchainProbeTests.swift`:

```swift
// Tests/SwiflowCLITests/MacToolchainProbeTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("MacToolchainProbe")
struct MacToolchainProbeTests {

    @Test("Reads CFBundleIdentifier from a real Info.plist file")
    func readsBundleIdentifier() throws {
        // Create a minimal Info.plist with a fake bundle ID in a temp dir.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-toolchain-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let plistURL = tmp.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["CFBundleIdentifier": "org.swift.6320250501"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        let id = MacToolchainProbe.bundleIdentifier(atInfoPlist: plistURL)
        #expect(id == "org.swift.6320250501")
    }

    @Test("Returns nil for a missing Info.plist")
    func missingPlist() {
        let missing = URL(fileURLWithPath: "/nonexistent/path/Info.plist")
        #expect(MacToolchainProbe.bundleIdentifier(atInfoPlist: missing) == nil)
    }

    @Test("Returns nil for an Info.plist without CFBundleIdentifier")
    func plistWithoutBundleID() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-toolchain-probe-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let plistURL = tmp.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["SomeOtherKey": "value"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        #expect(MacToolchainProbe.bundleIdentifier(atInfoPlist: plistURL) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MacToolchainProbeTests`
Expected: FAIL — `MacToolchainProbe` doesn't exist.

- [ ] **Step 3: Implement the probe**

Create `Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift`:

```swift
// Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift
//
// On macOS, the Xcode-default `swift` invokes the system clang, which has
// no WASM backend. PackageToJS then fails with "No available targets are
// compatible with triple 'wasm32-unknown-wasip1'". The workaround is to
// set TOOLCHAINS=<bundle-id-of-swift-org-toolchain> so the SwiftPM driver
// finds a clang that knows about WASM.
//
// This probe extracts that bundle ID from the standard install location
// at ~/Library/Developer/Toolchains/swift-latest.xctoolchain. We do NOT
// mutate the parent process's environment — BuildCommand merges the value
// into the child Process's environment dictionary only.

import Foundation

enum MacToolchainProbe {

    /// Standard install path for the swift.org toolchain on macOS.
    static var swiftLatestInfoPlist: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Developer/Toolchains/swift-latest.xctoolchain/Info.plist")
    }

    /// Convenience: returns the bundle ID for swift-latest, or nil if not
    /// installed / not on macOS (since the path won't exist on Linux).
    static func swiftLatestBundleIdentifier() -> String? {
        return bundleIdentifier(atInfoPlist: swiftLatestInfoPlist)
    }

    /// Reads `CFBundleIdentifier` from the plist at the given URL.
    /// Returns nil if the file doesn't exist, isn't a valid plist, or
    /// doesn't contain the key.
    static func bundleIdentifier(atInfoPlist url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return nil
        }
        guard let dict = plist as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String else {
            return nil
        }
        return bundleID
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter MacToolchainProbeTests`
Expected: PASS — 3 subtests green.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Toolchain/MacToolchainProbe.swift Tests/SwiflowCLITests/MacToolchainProbeTests.swift
git commit -m "$(cat <<'EOF'
feat: MacToolchainProbe reads CFBundleIdentifier from swift-latest.xctoolchain

BuildCommand sets TOOLCHAINS in the child Process environment so the
SwiftPM driver finds a WASM-aware clang. On Linux the helper returns nil
because the path doesn't exist — Linux's distribution swift already has
the right clang.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `BuildCommand` implementation — composes probes + runner

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Create: `Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift`
- Create: `Tests/SwiflowCLITests/BuildCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowCLITests/BuildCommandTests.swift`:

```swift
// Tests/SwiflowCLITests/BuildCommandTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("BuildCommand argv composition")
struct BuildCommandArgvTests {

    @Test("Builds the correct swift package js argv")
    func argvComposition() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        let result = try composer.run(using: stub)
        #expect(result.exitCode == 0)
        #expect(stub.calls.count == 1)
        let call = stub.calls[0]
        #expect(call.executable.path == "/usr/bin/swift")
        #expect(call.arguments == [
            "package",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
            "js",
            "--use-cdn",
            "--product", "App",
            "-c", "release",
        ])
        #expect(call.workingDirectory?.path == "/tmp/demo")
    }

    @Test("Sets TOOLCHAINS in the child environment when bundleID supplied")
    func sendsToolchainsEnv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: "org.swift.6320250501"
        )
        _ = try composer.run(using: stub)
        #expect(stub.calls[0].environment?["TOOLCHAINS"] == "org.swift.6320250501")
    }

    @Test("Omits TOOLCHAINS from the child environment when bundleID is nil")
    func skipsToolchainsEnv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        _ = try composer.run(using: stub)
        // No environment override — runner receives nil.
        #expect(stub.calls[0].environment == nil)
    }

    @Test("Surfaces non-zero exit codes via BuildCommandError")
    func nonZeroExit() {
        let stub = StubProcessRunner(stubbedExitCode: 42)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        #expect(throws: BuildCommandError.swiftPackageJSFailed(exitCode: 42)) {
            _ = try composer.run(using: stub)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BuildCommandArgvTests`
Expected: FAIL — `BuildInvocation` and `BuildCommandError` don't exist.

- [ ] **Step 3: Implement `SwiftExecutableLocator` (helper for resolving the `swift` binary path)**

Create `Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift`:

```swift
// Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift
//
// Resolves the path to the `swift` binary BuildCommand should invoke.
// We use /usr/bin/env so the child process honors the user's PATH —
// this matches the behavior of running `swift` directly in the user's
// shell and avoids hard-coding an install location that varies by
// platform (Homebrew, Xcode, Swiftly, swift-actions, distro packages).

import Foundation

enum SwiftExecutableLocator {
    /// Returns the path to `/usr/bin/env`. BuildCommand passes `swift` as
    /// the first argument; env then resolves `swift` against PATH.
    static var envExecutable: URL {
        URL(fileURLWithPath: "/usr/bin/env")
    }
}
```

> **Design note.** Using `/usr/bin/env swift ...` has one downside: it makes the argv slightly less self-documenting (`env swift package js ...` instead of `swift package js ...`). But it removes a whole class of "wrong swift on PATH" bugs. The first arg to env is `swift` — that goes in `BuildInvocation.arguments`.

Actually, simpler: BuildInvocation receives the absolute path to `swift` (resolved by `which swift` once at startup), and BuildCommand calls `which swift` via the runner. This keeps the argv clean. Let's go that route. Update SwiftExecutableLocator:

```swift
// Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift

import Foundation

enum SwiftExecutableLocator {
    /// Looks up `swift` on PATH via `/usr/bin/env swift -c true`. Returns
    /// the absolute path the parent's PATH resolves `swift` to, or nil if
    /// `swift` isn't on PATH.
    static func locate(using runner: ProcessRunner) throws -> URL? {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", "swift"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard result.exitCode == 0,
              let stdout = result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stdout.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: stdout)
    }
}
```

- [ ] **Step 4: Implement `BuildInvocation` + wire `BuildCommand.run()`**

Replace `Sources/SwiflowCLI/Commands/BuildCommand.swift` entirely:

```swift
// Sources/SwiflowCLI/Commands/BuildCommand.swift
//
// `swiflow build` — composes WasmSDKProbe + MacToolchainProbe +
// ProcessRunner to invoke `swift package ... js --use-cdn --product App
// -c release` against the user's project.
//
// BuildInvocation is the pure argv-composition + Process invocation step;
// it's split from BuildCommand so unit tests can drive it without parsing
// ArgumentParser's argv.

import ArgumentParser
import Foundation

enum BuildCommandError: Error, Equatable, CustomStringConvertible {
    case swiftNotOnPath
    case noWasmSDKInstalled
    case swiftPackageJSFailed(exitCode: Int32)

    var description: String {
        switch self {
        case .swiftNotOnPath:
            return "swift is not on PATH. Install Swift from https://swift.org/install and try again."
        case .noWasmSDKInstalled:
            return """
                No WASM Swift SDK is installed. Run:
                    swift sdk install <SDK URL for your Swift version>
                with a URL from https://swift.org/install (look for the WebAssembly SDK).
                """
        case .swiftPackageJSFailed(let code):
            return "swift package js failed with exit code \(code). See output above."
        }
    }
}

/// Pure argv-composition + Process invocation. BuildCommand.run() delegates here.
struct BuildInvocation {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    /// Runs `swift package --swift-sdk <id> js --use-cdn --product App -c release`
    /// in `projectPath`. Inherits stdout/stderr so the user sees swift's progress.
    @discardableResult
    func run(using runner: ProcessRunner) throws -> ProcessResult {
        let arguments = [
            "package",
            "--swift-sdk", swiftSDK,
            "js",
            "--use-cdn",
            "--product", "App",
            "-c", "release",
        ]

        let environment: [String: String]? = {
            guard let bundleID = toolchainBundleID else { return nil }
            return ["TOOLCHAINS": bundleID]
        }()

        let result = try runner.run(
            executable: swiftExecutable,
            arguments: arguments,
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: false
        )

        if result.exitCode != 0 {
            throw BuildCommandError.swiftPackageJSFailed(exitCode: result.exitCode)
        }
        return result
    }
}

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a Swiflow project to a browser-loadable WASM bundle."
    )

    @Option(
        name: .customLong("path"),
        help: "Path to the Swiflow project directory. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("swift-sdk"),
        help: ArgumentHelp(
            "Override the Swift WASM SDK identifier.",
            discussion: """
                When unset, swiflow runs `swift sdk list` and picks the first installed \
                WASM SDK. Use this flag to pin to a specific SDK across machines.
                """
        )
    )
    var swiftSDK: String?

    func run() async throws {
        let runner = SystemProcessRunner()

        // 1. Find swift on PATH.
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            throw ValidationError(String(describing: BuildCommandError.swiftNotOnPath))
        }

        // 2. Resolve the WASM SDK ID — either user-supplied or auto-picked.
        let sdk: String
        if let userSDK = swiftSDK {
            sdk = userSDK
        } else {
            let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
            let installed = try probe.list()
            guard let firstInstalled = installed.first else {
                throw ValidationError(String(describing: BuildCommandError.noWasmSDKInstalled))
            }
            sdk = firstInstalled
        }

        // 3. macOS: detect TOOLCHAINS bundle ID if not already set.
        let toolchainBundleID: String?
        if ProcessInfo.processInfo.environment["TOOLCHAINS"] != nil {
            // Respect the user's pin.
            toolchainBundleID = nil
        } else {
            toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()
        }

        // 4. Run the build.
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )

        print("swiflow: building with swift-sdk=\(sdk)\(toolchainBundleID.map { " toolchain=\($0)" } ?? "")")
        do {
            _ = try invocation.run(using: runner)
        } catch let error as BuildCommandError {
            throw ValidationError(String(describing: error))
        }

        print("""
            swiflow: build complete.
              Output:  .build/plugins/PackageToJS/outputs/Package/
              Serve:   python3 -m http.server 3000  (from \(projectURL.path))
            """)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter BuildCommandArgvTests`
Expected: PASS — 4 subtests green.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift Sources/SwiflowCLI/Commands/BuildCommand.swift Tests/SwiflowCLITests/BuildCommandTests.swift
git commit -m "$(cat <<'EOF'
feat: swiflow build composes WASM SDK probe + macOS TOOLCHAINS + swift package js

BuildInvocation is split from BuildCommand so argv composition stays
testable without a real swift toolchain. The env-var injection respects
an already-set TOOLCHAINS, never overwrites.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: End-to-end integration test — gated on WASM SDK presence

**Files:**
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift` (add a new suite)

This test invokes the real `swiflow init` + `swiflow build` against a temp directory. It's gated by a runtime probe: if no WASM SDK is installed, the test is recorded as skipped (not failed).

- [ ] **Step 1: Write the integration test**

Append to `Tests/SwiflowCLITests/BuildCommandTests.swift`:

```swift
// MARK: - End-to-end (gated on WASM SDK presence)

@Suite("BuildCommand end-to-end (requires WASM SDK)")
struct BuildCommandIntegrationTests {

    static var wasmSDKAvailable: Bool {
        let runner = SystemProcessRunner()
        let result = try? runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", "sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard let stdout = result?.standardOutput else { return false }
        return !WasmSDKProbe.parseSDKList(stdout).isEmpty
    }

    static var swiflowRepoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    @Test(
        "swiflow init + swiflow build produces a PackageToJS output bundle",
        .enabled(if: wasmSDKAvailable)
    )
    func endToEnd() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Init into the temp dir, pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: Self.swiflowRepoRoot.path,
            jsDriverSource: EmbeddedDriver.javascriptSource
        )

        // 2. Probe the SDK from the same shell-out path the production code uses.
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH; cannot run end-to-end test.")
            return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty even though .enabled gated true; flaky CI?")
            return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Build.
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: tmp.appendingPathComponent("Demo"),
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )
        let result = try invocation.run(using: runner)
        #expect(result.exitCode == 0)

        // 4. Assert the PackageToJS output exists.
        let outputDir = tmp.appendingPathComponent("Demo/.build/plugins/PackageToJS/outputs/Package")
        let indexJS = outputDir.appendingPathComponent("index.js")
        let appWASM = outputDir.appendingPathComponent("App.wasm")
        #expect(FileManager.default.fileExists(atPath: indexJS.path), "missing \(indexJS.path)")
        #expect(FileManager.default.fileExists(atPath: appWASM.path), "missing \(appWASM.path)")
    }
}
```

> **First-run perf note.** This test downloads JavaScriptKit + swift-syntax and compiles them from source. Budget 3–5 minutes for the first run; subsequent runs are much faster thanks to SwiftPM's package cache. CI runners hit the slow path on every job unless the workflow caches `~/.cache/org.swift.swiftpm` (Linux) or `~/Library/Caches/org.swift.swiftpm` (macOS) — out of scope for Phase 2b.

- [ ] **Step 2: Run the integration test**

```bash
swift test --filter BuildCommandIntegrationTests
```

Expected on machines with WASM SDK + swift-org toolchain installed: PASS (after multi-minute first-run download/compile).
Expected on machines without: skipped (no failures, no errors).

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: All tests pass (or skip cleanly).

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowCLITests/BuildCommandTests.swift
git commit -m "$(cat <<'EOF'
test: end-to-end swiflow init + swiflow build against a temp project

Gated on WASM SDK presence via Test.enabled(if:) so contributors without
the SDK don't see spurious failures. The test is the load-bearing
guarantee that Phase 2b's CLI reproduces the Phase 2a end-to-end flow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Regenerate `examples/HelloWorld/` via `swiflow init` — prove the CLI matches the verified baseline

**Files:**
- Delete + recreate: `examples/HelloWorld/`

The plan's load-bearing claim is "init produces the same project Phase 2a verified by hand." Now we prove it.

- [ ] **Step 1: Capture the current example for diff comparison**

```bash
cp -r examples/HelloWorld /tmp/swiflow-helloworld-baseline
```

- [ ] **Step 2: Wipe and regenerate via the CLI**

```bash
rm -rf examples/HelloWorld
cd examples
swift run --package-path .. swiflow init HelloWorld --swiflow-source ../..
cd ..
```

- [ ] **Step 3: Diff against the baseline**

```bash
diff -r /tmp/swiflow-helloworld-baseline examples/HelloWorld
```

Expected output: empty diff, OR only `.DS_Store` / `.build/` / `Package.resolved` differences (those are intentionally not generated by init).

If there are content differences in `Package.swift`, `Sources/App/App.swift`, `index.html`, or `.gitignore`, the templates need to be fixed in Task 4 to match. Go back, fix, regen.

The new `README.md` will differ from the old one (the init template differs from the Phase 2a hand-crafted README). That's expected and intentional — Phase 2a's README was bespoke, and now there's one canonical template.

- [ ] **Step 4: Restore `.gitignore`'d files not generated by init**

`examples/HelloWorld/Package.resolved` was in the previous version (Phase 2a wrote it during a build). Regenerate it:

```bash
cd examples/HelloWorld
# Use the parent's swift to resolve dependencies (no build, just resolve)
swift package resolve
cd ../..
```

Expected: `examples/HelloWorld/Package.resolved` reappears.

- [ ] **Step 5: Verify the example still builds end-to-end (manual)**

```bash
cd examples/HelloWorld
swift run --package-path ../.. swiflow build
python3 -m http.server 3000 &
SERVER_PID=$!
sleep 1
# Open http://localhost:3000 in a browser and verify Hello, Swiflow! shows
# and the Increment button increments the count.
kill $SERVER_PID
cd ../..
```

Or skip the manual browser step — the integration test in T10 covered the equivalent.

- [ ] **Step 6: Clean up tmp baseline**

```bash
rm -rf /tmp/swiflow-helloworld-baseline
```

- [ ] **Step 7: Commit**

```bash
git add examples/HelloWorld
git commit -m "$(cat <<'EOF'
chore: regenerate examples/HelloWorld via swiflow init

The example is now a snapshot of what `swiflow init HelloWorld
--swiflow-source ../..` produces. Any future template change auto-flows
here on the next regen, and any drift between this snapshot and the
template will be caught by TemplatesTests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Update top-level README, CONTRIBUTING, CI workflow

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Update `README.md`**

Replace `README.md` with:

```markdown
# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 2b complete. The `swiflow` CLI now scaffolds (`init`) and
builds (`build`) projects end-to-end. The dev server (`swiflow dev`) lands
in Phase 2c.

## Quick start

```bash
# 1. Build the CLI.
swift build -c release --product swiflow

# 2. Scaffold a project.
./.build/release/swiflow init my-app --swiflow-source $(pwd)
cd my-app

# 3. Build the WASM bundle.
../.build/release/swiflow build

# 4. Serve.
python3 -m http.server 3000
# Open http://localhost:3000
```

Prerequisites: Swift 6.0+ and a WebAssembly Swift SDK installed via
`swift sdk install`. See <https://swift.org/install> for SDK URLs.

## What's in the box

- **`Swiflow`** — pure-Swift VDOM core: tagged-enum `VNode`, 16-opcode `Patch`,
  hybrid keyed (LIS-based) + indexed children diff, `@resultBuilder` DSL.
- **`SwiflowWeb`** — WASM-only renderer + JavaScriptKit bridge.
- **`swiflow`** — the CLI: `init` scaffolds, `build` wraps `swift package js`
  with the right SDK + toolchain auto-detection.
- **JS driver** — vanilla JS, ~200 lines, embedded into the CLI binary as
  generated Swift code (single source of truth: `js-driver/swiflow-driver.js`).

## Architecture

See [docs/brainstorm/](docs/brainstorm/) for the original design exploration
and [docs/superpowers/plans/](docs/superpowers/plans/) for the per-phase
implementation plans.

## Testing

```bash
swift test
```

Phase 1+2a+2b ships NNN tests across MM suites (update count after the
final `swift test` run). Tests that require the WASM SDK end-to-end are
gated and skip cleanly when it's absent.

## License

Apache 2.0. See [LICENSE](LICENSE).
```

After running the full suite at the end, swap `NNN`/`MM` with actual counts. Run `swift test` and copy the summary line.

- [ ] **Step 2: Update `CONTRIBUTING.md`**

Replace `CONTRIBUTING.md` with:

```markdown
# Contributing to Swiflow

Thank you for considering a contribution.

## Development

```bash
swift build                            # build all targets
swift test                             # run all tests
swift run swiflow --help               # try the CLI
```

Tests use the Swift Testing framework (`import Testing`), available in Swift
6.0 and later.

## When you change the JS driver

`js-driver/swiflow-driver.js` is the single source of truth. The CLI embeds
its contents via codegen. After editing the driver, regenerate the embedded
copy:

```bash
swift scripts/embed-driver.swift
```

(If you forget, the `DriverEmbedderTests` freshness check will fail in CI
and tell you exactly this command to run.)

## Workflow

- Fork; create a topic branch.
- Keep commits small and focused; conventional commit prefixes are appreciated
  (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`).
- Open a pull request against `main`. CI must pass on macOS and Linux.

## License

By contributing, you agree your contribution will be licensed under the
Apache License, Version 2.0 (see [LICENSE](LICENSE)).
```

- [ ] **Step 3: Update `.github/workflows/ci.yml`**

Add a `Build CLI` step. Replace the file with:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    name: Test (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14, ubuntu-22.04]
    steps:
      - uses: actions/checkout@v4

      - name: Set up Swift (Linux)
        if: runner.os == 'Linux'
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "6.0"

      - name: Verify Swift version
        run: swift --version

      - name: Build library + WebTarget
        run: swift build

      - name: Build CLI
        run: swift build --product swiflow

      - name: Test
        run: swift test --parallel
```

(The integration test in T10 skips when no WASM SDK is installed — CI does NOT install the WASM SDK in Phase 2b. A future Phase 2b polish task may add SDK install + the gated integration test enabled, but for now the unit tests cover all argv composition + probe parsing.)

- [ ] **Step 4: Run the full test suite one more time**

```bash
swift test
```

Expected: All tests pass. Record the count for the README update.

- [ ] **Step 5: Fix the test count in `README.md`**

Replace `NNN tests across MM suites` with the real numbers from the test summary line.

- [ ] **Step 6: Verify the CLI builds and runs**

```bash
swift build -c release --product swiflow
./.build/release/swiflow --help
./.build/release/swiflow init --help
./.build/release/swiflow build --help
```

Expected: all three print useful help.

- [ ] **Step 7: Commit**

```bash
git add README.md CONTRIBUTING.md .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
docs: update README + CONTRIBUTING for Phase 2b; CI builds the CLI target

The README now describes the two-command swiflow init/build workflow.
CONTRIBUTING mentions the driver embedding regen step. CI adds an explicit
`swift build --product swiflow` step so the CLI compiles on both runners
even if no test exercises it directly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2b Completion Checklist

After Task 12, verify:

- [ ] `swift build` succeeds with no warnings on macOS.
- [ ] `swift build --product swiflow` succeeds and produces `.build/<config>/swiflow`.
- [ ] `swift test` passes — the new Phase 2b tests add at least:
  - 1 PackageSmokeTest
  - 2 DriverEmbedderTests
  - 4 CommandTreeTests
  - 7 TemplatesTests
  - 4 InitCommandTests
  - 3 ProcessRunnerTests
  - 7 WasmSDKProbeTests
  - 3 MacToolchainProbeTests
  - 4 BuildCommandArgvTests
  - 1 BuildCommandIntegrationTest (gated)

  ≈ 36 new tests on top of Phase 2a's 123, target ~159 total.
- [ ] `swift run swiflow init demo` in a fresh directory produces a complete project tree.
- [ ] `swift run swiflow build` in `examples/HelloWorld/` produces `App.wasm` + `index.js`.
- [ ] Manual browser smoke test: `python3 -m http.server` in the freshly-built example shows Hello, Swiflow! with a working Increment button.
- [ ] CI workflow includes the `swift build --product swiflow` step and passes on macOS + Linux.
- [ ] `examples/HelloWorld/` is byte-identical to a fresh `swiflow init HelloWorld --swiflow-source ../..` (modulo `Package.resolved` and `.build/`).
- [ ] `js-driver/swiflow-driver.js` and `Sources/SwiflowCLI/EmbeddedDriver.swift`'s string are in sync (the freshness test guarantees this).

When all boxes are checked, Phase 2b is done. Phase 2c begins with its own plan, which will:

- Add the `dev` subcommand to the CLI.
- Add a `swift-nio` (or `swift-http-types` + `Network`/`FoundationNetworking`) HTTP server target.
- Add an FSEvents (macOS) / inotify (Linux) file watcher abstraction.
- Wire a `/reload` WebSocket the JS driver can listen on.
- Ship `swiflow dev` so the edit-rebuild-reload loop is one command.

---

## Self-Review Notes (for the implementer)

This plan was reviewed against `~/.claude/plans/i-want-you-to-dynamic-pancake.md` §§ 5.1, 5.3, 5.5. Coverage check:

- **§ 5.1 `swiflow init <name>`** — Covered by T4 + T5 + T11. Layout differs from spec (no `public/`) per "Spec deviations" point 1.
- **§ 5.1 `swiflow build`** — Covered by T7 + T8 + T9 + T10. No artifact copy step per deviation point 2; no `--production` flag per deviation point 3.
- **§ 5.1 `swiflow dev`** — Explicitly out of scope (Phase 2c).
- **§ 5.3 Hello World template** — Covered by T4 (templates encode the Phase 2a App.swift verbatim).
- **§ 5.4 Phase 2 Test Matrix** — `InitCommandTests` covers file-tree generation and content match; `BuildCommandIntegrationTests` covers the `testGeneratedProjectIsValid` requirement (init + build → wasm exists). No `DevServerTests` since dev is Phase 2c.
- **§ 5.5 Phase 2 Success Criteria** — Partially covered: items 1 (init + dev → browser), 2 (Increment works), 5 (print → console) require Phase 2c's dev server for one-command verification. The Phase 2b checklist substitutes "manual python3 -m http.server" as the bridge.
- **§ 17 security pillar (Package.resolved checked in by init)** — Intentionally deferred per Architectural Decision 9. The decision is documented in the plan.

Placeholder scan: no TBDs, no "fill in details", no "similar to Task N" without code, no "add appropriate error handling" without specifics. Every file has paths; every code step has code; every test step has assertions.

Type consistency: `ProjectWriter`, `Templates`, `DriverEmbedder`, `EmbeddedDriver`, `WasmSDKProbe`, `MacToolchainProbe`, `ProcessRunner`, `StubProcessRunner`, `SystemProcessRunner`, `BuildInvocation`, `BuildCommandError` are introduced once and referenced consistently across later tasks. The `swiflowSource` argument label is used identically in `Templates.packageSwift`, `ProjectWriter.writeProject`, and `InitCommand`. The `jsDriverSource` label flows from `ProjectWriter` into `InitCommand` consistently.
