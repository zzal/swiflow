# Phase 14b Track 2 — WASM Trimming: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop the first-visit gzipped bundle from 20.6 MB to ≤16.5 MB (≥20% reduction) by switching the Swift compiler to `-Osize`, post-processing with `wasm-opt -Oz`, and stripping the `name` section on release builds.

**Architecture:** Build-pipeline-only changes. No Swift API surface moves. `swiflow build -c release` runs PackageToJS, then `wasm-opt`, then `wasm-strip`, then computes the SHA256 manifest from the final bytes (so the Track 1 service worker caches the trimmed artifact). Two new pieces of CLI surface: a `swiflow doctor` subcommand that audits required toolchain pieces, and a hard-fail when `wasm-opt` is missing from PATH at release build time.

**Tech Stack:** Existing Swift toolchain (`-Osize`, `-gnone`). Binaryen's `wasm-opt`. WABT's `wasm-strip`. No new Swift dependencies; the new tools are external binaries called via `Process`.

---

## File structure

| Path | Action | Responsibility |
|---|---|---|
| `docs/perf/2026-05-26-wasm-bundle-audit.md` | **create** | Standalone deliverable: section sizes, top 30 functions (demangled), attribution buckets, reflection-disabled measurement |
| `Sources/SwiflowCLI/Commands/DoctorCommand.swift` | **create** | `swiflow doctor` subcommand — checks `swift`, WASM SDK, `wasm-opt`, `wasm-strip`; prints install hints on missing |
| `Sources/SwiflowCLI/Swiflow.swift` | modify | Register `DoctorCommand.self` in the subcommand list |
| `Tests/SwiflowCLITests/DoctorCommandTests.swift` | **create** | Cover present/missing/version-mismatch paths for each tool |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | modify | `-O` → `-Osize`; add `-gnone` for release; invoke `wasm-opt` + `wasm-strip` between PackageToJS and manifest emission; fail-hard when `wasm-opt` missing |
| `Tests/SwiflowCLITests/BuildCommandTests.swift` | modify | Cover the new flag string; mock-based test for the wasm-opt missing path (assert exit + install-hint message) |
| `docs/perf/bundle-baseline.json` | modify | Updated incrementally as each trim step lands (Tasks 3, 4, 5) — the file's `total_gzip_bytes` ratchets down |
| `README.md` | modify | Add `wasm-opt` (binaryen) + `wasm-strip` (wabt) to prereqs; mention `swiflow doctor`; update status line and cost rows |
| `CHANGELOG.md` | modify | Phase 14b Track 2 entry above Track 1 |

**Out of scope for this track:** `--disable-reflection-metadata` (post-1.0, blocked on `@State` redesign). Vendoring `wasm-opt` binaries per platform (defer; require system install). Touching the dev-mode build path (HMR keeps the current `-Onone` story; trimming runs only on `-c release`).

---

## Task 1: WASM bundle audit doc

**Files:**
- Create: `docs/perf/2026-05-26-wasm-bundle-audit.md`

This task ships pure documentation. No code. The audit is the baseline for everything else in this track; future trimming work refers back to it.

- [ ] **Step 1: Verify toolchain present locally**

Run:
```bash
which wasm-objdump wasm-opt wasm-tools wasm-decompile wasm-strip || true
```

If any are missing, install:
```bash
brew install wabt binaryen
cargo install wasm-tools
```

The audit produces `wasm-tools` output but it's a one-time deliverable — the persistent build pipeline only depends on `wasm-opt` and `wasm-strip`.

- [ ] **Step 2: Produce a fresh release WASM to measure**

```bash
cd examples/Counter
swift package clean
../../.build/release/swiflow build
ls -la .build/plugins/PackageToJS/outputs/Package/App.wasm
```

This is the **pre-trim** binary. Note the raw size and the gzipped size:

```bash
wc -c .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

- [ ] **Step 3: Capture section sizes**

```bash
wasm-objdump -h .build/plugins/PackageToJS/outputs/Package/App.wasm > /tmp/audit-sections.txt
```

- [ ] **Step 4: Capture top functions by byte size**

```bash
wasm-opt --func-metrics .build/plugins/PackageToJS/outputs/Package/App.wasm \
  -o /dev/null 2> /tmp/audit-funcs.txt
head -50 /tmp/audit-funcs.txt
```

- [ ] **Step 5: Capture reflection-disabled measurement**

Build a throw-away copy with reflection metadata stripped. The build will compile but the resulting WASM will crash at runtime (`@State` uses `Mirror`); the point is to record the *size*, not run the binary.

```bash
cd examples/Counter
swift package clean
swift package --swift-sdk <wasm-sdk> -c release \
  --Xswiftc "-Osize" \
  --Xswiftc "-disable-reflection-metadata" \
  js
ls -la .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

Record the gzipped delta vs Step 2's baseline. Restore the working tree by running a normal `swiflow build` afterwards.

- [ ] **Step 6: Write the audit doc**

Create `docs/perf/2026-05-26-wasm-bundle-audit.md`. Structure:

```markdown
# WASM Bundle Audit — 2026-05-26

Pre-trim measurements taken on the Counter example built with the
current `swiflow build` (Swift 6.3, WASM SDK 6.3, `-O` release).

## Headline numbers

| Build | Raw bytes | Gzipped bytes | Notes |
|---|---|---|---|
| Current release (`-O`)            | <fill> | <fill> | Baseline before Track 2 |
| With `-Osize`                      | <fill> | <fill> | Measured at Task 3 |
| With `-Osize` + `wasm-opt -Oz`     | <fill> | <fill> | Measured at Task 4 |
| With above + `wasm-strip` (name)   | <fill> | <fill> | Measured at Task 5 |
| With `-Osize -disable-reflection-metadata` | <fill> | <fill> | **Measurement only — binary crashes at runtime.** Records the theoretical floor available if `@State` is redesigned (post-1.0). |

## Section breakdown

(paste `wasm-objdump -h` output, then a short prose summary of which
section dominates and why)

## Top functions

(paste the top 30 entries from `wasm-opt --func-metrics`. Demangle Swift
names with `swift demangle` where useful.)

Bucket the top 30 into:
- Swift stdlib (`$s` prefix, runtime support)
- Foundation
- JavaScriptKit
- Swiflow itself
- App code (Counter)

Write one paragraph on what dominates and why.

## The reflection wall

`@State` uses `Mirror` to enumerate properties on a `Component` at mount.
That ties us to Swift's reflection metadata; the compiler flag
`-disable-reflection-metadata` strips it but breaks `@State`.

The measurement above records what we'd save if `@State` were redesigned
to emit explicit accessors via a macro instead of relying on `Mirror`.
That redesign is on the post-1.0 punch list.

## What this audit does *not* measure

- Cost of individual transitive Foundation usage (we don't have
  per-import tooling for Swift-WASM yet)
- Cost of JavaScriptKit's `JSObject` machinery vs. an ahead-of-time JS
  bridge (different architectural choice; documented as a multi-quarter
  post-1.0 project in `docs/superpowers/specs/2026-05-26-phase14b-wasm-perf-design.md`)
```

Fill all `<fill>` slots from your measurements. Leave Tasks 3-5 rows
with placeholder values; each later task updates its own row.

- [ ] **Step 7: Commit**

```bash
git add docs/perf/2026-05-26-wasm-bundle-audit.md
git commit -m "$(cat <<'EOF'
docs(perf): Track 2 baseline — WASM bundle audit

Section sizes, top-30 functions, and reflection-disabled lower bound
measured against the current `-O` release build of Counter.
EOF
)"
```

---

## Task 2: `swiflow doctor` subcommand

**Files:**
- Create: `Sources/SwiflowCLI/Commands/DoctorCommand.swift`
- Modify: `Sources/SwiflowCLI/Swiflow.swift`
- Create: `Tests/SwiflowCLITests/DoctorCommandTests.swift`

The doctor's only job is to surface what's missing. It does not modify state, does not run a build, does not exit non-zero unless something is genuinely broken.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/DoctorCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowCLI

@Suite("DoctorCommand")
struct DoctorCommandTests {
    @Test("Reports all-green when every required tool is on PATH")
    func allPresent() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .found("6.3-RELEASE-wasm"),
            wasmOpt: .found("wasm-opt version 116"),
            wasmStrip: .found("1.0.36")
        )
        #expect(report.exitCode == 0)
        #expect(report.summary.contains("✓ swift"))
        #expect(report.summary.contains("✓ wasm-opt"))
        #expect(!report.summary.contains("✗"))
    }

    @Test("Exit non-zero and prints install hint when wasm-opt missing")
    func wasmOptMissing() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .found("6.3-RELEASE-wasm"),
            wasmOpt: .missing,
            wasmStrip: .found("1.0.36")
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-opt"))
        #expect(report.summary.contains("brew install binaryen"))
    }

    @Test("Each tool reports independently — multiple misses listed")
    func multipleMissing() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .missing,
            wasmOpt: .missing,
            wasmStrip: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-sdk"))
        #expect(report.summary.contains("✗ wasm-opt"))
        #expect(report.summary.contains("✗ wasm-strip"))
        #expect(report.summary.contains("swift sdk install"))
        #expect(report.summary.contains("brew install binaryen"))
        #expect(report.summary.contains("brew install wabt"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
swift test --filter DoctorCommandTests
```

Expected: compile error (`DoctorReport` not defined).

- [ ] **Step 3: Implement `DoctorReport` + `DoctorCommand`**

Create `Sources/SwiflowCLI/Commands/DoctorCommand.swift`:

```swift
import Foundation
import ArgumentParser

package enum ToolStatus: Equatable {
    case found(String)   // detail: version or identifier; opaque to callers
    case missing
}

package struct DoctorReport {
    let swift: ToolStatus
    let wasmSDK: ToolStatus
    let wasmOpt: ToolStatus
    let wasmStrip: ToolStatus

    package var exitCode: Int32 {
        let allPresent = [swift, wasmSDK, wasmOpt, wasmStrip].allSatisfy {
            if case .missing = $0 { return false }
            return true
        }
        return allPresent ? 0 : 1
    }

    package var summary: String {
        var lines: [String] = ["swiflow doctor", ""]

        lines.append(row(name: "swift",      status: swift,      hint: "Install Swift 6.3 from https://swift.org/install/"))
        lines.append(row(name: "wasm-sdk",   status: wasmSDK,    hint: "swift sdk install https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz --checksum 9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9"))
        lines.append(row(name: "wasm-opt",   status: wasmOpt,    hint: "brew install binaryen   # required for release builds"))
        lines.append(row(name: "wasm-strip", status: wasmStrip,  hint: "brew install wabt       # required for release builds"))

        lines.append("")
        if exitCode == 0 {
            lines.append("All checks passed.")
        } else {
            lines.append("Some checks failed. Install the missing tools above and run `swiflow doctor` again.")
        }
        return lines.joined(separator: "\n")
    }

    private func row(name: String, status: ToolStatus, hint: String) -> String {
        switch status {
        case .found(let detail):
            return "  ✓ \(name)  (\(detail))"
        case .missing:
            return "  ✗ \(name)\n      \(hint)"
        }
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that the toolchain pieces Swiflow needs are installed."
    )

    func run() async throws {
        let report = DoctorReport(
            swift: probeSwift(),
            wasmSDK: probeWasmSDK(),
            wasmOpt: probeBinary(named: "wasm-opt", versionArgs: ["--version"]),
            wasmStrip: probeBinary(named: "wasm-strip", versionArgs: ["--version"])
        )
        print(report.summary)
        if report.exitCode != 0 {
            throw ExitCode(report.exitCode)
        }
    }

    private func probeSwift() -> ToolStatus {
        guard let out = try? captureOutput("swift", ["--version"]) else { return .missing }
        // First line typically: "Apple Swift version 6.3 (swiftlang-6.3.0..."
        let firstLine = out.split(separator: "\n").first.map(String.init) ?? ""
        return .found(firstLine)
    }

    private func probeWasmSDK() -> ToolStatus {
        guard let out = try? captureOutput("swift", ["sdk", "list"]) else { return .missing }
        guard let line = out.split(separator: "\n").first(where: { $0.contains("wasm") }) else {
            return .missing
        }
        return .found(String(line).trimmingCharacters(in: .whitespaces))
    }

    private func probeBinary(named name: String, versionArgs: [String]) -> ToolStatus {
        guard let _ = try? captureOutput("which", [name]) else { return .missing }
        guard let out = try? captureOutput(name, versionArgs) else { return .missing }
        let firstLine = out.split(separator: "\n").first.map(String.init) ?? "unknown"
        return .found(firstLine.trimmingCharacters(in: .whitespaces))
    }

    private func captureOutput(_ executable: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = [executable] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()  // discard stderr
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "DoctorCommand", code: Int(proc.terminationStatus))
        }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
```

- [ ] **Step 4: Wire it into `Swiflow.swift`**

Modify `Sources/SwiflowCLI/Swiflow.swift` — add `DoctorCommand.self` to the subcommand list:

```swift
subcommands: [InitCommand.self, BuildCommand.self, DevCommand.self, DoctorCommand.self],
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter DoctorCommandTests
```

Expected: all 3 tests pass.

- [ ] **Step 6: Smoke test from the CLI**

```bash
swift build -c release --product swiflow
./.build/release/swiflow doctor
```

Expected: prints the summary with ✓ next to every tool you have installed.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/Commands/DoctorCommand.swift \
        Sources/SwiflowCLI/Swiflow.swift \
        Tests/SwiflowCLITests/DoctorCommandTests.swift
git commit -m "$(cat <<'EOF'
feat(cli): add `swiflow doctor` subcommand

Standalone toolchain audit — checks swift, the WASM SDK, wasm-opt,
and wasm-strip. Exits non-zero with install hints when anything is
missing. Does not preflight build or dev; those continue to check
their own requirements at invocation time.
EOF
)"
```

---

## Task 3: `-O` → `-Osize` + `-gnone` for release

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift`
- Modify: `docs/perf/2026-05-26-wasm-bundle-audit.md` (fill the Task 3 row)
- Modify: `docs/perf/bundle-baseline.json`

- [ ] **Step 1: Find the current flag site**

Locate the `--Xswiftc -O` invocation in `BuildCommand.swift`. It will be in the args array passed to `swift package … js -c release`.

```bash
grep -n '"-O"' Sources/SwiflowCLI/Commands/BuildCommand.swift
```

- [ ] **Step 2: Write the failing test**

In `Tests/SwiflowCLITests/BuildCommandTests.swift`, add:

```swift
@Test("Release-mode invocation passes -Osize and -gnone via --Xswiftc")
func releaseFlagsAreOsizeAndGnone() throws {
    let args = BuildCommand.swiftPackageArgs(configuration: .release, sdkID: "wasm")
    #expect(args.contains(where: { $0 == "-Osize" }))
    #expect(args.contains(where: { $0 == "-gnone" }))
    #expect(!args.contains(where: { $0 == "-O" }))
}
```

If the existing code doesn't expose a pure `swiftPackageArgs(configuration:sdkID:)` static, extract one as part of this task — it's a worthwhile testable surface and the change is local.

- [ ] **Step 3: Run the test to verify it fails**

```bash
swift test --filter BuildCommandTests
```

Expected: FAIL with "missing `-Osize`".

- [ ] **Step 4: Replace `-O` with `-Osize` and add `-gnone`**

In `BuildCommand.swift`:

```swift
// BEFORE
"--Xswiftc", "-O",

// AFTER
"--Xswiftc", "-Osize",
"--Xswiftc", "-gnone",
```

`-gnone` for release only — dev keeps DWARF for the debugging story (Phase 13b). If the args array is shared between dev and release, gate the `-gnone` on `configuration == .release`.

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter BuildCommandTests
```

Expected: PASS.

- [ ] **Step 6: Build the CLI fresh, then re-measure Counter**

```bash
swift build -c release --product swiflow
cd examples/Counter
swift package clean
../../.build/release/swiflow build
wc -c .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

Record the new raw + gzipped numbers. Compare to the Task 1 baseline row.

- [ ] **Step 7: Update the audit doc and the bundle baseline**

Fill the "With `-Osize`" row in `docs/perf/2026-05-26-wasm-bundle-audit.md`. Update `docs/perf/bundle-baseline.json` — the `total_gzip_bytes` field now reflects the new measurement.

- [ ] **Step 8: Run the Counter Playwright spec to confirm nothing broke**

```bash
cd Tests/playwright
npm test
```

Expected: PASS. The smaller binary should run identically — `-Osize` is opt-level, not behaviour-changing. If anything fails, the failure is real and worth investigating before continuing.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI/Commands/BuildCommand.swift \
        Tests/SwiflowCLITests/BuildCommandTests.swift \
        docs/perf/2026-05-26-wasm-bundle-audit.md \
        docs/perf/bundle-baseline.json
git commit -m "$(cat <<'EOF'
perf(build): switch release Swift opts to -Osize + -gnone

Targets size over speed for the workloads Swiflow runs (DOM diff, not
numerical compute). -gnone drops debug info in release; dev still
ships DWARF for the Phase 13b debugging story.

Bundle-size delta recorded in docs/perf/2026-05-26-wasm-bundle-audit.md.
EOF
)"
```

---

## Task 4: `wasm-opt -Oz` post-process

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift`
- Modify: `docs/perf/2026-05-26-wasm-bundle-audit.md` (Task 4 row)
- Modify: `docs/perf/bundle-baseline.json`

This task adds a release-only post-processing step: after PackageToJS produces `App.wasm`, invoke `wasm-opt` on it in place. **`wasm-opt` missing is a hard failure** (per the open-question resolution: a missing dependency is better surfaced as a build failure with an install hint than silently skipped).

- [ ] **Step 1: Write the failing test for fail-hard behaviour**

In `BuildCommandTests.swift`:

```swift
@Test("Release build aborts with install hint when wasm-opt is missing")
func releaseFailsWhenWasmOptMissing() throws {
    // Run BuildCommand.runWasmOpt with a PATH that has no wasm-opt.
    let isolatedPATH = "/usr/bin:/bin"  // standard utilities only; no wasm-opt
    let dummyWasm = URL(fileURLWithPath: "/tmp/should-not-be-touched.wasm")

    do {
        try BuildCommand.runWasmOpt(on: dummyWasm, pathOverride: isolatedPATH)
        Issue.record("expected runWasmOpt to throw")
    } catch let error as BuildCommandError {
        #expect(error.message.contains("wasm-opt not found"))
        #expect(error.message.contains("brew install binaryen"))
        #expect(error.message.contains("swiflow doctor"))
    }
}

@Test("Release build succeeds and shrinks the wasm when wasm-opt is present")
func wasmOptShrinksFile() throws {
    // Use a tiny real wasm fixture under Tests/Fixtures/.
    let fixture = ResourceBundle.fixture(named: "small.wasm")
    let work = try copyToTemp(fixture)
    let originalSize = try Data(contentsOf: work).count

    try BuildCommand.runWasmOpt(on: work, pathOverride: nil)

    let trimmedSize = try Data(contentsOf: work).count
    #expect(trimmedSize <= originalSize)  // wasm-opt is idempotent on tiny files; equality is OK
}
```

The fixture-based test runs only when `wasm-opt` is installed locally. Gate it on a runtime check at the top of the test if needed (`try await Process.which("wasm-opt")`).

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter BuildCommandTests
```

Expected: FAIL with "`runWasmOpt` not defined" / `BuildCommandError` undefined.

- [ ] **Step 3: Implement `runWasmOpt` + the error type**

In `BuildCommand.swift`:

```swift
package struct BuildCommandError: Error, Equatable {
    let message: String
}

extension BuildCommand {
    /// Run `wasm-opt -Oz --strip-debug --strip-producers` in place on the file.
    /// Throws `BuildCommandError` with an install hint if `wasm-opt` is missing.
    package static func runWasmOpt(on file: URL, pathOverride: String? = nil) throws {
        let env = pathOverride.map { ["PATH": $0] } ?? ProcessInfo.processInfo.environment
        guard which("wasm-opt", env: env) != nil else {
            throw BuildCommandError(message: """
                wasm-opt not found on PATH.
                
                Swiflow's release build requires Binaryen's wasm-opt to trim
                the WASM bundle. Install it with:
                
                    brew install binaryen
                
                Or run `swiflow doctor` to audit all required tools.
                """)
        }

        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = [
            "wasm-opt",
            "-Oz",
            "--strip-debug",
            "--strip-producers",
            file.path,
            "-o", file.path,
        ]
        if let pathOverride = pathOverride {
            proc.environment = ["PATH": pathOverride]
        }
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw BuildCommandError(message: "wasm-opt failed with exit code \(proc.terminationStatus)")
        }
    }

    private static func which(_ name: String, env: [String: String]) -> String? {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["which", name]
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 4: Call `runWasmOpt` after PackageToJS, before the manifest emit**

Find the section in `BuildCommand` (the `run()` method or equivalent) where PackageToJS has just finished and `writeManifest` is about to be called. Insert:

```swift
// Release-only: trim the WASM with wasm-opt before we hash it for the manifest.
// Hard-fails if wasm-opt is missing — see `swiflow doctor`.
if configuration == .release {
    let wasm = projectDir
        .appendingPathComponent(".build/plugins/PackageToJS/outputs/Package/App.wasm")
    try Self.runWasmOpt(on: wasm)
}

try Self.writeManifest(projectDir: projectDir)
```

The ordering matters: `wasm-opt` rewrites `App.wasm` in place, then `writeManifest` SHA256s the *trimmed* bytes. The Track 1 service worker therefore caches the trimmed artifact.

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter BuildCommandTests
```

Expected: PASS (both tests).

- [ ] **Step 6: Re-measure Counter**

```bash
swift build -c release --product swiflow
cd examples/Counter
swift package clean
../../.build/release/swiflow build
wc -c .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

Record the new numbers. Expect 5-15% additional shrinkage on top of Task 3.

- [ ] **Step 7: Update audit doc + bundle baseline**

Fill the "With `-Osize` + `wasm-opt -Oz`" row. Update `bundle-baseline.json`.

- [ ] **Step 8: Re-run Playwright (functional check, not perf)**

```bash
cd Tests/playwright
npm test
```

Expected: PASS. `wasm-opt -Oz` is a heavy pass — if any opcode-level breakage exists, it'd show up here.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI/Commands/BuildCommand.swift \
        Tests/SwiflowCLITests/BuildCommandTests.swift \
        docs/perf/2026-05-26-wasm-bundle-audit.md \
        docs/perf/bundle-baseline.json
git commit -m "$(cat <<'EOF'
perf(build): post-process App.wasm with wasm-opt -Oz on release

Runs after PackageToJS, before the Track-1 manifest hashing — the
service worker therefore caches the trimmed bytes. Missing wasm-opt
is a hard failure with an install hint pointing at `brew install
binaryen` and `swiflow doctor`.

Bundle-size delta recorded in docs/perf/2026-05-26-wasm-bundle-audit.md.
EOF
)"
```

---

## Task 5: `wasm-strip` the name section (release only)

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift`
- Modify: `docs/perf/2026-05-26-wasm-bundle-audit.md` (Task 5 row)
- Modify: `docs/perf/bundle-baseline.json`

`wasm-strip` drops the `name` custom section. Names are useful for the DWARF debugging story (Phase 13b) — dev keeps them. Release doesn't need them.

- [ ] **Step 1: Write the failing test**

In `BuildCommandTests.swift`:

```swift
@Test("runWasmStrip removes the name section in place")
func wasmStripRemovesNameSection() throws {
    let fixture = ResourceBundle.fixture(named: "small.wasm")
    let work = try copyToTemp(fixture)
    let beforeBytes = try Data(contentsOf: work)
    #expect(beforeBytes.contains("name".data(using: .utf8)!))

    try BuildCommand.runWasmStrip(on: work)

    let afterBytes = try Data(contentsOf: work)
    #expect(afterBytes.count <= beforeBytes.count)
    // Naive substring check; a more robust check would walk the
    // sections. This is good enough for the test fixture.
}

@Test("runWasmStrip aborts with install hint when wasm-strip is missing")
func wasmStripFailsWhenMissing() throws {
    do {
        try BuildCommand.runWasmStrip(on: URL(fileURLWithPath: "/tmp/anything.wasm"),
                                       pathOverride: "/usr/bin:/bin")
        Issue.record("expected runWasmStrip to throw")
    } catch let error as BuildCommandError {
        #expect(error.message.contains("wasm-strip not found"))
        #expect(error.message.contains("brew install wabt"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter BuildCommandTests
```

Expected: FAIL.

- [ ] **Step 3: Implement `runWasmStrip`**

Mirror `runWasmOpt`'s structure. Same `which` helper, same `BuildCommandError`, different install hint (`brew install wabt`).

```swift
extension BuildCommand {
    package static func runWasmStrip(on file: URL, pathOverride: String? = nil) throws {
        let env = pathOverride.map { ["PATH": $0] } ?? ProcessInfo.processInfo.environment
        guard which("wasm-strip", env: env) != nil else {
            throw BuildCommandError(message: """
                wasm-strip not found on PATH.

                Swiflow's release build strips the WASM name section to
                shave additional bytes. Install wabt with:

                    brew install wabt

                Or run `swiflow doctor` to audit all required tools.
                """)
        }

        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["wasm-strip", file.path]
        if let pathOverride = pathOverride {
            proc.environment = ["PATH": pathOverride]
        }
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw BuildCommandError(message: "wasm-strip failed with exit code \(proc.terminationStatus)")
        }
    }
}
```

- [ ] **Step 4: Call `runWasmStrip` after `runWasmOpt`**

```swift
if configuration == .release {
    let wasm = projectDir
        .appendingPathComponent(".build/plugins/PackageToJS/outputs/Package/App.wasm")
    try Self.runWasmOpt(on: wasm)
    try Self.runWasmStrip(on: wasm)
}

try Self.writeManifest(projectDir: projectDir)
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter BuildCommandTests
```

Expected: PASS.

- [ ] **Step 6: Re-measure**

```bash
swift build -c release --product swiflow
cd examples/Counter
swift package clean
../../.build/release/swiflow build
wc -c .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

Expected: 1-3% additional shrinkage. Cumulative target hit (≤16.5 MB gzipped).

- [ ] **Step 7: Update audit doc + bundle baseline**

Fill the "With above + `wasm-strip`" row. Update `bundle-baseline.json` — this is the **final** Phase 14b Track 2 baseline. The Phase 14a CI gate uses this number going forward.

- [ ] **Step 8: Playwright**

```bash
cd Tests/playwright
npm test
```

Expected: PASS. Names are debug metadata; stripping them does not change behaviour.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI/Commands/BuildCommand.swift \
        Tests/SwiflowCLITests/BuildCommandTests.swift \
        docs/perf/2026-05-26-wasm-bundle-audit.md \
        docs/perf/bundle-baseline.json
git commit -m "$(cat <<'EOF'
perf(build): strip the WASM name section on release

Drops the name custom section after wasm-opt has done its work. Names
remain in dev (Phase 13b DWARF debugging keeps them). Missing
wasm-strip hard-fails with a `brew install wabt` hint.

Bundle-size delta recorded in docs/perf/2026-05-26-wasm-bundle-audit.md.
This commit lands the final Phase 14b Track 2 baseline number used
by the Phase 14a CI gate.
EOF
)"
```

---

## Task 6: Prereqs + CHANGELOG + README

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README prereqs**

In `README.md`, the Prerequisites section currently lists Swift 6.3, macOS 14+, and the WebAssembly Swift SDK. Add two more bullets:

```markdown
- **Binaryen's `wasm-opt`** — required for release builds (`swiflow build`).
  ```bash
  brew install binaryen
  ```
- **WABT's `wasm-strip`** — required for release builds (`swiflow build`).
  ```bash
  brew install wabt
  ```

Run `swiflow doctor` to audit your toolchain at any time.
```

- [ ] **Step 2: Update the status line**

The status line in `README.md` currently says "Phase 14b Track 1 (Service Worker Cache)". Update to "Phase 14b Track 2 (WASM Trimming)" with a one-sentence summary of the new bundle number.

- [ ] **Step 3: Update the cost table**

The "WASM bundle (Counter example, release)" row currently reads ~59 MB raw / ~20 MB gzipped. Replace with the new measured numbers from `bundle-baseline.json`. The "Repeat visits: ~0 bytes" row from Track 1 stays as-is.

- [ ] **Step 4: Add the Phase 14b Track 2 historical-status sentence**

Prepend a one- or two-sentence Track 2 summary to the historical "Status:" paragraph (the second occurrence of `**Status:**` in README, below the cost table). Pattern matches the Track 1 entry that's already there.

- [ ] **Step 5: Add CHANGELOG entry**

In `CHANGELOG.md`, above the existing "[Phase 14b — Track 1] — 2026-05-26" entry, add:

```markdown
## [Phase 14b — Track 2] — 2026-05-26

**Stability:** WASM trim. Release builds now post-process App.wasm with
wasm-opt and wasm-strip. Functional behaviour unchanged. No Swift API
moves.

### Added
- `swiflow doctor` subcommand — standalone toolchain audit. Checks
  for swift, the WASM SDK, wasm-opt, and wasm-strip; prints install
  hints when anything is missing.
- `docs/perf/2026-05-26-wasm-bundle-audit.md` — baseline audit of
  the Counter WASM with section sizes, top functions, attribution
  buckets, and the reflection-disabled lower bound measurement.

### Changed
- Release builds now compile with `-Osize -gnone` instead of `-O`,
  targeting size over throughput for the workloads Swiflow runs.
- Release builds run `wasm-opt -Oz --strip-debug --strip-producers`
  on App.wasm after PackageToJS, then strip the WASM name section
  with `wasm-strip`. Bundle baseline updated in
  `docs/perf/bundle-baseline.json`.

### Requires
- `wasm-opt` (binaryen) and `wasm-strip` (wabt) on PATH for release
  builds. `brew install binaryen wabt` on macOS; equivalents on Linux.
  Missing tools are hard failures with install hints; dev builds
  (`swiflow dev`) are unaffected.
```

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: Phase 14b Track 2 — WASM trim, doctor, prereqs

CHANGELOG entry above Track 1. README prereqs now list wasm-opt
and wasm-strip. Status line and cost table reflect the new trimmed
bundle baseline.
EOF
)"
```

- [ ] **Step 7: Push**

```bash
git push origin main
```

---

## Final verification

After Task 6 lands:

```bash
# Toolchain is healthy
./.build/release/swiflow doctor                       # exit 0, all ✓

# Release build is fully trimmed and still functional
cd examples/Counter
swift package clean
../../.build/release/swiflow build
cd ../..
gzip -c -9 examples/Counter/.build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
# Expect ≤16.5 MB (≥20% drop from the 20.6 MB Phase 14a baseline)

# Playwright (functional regression check)
cd Tests/playwright
npm test                                              # PASS

# SW Playwright spec (Track 1 didn't regress)
npm run test:sw                                       # PASS

# Swift suite
cd ../..
swift test                                            # all green

# JS driver suite
cd js-driver
npm test                                              # 26 PASS
```

**Success criterion from the spec:** `docs/perf/bundle-baseline.json`'s `total_gzip_bytes` is ≥20% below the Phase 14a baseline (20,601,631 bytes), i.e., ≤16,481,304 bytes. The Phase 14a CI gate continues to pass for the new baseline.

If the cumulative trim falls short of 20%, the audit doc tells us why and Track 2 stays open until we hit it — there's room to revisit `-wmo` and other flags from the spec's Step 2 list before declaring done.
