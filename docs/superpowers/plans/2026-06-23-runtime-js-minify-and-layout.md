# Runtime JS Minify, Mode-Aware Emission & SW Rename — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship minified runtime JS in production builds (readable in dev), emit the region JS pair only when a project actually uses regions, and rename `swiflow-sw.js` → `swiflow-service-worker.js`.

**Architecture:** Minification happens at *embed/codegen time* — `scripts/embed-driver.swift` shells out to a pinned **esbuild** (a `js-driver` devDependency) and bakes both readable and minified bytes into `EmbeddedDriver.swift` as string constants, so the shipped CLI binary stays Node-free. `DriverInstaller` (called by `dev`/`build`) and `ProjectWriter` (called by `init`) become mode-aware (readable vs minified) and region-aware (write the region pair only when `index.html` references `swiflow-regions.js`).

**Tech Stack:** Swift (SwiftPM, Swift Testing), Foundation `Process`, esbuild (npm), GitHub Actions.

**Design spec:** `docs/superpowers/specs/2026-06-23-runtime-js-minify-and-layout-design.md`

---

## Background facts (read before starting)

- Source of truth for runtime JS: `js-driver/swiflow-driver.js`, `js-driver/swiflow-sw.js`, `js-driver/swiflow-regions.js`, `js-driver/swiflow-region-guest.js`.
- `scripts/embed-driver.swift` reads those 4 files and writes `Sources/SwiflowCLI/EmbeddedDriver.swift`. The wrapping logic is duplicated in `Sources/SwiflowCLI/DriverEmbedder.swift` (`DriverEmbedder.swiftSource(...)`), kept in sync by tests.
- `EmbeddedDriver` today exposes 4 constants: `javascriptSource`, `serviceWorkerSource`, `regionsSource`, `guestSdkSource`.
- `DriverInstaller.install(into:)` writes driver + sw on every `dev`/`build`. `stampServiceWorker(into:buildTag:)` re-emits the SW with a build tag.
- `ProjectWriter.writeProject(...)` (called by `swiflow init`) writes **all four** JS files into every project, unconditionally.
- 9 examples vendor `swiflow-sw.js` (`examples/{AsyncFetch,EdgeCases,HelloWorld,MiniRouter,MissionControl,QueryDemo,RegionDemo,SwiflowUIDemo,TodoCRUD}/`). Only `examples/RegionDemo/` vendors `swiflow-regions.js` + `swiflow-region-guest.js`. `examples/HelloWorld/` byte-equality is enforced by `TemplatesTests`.
- Run all Swift tests with: `swift test --no-parallel` (matches CI). If you hit "cannot find X in scope" after adding a file/symbol, run `swift package clean` first (known stale-module-cache issue).

---

## Task 1: Add pinned esbuild to the js-driver toolchain

**Files:**
- Modify: `js-driver/package.json`
- Modify: `js-driver/package-lock.json` (regenerated)

- [ ] **Step 1: Add esbuild as a pinned devDependency**

Edit `js-driver/package.json`, adding `esbuild` to `devDependencies` with an **exact** version (no `^`/`~` — determinism matters for the embed codegen):

```json
  "devDependencies": {
    "assemblyscript": "0.28.19",
    "esbuild": "0.25.5",
    "jsdom": "29.1.1"
  }
```

- [ ] **Step 2: Install and regenerate the lockfile**

Run:
```bash
cd js-driver && npm install --no-audit --no-fund && cd ..
```
Expected: `js-driver/node_modules/.bin/esbuild` now exists; `package-lock.json` updated.

- [ ] **Step 3: Verify the binary runs and is the pinned version**

Run:
```bash
js-driver/node_modules/.bin/esbuild --version
```
Expected: prints `0.25.5`.

- [ ] **Step 4: Verify per-file minify-to-stdout works (no bundling)**

Run:
```bash
js-driver/node_modules/.bin/esbuild js-driver/swiflow-driver.js --minify | head -c 80; echo
```
Expected: a single dense line of minified JS on stdout (no errors, no IIFE wrapper added).

- [ ] **Step 5: Commit**

```bash
git add js-driver/package.json js-driver/package-lock.json
git commit -m "build(js-driver): add pinned esbuild for runtime JS minification"
```

---

## Task 2: Region-usage detection predicate

A pure function used by both `DriverInstaller` and `ProjectWriter` to decide whether the region JS pair should be written. A project uses regions iff its `index.html` references `swiflow-regions.js`.

**Files:**
- Create: `Sources/SwiflowCLI/RuntimeFiles.swift`
- Test: `Tests/SwiflowCLITests/RuntimeFilesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/RuntimeFilesTests.swift`:

```swift
// Tests/SwiflowCLITests/RuntimeFilesTests.swift
import Testing
@testable import SwiflowCLI

@Suite("RuntimeFiles.usesRegions")
struct RuntimeFilesTests {

    @Test("true when index.html references the regions script")
    func positive() {
        let html = """
        <body>
          <script src="swiflow-driver.js"></script>
          <script type="module" src="swiflow-regions.js"></script>
        </body>
        """
        #expect(RuntimeFiles.usesRegions(indexHTML: html) == true)
    }

    @Test("false for a plain page with no regions reference")
    func negative() {
        let html = """
        <body>
          <script src="swiflow-driver.js"></script>
        </body>
        """
        #expect(RuntimeFiles.usesRegions(indexHTML: html) == false)
    }

    @Test("true regardless of quote style or surrounding whitespace")
    func quoteRobust() {
        #expect(RuntimeFiles.usesRegions(indexHTML: "<script src='swiflow-regions.js' >") == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --no-parallel --filter RuntimeFilesTests`
Expected: FAIL — "cannot find 'RuntimeFiles' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/SwiflowCLI/RuntimeFiles.swift`:

```swift
// Sources/SwiflowCLI/RuntimeFiles.swift
//
// Shared rules about which runtime JS files a project needs. Pure and
// side-effect-free so the predicate is unit-tested without touching disk.

import Foundation

enum RuntimeFiles {
    /// A project uses the region runtime iff its `index.html` references the
    /// regions entrypoint script. Region templates carry
    /// `<script type="module" src="swiflow-regions.js">`; plain templates do
    /// not — so this substring is the single source of truth for "is this a
    /// region project", driving whether `swiflow-regions.js` /
    /// `swiflow-region-guest.js` get emitted.
    static func usesRegions(indexHTML: String) -> Bool {
        indexHTML.contains("swiflow-regions.js")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --no-parallel --filter RuntimeFilesTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/RuntimeFiles.swift Tests/SwiflowCLITests/RuntimeFilesTests.swift
git commit -m "feat(cli): add RuntimeFiles.usesRegions region-detection predicate"
```

---

## Task 3: Rename `swiflow-sw.js` → `swiflow-service-worker.js`

A mechanical, repo-wide rename. Do it in one commit so the byte-equality and freshness tests never see a half-renamed tree. **Do not change minification yet** — this task keeps `EmbeddedDriver` at 4 readable constants.

**Files:**
- Rename: `js-driver/swiflow-sw.js` → `js-driver/swiflow-service-worker.js`
- Modify: `js-driver/swiflow-driver.js` (SW registration + stale-SW guard + comments)
- Modify: `scripts/embed-driver.swift` (path + comments)
- Modify: `Sources/SwiflowCLI/DriverEmbedder.swift` (header comment string)
- Modify: `Sources/SwiflowCLI/DriverInstaller.swift` (output filename, both methods + header comment)
- Modify: `Sources/SwiflowCLI/Project/ProjectWriter.swift` (output filename)
- Modify: `Sources/SwiflowCLI/TemplateEmbedder.swift` (blacklist entry)
- Rename: `examples/{AsyncFetch,EdgeCases,HelloWorld,MiniRouter,MissionControl,QueryDemo,RegionDemo,SwiflowUIDemo,TodoCRUD}/swiflow-sw.js` → `swiflow-service-worker.js`
- Modify: `Tests/SwiflowCLITests/DriverInstallerTests.swift`, `Tests/SwiflowCLITests/DriverEmbedderTests.swift`, `Tests/SwiflowCLITests/TemplatesTests.swift`
- Modify: any `js-driver/test/*.js` referencing the old filename
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`

- [ ] **Step 1: Rename the source file and the 9 example copies (git mv)**

```bash
git mv js-driver/swiflow-sw.js js-driver/swiflow-service-worker.js
for d in AsyncFetch EdgeCases HelloWorld MiniRouter MissionControl QueryDemo RegionDemo SwiflowUIDemo TodoCRUD; do
  git mv "examples/$d/swiflow-sw.js" "examples/$d/swiflow-service-worker.js"
done
```
Expected: 10 renames staged.

- [ ] **Step 2: Update the driver's SW registration + stale-SW guard**

In `js-driver/swiflow-driver.js`, replace the three occurrences of the old filename:
- `navigator.serviceWorker.register("swiflow-sw.js")` → `navigator.serviceWorker.register("swiflow-service-worker.js")`
- `if (!url.endsWith("/swiflow-sw.js")) continue;` → `if (!url.endsWith("/swiflow-service-worker.js")) continue;`
- The surrounding comments that mention `swiflow-sw.js` (e.g. "register swiflow-sw.js", "Unregister any stale swiflow-sw.js SW", the `my-swiflow-sw.js` false-positive example) → update the filename to `swiflow-service-worker.js` (and the false-positive example to `my-swiflow-service-worker.js`).

- [ ] **Step 3: Update the embed script + DriverEmbedder header + Swift filename writers**

- `scripts/embed-driver.swift`: change `let swPath = cwd.appendingPathComponent("js-driver/swiflow-sw.js")` → `"js-driver/swiflow-service-worker.js"`, and update the two header/`Source:` comments that list `swiflow-sw.js`.
- `Sources/SwiflowCLI/DriverEmbedder.swift`: in the generated header `// Source: ... swiflow-sw.js ...`, change to `swiflow-service-worker.js` (must match the script's header exactly).
- `Sources/SwiflowCLI/DriverInstaller.swift`: both `appendingPathComponent("swiflow-sw.js")` occurrences (in `install` and `stampServiceWorker`) → `"swiflow-service-worker.js"`, and update the file header comment.
- `Sources/SwiflowCLI/Project/ProjectWriter.swift`: `appendingPathComponent("swiflow-sw.js")` → `"swiflow-service-worker.js"`.
- `Sources/SwiflowCLI/TemplateEmbedder.swift`: in `blacklist`, `"swiflow-sw.js"` → `"swiflow-service-worker.js"`.

- [ ] **Step 4: Update js-driver tests that name the file**

Run to find them:
```bash
grep -rln "swiflow-sw.js" js-driver/test
```
For each hit (e.g. `sw.test.js`, `sw-registration.test.js`), replace `swiflow-sw.js` → `swiflow-service-worker.js`. Then:
```bash
cd js-driver && npm test && cd ..
```
Expected: PASS (driver tests green with the new registration target).

- [ ] **Step 5: Update the Swift tests that name the file**

- `Tests/SwiflowCLITests/DriverInstallerTests.swift`: every `"swiflow-sw.js"` → `"swiflow-service-worker.js"` (test bodies + `@Test` descriptions).
- `Tests/SwiflowCLITests/DriverEmbedderTests.swift`: in `swSourceIsFresh`, the path `js-driver/swiflow-sw.js` → `js-driver/swiflow-service-worker.js`. In `embeddedDriverMatchesDriverEmbedderOutput`, the `swURL` path likewise.
- `Tests/SwiflowCLITests/TemplatesTests.swift`: the `exampleServiceWorkerMatchesCanonical` test — path `js-driver/swiflow-sw.js` → `js-driver/swiflow-service-worker.js`, `exampleFile("swiflow-sw.js")` → `exampleFile("swiflow-service-worker.js")`, and the `@Test` description.

- [ ] **Step 6: Regenerate EmbeddedDriver and re-vendor the example driver copies**

The driver source changed (Step 2), so regenerate and push the canonical driver/sw over every example:
```bash
swift scripts/embed-driver.swift
for d in AsyncFetch EdgeCases HelloWorld MiniRouter MissionControl QueryDemo RegionDemo SwiflowUIDemo TodoCRUD; do
  cp js-driver/swiflow-driver.js "examples/$d/swiflow-driver.js"
  cp js-driver/swiflow-service-worker.js "examples/$d/swiflow-service-worker.js"
done
cp js-driver/swiflow-regions.js examples/RegionDemo/swiflow-regions.js
cp js-driver/swiflow-region-guest.js examples/RegionDemo/swiflow-region-guest.js
```

- [ ] **Step 7: Verify no stale references remain**

Run:
```bash
grep -rn "swiflow-sw\.js" Sources js-driver scripts examples Tests | grep -v CHANGELOG
```
Expected: **no output** (every reference migrated).

- [ ] **Step 8: Run the full Swift suite**

Run: `swift test --no-parallel`
Expected: PASS (freshness + byte-equality green under the new name). If "cannot find in scope", run `swift package clean` and retry.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(runtime): rename swiflow-sw.js -> swiflow-service-worker.js

Sweeps the driver's register()/stale-SW guard, embed codegen, installers,
blacklist, 9 vendored example copies, and tests. Regenerates EmbeddedDriver.
Pre-1.0: already-deployed swiflow-sw.js workers are not auto-unregistered."
```

---

## Task 4: Embed minified variants (8 constants)

Teach the embed pipeline to produce a minified variant of each file via esbuild, so `EmbeddedDriver` exposes 8 constants. `DriverEmbedder.swiftSource` becomes a pure wrapper of 8 strings; the embed script computes the minified inputs.

**Files:**
- Modify: `Sources/SwiflowCLI/DriverEmbedder.swift`
- Modify: `scripts/embed-driver.swift`
- Modify: `Tests/SwiflowCLITests/DriverEmbedderTests.swift`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`

- [ ] **Step 1: Extend DriverEmbedder.swiftSource to wrap 8 constants**

In `Sources/SwiflowCLI/DriverEmbedder.swift`, change the signature and body so it accepts a minified counterpart for each source and emits 8 `static let`s. New signature:

```swift
static func swiftSource(
    driverJS: String, driverJSMinified: String,
    swJS: String, swJSMinified: String,
    regionsJS: String, regionsJSMinified: String,
    guestSdkJS: String, guestSdkJSMinified: String
) -> String {
```

Emit, in this order (keep the existing `#"""` raw-string wrapping pattern — interpolation on its own line, `"""#` on the next — for each):
`javascriptSource`, `javascriptSourceMinified`, `serviceWorkerSource`, `serviceWorkerSourceMinified`, `regionsSource`, `regionsSourceMinified`, `guestSdkSource`, `guestSdkSourceMinified`. Update the `// Source:` header comment to note the minified variants are esbuild-generated.

- [ ] **Step 2: Update the DriverEmbedder unit test to the 8-arg shape**

In `Tests/SwiflowCLITests/DriverEmbedderTests.swift`, update `wrapsJSAsSwiftConstant` to pass 8 stub strings and assert all 8 constant names + all 8 stub bodies appear. **Delete** the `embeddedDriverMatchesDriverEmbedderOutput` test — it cannot reconstruct the minified inputs without esbuild; its guarantee is replaced by the CI regen+diff gate in Task 8. Leave the readable freshness tests (`embeddedDriverIsFresh`, `regionsSourceIsFresh`, `guestSdkSourceIsFresh`, `swSourceIsFresh`) **unchanged** — they compare readable constants to on-disk files and need no esbuild.

```swift
    @Test("DriverEmbedder.swiftSource wraps all eight JS sources as Swift constants")
    func wrapsJSAsSwiftConstant() {
        let g = DriverEmbedder.swiftSource(
            driverJS: "DRIVER", driverJSMinified: "DRIVERMIN",
            swJS: "SW", swJSMinified: "SWMIN",
            regionsJS: "REGIONS", regionsJSMinified: "REGIONSMIN",
            guestSdkJS: "GUEST", guestSdkJSMinified: "GUESTMIN"
        )
        for name in ["javascriptSource", "javascriptSourceMinified",
                     "serviceWorkerSource", "serviceWorkerSourceMinified",
                     "regionsSource", "regionsSourceMinified",
                     "guestSdkSource", "guestSdkSourceMinified"] {
            #expect(g.contains("static let \(name): String"))
        }
        for body in ["DRIVER", "DRIVERMIN", "SW", "SWMIN", "REGIONS", "REGIONSMIN", "GUEST", "GUESTMIN"] {
            #expect(g.contains(body))
        }
    }
```

- [ ] **Step 3: Teach the embed script to minify via esbuild**

In `scripts/embed-driver.swift`, add a helper that shells out to the pinned esbuild and returns minified bytes (with a trailing newline appended so the raw-string wrapping stays uniform), then pass all 8 strings to the inline wrapper. Add near the top (after the reads):

```swift
func minify(_ path: URL, esm: Bool) -> String {
    let esbuild = cwd.appendingPathComponent("js-driver/node_modules/.bin/esbuild")
    guard fm.isExecutableFile(atPath: esbuild.path) else {
        FileHandle.standardError.write(Data("error: \(esbuild.path) not found — run `npm ci` in js-driver/\n".utf8))
        exit(1)
    }
    let proc = Process()
    proc.executableURL = esbuild
    proc.arguments = [path.path, "--minify"] + (esm ? ["--format=esm"] : [])
    let out = Pipe(), errPipe = Pipe()
    proc.standardOutput = out
    proc.standardError = errPipe
    do { try proc.run() } catch {
        FileHandle.standardError.write(Data("error: failed to launch esbuild: \(error)\n".utf8))
        exit(1)
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        let msg = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        FileHandle.standardError.write(Data("error: esbuild failed for \(path.lastPathComponent):\n\(msg)\n".utf8))
        exit(1)
    }
    var s = String(decoding: data, as: UTF8.self)
    if !s.hasSuffix("\n") { s += "\n" }   // keep the raw-string wrapping uniform
    return s
}

let jsMin       = minify(jsPath, esm: false)
let swMin       = minify(swPath, esm: false)
let regionsMin  = minify(regionsPath, esm: true)
let guestSdkMin = minify(guestSdkPath, esm: true)
```

Then replace the inline `let output = """ ... """` block so it emits 8 constants in the same order as `DriverEmbedder` (Task 4 Step 1). Keep the inline format byte-identical to `DriverEmbedder.swiftSource` output — the readable freshness tests and the Task 8 CI gate both depend on it.

- [ ] **Step 4: Regenerate EmbeddedDriver**

Run: `swift scripts/embed-driver.swift`
Expected: prints `wrote .../EmbeddedDriver.swift (<bytes>)`; the file now has 8 constants.

- [ ] **Step 5: Add a structural test for the minified constants**

Append to `Tests/SwiflowCLITests/DriverEmbedderTests.swift`:

```swift
    @Test("minified constants are non-empty, shorter, and collapsed to one line")
    func minifiedConstantsLookMinified() {
        for (readable, min) in [
            (EmbeddedDriver.javascriptSource, EmbeddedDriver.javascriptSourceMinified),
            (EmbeddedDriver.serviceWorkerSource, EmbeddedDriver.serviceWorkerSourceMinified),
            (EmbeddedDriver.regionsSource, EmbeddedDriver.regionsSourceMinified),
            (EmbeddedDriver.guestSdkSource, EmbeddedDriver.guestSdkSourceMinified),
        ] {
            #expect(!min.isEmpty)
            #expect(min.utf8.count < readable.utf8.count)
            // Minified output is essentially one line (+ trailing newline).
            #expect(min.split(separator: "\n").count <= 2)
        }
    }

    @Test("minified service worker keeps the build-tag placeholder for stamping")
    func minifiedSWKeepsBuildTagPlaceholder() {
        #expect(EmbeddedDriver.serviceWorkerSourceMinified.contains("__SWIFLOW_BUILD_TAG__"))
    }
```

- [ ] **Step 6: Run the suite**

Run: `swift test --no-parallel --filter DriverEmbedderTests`
Expected: PASS (readable freshness, 8-constant wrap, minified structural checks). Then run the full `swift test --no-parallel` to confirm nothing else broke.

- [ ] **Step 7: Commit**

```bash
git add scripts/embed-driver.swift Sources/SwiflowCLI/DriverEmbedder.swift Sources/SwiflowCLI/EmbeddedDriver.swift Tests/SwiflowCLITests/DriverEmbedderTests.swift
git commit -m "feat(runtime): embed esbuild-minified variants of the runtime JS"
```

---

## Task 5: Make DriverInstaller mode-aware and region-aware

`install` gains a `minified:` flag, writes the region pair only when the project's `index.html` uses regions, and `stampServiceWorker` gains a `minified:` flag.

**Files:**
- Modify: `Sources/SwiflowCLI/DriverInstaller.swift`
- Modify: `Tests/SwiflowCLITests/DriverInstallerTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace the bodies of `DriverInstallerTests` to exercise the new API. Key new tests:

```swift
    @Test("dev (minified:false) writes readable driver + service worker")
    func devWritesReadable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: false)
        let driver = try String(contentsOf: dir.appendingPathComponent("swiflow-driver.js"), encoding: .utf8)
        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-service-worker.js"), encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSource)
        #expect(sw == EmbeddedDriver.serviceWorkerSource)
    }

    @Test("build (minified:true) writes minified driver + service worker")
    func buildWritesMinified() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: true)
        let driver = try String(contentsOf: dir.appendingPathComponent("swiflow-driver.js"), encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSourceMinified)
    }

    @Test("no index.html → region files are not written")
    func plainProjectGetsNoRegionFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: false)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("swiflow-regions.js").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("swiflow-region-guest.js").path))
    }

    @Test("index.html referencing regions → region pair is written (variant follows minified)")
    func regionProjectGetsRegionFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "<script type=\"module\" src=\"swiflow-regions.js\"></script>\n"
            .write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try DriverInstaller.install(into: dir, minified: false)
        let regions = try String(contentsOf: dir.appendingPathComponent("swiflow-regions.js"), encoding: .utf8)
        let guest = try String(contentsOf: dir.appendingPathComponent("swiflow-region-guest.js"), encoding: .utf8)
        #expect(regions == EmbeddedDriver.regionsSource)
        #expect(guest == EmbeddedDriver.guestSdkSource)
    }

    @Test("stampServiceWorker(minified:true) stamps the minified SW variant")
    func stampMinified() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: true)
        try DriverInstaller.stampServiceWorker(into: dir, buildTag: "deadbeefcafe", minified: true)
        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-service-worker.js"), encoding: .utf8)
        #expect(sw.contains("deadbeefcafe"))
        #expect(!sw.contains("__SWIFLOW_BUILD_TAG__"))
    }
```

Keep `embeddedServiceWorkerCarriesThePlaceholder` (readable) as-is.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter DriverInstallerTests`
Expected: FAIL — `install`/`stampServiceWorker` don't accept `minified:`.

- [ ] **Step 3: Implement the mode-aware installer**

Rewrite `Sources/SwiflowCLI/DriverInstaller.swift`:

```swift
import Foundation

enum DriverInstaller {
    /// Writes the runtime JS into `projectDir`, overwriting existing copies.
    /// `swiflow-driver.js` + `swiflow-service-worker.js` are always written.
    /// The region pair (`swiflow-regions.js` + `swiflow-region-guest.js`) is
    /// written only when the project's `index.html` references the regions
    /// script (see `RuntimeFiles.usesRegions`). `minified` selects the
    /// readable (dev) or esbuild-minified (build) variant.
    static func install(into projectDir: URL, minified: Bool) throws {
        let driver = minified ? EmbeddedDriver.javascriptSourceMinified : EmbeddedDriver.javascriptSource
        let sw = minified ? EmbeddedDriver.serviceWorkerSourceMinified : EmbeddedDriver.serviceWorkerSource
        try driver.write(to: projectDir.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
        try sw.write(to: projectDir.appendingPathComponent("swiflow-service-worker.js"), atomically: true, encoding: .utf8)

        guard projectUsesRegions(projectDir) else { return }
        let regions = minified ? EmbeddedDriver.regionsSourceMinified : EmbeddedDriver.regionsSource
        let guest = minified ? EmbeddedDriver.guestSdkSourceMinified : EmbeddedDriver.guestSdkSource
        try regions.write(to: projectDir.appendingPathComponent("swiflow-regions.js"), atomically: true, encoding: .utf8)
        try guest.write(to: projectDir.appendingPathComponent("swiflow-region-guest.js"), atomically: true, encoding: .utf8)
    }

    /// Re-emits the service worker with the build tag stamped in. `minified`
    /// must match the variant written by `install` for this build so the
    /// served SW stays consistent.
    static func stampServiceWorker(into projectDir: URL, buildTag: String, minified: Bool) throws {
        let base = minified ? EmbeddedDriver.serviceWorkerSourceMinified : EmbeddedDriver.serviceWorkerSource
        let stamped = base.replacingOccurrences(of: "__SWIFLOW_BUILD_TAG__", with: buildTag)
        try stamped.write(to: projectDir.appendingPathComponent("swiflow-service-worker.js"), atomically: true, encoding: .utf8)
    }

    private static func projectUsesRegions(_ projectDir: URL) -> Bool {
        let indexURL = projectDir.appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: indexURL, encoding: .utf8) else { return false }
        return RuntimeFiles.usesRegions(indexHTML: html)
    }
}
```

Keep the file's existing header comment, updating it to describe the `minified` + region-aware behavior.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --no-parallel --filter DriverInstallerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DriverInstaller.swift Tests/SwiflowCLITests/DriverInstallerTests.swift
git commit -m "feat(cli): mode-aware + region-aware DriverInstaller"
```

---

## Task 6: Wire dev (readable) and build (minified) call sites

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/DevCommand.swift:63`
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` (the `install` call ~325 and the `stampServiceWorker` call ~338)

- [ ] **Step 1: dev → readable**

In `Sources/SwiflowCLI/Commands/DevCommand.swift`, change:
```swift
try DriverInstaller.install(into: projectURL)
```
to:
```swift
try DriverInstaller.install(into: projectURL, minified: false)
```

- [ ] **Step 2: build → minified (install + stamp)**

In `Sources/SwiflowCLI/Commands/BuildCommand.swift`, change the install call:
```swift
try DriverInstaller.install(into: projectURL, minified: true)
```
and the stamp call:
```swift
try DriverInstaller.stampServiceWorker(into: projectURL, buildTag: String(tag), minified: true)
```

- [ ] **Step 3: Build the CLI to confirm both call sites compile**

Run: `swift build --product swiflow`
Expected: builds cleanly (no other callers of the old signatures — verify with `grep -rn "DriverInstaller.install\|stampServiceWorker" Sources` showing only these sites).

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowCLI/Commands/DevCommand.swift Sources/SwiflowCLI/Commands/BuildCommand.swift
git commit -m "feat(cli): dev serves readable runtime, build serves minified"
```

---

## Task 7: ProjectWriter emits region files only for region templates

`swiflow init` must stop writing the region pair into non-region projects. Detect from the rendered `index.html` using the same predicate.

**Files:**
- Modify: `Sources/SwiflowCLI/Project/ProjectWriter.swift`
- Test: `Tests/SwiflowCLITests/ProjectWriterTests.swift` (create if absent)

- [ ] **Step 1: Write the failing tests**

Create/extend `Tests/SwiflowCLITests/ProjectWriterTests.swift`. Use real embedded templates: `HelloWorld` (plain) must get **no** region files; a region template's index.html triggers them. (If no region starter template is embedded, drive the predicate-path via a hand-built `EmbeddedTemplates.Template` whose `index.html` references `swiflow-regions.js`.)

```swift
// Tests/SwiflowCLITests/ProjectWriterTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("ProjectWriter region emission")
struct ProjectWriterRegionTests {
    private func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("swiflow-pw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test("a plain template scaffolds no region JS")
    func plainTemplateNoRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tpl = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        try ProjectWriter.writeProject(
            name: "Plain", template: tpl, into: parent, swiflowDep: .versioned("0.0.0"),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Plain")
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-regions.js").path))
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-region-guest.js").path))
    }

    @Test("a region template scaffolds the region JS pair")
    func regionTemplateWritesRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tpl = EmbeddedTemplates.Template(
            name: "RegionStub",
            files: [("index.html", "<script type=\"module\" src=\"swiflow-regions.js\"></script>\n"),
                    ("Package.swift", "// {{SWIFLOW_DEP}}\n")]
        )
        try ProjectWriter.writeProject(
            name: "Reg", template: tpl, into: parent, swiflowDep: .versioned("0.0.0"),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Reg")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-regions.js"), encoding: .utf8) == "R")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-region-guest.js"), encoding: .utf8) == "G")
    }
}
```

> Note: confirm the exact `SwiflowDep` case (e.g. `.versioned(...)`) and `EmbeddedTemplates.Template` initializer against the current source before running; adjust the constructor calls to match.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ProjectWriterRegionTests`
Expected: FAIL — `plainTemplateNoRegions` fails because region files are currently always written.

- [ ] **Step 3: Implement conditional region writes**

In `Sources/SwiflowCLI/Project/ProjectWriter.swift`, after the template-files loop and the driver+sw writes, gate the region pair on the rendered `index.html`:

```swift
// Region runtime is written only when the template's index.html uses it,
// so plain projects don't carry ~15KB of unused region JS. dev/build
// re-emit on the same rule (see DriverInstaller).
let indexHTML = template.files.first { $0.relativePath == "index.html" }
    .map { Templates.render($0.contents, name: name, swiflowDep: swiflowDep) } ?? ""
if RuntimeFiles.usesRegions(indexHTML: indexHTML) {
    try jsRegionsSource.write(
        to: project.appendingPathComponent("swiflow-regions.js"),
        atomically: true, encoding: .utf8
    )
    try jsGuestSdkSource.write(
        to: project.appendingPathComponent("swiflow-region-guest.js"),
        atomically: true, encoding: .utf8
    )
}
```

Remove the previous unconditional `jsRegionsSource.write` / `jsGuestSdkSource.write` block. Update the method's doc comment to note region files are conditional.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --no-parallel --filter ProjectWriterRegionTests`
Expected: PASS. Then `swift test --no-parallel` — fix any `TemplatesTests` round-trip expectations that assumed region files for non-region templates (there should be none, since only RegionDemo vendors them).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Project/ProjectWriter.swift Tests/SwiflowCLITests/ProjectWriterTests.swift
git commit -m "feat(init): scaffold region JS only for region templates"
```

---

## Task 8: CI minified-freshness gate, CHANGELOG, demo build

Guarantee the committed minified bytes match a fresh esbuild run (the deterministic equivalent of the readable freshness test), document the change, and validate the demo per repo convention.

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add an embed-freshness CI job**

In `.github/workflows/ci.yml`, add a job that has both Swift and Node, regenerates `EmbeddedDriver.swift`, and fails if it differs from the committed copy. Place it as a sibling of `js-driver-tests`:

```yaml
  embed-freshness:
    name: Embedded driver is fresh (incl. minified)
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v7
      - name: Set up Swift
        uses: vapor/swiftly-action@bedb227456c5f495afbef80baebee17a8a02cef4 # v0.2.1
        with:
          toolchain: "6.3.2"
      - name: Set up Node 20
        uses: actions/setup-node@v6
        with:
          node-version: "20"
          cache: npm
          cache-dependency-path: js-driver/package-lock.json
      - name: Install JS deps (brings in pinned esbuild)
        working-directory: js-driver
        run: npm ci --no-audit --no-fund
      - name: Regenerate EmbeddedDriver.swift
        run: swift scripts/embed-driver.swift
      - name: Fail if EmbeddedDriver.swift is stale
        run: git diff --exit-code Sources/SwiflowCLI/EmbeddedDriver.swift
```

> Confirm the `toolchain:`/`with:` keys match how the existing `test` job configures `vapor/swiftly-action` (copy that job's `with:` block verbatim if it differs).

- [ ] **Step 2: Add the CHANGELOG entry**

In `CHANGELOG.md`, add a new section above `## [0.3.2]` (use the next version you intend to cut — e.g. `## [0.4.0] — 2026-06-23` since this is user-visible behavior change):

```markdown
## [0.4.0] — 2026-06-23

### Changed

- **Production builds now ship minified runtime JS.** `swiflow build` emits
  esbuild-minified `swiflow-driver.js` / `swiflow-service-worker.js` (and the
  region runtime when used); `swiflow dev` keeps the readable variant for
  debugging. The CLI binary stays Node-free — minification runs at release
  build time.
- **Region JS is scaffolded only when used.** Plain projects no longer carry
  `swiflow-regions.js` / `swiflow-region-guest.js` (~15KB of previously-dead
  files).
- **Renamed `swiflow-sw.js` → `swiflow-service-worker.js`** for clarity.

### Migration

- An already-deployed `swiflow-sw.js` service worker is not auto-unregistered
  by the renamed worker. Re-deploy and hard-reload; or unregister the old SW
  manually in DevTools → Application → Service Workers.
```

Also bump `Sources/SwiflowCLI/SwiflowVersion.swift` `current` to `"0.4.0"` if you intend to release this (coordinate with the actual release per repo protocol).

- [ ] **Step 3: Build the SwiflowUIDemo locally (CI skips example builds)**

Per repo convention, CI never compiles the examples — build the demo to catch breakage the rename/minify might cause:
```bash
swift build -c release --product swiflow
.build/release/swiflow build --path examples/SwiflowUIDemo
```
Expected: build completes; the output dir contains `swiflow-driver.js` + `swiflow-service-worker.js` (minified — single dense line). Spot-check:
```bash
head -c 60 examples/SwiflowUIDemo/swiflow-service-worker.js; echo
```
Expected: dense minified JS (not the readable multi-line source).

- [ ] **Step 4: Final full verification**

Run:
```bash
swift test --no-parallel
cd js-driver && npm test && cd ..
grep -rn "swiflow-sw\.js" Sources js-driver scripts examples Tests | grep -v CHANGELOG
```
Expected: Swift suite PASS, JS driver tests PASS, grep returns **no output**.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml CHANGELOG.md Sources/SwiflowCLI/SwiflowVersion.swift
git commit -m "ci(runtime): gate EmbeddedDriver freshness incl. minified; changelog"
```

---

## Self-review notes (addressed)

- **Spec coverage:** Piece 1 (minify at embed time) → Tasks 1, 4. Piece 2 (mode-aware + region-aware emission) → Tasks 2, 5, 6, 7. Piece 3 (SW rename) → Task 3. Testing section → region-detection (Task 2), mode selection (Task 5), minified-correctness via js-driver tests on the renamed SW + structural checks (Tasks 3, 4), plain-project-has-no-region-JS (Tasks 5, 7), freshness determinism (Task 8 CI gate). Non-goals (no bundling, no relocation, no source maps) are respected — no task moves files into a subfolder or adds maps.
- **Determinism:** esbuild pinned exactly (Task 1); CI regen+diff (Task 8) is the authoritative minified-freshness guarantee, replacing the deleted `embeddedDriverMatchesDriverEmbedderOutput` unit test.
- **Type consistency:** `install(into:minified:)` and `stampServiceWorker(into:buildTag:minified:)` used identically in Tasks 5 and 6. `RuntimeFiles.usesRegions(indexHTML:)` defined in Task 2, consumed in Tasks 5 and 7. The 8 `EmbeddedDriver` constant names are fixed in Task 4 and reused verbatim in Task 5.
- **Open verification points flagged inline:** exact `SwiflowDep` case + `EmbeddedTemplates.Template` initializer (Task 7 Step 1); the `vapor/swiftly-action` `with:` block (Task 8 Step 1). Confirm against current source when executing those steps.
