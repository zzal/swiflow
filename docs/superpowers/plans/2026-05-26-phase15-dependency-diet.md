# Phase 15 — Pre-1.0 Dependency Diet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every runtime `Mirror` call site, drop the small runtime Foundation surface, enable `-Xswiftc -disable-reflection-metadata` on release builds, then measure. Target ≥5% gzipped reduction from the Phase 14b post-trim baseline (18,176,904 bytes).

**Architecture:** Three coordinated moves. (1) Replace the per-`@State` Mirror walks (`wireStateAndRestore`, `makeSnapshot`, `applyRestore`) with macro-emitted `_ComponentRuntime.stateCells` iteration — `@State` becomes a Swift attached macro that drops the `State<T>` class entirely. (2) Replace the two `Mirror.displayStyle == .optional` call sites in the JS bridge with an exhaustive type switch over the four HMR-supported primitives. (3) Drop vestigial runtime `import Foundation`s (URLSanitizer's `replacingOccurrences` and HMR.swift's unused import). Then flip the compiler flag and measure. The big bundle-size jump is expected only when all Mirror call sites are removed *and* the flag is on — so the linker can dead-strip the demangler/SIMD `debugDescription` helpers transitively pulled in by Mirror references.

**Tech Stack:** Swift 6.3 macros (`@attached(accessor)`, `@attached(peer, names: prefixed($))`, `MemberMacro`, `ExtensionMacro`), SwiftSyntax for AST inspection, existing PackageToJS pipeline, existing Phase 14b bundle-size CI gate. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-26-phase15-dependency-diet-design.md` (commit `0c83b8f`).

---

## File structure

| Path | Action | Responsibility |
|---|---|---|
| `Sources/SwiflowWeb/HMR/HMRBridge.swift` | modify | Replace `Mirror.displayStyle == .optional` block in `encodeStateMap` with explicit `as Bool?/Int?/Double?/String?` switch |
| `Sources/SwiflowWeb/DevAPI.swift` | modify | Same replacement in `encodeStateForDisplay` |
| `Sources/Swiflow/Reactivity/URLSanitizer.swift` | modify | Drop `import Foundation`; replace `replacingOccurrences` calls with stdlib-only scanner |
| `Sources/Swiflow/Reactivity/HMR.swift` | modify | Drop vestigial `import Foundation` after verifying nothing else needs it |
| `Sources/Swiflow/Reactivity/StateCell.swift` | **create** | `AnyStateCell` protocol + `StateCell<Owner>` generic struct |
| `Sources/Swiflow/Reactivity/Component.swift` | modify | Add `_ComponentRuntime` sub-protocol; rewrite `wireStateAndRestore` to use it; drop the Mirror walk |
| `Sources/Swiflow/Reactivity/State.swift` | rewrite | Drop `State<T>` class, `Box<T>` class, `StateWireable` protocol; keep `Binding<T>` only |
| `Sources/Swiflow/Macros.swift` | modify | Add `@State` macro declaration |
| `Sources/SwiflowMacrosPlugin/StateMacro.swift` | **create** | `@attached(accessor)` adds `didSet`; `@attached(peer, names: prefixed($))` adds `$name` Binding |
| `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` | modify | Add `MemberMacro` conformance — scan `@State` vars; emit `_ComponentRuntime` conformance, `stateCells`, `bind`, `runtimeOwner`, `runtimeScheduler` |
| `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` | modify | Register `StateMacro` |
| `Tests/SwiflowMacrosTests/StateMacroTests.swift` | **create** | Expansion tests for `@State` (single, multiple, Optional, didSet conflict diagnostic) |
| `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` | modify | Add tests for the new member emissions (stateCells array, bind method, runtime stored props) |
| `Tests/SwiflowTests/Reactivity/ComponentRuntimeTests.swift` | **create** | Hand-rolled `_ComponentRuntime` types driving `wireStateAndRestore` without macros |
| `Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift` | modify | Migrate any direct `State<T>` constructors to component-based pattern |
| `Tests/SwiflowTests/HMR/StateHMRHookTests.swift` | modify | Same migration |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | modify | Add `-Xswiftc -disable-reflection-metadata` to release path in `composeArguments` |
| `Tests/SwiflowCLITests/BuildCommandTests.swift` | modify | Assert the new flag |
| `docs/perf/bundle-baseline.json` | modify | Refresh `total_bytes` + `total_gzip_bytes` after Task 7 |
| `docs/perf/2026-05-26-wasm-bundle-audit.md` | modify | Append a "Phase 15" headline row + section breakdown after Task 7 |
| `CHANGELOG.md` | modify | Phase 15 entry above Phase 14b Track 3 |
| `README.md` | modify | Status line, cost row, test counts |

**Key invariant across tasks:** `js-driver/swiflow-driver.js` and `examples/HelloWorld/swiflow-driver.js` must stay byte-equal; same for `swiflow-sw.js`. This plan does NOT touch the JS driver, but Task 6 might surface side effects. If TemplatesTests fails on a sync invariant after a framework rewrite, that's a regression to fix in the same task — not a separate one.

---

## Task 1: Replace `Mirror.displayStyle` Optional handling in HMRBridge + DevAPI

**Files:**
- Modify: `Sources/SwiflowWeb/HMR/HMRBridge.swift` (function `encodeStateMap` — find the block currently using `Mirror(reflecting: v)`)
- Modify: `Sources/SwiflowWeb/DevAPI.swift` (function `encodeStateForDisplay` — same shape)

This task is independent and lands first because it's the smallest Mirror-removal step and gives us a clean baseline before the macro work begins.

- [ ] **Step 1: Locate the existing Mirror block in HMRBridge.swift**

```bash
grep -n "Mirror(reflecting" Sources/SwiflowWeb/HMR/HMRBridge.swift
```

Expected output: one line number around 140 in the `encodeStateMap` function. Read 20 lines of context around it so you see the surrounding `if let b = v as? Bool { ... } else if let s = v as? String { ... }` ladder.

- [ ] **Step 2: Locate the same block in DevAPI.swift**

```bash
grep -n "Mirror(reflecting" Sources/SwiflowWeb/DevAPI.swift
```

Expected: one line number around 115. Read context — same shape.

- [ ] **Step 3: Run the existing test suite to capture green baseline**

```bash
swift test 2>&1 | tail -5
```

Expected: all green. Note the test count (should be 546 + JS driver).

- [ ] **Step 4: Replace the HMRBridge block with the exhaustive switch**

Open `Sources/SwiflowWeb/HMR/HMRBridge.swift`. The current ladder uses `if/else if` for `Bool`, `String`, `Int`, `Double` then falls into a `Mirror`-based Optional branch. Replace the ENTIRE if-ladder (from `if let b = v as? Bool {` through the closing `}` of the `if mirror.displayStyle == .optional` block) with a single switch:

```swift
switch v {
case let b as Bool:    obj[k] = .boolean(b)
case let s as String:  obj[k] = .string(s)
case let i as Int:     obj[k] = .number(Double(i))
case let d as Double:  obj[k] = .number(d)
case let b as Bool?:   obj[k] = b.map { .boolean($0) } ?? .null
case let s as String?: obj[k] = s.map { .string($0) } ?? .null
case let i as Int?:    obj[k] = i.map { .number(Double($0)) } ?? .null
case let d as Double?: obj[k] = d.map { .number($0) } ?? .null
default: break
}
```

**Order matters.** Non-Optional cases come first because `Int` matches `as Int?` via runtime promotion — if the Optional case were first it would shadow concrete `Int` (still correct output, but the wrong arm).

- [ ] **Step 5: Replace the DevAPI block with the same switch**

Open `Sources/SwiflowWeb/DevAPI.swift` and do the equivalent replacement in `encodeStateForDisplay`. The surrounding context (the `for (k, v) in state` loop, the `obj[k] = .boolean(b)` assignments) is identical to HMRBridge — copy the same 9-case switch verbatim.

- [ ] **Step 6: Verify Optional-in-Any behavior matches expectations**

This is the high-risk assumption Task 1 needs to prove. Add a one-shot Swift snippet to a test:

Create or extend `Tests/SwiflowTests/HMR/StateHMRHookTests.swift` with this test (place it next to existing tests, or in a new `OptionalEncodingTests.swift` if you prefer):

```swift
@Test("Optional<T>.none stored as Any matches case let x as T?")
func optionalNoneInAnyTypeSwitch() throws {
    func classify(_ v: Any) -> String {
        switch v {
        case let b as Bool:    return "bool=\(b)"
        case let s as String:  return "string=\(s)"
        case let i as Int:     return "int=\(i)"
        case let d as Double:  return "double=\(d)"
        case let b as Bool?:   return b.map { "boolopt.some=\($0)" } ?? "boolopt.none"
        case let s as String?: return s.map { "stropt.some=\($0)" } ?? "stropt.none"
        case let i as Int?:    return i.map { "intopt.some=\($0)" } ?? "intopt.none"
        case let d as Double?: return d.map { "doubleopt.some=\($0)" } ?? "doubleopt.none"
        default: return "unknown"
        }
    }

    let noneBool: Bool? = nil
    let noneInt: Int? = nil
    let someInt: Int? = 5

    #expect(classify(noneBool as Any) == "boolopt.none")
    #expect(classify(noneInt as Any) == "intopt.none")
    // Some<Int> arrives as concrete Int — first matching case wins.
    #expect(classify(someInt as Any) == "int=5")
    #expect(classify(5 as Any) == "int=5")
    #expect(classify("hi" as Any) == "string=hi")
    #expect(classify(true as Any) == "bool=true")
}
```

This test BOTH validates the runtime semantics AND documents the design choice in the test suite.

- [ ] **Step 7: Run the new test in isolation**

```bash
swift test --filter optionalNoneInAnyTypeSwitch 2>&1 | tail -10
```

Expected: PASS. If FAIL (specifically if `noneBool as Any` matches `default` instead of `boolopt.none`), the Swift runtime IS losing the Optional layer when storing `.none` in `Any` — the design needs to fall back to checking via `Mirror` after all. **If this happens, STOP and report BLOCKED** — the spec's whole non-Mirror approach for Optional-in-Any is invalidated and we need to redesign.

- [ ] **Step 8: Run full suite to verify nothing regressed**

```bash
swift test 2>&1 | tail -5
```

Expected: all green, test count up by 1.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowWeb/HMR/HMRBridge.swift \
        Sources/SwiflowWeb/DevAPI.swift \
        Tests/SwiflowTests/HMR/StateHMRHookTests.swift
git commit -m "$(cat <<'EOF'
refactor(hmr): drop Mirror.displayStyle from JS-bridge encoding

HMRBridge.encodeStateMap and DevAPI.encodeStateForDisplay used
Mirror(reflecting: v).displayStyle == .optional to detect Optional
values. Replace with an exhaustive type switch over the four
HMR-supported primitives (Bool, Int, Double, String) and their
Optionals. New OptionalEncodingTests proves Optional<T>.none stored
as Any matches `case let x as T?` reliably.

First in a series of Mirror call-site removals (Phase 15). Bundle
impact ~0% by itself; the saving needs all Mirror references gone
AND -disable-reflection-metadata on before the linker can dead-strip
the demangler.
EOF
)"
```

---

## Task 2: `URLSanitizer` Foundation-free + vestigial import audit

**Files:**
- Modify: `Sources/Swiflow/Reactivity/URLSanitizer.swift`
- Modify: `Sources/Swiflow/Reactivity/HMR.swift` (only the import line, if audit confirms it's unused)

- [ ] **Step 1: Identify URLSanitizer's only Foundation API**

```bash
grep -n "replacingOccurrences\|import Foundation" Sources/Swiflow/Reactivity/URLSanitizer.swift
```

Expected: `import Foundation` at line 3, and two `replacingOccurrences` calls inside `decodeHTMLColonEntities` around lines 80-86 (the `&#58;` and `&#x3a;` replacements).

- [ ] **Step 2: Write a failing test for the Foundation-free scanner**

Open `Tests/SwiflowTests/` and find or create `URLSanitizerTests.swift`. Add:

```swift
@Test("decodeHTMLColonEntities handles bare colon entities without Foundation")
func decodeBareColonEntities() throws {
    // Internal helper — exercise via the public sanitize path that calls into it.
    // `&#58;` and case-insensitive `&#x3a;` / `&#x3A;` should normalize to ":".
    #expect(URLSanitizer.sanitize("javascript&#58;alert(1)") == nil)
    #expect(URLSanitizer.sanitize("javascript&#x3a;alert(1)") == nil)
    #expect(URLSanitizer.sanitize("javascript&#x3A;alert(1)") == nil)
    // Non-entity colons pass through unchanged for known schemes.
    #expect(URLSanitizer.sanitize("https://example.com") == "https://example.com")
    // Strings with no colon at all are returned verbatim.
    #expect(URLSanitizer.sanitize("/local/path") == "/local/path")
}
```

If there's already an equivalent test, skip the create and just add the missing assertions.

- [ ] **Step 3: Run the test to capture current behavior**

```bash
swift test --filter decodeBareColonEntities 2>&1 | tail -10
```

Expected: PASS against the current Foundation-based implementation. This locks behavior before we change it.

- [ ] **Step 4: Rewrite `decodeHTMLColonEntities` without Foundation**

Replace the function body in `Sources/Swiflow/Reactivity/URLSanitizer.swift`:

```swift
/// Decodes the literal colon entities only (`&#58;` decimal,
/// `&#x3a;` / `&#x3A;` hex — the hex form is matched
/// case-insensitively). Other colon encodings (`&colon;`,
/// zero-padded `&#058;`, `&#x0003A;`) are intentionally left
/// literal — DSL callers pass Swift strings, not HTML text, so
/// only the exact obfuscations a hand-crafted attack would use
/// need to be normalised.
///
/// stdlib-only — no Foundation dep. Single-pass scan with a small
/// state machine.
private static func decodeHTMLColonEntities(_ s: String) -> String {
    guard s.contains("&") else { return s }   // fast path: nothing to do
    var out = ""
    out.reserveCapacity(s.count)
    var i = s.startIndex
    while i < s.endIndex {
        if matches(s, at: i, pattern: "&#58;") {
            out.append(":")
            i = s.index(i, offsetBy: "&#58;".count)
        } else if matchesCaseInsensitive(s, at: i, pattern: "&#x3a;") {
            out.append(":")
            i = s.index(i, offsetBy: "&#x3a;".count)
        } else {
            out.append(s[i])
            i = s.index(after: i)
        }
    }
    return out
}

/// True if `s` has `pattern` as an exact substring starting at `i`.
private static func matches(_ s: String, at i: String.Index, pattern: String) -> Bool {
    var si = i
    var pi = pattern.startIndex
    while pi < pattern.endIndex {
        guard si < s.endIndex, s[si] == pattern[pi] else { return false }
        si = s.index(after: si)
        pi = pattern.index(after: pi)
    }
    return true
}

/// Same as `matches`, but ASCII-case-insensitive (pattern lowercased; input
/// folded per-character). Adequate for the two hex entities we care about.
private static func matchesCaseInsensitive(_ s: String, at i: String.Index, pattern: String) -> Bool {
    var si = i
    var pi = pattern.startIndex
    while pi < pattern.endIndex {
        guard si < s.endIndex else { return false }
        let inputLower = Character(s[si].lowercased())
        guard inputLower == pattern[pi] else { return false }
        si = s.index(after: si)
        pi = pattern.index(after: pi)
    }
    return true
}
```

- [ ] **Step 5: Drop `import Foundation` at the top of URLSanitizer.swift**

```swift
// Sources/Swiflow/Reactivity/URLSanitizer.swift
// (delete the line: import Foundation)
```

- [ ] **Step 6: Rerun the URL-sanitizer tests**

```bash
swift test --filter URLSanitizer 2>&1 | tail -20
```

Expected: all green.

- [ ] **Step 7: Audit HMR.swift for actual Foundation use**

```bash
grep -E "Date|UUID|URL\(|JSON|FileManager|NSObject|NSNumber|CharacterSet|String\(format" Sources/Swiflow/Reactivity/HMR.swift
```

Expected: zero hits. If you find any, leave `import Foundation` alone and note the finding in the commit message. If empty:

Open `Sources/Swiflow/Reactivity/HMR.swift` and delete the line `import Foundation` (around line 10).

- [ ] **Step 8: Rebuild to confirm both files compile without Foundation**

```bash
swift build 2>&1 | tail -10
```

Expected: clean build, no errors. If HMR.swift fails to compile after dropping Foundation, restore the import and document why (probably a transitive ext like `String.replacingOccurrences` that I missed).

- [ ] **Step 9: Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add Sources/Swiflow/Reactivity/URLSanitizer.swift \
        Sources/Swiflow/Reactivity/HMR.swift \
        Tests/SwiflowTests/URLSanitizerTests.swift
git commit -m "$(cat <<'EOF'
refactor(swiflow): drop runtime Foundation from URLSanitizer + HMR

URLSanitizer: replace String.replacingOccurrences (Foundation) with
a stdlib-only single-pass scanner over the two literal colon entities
the sanitizer normalizes. Behaviour byte-equivalent.

HMR.swift: import Foundation was vestigial (no Foundation API usage
in the file). Dropped.

Bundle impact small per file; each removed `import Foundation` lets
the linker dead-strip more of Foundation as the build's transitive
references shrink. Mirror call-site removal in upcoming tasks is the
bigger lever.
EOF
)"
```

---

## Task 3: Add `AnyStateCell` protocol + `StateCell<Owner>` + `_ComponentRuntime` sub-protocol

**Files:**
- Create: `Sources/Swiflow/Reactivity/StateCell.swift`
- Modify: `Sources/Swiflow/Reactivity/Component.swift` (add `_ComponentRuntime` protocol; do NOT modify `wireStateAndRestore` yet — that's Task 6)
- Create: `Tests/SwiflowTests/Reactivity/ComponentRuntimeTests.swift`

Task 3 lays the foundation types without removing anything. After this task lands, the build is still green and the existing Mirror-based wireState path still runs.

- [ ] **Step 1: Write the failing test driving the new types**

Create `Tests/SwiflowTests/Reactivity/ComponentRuntimeTests.swift`:

```swift
import Testing
import Foundation
@testable import Swiflow

@Suite("ComponentRuntime + StateCell")
struct ComponentRuntimeTests {

    @Test("StateCell witness dispatches through the typed closures")
    @MainActor
    func witnessDispatch() throws {
        @MainActor final class Owner: Component {
            var box: Int = 7
            var body: VNode { .text("") }
        }
        let cell = StateCell<Owner>(
            name: "box",
            snapshot: { $0.box as Any },
            restore: { o, v in
                guard let i = v as? Int else { return false }
                o.box = i
                return true
            },
            restoreNil: { _ in false }
        )
        let inst = Owner()
        let any: any AnyStateCell = cell

        #expect(any.name == "box")
        #expect(any.snapshot(of: inst) as? Int == 7)
        #expect(any.restore(on: inst, value: 42) == true)
        #expect(inst.box == 42)
        #expect(any.restore(on: inst, value: "wrong type") == false)
        #expect(any.restoreNil(on: inst) == false)
    }

    @Test("_ComponentRuntime adoption keeps Component working for non-adopters")
    @MainActor
    func runtimeOptional() throws {
        @MainActor final class NoRuntime: Component {
            var body: VNode { .text("plain") }
        }
        let inst = NoRuntime()
        let asComponent: any Component = inst
        // Hand-rolled Component conformances simply don't conform.
        #expect((asComponent as? any _ComponentRuntime) == nil)
    }
}
```

- [ ] **Step 2: Run the test — it should fail because types don't exist**

```bash
swift test --filter ComponentRuntime 2>&1 | tail -15
```

Expected: compile error — `cannot find StateCell in scope`, `cannot find AnyStateCell in scope`, `cannot find _ComponentRuntime in scope`.

- [ ] **Step 3: Create `StateCell.swift`**

```bash
mkdir -p Sources/Swiflow/Reactivity
```

Create `Sources/Swiflow/Reactivity/StateCell.swift`:

```swift
// Sources/Swiflow/Reactivity/StateCell.swift
//
// Per-`@State` cell descriptor. Emitted by the `@Component` macro as
// `static let stateCells: [any AnyStateCell]`. The framework iterates
// this array to wire owners, take HMR snapshots, and apply HMR restores —
// replacing the Mirror-based walk that earlier framework versions used.
//
// Two-tier shape: `StateCell<Owner>` is generic so macro-emitted closures
// receive `Owner` directly (no `as!` casts in expanded code, which makes
// the expansion read like Swift a careful human would have written).
// The framework stores them as `[any AnyStateCell]` so it can iterate
// uniformly across component types; the single `as!` cast lives in the
// witness methods below.

/// Existential storage shape for `StateCell<Owner>`. Used by framework
/// code that iterates state cells without knowing the concrete owner type.
@MainActor
public protocol AnyStateCell {
    /// Field name as written by the user (e.g. `"count"` for
    /// `@State var count: Int = 0`). HMR snapshot/restore maps key by this.
    var name: String { get }

    /// Reads the current value from `owner` and returns it as `Any`.
    /// Caller is responsible for passing an `owner` of the right runtime
    /// type — a wrong type is a programmer error and traps via the
    /// `as!` cast inside the witness method.
    func snapshot(of owner: any Component) -> Any

    /// Attempts to write `value` into the cell on `owner`. Returns true
    /// on success, false on type mismatch (the framework logs a
    /// diagnostic and leaves the cell at its declared initial value).
    func restore(on owner: any Component, value: Any) -> Bool

    /// Restores the cell to `nil`. Returns false when `Value` is not
    /// Optional. Called by the HMR walker when the decoded state map
    /// contains an `HMRNilSentinel`.
    func restoreNil(on owner: any Component) -> Bool
}

/// Type-safe `StateCell`. The macro emits these directly per `@State`
/// declaration, e.g. `StateCell<Counter>(name: "count", snapshot: { $0.count as Any }, ...)`.
@MainActor
public struct StateCell<Owner: Component>: AnyStateCell {
    public let name: String
    private let _snapshot: (Owner) -> Any
    private let _restore: (Owner, Any) -> Bool
    private let _restoreNil: (Owner) -> Bool

    public init(
        name: String,
        snapshot: @escaping (Owner) -> Any,
        restore: @escaping (Owner, Any) -> Bool,
        restoreNil: @escaping (Owner) -> Bool
    ) {
        self.name = name
        self._snapshot = snapshot
        self._restore = restore
        self._restoreNil = restoreNil
    }

    // Single cast site for the whole framework. Macro-emitted closures
    // never say `as! Counter` — they receive `Owner` directly.
    public func snapshot(of owner: any Component) -> Any {
        _snapshot(owner as! Owner)
    }
    public func restore(on owner: any Component, value: Any) -> Bool {
        _restore(owner as! Owner, value)
    }
    public func restoreNil(on owner: any Component) -> Bool {
        _restoreNil(owner as! Owner)
    }
}
```

- [ ] **Step 4: Add the `_ComponentRuntime` sub-protocol to `Component.swift`**

Open `Sources/Swiflow/Reactivity/Component.swift`. Below the existing `Component` protocol and its default extension (around the existing `extension Component { ... }` block), add:

```swift
/// Framework-runtime adoption point for `@Component`-decorated classes.
/// The macro emits the conformance + members. Hand-rolled `Component`
/// implementations (test mocks, stubs) can skip it — they just don't
/// get HMR wiring or state-cell dispatch, which is the right default
/// for code outside the macro's contract.
///
/// The leading underscore on the protocol name carries the
/// framework-internal signal once for the whole surface; members inside
/// have clean, unprefixed names.
@MainActor
public protocol _ComponentRuntime: Component {
    /// Descriptors for each `@State` cell on this type. Macro-emitted.
    static var stateCells: [any AnyStateCell] { get }

    /// Installs the owner + scheduler refs the synthesized `didSet`
    /// blocks call into. One call per instance per mount, not one per
    /// state cell. Macro-emitted.
    func bind(owner: AnyComponent, scheduler: Scheduler)
}
```

Do NOT add a default extension with `stateCells: []` and a no-op `bind`. We *want* the type system to enforce that you've adopted both members — and we *want* the framework's `as? any _ComponentRuntime` cast to be the gate for non-macro types.

- [ ] **Step 5: Run the new tests — they should now compile and pass**

```bash
swift test --filter ComponentRuntime 2>&1 | tail -15
```

Expected: both tests pass.

- [ ] **Step 6: Run the full suite to verify no regression**

```bash
swift test 2>&1 | tail -5
```

Expected: all green (existing 546 + 2 new = 548).

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/Reactivity/StateCell.swift \
        Sources/Swiflow/Reactivity/Component.swift \
        Tests/SwiflowTests/Reactivity/ComponentRuntimeTests.swift
git commit -m "$(cat <<'EOF'
feat(swiflow): add AnyStateCell + StateCell<Owner> + _ComponentRuntime

Foundation types for the Phase 15 redesign. Nothing else uses them
yet — Task 5 (Component macro update) and Task 6 (framework rewiring)
will. Existing Mirror-based wireStateAndRestore is unchanged in this
task; the build is still fully Mirror-driven post-commit.

`_ComponentRuntime: Component` is the opt-in sub-protocol the macro
emits conformance for. Hand-rolled Component conformances skip it
entirely; framework checks `as? any _ComponentRuntime` at the wiring
entry point. One underscore on the protocol name carries the
framework-internal signal for the whole surface.

StateCell<Owner> is generic at source so macro-emitted closures
receive Owner directly with no `as!` cast. The single cast site is
inside StateCell's witness methods that satisfy the AnyStateCell
existential.
EOF
)"
```

---

## Task 4: Implement `@State` macro (accessor `didSet` + peer `$projection`)

**Files:**
- Modify: `Sources/Swiflow/Macros.swift` (add `@State` macro declaration)
- Create: `Sources/SwiflowMacrosPlugin/StateMacro.swift`
- Modify: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` (register `StateMacro`)
- Create: `Tests/SwiflowMacrosTests/StateMacroTests.swift`

This task ships the macro standalone. Until Task 5 + 6 land, the macro is harmless — it expands but the framework still uses the Mirror path (which won't find the macro-generated stored properties because they're called `count`, not `_count`, so the Mirror walk will skip them silently). The macro must NOT replace `@State` on the user-side yet — that needs the framework rewiring from Task 6.

**Strategy:** to avoid breaking the existing tree, the macro lives at a NEW name `@MacroState` during this task. Task 6 will swap the `@State` keyword over. This isolation prevents the half-finished surface from breaking existing examples mid-phase.

- [ ] **Step 1: Write the macro expansion test FIRST**

Create `Tests/SwiflowMacrosTests/StateMacroTests.swift`:

```swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "MacroState": StateMacro.self,
]

final class StateMacroTests: XCTestCase {

    // Test 1: Single Int var — emits didSet + $name peer.
    func testSingleIntState() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var count: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                var count: Int = 0 {
                    didSet {
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $count: Binding<Int> {
                    Binding(
                        get: { [unowned self] in self.count },
                        set: { [unowned self] in self.count = $0 }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // Test 2: Optional Int — same shape, just propagates the ? to Binding<Int?>.
    func testOptionalState() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var maybeId: Int? = nil
            }
            """,
            expandedSource: """
            final class Counter {
                var maybeId: Int? = nil {
                    didSet {
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $maybeId: Binding<Int?> {
                    Binding(
                        get: { [unowned self] in self.maybeId },
                        set: { [unowned self] in self.maybeId = $0 }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // Test 3: User-defined didSet on a @MacroState var → diagnostic.
    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var count: Int = 0 {
                    didSet { print("user") }
                }
            }
            """,
            expandedSource: """
            final class Counter {
                @MacroState var count: Int = 0 {
                    didSet { print("user") }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State properties cannot declare their own didSet; move the side effect into a method.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 4: Applied to `let` — diagnostic.
    func testRejectsLet() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState let count: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                @MacroState let count: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State requires a `var` — state cells must be mutable.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 5: Missing type annotation → diagnostic (we need the type for the Binding).
    func testRequiresTypeAnnotation() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var count = 0
            }
            """,
            expandedSource: """
            final class Counter {
                @MacroState var count = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State requires an explicit type annotation (e.g. `@State var count: Int = 0`).",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }
}
```

- [ ] **Step 2: Run tests — they should fail because `StateMacro` doesn't exist**

```bash
swift test --filter StateMacroTests 2>&1 | tail -15
```

Expected: compile error — `cannot find StateMacro in scope` inside the test file's `testMacros` dictionary.

- [ ] **Step 3: Declare the macro at the framework level**

Open `Sources/Swiflow/Macros.swift`. Currently contains only the `@Component` macro declaration. Append:

```swift
/// Reactive state cell on a `@Component`-decorated class. Expansion adds
/// a `didSet` block to the stored property and emits a `$name: Binding<T>`
/// peer property for two-way bindings (`input(.value($count))`).
///
/// **Requires:**
/// - Must be applied to a `var`, not `let`.
/// - Requires an explicit type annotation (`@State var count: Int = 0`).
/// - The host class must be `@MainActor @Component final class` — the
///   `@Component` macro emits the runtime stored properties (`runtimeOwner`,
///   `runtimeScheduler`) that `@State`'s `didSet` writes through.
/// - Cannot declare its own `didSet`. Use a regular `var` and a method
///   if you need observation side-effects.
@attached(accessor)
@attached(peer, names: prefixed($))
public macro MacroState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "StateMacro")
```

The name is `MacroState` for this task; Task 6 renames to `State` when the framework swap-over happens.

- [ ] **Step 4: Implement the macro**

Create `Sources/SwiflowMacrosPlugin/StateMacro.swift`:

```swift
// Sources/SwiflowMacrosPlugin/StateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct StateMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            return []   // diagnosed in peer expansion
        }

        // Reject `let`.
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl.bindingSpecifier),
                message: StateMacroDiagnostic.requiresVar
            ))
            return []
        }

        // Reject user-supplied accessor blocks (didSet/willSet/get/set).
        guard let binding = varDecl.bindings.first,
              binding.accessorBlock == nil else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl.bindings.first?.accessorBlock ?? PatternBindingSyntax(pattern: PatternSyntax(IdentifierPatternSyntax(identifier: "_"))).cast(Syntax.self)),
                message: StateMacroDiagnostic.userDidSetRejected
            ))
            return []
        }

        // Emit a didSet that calls scheduler.markDirty(owner) when both
        // are wired. Runtime fields are emitted by @Component on the
        // enclosing class.
        let didSet: AccessorDeclSyntax = """
            didSet {
                if let s = runtimeScheduler, let o = runtimeOwner {
                    s.markDirty(o)
                }
            }
            """
        return [didSet]
    }

    // MARK: - PeerMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            return []
        }

        // Type annotation is required so we can emit Binding<T>.
        guard let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: StateMacroDiagnostic.requiresType
            ))
            return []
        }
        let valueType = typeAnno.type.trimmedDescription
        let name = identifier.text

        let projected: DeclSyntax = """
            var $\(raw: name): Binding<\(raw: valueType)> {
                Binding(
                    get: { [unowned self] in self.\(raw: name) },
                    set: { [unowned self] in self.\(raw: name) = $0 }
                )
            }
            """
        return [projected]
    }
}

enum StateMacroDiagnostic: DiagnosticMessage {
    case requiresVar
    case requiresType
    case userDidSetRejected

    var message: String {
        switch self {
        case .requiresVar:
            return "@State requires a `var` — state cells must be mutable."
        case .requiresType:
            return "@State requires an explicit type annotation (e.g. `@State var count: Int = 0`)."
        case .userDidSetRejected:
            return "@State properties cannot declare their own didSet; move the side effect into a method."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiflowMacros", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 5: Register the macro in the plugin entry point**

Open `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` and add `StateMacro.self`:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiflowMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ComponentMacro.self,
        StateMacro.self,
    ]
}
```

- [ ] **Step 6: Run the macro tests**

```bash
swift test --filter StateMacroTests 2>&1 | tail -30
```

Expected: all 5 tests pass. If `testRequiresTypeAnnotation` or `testUserDidSetIsRejected` produce extra emissions, tighten the diagnostic guards in the macro until expansion matches the empty-rewrite spec.

If `prefixed($)` causes an error from the Swift Macros API (the peer-name spec is wrong on this Swift version), report BLOCKED — fallback is to keep a tiny value-type `State<T>` purely for the `$projection` (brainstorm option C). Don't paper over.

- [ ] **Step 7: Run the full suite to confirm no regression**

```bash
swift test 2>&1 | tail -5
```

Expected: all green (548 + 5 macro expansion tests = 553).

- [ ] **Step 8: Commit**

```bash
git add Sources/Swiflow/Macros.swift \
        Sources/SwiflowMacrosPlugin/StateMacro.swift \
        Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift \
        Tests/SwiflowMacrosTests/StateMacroTests.swift
git commit -m "$(cat <<'EOF'
feat(macros): implement @MacroState (accessor didSet + peer $projection)

Per Phase 15 spec — the new macro that will replace the State<T>
property wrapper class. Lives at @MacroState for this task to avoid
breaking the existing tree mid-phase; Task 6 swaps the keyword over
to @State once @Component is also updated and the framework is
rewired to use _ComponentRuntime.stateCells.

Macro emits:
  - didSet that calls runtimeScheduler.markDirty(runtimeOwner) (both
    fields synthesized by @Component on the host class — Task 5).
  - $name peer property returning Binding<T> (read/write closures
    capture [unowned self] — bindings are render-frame-scoped).

Diagnostics:
  - @State on let → error
  - @State without type annotation → error
  - @State on a var with user-written didSet → error

Five SwiftSyntaxMacros expansion tests cover the happy path,
Optional<T>, and all three diagnostics.
EOF
)"
```

---

## Task 5: Update `@Component` macro to scan `@State` members + emit runtime conformance

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` (add `MemberMacro` conformance to the existing `ExtensionMacro` struct)
- Modify: `Sources/Swiflow/Macros.swift` (add `@attached(member, names: arbitrary)` to the `@Component` declaration)
- Modify: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` (add tests for the new member emissions)

After this task, `@Component` adds the runtime infrastructure but the framework still uses the Mirror walk — both paths coexist. Task 6 cuts the Mirror path and the framework starts iterating the new `stateCells`.

- [ ] **Step 1: Add the `MemberMacro` test cases first**

Open `Tests/SwiflowMacrosTests/ComponentMacroTests.swift`. The existing `testHappyPath` test asserts only the extension. Add a new test that asserts the member-macro emissions:

```swift
// Test: @Component emits _ComponentRuntime conformance + members.
func testEmitsRuntimeMembers() {
    assertMacroExpansion(
        """
        @Component
        final class Counter {
            @MacroState var count: Int = 0
            @MacroState var label: String = "hi"
            var body: VNode { .text("") }
        }
        """,
        expandedSource: """
        final class Counter {
            @MacroState var count: Int = 0
            @MacroState var label: String = "hi"
            var body: VNode { .text("") }

            private weak var runtimeOwner: AnyComponent?

            private var runtimeScheduler: Scheduler?

            static let stateCells: [any AnyStateCell] = [
                StateCell<Counter>(
                    name: "count",
                    snapshot: {
                        $0.count as Any
                    },
                    restore: { c, v in
                        guard let typed = v as? Int else {
                            return false
                        }
                        c.count = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                ),
                StateCell<Counter>(
                    name: "label",
                    snapshot: {
                        $0.label as Any
                    },
                    restore: { c, v in
                        guard let typed = v as? String else {
                            return false
                        }
                        c.label = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                ),
            ]

            func bind(owner: AnyComponent, scheduler: Scheduler) {
                self.runtimeOwner = owner
                self.runtimeScheduler = scheduler
            }
        }

        extension Counter: Component, _ComponentRuntime {
        }
        """,
        macros: ["Component": ComponentMacro.self, "MacroState": StateMacro.self]
    )
}

// Test: @Component on a class without @State emits empty stateCells.
func testEmptyStateCells() {
    assertMacroExpansion(
        """
        @Component
        final class Static {
            var body: VNode { .text("hi") }
        }
        """,
        expandedSource: """
        final class Static {
            var body: VNode { .text("hi") }

            private weak var runtimeOwner: AnyComponent?

            private var runtimeScheduler: Scheduler?

            static let stateCells: [any AnyStateCell] = []

            func bind(owner: AnyComponent, scheduler: Scheduler) {
                self.runtimeOwner = owner
                self.runtimeScheduler = scheduler
            }
        }

        extension Static: Component, _ComponentRuntime {
        }
        """,
        macros: ["Component": ComponentMacro.self]
    )
}

// Test: Optional @State emits non-trivial restoreNil.
func testOptionalRestoreNil() {
    assertMacroExpansion(
        """
        @Component
        final class Counter {
            @MacroState var maybeId: Int? = nil
            var body: VNode { .text("") }
        }
        """,
        expandedSource: """
        final class Counter {
            @MacroState var maybeId: Int? = nil
            var body: VNode { .text("") }

            private weak var runtimeOwner: AnyComponent?

            private var runtimeScheduler: Scheduler?

            static let stateCells: [any AnyStateCell] = [
                StateCell<Counter>(
                    name: "maybeId",
                    snapshot: {
                        $0.maybeId as Any
                    },
                    restore: { c, v in
                        guard let typed = v as? Int? else {
                            return false
                        }
                        c.maybeId = typed
                        return true
                    },
                    restoreNil: { c in
                        c.maybeId = nil
                        return true
                    }
                ),
            ]

            func bind(owner: AnyComponent, scheduler: Scheduler) {
                self.runtimeOwner = owner
                self.runtimeScheduler = scheduler
            }
        }

        extension Counter: Component, _ComponentRuntime {
        }
        """,
        macros: ["Component": ComponentMacro.self, "MacroState": StateMacro.self]
    )
}
```

- [ ] **Step 2: Run — tests should fail because the macro doesn't emit members yet**

```bash
swift test --filter ComponentMacroTests 2>&1 | tail -25
```

Expected: the new tests fail — expansion doesn't include `runtimeOwner`, `runtimeScheduler`, `stateCells`, or `bind`.

- [ ] **Step 3: Update the `@Component` macro declaration in `Macros.swift`**

Open `Sources/Swiflow/Macros.swift`. Change the existing `@attached(extension, ...)` declaration to add member emission:

```swift
/// Conforms a `final class` to `Component` and emits the
/// `_ComponentRuntime` runtime infrastructure: stored properties for
/// owner/scheduler refs, the `bind(owner:scheduler:)` hook, and a
/// `stateCells` array describing each `@State`-decorated member.
@attached(extension, conformances: Component, _ComponentRuntime)
@attached(member, names:
    named(runtimeOwner),
    named(runtimeScheduler),
    named(stateCells),
    named(bind)
)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")
```

- [ ] **Step 4: Add the `MemberMacro` conformance to ComponentMacro.swift**

Open `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`. The existing struct conforms to `ExtensionMacro`. Add `MemberMacro` conformance:

Change the struct declaration line:

```swift
// BEFORE
public struct ComponentMacro: ExtensionMacro {

// AFTER
public struct ComponentMacro: ExtensionMacro, MemberMacro {
```

Update the `expansion(of:attachedTo:providingExtensionsOf:...)` method to include `_ComponentRuntime` in the emitted extension:

```swift
// Replace:
return [try ExtensionDeclSyntax("extension \(type): Component {}")]

// With:
return [try ExtensionDeclSyntax("extension \(type): Component, _ComponentRuntime {}")]
```

At the bottom of the struct (before its closing `}`), add the `MemberMacro` expansion:

```swift
    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return []   // already diagnosed by ExtensionMacro path
        }
        let className = classDecl.name.text

        // Scan member list for @MacroState (Task 4-and-Task-6 use the same
        // macro under different keywords during the migration window).
        // Task 6 renames @MacroState → @State; this scanner accepts both
        // attribute names for the lifetime of Task 5 + Task 6.
        var cellEntries: [String] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isState = varDecl.attributes.contains { attr in
                guard let attrName = attr.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                    return false
                }
                return attrName == "MacroState" || attrName == "State"
            }
            guard isState else { continue }
            guard let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  let typeAnno = binding.typeAnnotation else {
                continue   // diagnosed by @State's own expansion
            }
            let name = identifier.text
            let valueType = typeAnno.type.trimmedDescription
            let isOptional = valueType.hasSuffix("?")

            let restoreNilBody = isOptional
                ? "c.\(name) = nil\n        return true"
                : "false"

            cellEntries.append("""
                StateCell<\(className)>(
                    name: "\(name)",
                    snapshot: { $0.\(name) as Any },
                    restore: { c, v in
                        guard let typed = v as? \(valueType) else { return false }
                        c.\(name) = typed
                        return true
                    },
                    restoreNil: { \(isOptional ? "c" : "_") in
                        \(restoreNilBody)
                    }
                )
                """)
        }

        let stateCellsArray: String
        if cellEntries.isEmpty {
            stateCellsArray = "static let stateCells: [any AnyStateCell] = []"
        } else {
            let joined = cellEntries.joined(separator: ",\n    ")
            stateCellsArray = "static let stateCells: [any AnyStateCell] = [\n    \(joined),\n]"
        }

        return [
            "private weak var runtimeOwner: AnyComponent?",
            "private var runtimeScheduler: Scheduler?",
            DeclSyntax(stringLiteral: stateCellsArray),
            """
            func bind(owner: AnyComponent, scheduler: Scheduler) {
                self.runtimeOwner = owner
                self.runtimeScheduler = scheduler
            }
            """,
        ]
    }
```

- [ ] **Step 5: Run the ComponentMacro tests**

```bash
swift test --filter ComponentMacroTests 2>&1 | tail -40
```

Expected: all 4-5 tests pass (existing happy-path + diagnostics + the 3 new tests). Formatting may differ slightly from the spec text (SwiftSyntax pretty-printing) — adjust the test's `expandedSource` to match what the macro actually produces, but verify the structure (member names, types, count) is correct.

- [ ] **Step 6: Run the full Swift suite**

```bash
swift test 2>&1 | tail -5
```

Expected: all green. The existing examples still build because `@MacroState` doesn't exist on any of them yet, and `@Component` now also emits members that the framework doesn't use (harmless — extra stored properties that nothing reads).

- [ ] **Step 7: Confirm HelloWorld still builds (release path)**

```bash
swift build -c release --product swiflow 2>&1 | tail -5
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build 2>&1 | tail -5
cd ../..
```

Expected: clean builds. The HelloWorld Counter uses `@State` (the old class-based wrapper), not `@MacroState`, so it's unaffected by this task.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowMacrosPlugin/ComponentMacro.swift \
        Sources/Swiflow/Macros.swift \
        Tests/SwiflowMacrosTests/ComponentMacroTests.swift
git commit -m "$(cat <<'EOF'
feat(macros): @Component scans @State members + emits runtime conformance

The @Component macro now both:
  - Extension macro: emits `extension Foo: Component, _ComponentRuntime {}`
  - Member macro: scans the class body for @MacroState (Task 4) and
    @State (Task 6 rename) decorated vars; emits stateCells array,
    runtimeOwner/runtimeScheduler stored props, and bind() hook.

Optional types get a non-trivial restoreNil; non-Optional get
`{ _ in false }`. Member emission preserves field name as written.

Existing tree is unaffected — no example uses @MacroState yet, and
the new @Component-emitted runtimeOwner/runtimeScheduler stored
properties are unused until Task 6 wires the framework path.
EOF
)"
```

---

## Task 6: Rewrite framework + delete `State<T>`; swap `@MacroState` → `@State`

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Component.swift` (rewrite `wireStateAndRestore`)
- Modify: `Sources/Swiflow/Reactivity/HMR.swift` (rewrite `makeSnapshot` + `applyRestore`)
- Rewrite: `Sources/Swiflow/Reactivity/State.swift` (delete `State<T>`, `Box<T>`, `StateWireable`; keep `Binding<T>` only)
- Modify: `Sources/Swiflow/Macros.swift` (rename `@MacroState` → `@State`)
- Delete: nothing — the renamed macro keeps the same module/type/external name
- Modify: `Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift` (migrate any direct `State<T>` constructors)
- Modify: `Tests/SwiflowTests/HMR/StateHMRHookTests.swift` (same)
- Modify: `Tests/SwiflowMacrosTests/StateMacroTests.swift` (update `testMacros` map: `"State": StateMacro.self`)
- Modify: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` (testMacros maps too)

This is the highest-risk task in the phase. It cuts the Mirror path and switches every `@State` site over to the new macro. After commit, every example + test runs through the new path.

- [ ] **Step 1: Audit `State<T>` direct usage in tests**

```bash
grep -n "State<" Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift Tests/SwiflowTests/HMR/StateHMRHookTests.swift
```

Read the matching lines + context. Each direct `State<Int>()` (or similar) constructor will need to be replaced with a `@MainActor` test-only `Component` class that holds an `@State` and exposes it for the test. Pattern:

```swift
// BEFORE (today):
let s = State<Int>(wrappedValue: 5)
s.wrappedValue = 10

// AFTER (post-Phase-15):
@MainActor final class TestHost: Component {
    @State var box: Int = 5
    var body: VNode { .text("") }
}
let host = TestHost()
host.box = 10
```

Most call sites are small; rewrite each one inline as part of this task.

- [ ] **Step 2: Rewrite `wireStateAndRestore` in `Component.swift`**

Replace the entire current `wireStateAndRestore` function (the one containing `let mirror = Mirror(reflecting: owner.instance)`) with:

```swift
/// Fused owner-wiring + HMR restore. Iterates the macro-emitted
/// `_ComponentRuntime.stateCells` to apply scheduler ownership and
/// snapshot values — no Mirror, no reflection metadata required.
///
/// Hand-rolled `Component` conformances skip this entirely (they don't
/// adopt `_ComponentRuntime`), which is the right default for code
/// outside the macro's contract.
///
/// `stateMap` is nil when no HMR swap is pending; wiring still happens,
/// restore is skipped.
func wireStateAndRestore(
    on owner: AnyComponent,
    scheduler: Scheduler?,
    stateMap: [String: Any]?,
    path: String = ""
) {
    guard scheduler != nil || stateMap != nil else { return }
    guard let runtime = owner.instance as? any _ComponentRuntime else { return }

    if let scheduler {
        runtime.bind(owner: owner, scheduler: scheduler)
    }

    guard let stateMap else { return }
    let cells = type(of: runtime).stateCells
    for cell in cells {
        guard let newValue = stateMap[cell.name] else { continue }
        let ok = newValue is HMRNilSentinel
            ? cell.restoreNil(on: runtime)
            : cell.restore(on: runtime, value: newValue)
        if !ok {
            let typeName = String(reflecting: type(of: runtime))
            swiflowDiagnostic(
                "HMR restore: type mismatch on \(typeName).\(cell.name) at path '\(path)'. Field reset to its declared initial value."
            )
        }
    }
}
```

Also update the doc comment on the package-level `wireState(on:scheduler:)` thin wrapper — it still calls `wireStateAndRestore` so its body doesn't change, but the comment shouldn't mention Mirror anymore.

- [ ] **Step 3: Rewrite `makeSnapshot` in `HMR.swift`**

Find `makeSnapshot(for:path:vnode:)`. Replace the Mirror walk:

```swift
// BEFORE:
var stateMap: [String: Any] = [:]
let mirror = Mirror(reflecting: instance)
for child in mirror.children {
    guard let label = child.label else { continue }
    guard let wireable = child.value as? StateWireable else { continue }
    let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
    stateMap[fieldName] = wireable._hmrSnapshotValue()
}

// AFTER:
var stateMap: [String: Any] = [:]
if let runtime = instance as? any _ComponentRuntime {
    for cell in type(of: runtime).stateCells {
        stateMap[cell.name] = cell.snapshot(of: runtime)
    }
}
```

- [ ] **Step 4: Rewrite `applyRestore` in `HMR.swift`**

Find `applyRestore(index:to:at:key:)`. Replace its Mirror walk identically:

```swift
// BEFORE:
let mirror = Mirror(reflecting: instance)
for child in mirror.children {
    guard let label = child.label else { continue }
    guard let wireable = child.value as? StateWireable else { continue }
    let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
    guard let newValue = stateMap[fieldName] else { continue }
    let ok: Bool
    if newValue is HMRNilSentinel {
        ok = wireable._hmrRestoreNil()
    } else {
        ok = wireable._hmrRestore(newValue)
    }
    // ... diagnostic ...
}

// AFTER:
guard let runtime = instance as? any _ComponentRuntime else { return }
for cell in type(of: runtime).stateCells {
    guard let newValue = stateMap[cell.name] else { continue }
    let ok = newValue is HMRNilSentinel
        ? cell.restoreNil(on: runtime)
        : cell.restore(on: runtime, value: newValue)
    if !ok {
        let typeName = String(reflecting: type(of: runtime))
        swiflowDiagnostic(
            "HMR restore: type mismatch on \(typeName).\(cell.name) at path '\(path)'. Field reset to its declared initial value."
        )
    }
}
```

- [ ] **Step 5: Rewrite `State.swift` to keep only `Binding<T>`**

Open `Sources/Swiflow/Reactivity/State.swift`. Delete everything except the `Binding<T>` struct. The new file body should be:

```swift
// Sources/Swiflow/Reactivity/State.swift
//
// Phase 15 — `@State` is now an attached macro (see `Macros.swift` and
// `SwiflowMacrosPlugin/StateMacro.swift`). The previous `State<T>` /
// `Box<T>` / `StateWireable` machinery is deleted; per-cell wiring is
// now driven by `_ComponentRuntime.stateCells` emitted by `@Component`.
//
// What survives: the `Binding<T>` value type that `@State`'s peer-macro
// expansion uses for the `$name` projection.

/// Two-way binding shaped like SwiftUI's. Returned from a `@State` var's
/// `$`-prefix projection:
///
/// ```swift
/// @State var text = ""
/// // ...
/// input(.value($text))         // .input event, text round-trip
/// ```
///
/// Consumers ship in `SwiflowWeb.AttributeModifiers`: `.value(_:)`,
/// `.checked(_:)`, and `.selection(_:)` — all in both prefix
/// (`Attribute` static) and postfix (`VNode` method) shapes.
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}
```

That's the whole file. ~28 lines, down from the current 200+.

- [ ] **Step 6: Rename `@MacroState` to `@State` in `Macros.swift`**

Open `Sources/Swiflow/Macros.swift`. Change:

```swift
// BEFORE
public macro MacroState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "StateMacro")

// AFTER
public macro State() = #externalMacro(module: "SwiflowMacrosPlugin", type: "StateMacro")
```

(Same module+type external pointer; only the user-facing name changes.)

- [ ] **Step 7: Update macro test fixtures to use `@State` instead of `@MacroState`**

In `Tests/SwiflowMacrosTests/StateMacroTests.swift`:

```swift
// BEFORE
private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "MacroState": StateMacro.self,
]
// Tests use @MacroState

// AFTER
private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "State": StateMacro.self,
]
// All @MacroState references in test fixtures → @State
```

Use `sed` for the fixture replacement:

```bash
sed -i.bak 's/@MacroState/@State/g; s/"MacroState"/"State"/g' \
    Tests/SwiflowMacrosTests/StateMacroTests.swift
rm Tests/SwiflowMacrosTests/StateMacroTests.swift.bak
```

In `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` do the same:

```bash
sed -i.bak 's/@MacroState/@State/g; s/"MacroState"/"State"/g' \
    Tests/SwiflowMacrosTests/ComponentMacroTests.swift
rm Tests/SwiflowMacrosTests/ComponentMacroTests.swift.bak
```

Also: in `ComponentMacro.swift`, the member-macro scanner accepts both `"MacroState"` and `"State"` — that dual handling can now be simplified to `"State"` only, but it's harmless to leave both in place for safety. Recommendation: leave both for now; tighten in a follow-up if anyone cares.

- [ ] **Step 8: Migrate direct `State<T>` constructors in non-macro tests**

For each match from Step 1, rewrite the test to use a `@MainActor`-isolated `@State`-bearing test class. Specific files:

`Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift`:
- Wherever you see `let s = State<X>(wrappedValue: ...)`, replace with a small test-only Component:
  ```swift
  @MainActor @Component final class _BindingHost {
      @State var value: X = ...
      var body: VNode { .text("") }
  }
  let host = _BindingHost()
  // use host.value and host.$value instead of s.wrappedValue / s.projectedValue
  ```

`Tests/SwiflowTests/HMR/StateHMRHookTests.swift`: same pattern. If a test was specifically validating `State<T>._setOwner` semantics (an internal contract that's now gone), delete it — the new framework path is covered by `ComponentRuntimeTests` from Task 3.

- [ ] **Step 9: Build the framework**

```bash
swift build 2>&1 | tail -15
```

Expected: clean build. Common breaks:
- `cannot find 'State' in scope` somewhere — find any leftover reference to the old class. The macro doesn't introduce a `State` type name; the var the macro is applied to keeps its user-given type (Int, String, etc.).
- `cannot find 'StateWireable' in scope` — find any test or source still referencing this protocol; delete the reference.

- [ ] **Step 10: Run the full Swift suite**

```bash
swift test 2>&1 | tail -10
```

Expected: all green. Common failures:
- HMR round-trip test fails: probably the `String(reflecting: type(of: runtime))` is returning a different typeName under the new path. Run the specific test in isolation to see what it actually got.
- A test asserts an exact count of `@State` cells: the macro might be including or excluding something differently from Mirror. Compare cell name lists.

- [ ] **Step 11: Confirm HelloWorld release build still works end-to-end**

```bash
swift build -c release --product swiflow 2>&1 | tail -3
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build 2>&1 | tail -10
ls -la .build/plugins/PackageToJS/outputs/Package/App.wasm
cd ../..
```

Expected: clean release build, App.wasm present. The byte size will be close to the Task 5 baseline (Mirror call sites in source are gone, but the runtime helpers still load because the flag isn't on yet — Task 7).

- [ ] **Step 12: Re-measure WASM byte sizes (informational)**

```bash
wc -c examples/HelloWorld/.build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -c -9 examples/HelloWorld/.build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
```

Note the numbers. Expectation: ~no change vs Phase 14b Track 2 baseline (46,059,478 raw / 18,165,326 gzipped). The big change waits for Task 7.

- [ ] **Step 13: Commit**

```bash
git add Sources/Swiflow/Reactivity/Component.swift \
        Sources/Swiflow/Reactivity/HMR.swift \
        Sources/Swiflow/Reactivity/State.swift \
        Sources/Swiflow/Macros.swift \
        Tests/SwiflowMacrosTests/StateMacroTests.swift \
        Tests/SwiflowMacrosTests/ComponentMacroTests.swift \
        Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift \
        Tests/SwiflowTests/HMR/StateHMRHookTests.swift
git commit -m "$(cat <<'EOF'
refactor(swiflow): cut Mirror walk; @State is now a macro

The big surgery for Phase 15:
  - wireStateAndRestore, makeSnapshot, applyRestore all switched to
    iterating type(of: runtime).stateCells emitted by the @Component
    macro. The Mirror(reflecting:).children walks are gone.
  - State<T> class, Box<T>, StateWireable protocol deleted.
    State.swift is now ~28 lines, holding only the Binding<T>
    value type used by the @State macro's $-projection.
  - @MacroState renamed to @State (the new user-facing macro). All
    macro test fixtures + the ComponentMacro member scanner updated.
  - Tests that constructed State<T> directly migrated to use a small
    @MainActor @Component @State-bearing test-host class instead.

Bundle impact at this commit: ~0% (Mirror references in user code
are gone, but the runtime demangler stays alive until -disable-
reflection-metadata flips in Task 7).
EOF
)"
```

---

## Task 7: Flip `-Xswiftc -disable-reflection-metadata` in release builds

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` (in `BuildInvocation.composeArguments()`)
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift`

- [ ] **Step 1: Locate the existing `-Xswiftc -Osize` site**

```bash
grep -n "Xswiftc" Sources/SwiflowCLI/Commands/BuildCommand.swift
```

Expected: lines in `composeArguments()` for the release branch where `-Xswiftc -Osize` and `-Xswiftc -gnone` are appended.

- [ ] **Step 2: Write the failing test**

In `Tests/SwiflowCLITests/BuildCommandTests.swift`, add (next to the existing release-flags test):

```swift
@Test("Release-mode invocation passes -disable-reflection-metadata via -Xswiftc")
func releaseDisablesReflectionMetadata() throws {
    let invocation = BuildInvocation(
        swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
        projectPath: URL(fileURLWithPath: "/tmp/demo"),
        swiftSDK: "swift-6.3-RELEASE_wasm",
        toolchainBundleID: nil,
        configuration: .release
    )
    let args = invocation.composeArguments()

    let xSwiftcIndices = args.indices.filter { args[$0] == "-Xswiftc" }
    let followers = xSwiftcIndices.map { args[args.index(after: $0)] }
    #expect(followers.contains("-disable-reflection-metadata"))
}

@Test("Dev-mode invocation does NOT pass -disable-reflection-metadata")
func devKeepsReflectionMetadata() throws {
    let invocation = BuildInvocation(
        swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
        projectPath: URL(fileURLWithPath: "/tmp/demo"),
        swiftSDK: "swift-6.3-RELEASE_wasm",
        toolchainBundleID: nil,
        configuration: .dev
    )
    let args = invocation.composeArguments()
    #expect(!args.contains("-disable-reflection-metadata"))
}
```

- [ ] **Step 3: Run — tests should fail**

```bash
swift test --filter BuildCommandTests 2>&1 | tail -10
```

Expected: FAIL (the flag isn't in the composed args yet).

- [ ] **Step 4: Add the flag to the release branch of `composeArguments()`**

Open `Sources/SwiflowCLI/Commands/BuildCommand.swift` and find the release case in `composeArguments`. Append `-Xswiftc -disable-reflection-metadata` after the existing `-Xswiftc -gnone`:

```swift
case .release:
    arguments.append(contentsOf: [
        "-c", "release",
        "-Xswiftc", "-Osize",
        "-Xswiftc", "-gnone",
        "-Xswiftc", "-disable-reflection-metadata",
    ])
```

(If the existing block adds these BEFORE the `js` subcommand per Track 2's fix, follow that placement — the test asserts on `args.contains` rather than position.)

- [ ] **Step 5: Run BuildCommand tests**

```bash
swift test --filter BuildCommandTests 2>&1 | tail -10
```

Expected: PASS (both new tests + existing pinned-argv test if any).

- [ ] **Step 6: Build the CLI fresh and verify a release build of HelloWorld still works**

```bash
swift build -c release --product swiflow 2>&1 | tail -3
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build 2>&1 | tail -5
```

**Crucial check:** the build succeeds. If `-disable-reflection-metadata` is rejected by the WASM SDK toolchain (Swift 6.3 should accept it), report BLOCKED. If the build SUCCEEDS but App.wasm crashes at runtime when loaded by HelloWorld, also BLOCKED — that's the spec's "high-risk assumption" about `String(reflecting:)` failing.

- [ ] **Step 7: Smoke-test the actual page**

```bash
# from examples/HelloWorld (you're still cd'd in there from Step 6):
python3 -m http.server 3030 &
SERVER_PID=$!
sleep 1
# Open http://localhost:3030 in a browser, observe the Counter component renders + count increments.
# (If running headless, use playwright instead — see Step 8.)
kill $SERVER_PID
cd ../..
```

Expected: Counter renders, increment button works, no console errors.

- [ ] **Step 8: Run the Playwright SW + progress specs end-to-end**

```bash
cd Tests/playwright
npx playwright test --config=playwright.sw.config.ts 2>&1 | tail -15
cd ../..
```

Expected: both `sw-cache.spec.ts` and `progress.spec.ts` pass. This is the strongest end-to-end signal that the new path works in a real browser with the flag on.

If they fail: revert the flag flip locally (`git stash`), confirm they pass, then re-investigate — the symptom will tell you whether HMR keying broke (typeName), the macro emission has a bug Task 5-6 didn't catch, or the runtime can't compile with reflection off.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowCLI/Commands/BuildCommand.swift \
        Tests/SwiflowCLITests/BuildCommandTests.swift
git commit -m "$(cat <<'EOF'
perf(build): enable -disable-reflection-metadata for release builds

The payoff flag. Mirror call sites are gone (Phase 15 Tasks 1+6),
which lets the linker dead-strip the demangler and SIMD
debugDescription helpers that Mirror references pin. Dev builds keep
reflection metadata (Phase 13b DWARF debugging story unaffected).

Measurement of the actual bundle saving happens in Task 8.
EOF
)"
```

---

## Task 8: Measure, audit, update baseline

**Files:**
- Modify: `docs/perf/bundle-baseline.json`
- Modify: `docs/perf/2026-05-26-wasm-bundle-audit.md` (append a "Phase 15" row + brief commentary)

- [ ] **Step 1: Capture the post-Task-7 measurements**

```bash
swift build -c release --product swiflow 2>&1 | tail -2
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build 2>&1 | tail -5
RAW=$(wc -c < .build/plugins/PackageToJS/outputs/Package/App.wasm | tr -d ' ')
GZIP=$(gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c | tr -d ' ')
echo "WASM raw: $RAW"
echo "WASM gzip: $GZIP"
cd ../..
```

Note both numbers.

- [ ] **Step 2: Compute the delta against the Phase 14b baseline**

Phase 14b baseline (from `docs/perf/bundle-baseline.json` pre-Phase-15):
- `wasm_bytes: 46059478`
- `wasm_gzip_bytes: 18165326`
- `total_gzip_bytes: 18176904`

```bash
PHASE15_RAW=$RAW            # from Step 1
PHASE15_GZIP=$GZIP          # from Step 1
python3 -c "
gzip_old = 18165326
gzip_new = $PHASE15_GZIP
delta = gzip_old - gzip_new
pct = (delta / gzip_old) * 100
print(f'gzip delta: {delta:,} bytes ({pct:.2f}%)')
"
```

**Decision gate:**
- ≥ 5% reduction → ship as planned.
- 2-5% → ship, document the lower-than-expected savings in the audit doc.
- < 2% → STOP. The phase doesn't deliver. Surface to user; do not advance to Task 9 without explicit sign-off. The likely cause is a Mirror reference we missed — re-run `grep -rn "Mirror(reflecting" Sources/ --include="*.swift"` and look at every remaining hit.

- [ ] **Step 3: Update `docs/perf/bundle-baseline.json`**

Read the current file, update the WASM bytes + total bytes fields with the new numbers:

```bash
cat docs/perf/bundle-baseline.json
```

Edit values:
- `wasm_bytes` → new raw from Step 1
- `wasm_gzip_bytes` → new gzip from Step 1
- `total_bytes` → new raw + js_bytes (js_bytes unchanged)
- `total_gzip_bytes` → new gzip + js_gzip_bytes (js_gzip_bytes unchanged)
- `measured_at` → today's date

- [ ] **Step 4: Append a Phase 15 row to the audit doc**

Open `docs/perf/2026-05-26-wasm-bundle-audit.md`. Find the headline-numbers table. Append a row:

```markdown
| Phase 15 — Mirror call sites removed + -disable-reflection-metadata | <new raw> | <new gzip> | Phase 15 — see `docs/superpowers/specs/2026-05-26-phase15-dependency-diet-design.md` |
```

Below the table, add a brief paragraph capturing what changed:

```markdown
## Phase 15 outcome — 2026-05-26

`@State` is now a Swift attached macro (no more `State<T>` heap class).
The framework's three Mirror walks (wireStateAndRestore, makeSnapshot,
applyRestore) now iterate macro-emitted `_ComponentRuntime.stateCells`.
JS-bridge Optional unwraps moved from `Mirror.displayStyle` to an
exhaustive type switch. Two runtime `import Foundation`s dropped
(URLSanitizer, HMR.swift).

Release builds now compile with `-Xswiftc -disable-reflection-metadata`.

**Saving:** <delta> bytes (<%>%) gzipped from the Phase 14b post-trim
baseline.

**Remaining levers post-Phase-15:**
- The four runtime imports still needed (JavaScriptKit's bridge types,
  NSNumber where unavoidable) — small individual but each removal lets
  more of Foundation dead-strip.
- Custom serializer for HMR primitives (replacing the closed Bool/Int/
  Double/String switch with a `HMRPrimitive` enum + macro-generated
  encoders) would eliminate the remaining type-switch ladders.
```

Fill in `<new raw>`, `<new gzip>`, `<delta>`, `<%>`.

- [ ] **Step 5: Commit**

```bash
git add docs/perf/bundle-baseline.json \
        docs/perf/2026-05-26-wasm-bundle-audit.md
git commit -m "$(cat <<'EOF'
docs(perf): record Phase 15 bundle-size measurement

Post-Mirror-removal + -disable-reflection-metadata measurement.
bundle-baseline.json updated with new totals; audit doc gets a Phase
15 row and a brief outcome section pointing at remaining levers.
EOF
)"
```

---

## Task 9: CHANGELOG + README + push

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Add the CHANGELOG entry**

Open `CHANGELOG.md`. Above the existing `[Phase 14b — Track 3]` entry, add:

```markdown
## [Phase 15] — 2026-05-26

**Stability:** Internal redesign. User-facing API unchanged: `@MainActor
@Component final class Foo`, `@State var count = 0`, `$count`, and all
forms-validation / router / SwiflowTesting surfaces work identically.

### Changed
- `@State` is now an attached macro (accessor `didSet` + peer
  `$`-projection). The previous `final class State<Value>` property
  wrapper + `Box<Value>` heap cell + `StateWireable` protocol are
  deleted; state lives inline on the component class. Setter routes
  through a synthesized `didSet` that calls `scheduler.markDirty(owner)`.
- `@Component` macro now also scans its class body for `@State` members
  and emits `_ComponentRuntime` conformance: a static `stateCells: [any
  AnyStateCell]` array, a `bind(owner:scheduler:)` hook, and the
  private `runtimeOwner` / `runtimeScheduler` storage. The framework
  iterates `stateCells` instead of walking `Mirror.children` — no
  reflection metadata required.
- HMRBridge + DevAPI Optional-value encoding switched from
  `Mirror.displayStyle == .optional` to an exhaustive type switch over
  `Bool?`, `Int?`, `Double?`, `String?`.
- `URLSanitizer` no longer imports Foundation — `decodeHTMLColonEntities`
  uses a stdlib-only single-pass scanner over the two literal entities.
- `HMR.swift` dropped its vestigial `import Foundation`.

### Added
- `_ComponentRuntime: Component` sub-protocol — opt-in adoption point
  for the framework-runtime members the `@Component` macro emits.
  Hand-rolled `Component` conformances skip it (correct default).
- `AnyStateCell` protocol + `StateCell<Owner>` generic struct in
  `Sources/Swiflow/Reactivity/StateCell.swift`. Macro-emitted closures
  receive the concrete owner type — no `as!` casts in expansion output.
- Release builds compile with `-Xswiftc -disable-reflection-metadata`.

### Bundle-size impact
See `docs/perf/2026-05-26-wasm-bundle-audit.md` for the Phase 15 row
and outcome section. `docs/perf/bundle-baseline.json` refreshed to
the new measured totals.

### Migration
- `@Component`-decorated classes: zero source changes required. The
  macro syntax and runtime behaviour are unchanged.
- Hand-rolled `Component` conformances (test mocks, exotic adopters):
  zero *required* changes — Component's existing requirements are
  unchanged. To opt into HMR support, conform to `_ComponentRuntime`
  and implement `stateCells` + `bind(owner:scheduler:)` by hand. No
  existing hand-rolled type does this today.
- Tests that constructed `State<T>` directly were migrated to use a
  small `@MainActor @Component final class` test-host pattern.
```

- [ ] **Step 2: Refresh README status + cost + test counts**

Open `README.md`. Make these edits:

1. **Status line** (around line 16): replace the Phase 14b Track 3 wording with:
   > "**Status:** Phase 15 (Pre-1.0 Dependency Diet) — `@State` is now an attached macro; the runtime no longer walks `Mirror` to discover state cells. Release builds drop reflection metadata, shaving <delta>% off the gzipped bundle (was 18.17 MB, now <new gzip MB>). Track 1's service-worker cache still serves visit #2+ from disk. User-facing API unchanged."

2. **"What works today" header** (around line 18): bump to "(Phase 15)".

3. **Cost-table WASM row**: update raw + gzipped numbers to match the new `bundle-baseline.json`.

4. **Test counts**: refresh from `swift test` output. Both line 43 and the Testing section (~line 147) mention counts.

5. **Historical "Status" paragraph** (around line 74): prepend a Phase 15 sentence in the same pattern as Track 3's:
   > "Phase 15 (Pre-1.0 Dependency Diet) complete — @State is now a Swift attached macro, runtime Mirror walks deleted, release builds compile with -disable-reflection-metadata. Bundle saving documented in docs/perf/2026-05-26-wasm-bundle-audit.md. Phase 14b Track 3 (Progress UI) ..."

- [ ] **Step 3: Sanity-check the prose against actual numbers**

```bash
grep -c "Phase 15" CHANGELOG.md   # expect ≥ 1
grep -c "Phase 15" README.md      # expect ≥ 2
# Cross-check numbers in README against bundle-baseline.json:
cat docs/perf/bundle-baseline.json
```

If any number in README doesn't match the JSON, fix it.

- [ ] **Step 4: Commit and push**

```bash
git add CHANGELOG.md README.md
git commit -m "$(cat <<'EOF'
docs: Phase 15 — Pre-1.0 Dependency Diet shipped

CHANGELOG entry above Phase 14b Track 3 documents the @State macro
redesign, the Mirror call-site removals, and the -disable-reflection-
metadata flag flip. README status, cost table, and test counts updated
to reflect the new baseline.

User-facing API unchanged; the redesign is invisible to user code.
Bundle saving and audit details in docs/perf/2026-05-26-wasm-bundle-
audit.md.
EOF
)"
git push origin main
```

Pushing to main matches the established Phase 14b closeout pattern.

---

## Final verification

After Task 9:

```bash
# CLI tools healthy
./.build/release/swiflow doctor             # exit 0

# Swift suite
swift test 2>&1 | tail -5                    # all green, count >= 548

# Macro suite
swift test --filter SwiflowMacrosTests 2>&1 | tail -5   # all green

# JS driver suite
cd js-driver && npm test 2>&1 | tail -5     # 30 PASS
cd ..

# Playwright (SW + progress against the release build)
cd Tests/playwright
npx playwright test --config=playwright.sw.config.ts 2>&1 | tail -10
cd ../..

# HelloWorld release build measured matches the baseline
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build
gzip -c -9 .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c
# Must equal docs/perf/bundle-baseline.json:wasm_gzip_bytes
cd ../..
```

**Success criterion from the spec:** all 546+ Swift tests + 30+ JS tests + Playwright specs green AND `total_gzip_bytes` in `docs/perf/bundle-baseline.json` is ≥5% below the Phase 14b post-trim baseline (≤17,268,058 bytes; stretch ≤15,450,368 bytes). If <2% reduction landed at Task 8, the phase shipped with explicit user sign-off after audit.
