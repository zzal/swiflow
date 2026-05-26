# Phase 15 — Pre-1.0 Dependency Diet: Mirror Removal + Foundation Audit

**Goal:** Remove every runtime `Mirror` call site, prune the small runtime Foundation surface, and enable `-Xswiftc -disable-reflection-metadata` on release builds. Target ≥5% gzipped reduction from the Phase 14b post-trim baseline (18,176,904 bytes), stretch 15%.

**Strategy:** The phase is a dependency diet, not a single feature. Three coordinated moves; the @State redesign is the dominant lever, but it only delivers savings when paired with removing the smaller Mirror call sites AND flipping the compiler flag — because the runtime helpers Mirror pins (demangler, SIMD `debugDescription`, etc.) only dead-strip when every reference is gone.

---

## Honest framing — what Phase 14b taught us

Track 2's audit at `docs/perf/2026-05-26-wasm-bundle-audit.md` measured `-Xswiftc -disable-reflection-metadata` empirically and found only ~0.25% gzipped saving on its own. Not because the lever is small — it's not — but because the saving requires removing the *call sites that pin the runtime*. Mirror metadata stripping by itself just removes the per-type field descriptors; the heavy demangler + SIMD-debugDescription code path stays alive as long as any code says `Mirror(reflecting: x)`.

Swiflow's `Mirror` references are:

| File | Use | Removal approach |
|---|---|---|
| `Sources/Swiflow/Reactivity/Component.swift` (`wireStateAndRestore`) | Walks `@State` cells to wire owner + scheduler | Replace with macro-emitted static `_swiflowStateCells` |
| `Sources/Swiflow/Reactivity/HMR.swift` (`makeSnapshot`, `applyRestore`) | Walks `@State` cells for HMR snapshot/restore | Same |
| `Sources/SwiflowWeb/HMR/HMRBridge.swift` (`encodeStateMap`) | `Mirror.displayStyle == .optional` to detect Optional values for JS bridge | Replace with explicit type switch over the 4 supported primitives |
| `Sources/SwiflowWeb/DevAPI.swift` (`encodeStateForDisplay`) | Same Optional detection | Same |

After all four call sites are gone AND the flag is on, the linker should be free to dead-strip the demangler chain. That's the bet.

---

## Non-goals

- **No user-API change.** `@MainActor @Component final class Foo` and `@State var count = 0` and `$count` all read identically. The whole redesign is invisible to user code.
- **SSG, hydration, SwiftWasm runtime replacement.** Out of scope (post-1.0).
- **JS bridge redesign.** JavaScriptKit stays. The Optional encoding paths in HMRBridge/DevAPI change shape but the wire format is unchanged.
- **`@Environment` macro.** Phase 13e shipped `@Environment` with a property-wrapper shape; not part of this phase. (If it also gets a redesign later it'll be its own spec.)

---

## Three coordinated moves

### Move 1 — `@State` macro redesign (drop `State<T>` class)

Today `@State` is a `final class State<Value>` property wrapper with a `Box<Value>` heap cell, `weak var _owner: AnyComponent?`, and `_swiflowScheduler: AnyObject?`. The framework walks `Mirror(reflecting: instance).children` at mount time to find every `State<T>` and call its `_setOwner(_:scheduler:)`.

The redesign drops the `State<T>` class entirely. `@State` becomes a Swift attached macro (`@attached(accessor)` + `@attached(peer, names: prefixed($))`) that expands inline. The component holds the value as a normal stored property. The setter routes through a synthesized `didSet` that calls `scheduler.markDirty(owner)`.

#### What the user writes (unchanged)

```swift
@MainActor @Component
final class Counter {
    @State var count: Int = 0
    @State var label: String = "hello"
    @State var maybeId: Int? = nil

    var body: VNode {
        p("\(label): \(count)")
            .on(.click) { self.count += 1 }
    }
}
```

#### What `@State` + `@Component` expand to (conceptually)

```swift
@MainActor
final class Counter {
    // ── @State expansion (per variable) ──────────────────────────────
    var count: Int = 0 {
        didSet {
            if let s = _swiflowScheduler, let o = _swiflowOwner {
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

    var label: String = "hello" { didSet { /* same shape */ } }
    var $label: Binding<String> { /* same shape */ }

    var maybeId: Int? = nil { didSet { /* same shape */ } }
    var $maybeId: Binding<Int?> { /* same shape */ }

    // ── @Component expansion (per class) ─────────────────────────────
    private weak var _swiflowOwner: AnyComponent?
    private var _swiflowScheduler: Scheduler?

    static let _swiflowStateCells: [AnyStateCell] = [
        AnyStateCell(
            name: "count",
            snapshot:   { ($0 as! Counter).count as Any },
            restore:    { c, v in
                guard let typed = v as? Int else { return false }
                (c as! Counter).count = typed; return true
            },
            restoreNil: { _ in false }
        ),
        AnyStateCell(
            name: "label",
            snapshot:   { ($0 as! Counter).label as Any },
            restore:    { c, v in
                guard let typed = v as? String else { return false }
                (c as! Counter).label = typed; return true
            },
            restoreNil: { _ in false }
        ),
        AnyStateCell(
            name: "maybeId",
            snapshot:   { ($0 as! Counter).maybeId as Any },
            restore:    { c, v in
                guard let typed = v as? Int? else { return false }
                (c as! Counter).maybeId = typed; return true
            },
            restoreNil: { c in (c as! Counter).maybeId = nil; return true }
        ),
    ]

    func _swiflowSetOwner(_ owner: AnyComponent, scheduler: Scheduler) {
        self._swiflowOwner = owner
        self._swiflowScheduler = scheduler
    }

    var body: VNode { /* user code */ }
}
extension Counter: Component {}
```

#### Key invariants

- **No `State<T>` class. No `Box<Value>`. No `StateWireable` protocol.** All three deleted.
- **Reads are direct field reads.** Writes go through `didSet`. No heap indirection per assignment.
- **didSet idempotence during init.** Assignments to default values fire `didSet`, but `_swiflowScheduler` is nil — the guard short-circuits. Safe.
- **`$count` binding closures capture `[unowned self]`.** Bindings live one render frame; if a user stashes one in a long-lived var, an unowned crash is the right loud signal that they're misusing the API.
- **User `willSet`/`didSet` on `@State` vars is a macro-level error.** Diagnostic: `@State properties cannot declare their own didSet; use a regular var or move the side effect into a method.` Pre-1.0 stance — easier to remove the restriction later than to add it.
- **HMR field names match today's wire format.** Old code stripped underscore prefix from `_count`; new code uses the var name directly. JS bridge still sees `{"count": 5}`.

### Move 2 — Non-`@State` Mirror call sites

`HMRBridge.encodeStateMap` and `DevAPI.encodeStateForDisplay` use `Mirror(reflecting: v).displayStyle == .optional` to decide whether `v` is an Optional, then read `children.first?.value` to unwrap the payload.

Replace both with an exhaustive switch over the four HMR-supported primitive types:

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

This works because HMR's supported value set is **closed**: only `Bool`, `Int`, `Double`, `String` and their Optionals. Each `as Bool?` / `as Int?` / etc. pattern matches both `.some(x)` and `.none`. The order matters (non-Optional cases before Optional, because `Int` matches `as Int?` via runtime promotion).

### Move 3 — Foundation runtime surface cleanup

Four runtime files import Foundation:

1. **`URLSanitizer.swift`** — only Foundation API is `String.replacingOccurrences`, called twice in `decodeHTMLColonEntities` for `&#58;` and case-insensitive `&#x3a;`. Replace with a stdlib-only helper (~10 LOC manual scanner). Drop `import Foundation`.

2. **`HMR.swift`** — `import Foundation` with no detectable Foundation API. Audit (grep + try removing + rebuild). If genuinely vestigial, drop. If something subtle remains (e.g., a `Date()` deep inside), keep + document.

3. **`HMRBridge.swift`** — explicit `NSNumber` references exist. After Move 2 lands, audit whether Foundation is still needed for the JavaScriptKit bridge. Drop if not.

4. **`DevAPI.swift`** — same analysis as HMRBridge.

Savings here are small individually. Each `import Foundation` is a pin keeping Foundation alive in the link; dropping all four lets the linker dead-strip whatever Foundation portions aren't transitively required by JavaScriptKit or stdlib's own deps.

---

## Framework-side changes

### Protocol additions

Three public-with-underscore additions to `Component`:

```swift
public protocol Component {
    // ... existing requirements (body, etc.) ...

    /// Macro-emitted: descriptors for each `@State` cell on this type.
    /// Default `[]` for non-`@Component` types — wiring becomes a no-op.
    static var _swiflowStateCells: [AnyStateCell] { get }

    /// Macro-emitted: installs the owner + scheduler refs the synthesized
    /// `didSet` blocks call into. One call per instance per mount, not
    /// one per state cell.
    func _swiflowSetOwner(_ owner: AnyComponent, scheduler: Scheduler)
}

public extension Component {
    static var _swiflowStateCells: [AnyStateCell] { [] }
    func _swiflowSetOwner(_ owner: AnyComponent, scheduler: Scheduler) { /* no-op */ }
}
```

Public-with-underscore is consistent with today's `_setOwner`/`_hmrSnapshotValue` pattern — framework-internal, cross-module-visible.

### Type-erased `AnyStateCell`

```swift
public struct AnyStateCell {
    public let name: String
    public let snapshot: (Any) -> Any
    public let restore: (Any, Any) -> Bool
    public let restoreNil: (Any) -> Bool

    public init(
        name: String,
        snapshot: @escaping (Any) -> Any,
        restore: @escaping (Any, Any) -> Bool,
        restoreNil: @escaping (Any) -> Bool
    ) {
        self.name = name
        self.snapshot = snapshot
        self.restore = restore
        self.restoreNil = restoreNil
    }
}
```

The `Any` first parameter of each closure is the component instance erased. Inside the closure body the macro emits the concrete `as! Counter` cast — type-safe at the source, single-cast cost per cell per call.

### Rewritten `wireStateAndRestore`

`Sources/Swiflow/Reactivity/Component.swift`:

```swift
func wireStateAndRestore(
    on owner: AnyComponent,
    scheduler: Scheduler?,
    stateMap: [String: Any]?,
    path: String = ""
) {
    guard scheduler != nil || stateMap != nil else { return }
    let instance = owner.instance

    if let scheduler {
        instance._swiflowSetOwner(owner, scheduler: scheduler)
    }

    guard let stateMap else { return }
    let cells = type(of: instance)._swiflowStateCells
    for cell in cells {
        guard let newValue = stateMap[cell.name] else { continue }
        let ok = newValue is HMRNilSentinel
            ? cell.restoreNil(instance)
            : cell.restore(instance, newValue)
        if !ok {
            let typeName = String(reflecting: type(of: instance))
            swiflowDiagnostic("HMR restore: type mismatch on \(typeName).\(cell.name) at path '\(path)'. Field reset to its declared initial value.")
        }
    }
}
```

### Rewritten `makeSnapshot` + `applyRestore`

`Sources/Swiflow/Reactivity/HMR.swift` — same shape: `for cell in type(of: instance)._swiflowStateCells` replaces `for child in mirror.children`. The `String(reflecting: type(of: instance))` call for `typeName` stays (reads runtime type descriptor, not reflection metadata — empirical verification required, see Risks).

---

## Migration impact

**User-facing:** none. The public macro syntax + behavior is unchanged.

**Framework-internal:**
- `State<Value>` class — deleted
- `Box<Value>` class — deleted
- `StateWireable` protocol — deleted
- `State.swift` underscore methods (`_setOwner`, `_hmrSnapshotValueImpl`, `_hmrRestoreImpl`, `_hmrRestoreNil`) — deleted
- Mirror walks in `wireStateAndRestore`, `makeSnapshot`, `applyRestore` — replaced

**Tests that construct `State<T>` directly** need rewriting against a real `Component` instance. Today's `State.swift` comment ("useful for tests constructing `@State` values outside a Renderer") hints some exist. The implementation plan will include a test-audit pass as Task 6's first step.

**Examples and HelloWorld** require no source changes — the macro expansion is invisible.

---

## Testing strategy

**TDD-shaped, plan will sequence per task:**

1. **Macro expansion tests first.** SwiftSyntaxMacros' `assertMacroExpansion` against canonical inputs:
   - Single `@State var count: Int = 0`
   - Multiple `@State` members
   - Optional types (`Int?`, `String?`, `Bool?`, `Double?`)
   - `@State` on a non-`@Component` class (should be no-op or diagnostic)
   - `@State` with user-written `didSet` (should diagnose)

2. **Framework unit tests** for the rewritten `wireStateAndRestore` / `makeSnapshot` / `applyRestore` — drive with synthetic `_swiflowStateCells` arrays to test iteration logic without the macros.

3. **Existing 546 Swift tests** — most pass unchanged (public API unchanged). Audit pass for any direct `State<T>` constructors.

4. **End-to-end:** Counter renders + counts + survives HMR (the trickiest restore path). Forms validate. Router navigates. SwiflowTesting harness still works.

5. **Playwright:** all three spec sets (Counter, Router, SW cache + progress) green.

6. **Empirical verification** that `type(of: instance)` and `String(reflecting: type(of: instance))` still produce demangled names under `-disable-reflection-metadata`. This is the highest-risk assumption — if it breaks, HMR snapshot keying breaks (typeName mismatches → state doesn't restore).

---

## Success criteria

Both required:

1. **Functional.** All 546 Swift + 30 JS + 3 Playwright spec sets green. Counter renders, counts, survives HMR. Forms validate. Router navigates.

2. **Bundle size.** Target **≥5% gzipped reduction** from the Phase 14b post-trim baseline (18,176,904 bytes per `docs/perf/bundle-baseline.json`). Stretch **15%**. Floor: if measurement comes in **<2%**, the phase ships only with explicit user sign-off after follow-up audit — that's the signal we've left a Mirror reference somewhere that's pinning the runtime helpers.

### Measurement gate

Built into the phasing: re-measure gzipped bytes after each task, append a row to `docs/perf/2026-05-26-wasm-bundle-audit.md`. Individual Mirror-removal tasks should each be ~0%. The big jump is expected **only** when `-disable-reflection-metadata` lands on top of all the Mirror call sites being removed. If the flag flip yields <2% on top of the cleanup, the demangler is still alive — audit which symbol is keeping it (likely candidate: a transitive Foundation use we missed).

---

## Phasing (9 tasks)

| # | Task | Risk | Expected bundle impact |
|---|---|---|---|
| 1 | Replace `Mirror.displayStyle` in `HMRBridge` + `DevAPI` with explicit Optional switch | Low | ~0% (flag not yet on) |
| 2 | `URLSanitizer` Foundation-free + audit + drop vestigial `import Foundation`s | Low | small |
| 3 | Add `AnyStateCell` type + `Component` protocol additions with default no-op impls | Low | 0% |
| 4 | Implement `@State` macro (accessor `didSet` + peer `$projection`) with expansion tests | Medium | 0% (compiles, unused until task 6) |
| 5 | Update `@Component` macro to scan `@State` members + emit `_swiflowStateCells` + `_swiflowSetOwner` | Medium | 0% |
| 6 | Rewrite `wireStateAndRestore` / `makeSnapshot` / `applyRestore` to iterate `_swiflowStateCells`; delete `State<Value>`, `Box<Value>`, `StateWireable` | High | small (Mirror call sites in source gone) |
| 7 | Flip `-Xswiftc -disable-reflection-metadata` in `BuildCommand` release path | Low (if 6 works) | **biggest expected jump** |
| 8 | Measure, audit, update `docs/perf/bundle-baseline.json` + extend Phase 14b-Track-2 audit doc with the new column | — | — |
| 9 | CHANGELOG + README + status; push | — | — |

Tasks 4, 5, 6 are tightly coupled and likely flow as one execution session split into commits. Task 6 is the highest-risk in the phase — it's the moment the macros and framework rewiring meet for the first time end-to-end.

---

## Risks & open questions

1. **`String(reflecting: type(of: instance))` under `-disable-reflection-metadata`.** Assumption: class type names come from the runtime type descriptor, not reflection metadata. If wrong, HMR snapshot keying breaks. **Mitigation:** Task 7 verifies empirically before the flag flip ships. If it breaks, switch HMR key derivation to an opt-in macro-emitted `static let _swiflowTypeName: String` (small, but adds API surface to the macro).

2. **Macro emission of `$`-prefixed names.** Assumption: Swift Macros API (`@attached(peer, names: prefixed($))`) accepts emitting properties named `$count`. This is how Swift's property wrappers are internally implemented in 5.9+, so it should work. **Mitigation:** Task 4 starts with an expansion-test for this specific shape; if it fails, the fallback is to keep a tiny value-type `State<T>` purely for the `$projection` (per brainstorm option C) at the cost of leaving one class in the build.

3. **Macro plugin cross-compile under WASM SDK.** The macro plugin builds for the *host* (macOS) but produces metadata the WASM target consumes. Phase 13d already handled this. No expected friction, but Task 4 confirms early.

4. **Bundle size floor (<2%).** Possible outcome that even with everything done, the linker still can't dead-strip the demangler because of an indirect reference (e.g., string interpolation paths, exception unwinding). **Mitigation:** the audit gate. If we hit <2%, surface for sign-off rather than ship a phase that didn't deliver.

5. **Default Component protocol extensions interacting with macro-emitted overrides.** Concrete `_swiflowStateCells` declared on Counter must override the protocol-extension default. Swift's witness-table lookup handles this for value/static requirements, but the macro emission needs the exact attribute combination (e.g., `static let` with explicit `: [AnyStateCell]` type annotation to make witness-table dispatch happy). Verified during Task 5.

---

## Out of scope

- SSG, hydration, runtime replacement, multi-WASM splitting (all post-1.0 per Phase 14b spec).
- `@Environment` redesign. Stays property-wrapper-shaped from Phase 13e.
- `Ref<E>` redesign. Stays as-is.
- `@ChildrenBuilder` diagnostics. Stays as-is from Phase 13d.
- Any non-runtime Foundation removal (SwiflowCLI keeps Foundation freely — runs on dev machine, doesn't contribute to bundle).
