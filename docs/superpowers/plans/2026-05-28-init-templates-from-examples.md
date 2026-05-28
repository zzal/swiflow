# `swiflow init` — Templates From `examples/` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the inline template string constants in `Sources/SwiflowCLI/Templates/Templates.swift` and source `swiflow init` scaffolding from `examples/*/` via build-time codegen, with `--template <name>` selecting which example to scaffold (default `HelloWorld`).

**Architecture:** Mirror the existing `EmbeddedDriver` pattern. A standalone script (`scripts/embed-templates.swift`) walks `examples/`, normalizes per-example tokens, and emits a generated `Sources/SwiflowCLI/EmbeddedTemplates.swift`. The CLI consumes the generated file; a freshness test (`TemplateEmbedderTests`) asserts the on-disk generated file matches what the in-process codegen helper would produce now.

**Tech Stack:** Swift 6, Swift Testing, ArgumentParser, FileManager. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-28-init-templates-from-examples-design.md`

---

## File Structure

**New:**
- `Sources/SwiflowCLI/TemplateEmbedder.swift` — pure codegen helper (no I/O writes; reads `examples/` and returns Swift source string). Mirror of `Sources/SwiflowCLI/DriverEmbedder.swift`.
- `Sources/SwiflowCLI/EmbeddedTemplates.swift` — generated file containing all examples as `[Template]`. Mirror of `Sources/SwiflowCLI/EmbeddedDriver.swift`.
- `scripts/embed-templates.swift` — thin shell wrapper around `TemplateEmbedder` logic (re-implemented inline, since the script can't import `SwiflowCLI`). Mirror of `scripts/embed-driver.swift`.
- `Tests/SwiflowCLITests/TemplateEmbedderTests.swift` — freshness test + parity test. Mirror of `DriverEmbedderTests.swift`.
- `examples/MiniRouter/.gitignore`, `examples/MiniRouter/README.md`, `examples/RouterDemo/README.md` — example readiness.

**Modified:**
- `Sources/SwiflowCLI/Templates/Templates.swift` — collapses to `SwiflowDep` enum + a small `render(_:name:swiflowDep:)` helper.
- `Sources/SwiflowCLI/Project/ProjectWriter.swift` — accepts a `template: EmbeddedTemplates.Template` parameter and walks `template.files`.
- `Sources/SwiflowCLI/Commands/InitCommand.swift` — adds `--template <name>` flag (default `HelloWorld`); looks up the template before delegating.
- `Tests/SwiflowCLITests/TemplatesTests.swift` — replaces per-file byte-equality tests with template round-trip tests + blacklist coverage assertion.
- `Tests/SwiflowCLITests/InitCommandTests.swift` — adds `--template` parametric cases; signature update for the new `template:` parameter on `ProjectWriter.writeProject`.
- `examples/MiniRouter/index.html` — modernized to match HelloWorld/RouterDemo pattern (drops the legacy `<script type="module">` block).

---

### Task 1: Add `TemplateEmbedder` (pure helper, no I/O writes)

**Files:**
- Create: `Sources/SwiflowCLI/TemplateEmbedder.swift`
- Test: `Tests/SwiflowCLITests/TemplateEmbedderTests.swift` (created in Task 3; this task adds the file used by it)

This task adds the pure helper. The generated `EmbeddedTemplates.swift` arrives in Task 2; the freshness test arrives in Task 3.

- [ ] **Step 1: Write a failing unit test for `normalize`**

Create `Tests/SwiflowCLITests/TemplateEmbedderTests.swift`:

```swift
// Tests/SwiflowCLITests/TemplateEmbedderTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Template embedding")
struct TemplateEmbedderTests {

    // MARK: - normalize()

    @Test("normalize replaces literal example name with {{NAME}}")
    func normalizeReplacesName() {
        let raw = #"let package = Package(name: "MiniRouter", ...)"#
        let out = TemplateEmbedder.normalize(raw, exampleName: "MiniRouter", relativePath: "Package.swift")
        #expect(out.contains(#"name: "{{NAME}}""#))
        #expect(!out.contains("MiniRouter"))
    }

    @Test("normalize swaps .package(path: \"../..\") for {{SWIFLOW_DEP}} in Package.swift only")
    func normalizeSwapsSwiflowDep() {
        let pkg = #".package(path: "../..")"#
        let out = TemplateEmbedder.normalize(pkg, exampleName: "HelloWorld", relativePath: "Package.swift")
        #expect(out == "{{SWIFLOW_DEP}}")
    }

    @Test("normalize leaves .package(path: \"../..\") alone outside Package.swift")
    func normalizeSwiflowDepOnlyInPackage() {
        let txt = #"some docs mention .package(path: "../..") in prose"#
        let out = TemplateEmbedder.normalize(txt, exampleName: "HelloWorld", relativePath: "README.md")
        #expect(out.contains(#".package(path: "../..")"#),
                "non-Package.swift files keep the literal — SWIFLOW_DEP is Package.swift-only")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TemplateEmbedderTests`

Expected: Compile error — `TemplateEmbedder` not defined.

- [ ] **Step 3: Create `TemplateEmbedder.swift`**

Create `Sources/SwiflowCLI/TemplateEmbedder.swift`:

```swift
// Sources/SwiflowCLI/TemplateEmbedder.swift
//
// Pure codegen helper used by both the codegen script
// (scripts/embed-templates.swift) and the freshness test
// (Tests/SwiflowCLITests/TemplateEmbedderTests.swift). Same shape as
// DriverEmbedder.swift.
//
// Walks `examples/`, normalizes per-example tokens, and produces the
// Swift source for `EmbeddedTemplates.swift`. No file writes — the
// caller decides what to do with the returned string.

import Foundation

enum TemplateEmbedder {

    /// File / directory names excluded from every template.
    /// - `.build`, `Package.resolved`, `.DS_Store`: build artifacts and OS files.
    /// - `swiflow-driver.js`, `swiflow-sw.js`, `swiflow-manifest.json`:
    ///   the JS driver + service worker come from EmbeddedDriver (which is
    ///   itself codegen'd from js-driver/). Keeping them out of the template
    ///   avoids two paths for the same canonical bytes.
    static let blacklist: Set<String> = [
        ".build",
        ".DS_Store",
        "Package.resolved",
        "swiflow-driver.js",
        "swiflow-sw.js",
        "swiflow-manifest.json",
    ]

    struct TemplateData {
        let name: String
        /// Sorted by `relativePath` for deterministic codegen output.
        let files: [(relativePath: String, contents: String)]
    }

    // MARK: - Pure substitution (heavily tested)

    /// Applies the two codegen-time substitutions to a file's raw contents.
    ///
    /// - `{{NAME}}` ← every literal occurrence of `exampleName`.
    /// - `{{SWIFLOW_DEP}}` ← the literal line `.package(path: "../..")`, but
    ///   only in `Package.swift`. (We require all examples to use that exact
    ///   form so the substitution can stay a single dumb string replace.)
    static func normalize(_ raw: String, exampleName: String, relativePath: String) -> String {
        var out = raw.replacingOccurrences(of: exampleName, with: "{{NAME}}")
        if relativePath == "Package.swift" {
            out = out.replacingOccurrences(
                of: #".package(path: "../..")"#,
                with: "{{SWIFLOW_DEP}}"
            )
        }
        return out
    }

    // MARK: - Filesystem walk

    /// Walks `examplesRoot/*/`, collecting every template directory and its
    /// non-blacklisted files. Returns `TemplateData` sorted by name (so
    /// codegen output is deterministic regardless of directory enumeration order).
    static func collect(examplesRoot: URL) throws -> [TemplateData] {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: examplesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let templateDirs = entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && !blacklist.contains(url.lastPathComponent)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try templateDirs.map { dir in
            let name = dir.lastPathComponent
            let files = try collectFiles(in: dir, exampleName: name)
            return TemplateData(name: name, files: files)
        }
    }

    /// Recursively collects non-blacklisted files. Returns relative paths
    /// (POSIX-style, slash-separated) sorted alphabetically for determinism.
    static func collectFiles(in dir: URL, exampleName: String) throws -> [(relativePath: String, contents: String)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        var results: [(String, String)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if blacklist.contains(name) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir { continue }

            let rel = Self.relativePath(from: dir, to: url)
            let raw = try String(contentsOf: url, encoding: .utf8)
            let normalized = normalize(raw, exampleName: exampleName, relativePath: rel)
            results.append((rel, normalized))
        }
        return results.sorted { $0.0 < $1.0 }
    }

    private static func relativePath(from base: URL, to file: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return String(file.path.dropFirst(basePath.count))
    }

    // MARK: - Swift source emission

    /// Produces the Swift source for `EmbeddedTemplates.swift`.
    ///
    /// Layout: `enum EmbeddedTemplates { struct Template; static let all: [Template]; lookup; availableNames }`.
    /// File contents are emitted as `#"""..."""#` raw-string literals with
    /// the closing `"""#` at column 0 — Swift then strips zero indentation,
    /// preserving each file's contents byte-for-byte. The leading `\n` after
    /// `#"""` and the trailing `\n` before `"""#` are stripped by Swift's
    /// multi-line rules, which is why we wrap as `\n{contents}\n`: the file
    /// contents already end in `\n`, and that final `\n` is preserved (it's
    /// the `\n` after that — the one we emit — that gets stripped).
    static func swiftSource(examplesRoot: URL) throws -> String {
        let templates = try collect(examplesRoot: examplesRoot)

        var out = """
        // GENERATED FILE — do not edit.
        //
        // Regenerate by running, from the repo root:
        //     swift scripts/embed-templates.swift
        //
        // Source: examples/*/

        enum EmbeddedTemplates {
            struct Template {
                let name: String
                let files: [String: String]
            }

            static let all: [Template] = [

        """

        for t in templates {
            out += "        Template(\n"
            out += "            name: \"\(t.name)\",\n"
            out += "            files: [\n"
            for (path, contents) in t.files {
                out += "                \"\(path)\": #\"\"\"\n\(contents)\n\"\"\"#,\n"
            }
            out += "            ]\n"
            out += "        ),\n"
        }

        out += """
            ]

            static func lookup(_ name: String) -> Template? {
                return all.first(where: { $0.name == name })
            }

            static var availableNames: [String] {
                return all.map(\\.name)
            }
        }

        """

        return out
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TemplateEmbedderTests`

Expected: `Test run with X tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/TemplateEmbedder.swift Tests/SwiflowCLITests/TemplateEmbedderTests.swift
git commit -m "$(cat <<'EOF'
feat(cli): add TemplateEmbedder pure codegen helper

Walks examples/*, normalizes per-example tokens ({{NAME}} and
{{SWIFLOW_DEP}}), and produces Swift source for the upcoming
EmbeddedTemplates.swift. Mirrors DriverEmbedder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add `scripts/embed-templates.swift` + generate `EmbeddedTemplates.swift`

**Files:**
- Create: `scripts/embed-templates.swift`
- Create: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (generated by the script)

The script re-implements `TemplateEmbedder` logic inline (it runs standalone and can't `import SwiflowCLI`). The freshness test in Task 3 catches drift.

- [ ] **Step 1: Create the script**

Create `scripts/embed-templates.swift`:

```swift
#!/usr/bin/env swift
// scripts/embed-templates.swift
//
// One-shot codegen script. Run from the repo root:
//
//     swift scripts/embed-templates.swift
//
// Walks examples/*/, normalizes per-example tokens, and writes
// Sources/SwiflowCLI/EmbeddedTemplates.swift.
//
// The logic is duplicated from Sources/SwiflowCLI/TemplateEmbedder.swift
// because the script runs standalone (no SPM context, can't import
// SwiflowCLI). The TemplateEmbedderTests freshness test catches drift
// between this script and TemplateEmbedder.swiftSource.

import Foundation

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let examplesRoot = cwd.appendingPathComponent("examples")
let outPath = cwd.appendingPathComponent("Sources/SwiflowCLI/EmbeddedTemplates.swift")

guard fm.fileExists(atPath: examplesRoot.path) else {
    FileHandle.standardError.write(Data("error: \(examplesRoot.path) not found. Run from repo root.\n".utf8))
    exit(1)
}

let blacklist: Set<String> = [
    ".build", ".DS_Store", "Package.resolved",
    "swiflow-driver.js", "swiflow-sw.js", "swiflow-manifest.json",
]

func normalize(_ raw: String, exampleName: String, relativePath: String) -> String {
    var out = raw.replacingOccurrences(of: exampleName, with: "{{NAME}}")
    if relativePath == "Package.swift" {
        out = out.replacingOccurrences(
            of: #".package(path: "../..")"#,
            with: "{{SWIFLOW_DEP}}"
        )
    }
    return out
}

func relativePath(from base: URL, to file: URL) -> String {
    let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
    return String(file.path.dropFirst(basePath.count))
}

func collectFiles(in dir: URL, exampleName: String) throws -> [(String, String)] {
    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
        return []
    }
    var results: [(String, String)] = []
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if blacklist.contains(name) {
            if isDir { enumerator.skipDescendants() }
            continue
        }
        if isDir { continue }
        let rel = relativePath(from: dir, to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        results.append((rel, normalize(raw, exampleName: exampleName, relativePath: rel)))
    }
    return results.sorted { $0.0 < $1.0 }
}

do {
    let entries = try fm.contentsOfDirectory(
        at: examplesRoot,
        includingPropertiesForKeys: [.isDirectoryKey]
    )
    let templateDirs = entries
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !blacklist.contains(url.lastPathComponent)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var out = """
    // GENERATED FILE — do not edit.
    //
    // Regenerate by running, from the repo root:
    //     swift scripts/embed-templates.swift
    //
    // Source: examples/*/

    enum EmbeddedTemplates {
        struct Template {
            let name: String
            let files: [String: String]
        }

        static let all: [Template] = [

    """

    for dir in templateDirs {
        let name = dir.lastPathComponent
        let files = try collectFiles(in: dir, exampleName: name)
        out += "        Template(\n"
        out += "            name: \"\(name)\",\n"
        out += "            files: [\n"
        for (path, contents) in files {
            out += "                \"\(path)\": #\"\"\"\n\(contents)\n\"\"\"#,\n"
        }
        out += "            ]\n"
        out += "        ),\n"
    }

    out += """
        ]

        static func lookup(_ name: String) -> Template? {
            return all.first(where: { $0.name == name })
        }

        static var availableNames: [String] {
            return all.map(\\.name)
        }
    }

    """

    try out.write(to: outPath, atomically: true, encoding: .utf8)
    print("wrote \(outPath.path) (\(out.utf8.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
```

- [ ] **Step 2: Run the script from the repo root**

Run: `swift scripts/embed-templates.swift`

Expected: stdout `wrote /Users/<you>/Projets/swiflow/Sources/SwiflowCLI/EmbeddedTemplates.swift (NNNN bytes)`.

- [ ] **Step 3: Verify the generated file compiles**

Run: `swift build --target SwiflowCLI`

Expected: build succeeds.

- [ ] **Step 4: Sanity-check the generated file**

Open `Sources/SwiflowCLI/EmbeddedTemplates.swift` and verify it contains a `Template(name: "HelloWorld", files: [...])` block. The contents under `"Package.swift":` should start with `// swift-tools-version: 6.0` and contain `name: "{{NAME}}"` and `{{SWIFLOW_DEP}}`.

- [ ] **Step 5: Commit**

```bash
git add scripts/embed-templates.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "$(cat <<'EOF'
feat(cli): embed examples/* as EmbeddedTemplates via codegen script

Adds scripts/embed-templates.swift (mirror of embed-driver.swift) and
the initial generated Sources/SwiflowCLI/EmbeddedTemplates.swift. No
runtime callers yet — wiring follows in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add the freshness test for `EmbeddedTemplates.swift`

**Files:**
- Modify: `Tests/SwiflowCLITests/TemplateEmbedderTests.swift`

The test re-runs `TemplateEmbedder.swiftSource(examplesRoot:)` in-process and asserts it byte-equals the committed `EmbeddedTemplates.swift`. Drift between the script and the helper, or forgetting to rerun the script after editing an example, surfaces here. Mirror of `DriverEmbedderTests.embeddedDriverIsFresh`.

- [ ] **Step 1: Add the failing test**

Append to `Tests/SwiflowCLITests/TemplateEmbedderTests.swift`:

```swift
extension TemplateEmbedderTests {

    /// Repo root resolved relative to this test file's location.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    @Test("EmbeddedTemplates.swift is bit-for-bit what TemplateEmbedder would produce")
    func embeddedTemplatesIsFresh() throws {
        let examplesRoot = Self.repoRoot.appendingPathComponent("examples")
        let embeddedURL = Self.repoRoot.appendingPathComponent("Sources/SwiflowCLI/EmbeddedTemplates.swift")

        let expected = try TemplateEmbedder.swiftSource(examplesRoot: examplesRoot)
        let actual = try String(contentsOf: embeddedURL, encoding: .utf8)

        #expect(actual == expected, """
            EmbeddedTemplates.swift drifted from TemplateEmbedder.swiftSource output. \
            Regenerate by running, from the repo root:
                swift scripts/embed-templates.swift
            then commit Sources/SwiflowCLI/EmbeddedTemplates.swift.
            """)
    }

    @Test("EmbeddedTemplates.all is non-empty and contains HelloWorld")
    func embeddedTemplatesContainsHelloWorld() {
        #expect(!EmbeddedTemplates.all.isEmpty)
        #expect(EmbeddedTemplates.availableNames.contains("HelloWorld"))
    }

    @Test("EmbeddedTemplates.lookup returns nil for an unknown name")
    func embeddedTemplatesLookupMissing() {
        #expect(EmbeddedTemplates.lookup("DoesNotExist") == nil)
    }

    @Test("HelloWorld template contains Package.swift, App.swift, index.html")
    func helloWorldTemplateShape() throws {
        let t = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        #expect(t.files["Package.swift"] != nil)
        #expect(t.files["Sources/App/App.swift"] != nil)
        #expect(t.files["index.html"] != nil)
        #expect(t.files[".gitignore"] != nil)
        #expect(t.files["README.md"] != nil)
        // Driver / SW must NOT be in the template — they come from EmbeddedDriver.
        #expect(t.files["swiflow-driver.js"] == nil)
        #expect(t.files["swiflow-sw.js"] == nil)
    }

    @Test("Package.swift template uses {{NAME}} and {{SWIFLOW_DEP}} placeholders")
    func helloWorldPackageSwiftPlaceholders() throws {
        let t = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        let pkg = try #require(t.files["Package.swift"])
        #expect(pkg.contains(#"name: "{{NAME}}""#))
        #expect(pkg.contains("{{SWIFLOW_DEP}}"))
        #expect(!pkg.contains("HelloWorld"))
        #expect(!pkg.contains(#".package(path: "../..")"#))
    }
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter TemplateEmbedderTests`

Expected: all tests pass.

- [ ] **Step 3: Verify the test catches drift**

Temporarily corrupt `Sources/SwiflowCLI/EmbeddedTemplates.swift` (e.g. delete one line). Re-run the test. Expected: `embeddedTemplatesIsFresh` fails with the regen instructions in the message. Restore via:

```bash
swift scripts/embed-templates.swift
```

Re-run the test to confirm it passes again.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowCLITests/TemplateEmbedderTests.swift
git commit -m "$(cat <<'EOF'
test(cli): freshness test for EmbeddedTemplates.swift

Asserts the on-disk generated file matches what TemplateEmbedder
would produce now. Forgetting to rerun the codegen script after
editing an example surfaces here. Same shape as DriverEmbedderTests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `Templates.render` helper (additive; old API still works)

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift:39-67`
- Modify: `Tests/SwiflowCLITests/TemplatesTests.swift`

Add the generic substitution helper. This is purely additive — the old `packageSwift(name:swiflowDep:)` / `appSwift(name:)` / etc. functions still exist; they're removed in Task 8 once nothing depends on them.

- [ ] **Step 1: Add a failing test for `render`**

Add this to `Tests/SwiflowCLITests/TemplatesTests.swift` inside the `TemplatesTests` struct:

```swift
@Test("render substitutes {{NAME}} and {{SWIFLOW_DEP}}")
func renderSubstitutesBothTokens() {
    let raw = #"""
    name: "{{NAME}}", deps: [
        {{SWIFLOW_DEP}},
    ]
    """#
    let out = Templates.render(raw, name: "MyApp", swiflowDep: .path("/abs/swiflow"))
    #expect(out.contains(#"name: "MyApp""#))
    #expect(out.contains(#".package(path: "/abs/swiflow")"#))
    #expect(!out.contains("{{NAME}}"))
    #expect(!out.contains("{{SWIFLOW_DEP}}"))
}

@Test("render with URL dep produces .package(url:exact:)")
func renderUrlDep() {
    let raw = "{{SWIFLOW_DEP}}"
    let out = Templates.render(raw, name: "Demo", swiflowDep: .url("https://example.com/repo.git", version: "1.2.3"))
    #expect(out == #".package(url: "https://example.com/repo.git", exact: "1.2.3")"#)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "render substitutes"`

Expected: Compile error — `Templates.render` not defined.

- [ ] **Step 3: Add `render` to `Templates.swift`**

Open `Sources/SwiflowCLI/Templates/Templates.swift` and add this method inside the `Templates` enum (immediately after the `// MARK: - Public rendering API` line):

```swift
    /// Applies the two scaffold-time substitutions to a raw template file's
    /// contents. Used by `ProjectWriter` to render each file in a template.
    ///
    /// - `{{NAME}}` ← `name`
    /// - `{{SWIFLOW_DEP}}` ← `swiflowDep.packageFragment`
    static func render(_ raw: String, name: String, swiflowDep: SwiflowDep) -> String {
        return raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_DEP}}", with: swiflowDep.packageFragment)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TemplatesTests`

Expected: all existing tests + the two new ones pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift Tests/SwiflowCLITests/TemplatesTests.swift
git commit -m "$(cat <<'EOF'
feat(cli): add Templates.render generic substitution helper

Additive. Old packageSwift/appSwift/etc. helpers stay until the
ProjectWriter migration in the next commit. Render handles the two
scaffold-time tokens: {{NAME}} and {{SWIFLOW_DEP}}.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Switch `ProjectWriter` to walk a `Template`

**Files:**
- Modify: `Sources/SwiflowCLI/Project/ProjectWriter.swift`
- Modify: `Sources/SwiflowCLI/Commands/InitCommand.swift:111-117` (call site)
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift` (signature update)

`ProjectWriter.writeProject` gains a `template:` parameter and walks `template.files` instead of writing seven hardcoded files. JS driver + SW still come from `EmbeddedDriver` (out-of-band of the template). `InitCommand` keeps defaulting to `HelloWorld` for now — the `--template` flag arrives in Task 6.

- [ ] **Step 1: Update `InitCommandTests` call sites to the new signature**

The current tests call `ProjectWriter.writeProject(name:into:swiflowDep:jsDriverSource:jsServiceWorkerSource:)`. After this task, the signature requires `template:`. Update every call site in `Tests/SwiflowCLITests/InitCommandTests.swift` by inserting `template: EmbeddedTemplates.lookup("HelloWorld")!,` right after `name:`.

For example, `createsFileTree()` currently reads:

```swift
try ProjectWriter.writeProject(
    name: "Demo",
    into: tmp,
    swiflowDep: .path("../.."),
    jsDriverSource: "// fake driver\n",
    jsServiceWorkerSource: "// fake sw\n"
)
```

Change it to:

```swift
try ProjectWriter.writeProject(
    name: "Demo",
    template: EmbeddedTemplates.lookup("HelloWorld")!,
    into: tmp,
    swiflowDep: .path("../.."),
    jsDriverSource: "// fake driver\n",
    jsServiceWorkerSource: "// fake sw\n"
)
```

Repeat for `writesDriverVerbatim`, `writesServiceWorkerVerbatim`, `refusesOverwrite`, `cleansUpOnFailure`, `threadsSwiflowSource`, `appSwiftIsCounterComponent`. (Six call sites total in the file.)

- [ ] **Step 2: Run the tests to verify they now fail at compile time**

Run: `swift test --filter InitCommand`

Expected: Compile errors — `ProjectWriter.writeProject` has no `template:` parameter.

- [ ] **Step 3: Update `ProjectWriter.writeProject`**

Replace the body of `Sources/SwiflowCLI/Project/ProjectWriter.swift` with:

```swift
// Sources/SwiflowCLI/Project/ProjectWriter.swift
//
// Pure file-tree writer separated from InitCommand so it's trivially
// testable (no CLI invocation, no Process). InitCommand is a thin wrapper
// that resolves arguments, the chosen template, and the embedded driver,
// then delegates here.

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

    /// Creates `<into>/<name>/` and writes the chosen template's file tree
    /// into it, plus the JS driver + service worker (which come from
    /// EmbeddedDriver, not the template — see EmbeddedTemplates blacklist).
    ///
    /// - Parameters:
    ///   - name: project name; used as the directory name and `{{NAME}}` substitution value.
    ///   - template: the embedded template selected via `--template`.
    ///   - parent: parent directory in which the new project will be created.
    ///   - swiflowDep: how the generated `Package.swift` depends on Swiflow.
    ///   - jsDriverSource / jsServiceWorkerSource: pass `EmbeddedDriver.javascriptSource`
    ///     / `EmbeddedDriver.serviceWorkerSource` in production; tests pass stub strings.
    ///   - _testFailDuringWrites: test-only hook that throws after the target
    ///     directory has been created, so the cleanup path is exercised
    ///     deterministically. Production callers omit it.
    static func writeProject(
        name: String,
        template: EmbeddedTemplates.Template,
        into parent: URL,
        swiflowDep: SwiflowDep,
        jsDriverSource: String,
        jsServiceWorkerSource: String,
        _testFailDuringWrites: Bool = false
    ) throws {
        let fm = FileManager.default
        let project = parent.appendingPathComponent(name, isDirectory: false)

        if fm.fileExists(atPath: project.path) {
            throw ProjectWriterError.targetExists(project)
        }

        try fm.createDirectory(at: project, withIntermediateDirectories: true)

        do {
            if _testFailDuringWrites {
                throw CocoaError(.fileWriteUnknown)
            }

            // Walk the template's file map. Intermediate directories are
            // created on demand so nested paths (e.g. Sources/App/Pages/Foo.swift
            // in MiniRouter) work without per-template scaffolding logic.
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
            // template. Keeps canonical js-driver/ bytes in one place.
            try jsDriverSource.write(
                to: project.appendingPathComponent("swiflow-driver.js"),
                atomically: true,
                encoding: .utf8
            )
            try jsServiceWorkerSource.write(
                to: project.appendingPathComponent("swiflow-sw.js"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            try? fm.removeItem(at: project)
            throw error
        }
    }
}
```

- [ ] **Step 4: Update `InitCommand.run()` to pass the template**

Open `Sources/SwiflowCLI/Commands/InitCommand.swift` and change the `ProjectWriter.writeProject(...)` call (currently lines 111-117) to:

```swift
            try ProjectWriter.writeProject(
                name: name,
                template: EmbeddedTemplates.lookup("HelloWorld")!,
                into: parentURL,
                swiflowDep: dep,
                jsDriverSource: EmbeddedDriver.javascriptSource,
                jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
            )
```

The `!` is safe because `embeddedTemplatesContainsHelloWorld` (added in Task 3) asserts the entry exists; if it doesn't, every CLI test would fail loudly before reaching production.

- [ ] **Step 5: Run all SwiflowCLI tests**

Run: `swift test --filter SwiflowCLITests`

Expected: every existing test still passes. The old `Templates.packageSwift` / `Templates.appSwift` / etc. functions are no longer called by `ProjectWriter`, but they remain defined (compiled but unused). Tests that exercised them via direct call still work.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Project/ProjectWriter.swift Sources/SwiflowCLI/Commands/InitCommand.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "$(cat <<'EOF'
refactor(cli): ProjectWriter walks an EmbeddedTemplates.Template

Templates source-of-truth moves from inline Templates.swift constants
to EmbeddedTemplates (codegen'd from examples/HelloWorld/). Behavior
unchanged: --template flag not added yet, so InitCommand hardcodes
HelloWorld.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Add `--template` flag to `InitCommand`

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/InitCommand.swift`
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift`

- [ ] **Step 1: Add failing tests**

Add to `Tests/SwiflowCLITests/InitCommandTests.swift`, inside the `InitCommandArgvTests` suite:

```swift
@Test("Default: --template is HelloWorld")
func defaultTemplate() throws {
    let parsed = try InitCommand.parse(["demo"])
    #expect(parsed.template == "HelloWorld")
}

@Test("--template parses")
func parsesTemplate() throws {
    let parsed = try InitCommand.parse(["demo", "--template", "MiniRouter"])
    #expect(parsed.template == "MiniRouter")
}
```

Add to `InitCommandRunTests`:

```swift
@Test("Unknown --template surfaces a ValidationError listing available templates")
func unknownTemplateValidates() async throws {
    let tmp = try InitCommandTests.makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cmd = try InitCommand.parse([
        "Demo",
        "--path", tmp.path,
        "--template", "DoesNotExist",
        "--swiflow-source", "/abs/path/to/swiflow",
    ])
    await #expect(throws: ValidationError.self) {
        try await cmd.run()
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter InitCommand`

Expected: Compile errors — `InitCommand.template` not defined.

- [ ] **Step 3: Add the flag to `InitCommand`**

In `Sources/SwiflowCLI/Commands/InitCommand.swift`, add a new `@Option` after the existing `--path` option:

```swift
    @Option(
        name: .customLong("template"),
        help: ArgumentHelp(
            "Which embedded template to scaffold. Defaults to HelloWorld.",
            discussion: """
                Run `swiflow init --help` for the current list of available templates.
                Each name maps to a directory under examples/ in the Swiflow repo.
                """
        )
    )
    var template: String = "HelloWorld"
```

Then change the body of `run()` to look up the template before calling `ProjectWriter`:

Replace these lines in `InitCommand.run()`:

```swift
        do {
            try ProjectWriter.writeProject(
                name: name,
                template: EmbeddedTemplates.lookup("HelloWorld")!,
                into: parentURL,
                swiflowDep: dep,
                jsDriverSource: EmbeddedDriver.javascriptSource,
                jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
            )
        } catch let error as ProjectWriterError {
            throw ValidationError(String(describing: error))
        }
```

with:

```swift
        guard let chosenTemplate = EmbeddedTemplates.lookup(template) else {
            let names = EmbeddedTemplates.availableNames.joined(separator: ", ")
            throw ValidationError(#"unknown template "\#(template)" — available: \#(names)"#)
        }

        do {
            try ProjectWriter.writeProject(
                name: name,
                template: chosenTemplate,
                into: parentURL,
                swiflowDep: dep,
                jsDriverSource: EmbeddedDriver.javascriptSource,
                jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
            )
        } catch let error as ProjectWriterError {
            throw ValidationError(String(describing: error))
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter InitCommand`

Expected: all tests pass.

- [ ] **Step 5: Sanity-check the CLI from the shell**

Build the CLI and check that the help text lists `--template`:

```bash
swift build --product swiflow
.build/debug/swiflow init --help
```

Expected: `--template` documented under Options.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Commands/InitCommand.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "$(cat <<'EOF'
feat(cli): `swiflow init --template <name>` (default HelloWorld)

Unknown template surfaces a ValidationError listing available names.
List is populated from EmbeddedTemplates.availableNames so adding an
example/ directory and rerunning codegen is the only step needed to
ship a new template.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Replace per-file equality tests with template round-trip tests

**Files:**
- Modify: `Tests/SwiflowCLITests/TemplatesTests.swift`

The old per-file `packageSwiftMatchesExample` / `appSwiftMatchesExample` / etc. tests assert specific raw constants equal specific on-disk files. Replace them with a generic round-trip test that walks each `EmbeddedTemplates.Template` and asserts the rendered output equals what's on disk.

- [ ] **Step 1: Delete the obsolete tests**

In `Tests/SwiflowCLITests/TemplatesTests.swift`, delete these tests:

- `packageSwiftMatchesExample`
- `appSwiftMatchesExample`
- `indexHTMLMatchesExample`
- `gitignoreMatchesExample`
- `readmeMatchesExample`

Keep these (still relevant):

- `exampleDriverMatchesCanonical` — asserts `examples/HelloWorld/swiflow-driver.js` ↔ `js-driver/swiflow-driver.js`; orthogonal to templates.
- `exampleServiceWorkerMatchesCanonical` — same for SW.
- `renderSubstitutesBothTokens` and `renderUrlDep` (added in Task 4).

Delete these too (their behavior is now covered by the new round-trip + helloWorldPackageSwiftPlaceholders from Task 3):

- `readmeMentionsKeyCommands`
- `substitutesName`
- `substitutesSwiflowSource`
- `indexHTMLTitleSubstitutesName`
- `packageSwiftURLDep`
- `templateHasProgressHook`
- `packageSwiftPathDep`

- [ ] **Step 2: Add the new round-trip test**

Inside the `TemplatesTests` struct, add:

```swift
    @Test("Every template renders byte-identical to its examples/<name>/ tree",
          arguments: ["HelloWorld", "MiniRouter", "RouterDemo"])
    func templateRoundTrip(name: String) throws {
        let template = try #require(EmbeddedTemplates.lookup(name),
                                    "EmbeddedTemplates.lookup(\(name)) returned nil")
        let exampleRoot = Self.repoRoot.appendingPathComponent("examples").appendingPathComponent(name)

        for (relativePath, raw) in template.files {
            let rendered = Templates.render(raw, name: name, swiflowDep: .path("../.."))
            let onDisk = try String(
                contentsOf: exampleRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(rendered == onDisk,
                    "drift in \(name)/\(relativePath); regenerate via `swift scripts/embed-templates.swift`")
        }
    }

    @Test("Every non-blacklisted file under examples/<name>/ appears in the corresponding template",
          arguments: ["HelloWorld", "MiniRouter", "RouterDemo"])
    func templateCoversAllOnDiskFiles(name: String) throws {
        let template = try #require(EmbeddedTemplates.lookup(name))
        let exampleRoot = Self.repoRoot.appendingPathComponent("examples").appendingPathComponent(name)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: exampleRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            Issue.record("could not enumerate \(exampleRoot.path)"); return
        }

        var onDiskRelativePaths: Set<String> = []
        for case let url as URL in enumerator {
            let last = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if TemplateEmbedder.blacklist.contains(last) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir { continue }
            let basePath = exampleRoot.path + "/"
            onDiskRelativePaths.insert(String(url.path.dropFirst(basePath.count)))
        }

        let templatePaths = Set(template.files.keys)
        #expect(templatePaths == onDiskRelativePaths, """
            \(name) template files diverge from examples/\(name)/.
            Only-in-template: \(templatePaths.subtracting(onDiskRelativePaths))
            Only-on-disk:    \(onDiskRelativePaths.subtracting(templatePaths))
            Regenerate via `swift scripts/embed-templates.swift`.
            """)
    }
```

Note `templateRoundTrip` is parametric: it runs once per template name. The third parameter (`RouterDemo`) currently has no `README.md`; Task 10 adds one, and the round-trip will then expect that file too. This test stays green throughout the plan because the template is regenerated whenever the example changes.

- [ ] **Step 3: Run the test**

Run: `swift test --filter TemplatesTests`

Expected: `templateRoundTrip(name: "HelloWorld")` passes; `MiniRouter` and `RouterDemo` may pass or fail depending on whether the codegen has been re-run since the examples were last touched. If they fail with "drift", run the codegen and rebuild:

```bash
swift scripts/embed-templates.swift
swift test --filter TemplatesTests
```

Expected on second run: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowCLITests/TemplatesTests.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "$(cat <<'EOF'
test(cli): parametric round-trip + blacklist-coverage tests per template

Replaces five per-file byte-equality tests with two parametric tests
that scale to every template added to EmbeddedTemplates. Adds drift
detection: any file added to an example but not yet regenerated into
the template surfaces with a clear regen instruction.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Delete the obsolete raw-string constants and per-file render helpers

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`

After Task 5 nothing calls `Templates.packageSwift(name:swiflowDep:)` / `appSwift(name:)` / `indexHTML(name:)` / `gitignore()` / `readme(name:)`. After Task 7 nothing references the raw string constants. Time to delete them.

- [ ] **Step 1: Verify nothing depends on the old API**

Run from the repo root:

```bash
grep -rn "Templates.packageSwift\|Templates.appSwift\|Templates.indexHTML\|Templates.gitignore\|Templates.readme" Sources Tests
```

Expected: no matches.

- [ ] **Step 2: Rewrite `Templates.swift`**

Replace the entire file with:

```swift
// Sources/SwiflowCLI/Templates/Templates.swift
//
// Tiny module: SwiflowDep (how the generated Package.swift depends on
// Swiflow) + a `render` helper that applies the two scaffold-time tokens
// to any file's raw contents.
//
// Template contents live in EmbeddedTemplates.swift (generated from
// examples/ by scripts/embed-templates.swift).

import Foundation

/// How the generated Package.swift should depend on Swiflow.
enum SwiflowDep: Equatable {
    /// A local path dep: `.package(path: "/path/to/swiflow")`.
    case path(String)
    /// A versioned URL dep: `.package(url: "...", exact: "x.y.z")`.
    case url(String, version: String)

    /// The exact `.package(...)` fragment as it appears in the generated Package.swift.
    var packageFragment: String {
        switch self {
        case .path(let p):
            return #".package(path: "\#(p)")"#
        case .url(let u, let v):
            return #".package(url: "\#(u)", exact: "\#(v)")"#
        }
    }
}

extension SwiflowDep {
    /// The repo `swiflow init` points generated `Package.swift` files at
    /// when scaffolding a versioned URL dep.
    static let officialRepositoryURL = "https://github.com/zzal/swiflow.git"
}

enum Templates {
    /// Applies the two scaffold-time substitutions to a raw template file's
    /// contents. Used by `ProjectWriter` to render each file in a template.
    ///
    /// - `{{NAME}}` ← `name`
    /// - `{{SWIFLOW_DEP}}` ← `swiflowDep.packageFragment`
    static func render(_ raw: String, name: String, swiflowDep: SwiflowDep) -> String {
        return raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_DEP}}", with: swiflowDep.packageFragment)
    }
}
```

- [ ] **Step 3: Run the full test suite**

Run: `swift test --filter SwiflowCLITests`

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift
git commit -m "$(cat <<'EOF'
refactor(cli): drop obsolete raw-string constants from Templates.swift

Templates.swift collapses from ~440 lines to ~40. Source of truth for
template contents lives entirely in examples/ + EmbeddedTemplates.swift
now. The two-token substitution stays as a tiny `render` helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Modernize `examples/MiniRouter/index.html`

**Files:**
- Modify: `examples/MiniRouter/index.html`

MiniRouter's `index.html` uses a legacy pattern: it includes `swiflow-driver.js` AND a second `<script type="module">` block that hardcodes the `.build/plugins/PackageToJS/outputs/Package/index.js` path. The driver script handles init on its own — the second block is dead weight (and worse, the hardcoded `.build` path is wrong for `swiflow dev`-style flows). HelloWorld and RouterDemo already use the canonical single-script pattern.

This is necessary because once MiniRouter becomes a `--template`, every new project scaffolded from it would inherit the legacy pattern.

- [ ] **Step 1: Read the current file**

Run: `cat examples/MiniRouter/index.html`

Confirm it contains the `<script type="module">` block.

- [ ] **Step 2: Rewrite `examples/MiniRouter/index.html`**

Replace the file contents with:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>MiniRouter</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; }
      nav { display: flex; gap: 1rem; margin-bottom: 2rem; border-bottom: 1px solid #ccc; padding-bottom: 1rem; }
      nav a { text-decoration: none; color: #0070f3; }
      nav a:hover { text-decoration: underline; }
      button { padding: 0.4rem 1rem; cursor: pointer; }
    </style>
  </head>
  <body>
    <div id="app"></div>

    <!-- The Swiflow driver script owns WASM initialisation.
         It dynamically imports the PackageToJS module and calls init()
         so no <script type="module"> block is needed here. -->
    <script src="swiflow-driver.js"></script>
  </body>
</html>
```

- [ ] **Step 3: Smoke-test MiniRouter still runs**

Run: `cd examples/MiniRouter && swift run --package-path ../.. swiflow dev`

(Or whichever local dev command works; the test is "the page still renders with the navbar visible.")

Open `http://localhost:3000` and confirm the MiniRouter navbar + pages still work. Stop the server (Ctrl-C) and `cd` back to the repo root.

- [ ] **Step 4: Regenerate `EmbeddedTemplates.swift`**

`examples/MiniRouter/index.html` just changed; without a regen, the freshness test and the MiniRouter round-trip test fail.

Run: `swift scripts/embed-templates.swift`

Expected: stdout `wrote ...EmbeddedTemplates.swift (NNNN bytes)`.

- [ ] **Step 5: Run the SwiflowCLI tests**

Run: `swift test --filter SwiflowCLITests`

Expected: all pass.

- [ ] **Step 6: Commit (example change + regen together)**

```bash
git add examples/MiniRouter/index.html Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "$(cat <<'EOF'
chore(examples): MiniRouter index.html uses canonical driver pattern

Drops the legacy <script type="module"> block with the hardcoded
.build/plugins/... path. The Swiflow driver script handles init on
its own — HelloWorld and RouterDemo already use the single-script
pattern. Prerequisite for shipping MiniRouter as a `swiflow init
--template` option. Regenerated EmbeddedTemplates.swift in the same
commit so the freshness test stays green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Add `README.md` and `.gitignore` to `MiniRouter` + `README.md` to `RouterDemo`

**Files:**
- Create: `examples/MiniRouter/.gitignore`
- Create: `examples/MiniRouter/README.md`
- Create: `examples/RouterDemo/README.md`

- [ ] **Step 1: Create `examples/MiniRouter/.gitignore`**

```
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json
```

- [ ] **Step 2: Create `examples/MiniRouter/README.md`**

```markdown
# MiniRouter

A Swiflow project demonstrating client-side routing with `SwiflowRouter`.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A navbar with **Home**, **About**, and **Users** links.
- Clicking a link swaps the page content without a full reload — the
  router renders the matching `Route` from `Sources/App/App.swift`.
- `/users/:id` shows a dynamic `:id` segment via `ctx.params["id"]`.
```

- [ ] **Step 3: Create `examples/RouterDemo/README.md`**

```markdown
# RouterDemo

A Swiflow project demonstrating client-side routing with `SwiflowRouter`.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- The router renders the `/` route from `Sources/App/App.swift`.
- Navigating to `/about` or `/users/:id` swaps the page content via
  the `Route` declarations.
```

- [ ] **Step 4: Verify the file structure**

Run: `ls examples/MiniRouter/ examples/RouterDemo/`

Expected: MiniRouter shows `.gitignore` and `README.md`; RouterDemo shows `README.md`.

- [ ] **Step 5: Regenerate `EmbeddedTemplates.swift`**

Run: `swift scripts/embed-templates.swift`

Expected: stdout `wrote ...EmbeddedTemplates.swift (NNNN bytes)`. The file should now include the three new entries under `MiniRouter` (`.gitignore`, `README.md`) and `RouterDemo` (`README.md`).

- [ ] **Step 6: Run the SwiflowCLI tests**

Run: `swift test --filter SwiflowCLITests`

Expected: all pass, including the parametric round-trip and coverage tests for MiniRouter and RouterDemo with the new files.

- [ ] **Step 7: Commit (example additions + regen together)**

```bash
git add examples/MiniRouter/.gitignore examples/MiniRouter/README.md examples/RouterDemo/README.md Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "$(cat <<'EOF'
chore(examples): add README + .gitignore to MiniRouter, README to RouterDemo

Makes both ready to ship as `swiflow init --template` options.
Without these files, scaffolded MiniRouter / RouterDemo projects
would feel half-finished compared to HelloWorld. Regenerated
EmbeddedTemplates.swift in the same commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: End-to-end smoke test the new templates

**Files:** none — read-only verification.

After Task 10 the codebase is in its final state. This task drives the CLI from the shell to confirm `--template MiniRouter` and `--template RouterDemo` both produce valid scaffolds and the unknown-template path errors cleanly.

- [ ] **Step 1: Run the full SwiflowCLI test suite one last time**

Run: `swift test --filter SwiflowCLITests`

Expected: all pass, including:
- `embeddedTemplatesIsFresh`
- `templateRoundTrip(name: "HelloWorld")`, `(name: "MiniRouter")`, `(name: "RouterDemo")`
- `templateCoversAllOnDiskFiles(...)` for each template
- `unknownTemplateValidates`

- [ ] **Step 2: Build the release CLI**

Run: `swift build --product swiflow`

- [ ] **Step 3: End-to-end smoke test (`swiflow init --template MiniRouter`)**

```bash
swift build --product swiflow
TMP=$(mktemp -d)
.build/debug/swiflow init demo --template MiniRouter --path "$TMP" --swiflow-source "$(pwd)"
ls "$TMP/demo"
ls "$TMP/demo/Sources/App/Pages"
cat "$TMP/demo/Package.swift" | head -5
```

Expected:
- `ls "$TMP/demo"` shows `Package.swift`, `Sources/`, `index.html`, `.gitignore`, `README.md`, `swiflow-driver.js`, `swiflow-sw.js`.
- `ls "$TMP/demo/Sources/App/Pages"` shows `AboutPage.swift`, `HomePage.swift`, `UsersPage.swift`.
- `head -5 Package.swift` shows `name: "demo"` (not `"MiniRouter"`) and `.package(path: "<your-swiflow-checkout>")` (not the `{{SWIFLOW_DEP}}` placeholder).

Clean up: `rm -rf "$TMP"`.

- [ ] **Step 4: End-to-end smoke test (`swiflow init --template RouterDemo`)**

```bash
TMP=$(mktemp -d)
.build/debug/swiflow init demo --template RouterDemo --path "$TMP" --swiflow-source "$(pwd)"
ls "$TMP/demo"
head -3 "$TMP/demo/README.md"
rm -rf "$TMP"
```

Expected: `demo/` contains `Package.swift`, `Sources/App/App.swift`, `index.html`, `.gitignore`, `README.md`, `swiflow-driver.js`, `swiflow-sw.js`. `README.md` starts with `# demo` (not `# RouterDemo`).

- [ ] **Step 5: End-to-end smoke test (unknown template)**

```bash
TMP=$(mktemp -d)
.build/debug/swiflow init demo --template Bogus --path "$TMP" 2>&1 || true
ls "$TMP"
rm -rf "$TMP"
```

Expected: error message contains `unknown template "Bogus" — available: HelloWorld, MiniRouter, RouterDemo`. `ls "$TMP"` shows no `demo` directory (creation refused before any I/O).

- [ ] **Step 6: No commit needed — this task is verification only**

If everything above passed, the plan is done.

---

## Done When

- `Sources/SwiflowCLI/Templates/Templates.swift` ≤ ~50 lines, containing only `SwiflowDep` + `render`.
- `swiflow init <name> --template HelloWorld | MiniRouter | RouterDemo` all produce buildable projects.
- `swiflow init <name>` (no flag) still scaffolds HelloWorld.
- `swiflow init <name> --template Bogus` exits with a validation error listing available templates.
- `swift test --filter SwiflowCLITests` passes, including the freshness test and all three parametric round-trips.
- `examples/MiniRouter/` has `.gitignore`, `README.md`, and the modernized `index.html`.
- `examples/RouterDemo/` has `README.md`.

## Out of Scope (Follow-On PRs)

- Migrating `Tests/playwright/playwright.router.config.ts` to scaffold RouterDemo via `swiflow init --template RouterDemo` instead of pointing at the checked-in `examples/RouterDemo/` tree.
- Removing `examples/RouterDemo/` entirely once the Playwright config no longer points at it.
- Generalizing the substitution model beyond `{{NAME}}` + `{{SWIFLOW_DEP}}`.
