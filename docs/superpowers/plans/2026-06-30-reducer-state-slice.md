# B4 slice — `@ReducerState` local reducer cell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a local, per-component reducer primitive (`@ReducerState`) modeled 1:1 on `@MutationState`: a `Reducer` protocol + a per-component reactive cell wired at mount that re-renders on `send`. Minimal validation slice — primitive + one wizard example + tests.

**Architecture:** `Reducer` protocol + `ReducerRuntime`/`ReducerHandle` in core `Swiflow`; a peer macro `@ReducerState` (mirroring `MutationStateMacro`) that emits the runtime field + `$` projection; an additive scan in `ComponentMacro` that wires each reducer cell in `bind` and default-constructs it in the synthesized `init`. Pure synchronous `reduce`; effects at the call site.

**Tech Stack:** Swift 6.3, swift-syntax macros, swift-testing. Host-testable (the example also builds to wasm).

**Spec:** `docs/superpowers/specs/2026-06-30-reducer-state-slice-design.md`.

**Critical context (verified):**
- `@MutationState` precedent: `MutationStateMacro` (`@attached(peer)`, `Sources/SwiflowMacrosPlugin/MutationStateMacro.swift`) emits `private let _<name>_mutationRuntime = MutationRuntime<Type>()` + `var $<name>: MutationHandle<Type> { MutationHandle(runtime: _<name>_mutationRuntime, mutation: <name>) }`. `MutationHandle`/`MutationRuntime` have `public init`.
- `ComponentMacro` (`Sources/SwiflowMacrosPlugin/ComponentMacro.swift`, ~lines 155–225) scans members for the `MutationState` attribute by name string → `mutationNames` + `mutationInits`; builds `bind` as `["self.runtimeOwner = owner", "self.runtimeScheduler = scheduler"] + mutationNames.map { "_\($0)_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())" }`; synthesizes `init()` from `mutationInits` when there's no user init; emits `private weak var runtimeOwner`, `private var runtimeScheduler: Scheduler?`, `stateCellsDecl`, `bindDecl`.
- Macro decls for core live in `Sources/Swiflow/Macros.swift` (`@Component`, `@State`). Plugin registration: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` `providingMacros` list.
- `Scheduler` is now `@MainActor` (#92); `SyncScheduler { (_: AnyComponent) in … }` drives marks; `AnyComponent(SomeComponent())`.
- Macro test patterns: `Tests/SwiflowMacrosTests/MutationStateMacroTests.swift`, `ComponentMacroMutationTests.swift`, `ComponentAutoInitTests.swift` use `assertMacroExpansion(_, expandedSource:, macros:)`.
- `@Component` classes must be `@MainActor` (post-#92, a `@State`/`@ReducerState`-bearing component's `didSet`/wiring needs it) — test components use `@MainActor @Component`.

**Branch:** `feat/reducer-state-slice` (created off `origin/main`; spec committed there).

---

## Task 1: `Reducer` protocol + `ReducerRuntime` + `ReducerHandle`

**Files:**
- Create: `Sources/Swiflow/Reactivity/Reducer.swift`
- Test: `Tests/SwiflowTests/Reactivity/ReducerRuntimeTests.swift`

- [ ] **Step 1: Write the failing tests.** Create `Tests/SwiflowTests/Reactivity/ReducerRuntimeTests.swift`:

```swift
// Tests/SwiflowTests/Reactivity/ReducerRuntimeTests.swift
import Testing
@testable import Swiflow

@MainActor private final class RStub: Component { var body: VNode { .text("") } }

private struct Counter: Reducer {
    struct State: Equatable { var count = 0 }
    enum Action { case inc, reset }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a { case .inc: s.count += 1; case .reset: s.count = 0 }
    }
}

@Suite("Reducer runtime")
@MainActor
struct ReducerRuntimeTests {

    @Test("pure reduce: actions transform state without any wiring")
    func pureReduce() {
        let r = Counter()
        var s = r.initialState
        r.reduce(into: &s, .inc)
        r.reduce(into: &s, .inc)
        #expect(s.count == 2)
        r.reduce(into: &s, .reset)
        #expect(s.count == 0)
    }

    @Test("send transforms state, seeds from initialState, and marks the owner dirty")
    func sendUpdatesAndMarksDirty() {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let owner = AnyComponent(RStub())
        let runtime = ReducerRuntime<Counter>()
        runtime.wire(owner: owner, scheduler: scheduler)

        let reducer = Counter()
        #expect(runtime.seededState(reducer).count == 0)   // lazy seed from initialState
        runtime.send(reducer, .inc)
        scheduler.flush()
        #expect(runtime.seededState(reducer).count == 1)
        #expect(marks >= 1)                                // a transition marked the owner dirty
    }
}
```

- [ ] **Step 2: Run to verify it fails.** `swift test --filter ReducerRuntimeTests` → FAIL to compile (`cannot find 'Reducer'` / `ReducerRuntime`).

- [ ] **Step 3: Implement.** Create `Sources/Swiflow/Reactivity/Reducer.swift`:

```swift
// Sources/Swiflow/Reactivity/Reducer.swift
//
// A local, per-component reducer primitive (B4 slice). Models app-level CLIENT
// state with several fields + many actions sharing invariants (wizards, queues,
// multi-step flows) — between per-component @State and the SwiflowQuery cache.
// The reducer is PURE/synchronous/total; effects live at the call site.
// Wired into a component exactly like @MutationState (see @ReducerState).

/// A typed, pure state transition. Conform a value type; an FSM is just a
/// `State` enum whose `reduce` only writes valid transitions.
@MainActor
public protocol Reducer {
    associatedtype State
    associatedtype Action
    /// The state a fresh cell starts at.
    var initialState: State { get }
    /// Pure, synchronous, total: mutate `state` for `action`. No I/O, no async.
    func reduce(into state: inout State, _ action: Action)
}

/// Persistent, per-component reactive state for one `@ReducerState`. A class so
/// it survives across renders with the component instance. Wired once at mount
/// by `@Component`'s `bind`. Mirrors `MutationRuntime`.
@MainActor
public final class ReducerRuntime<R: Reducer> {
    private var _state: R.State?
    private weak var owner: AnyComponent?
    private var scheduler: (any Scheduler)?

    public init() {}

    /// Injected at mount by the synthesized `bind`.
    public func wire(owner: AnyComponent, scheduler: any Scheduler) {
        self.owner = owner
        self.scheduler = scheduler
    }

    /// Current state, lazily seeded from `reducer.initialState` on first access
    /// (the runtime is constructed before the reducer instance is assigned).
    public func seededState(_ reducer: R) -> R.State {
        if _state == nil { _state = reducer.initialState }
        return _state!
    }

    /// Apply `action` via `reducer`, then mark the owner dirty so it re-renders.
    public func send(_ reducer: R, _ action: R.Action) {
        if _state == nil { _state = reducer.initialState }
        reducer.reduce(into: &_state!, action)
        if let owner, let scheduler { scheduler.markDirty(owner) }
    }
}

/// The `$`-projection a component uses to read state and dispatch actions.
/// A lightweight value over the persistent runtime + a snapshot of the current
/// `Reducer` definition. Mirrors `MutationHandle`.
@MainActor
public struct ReducerHandle<R: Reducer> {
    let runtime: ReducerRuntime<R>
    let reducer: R

    public init(runtime: ReducerRuntime<R>, reducer: R) {
        self.runtime = runtime
        self.reducer = reducer
    }

    /// The current reduced state.
    public var state: R.State { runtime.seededState(reducer) }

    /// Dispatch an action: reduces + re-renders the owner.
    public func send(_ action: R.Action) { runtime.send(reducer, action) }
}
```

- [ ] **Step 4: Run to verify it passes.** `swift test --filter ReducerRuntimeTests` → PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add Sources/Swiflow/Reactivity/Reducer.swift Tests/SwiflowTests/Reactivity/ReducerRuntimeTests.swift
git commit -m "feat(reactivity): Reducer protocol + ReducerRuntime/Handle (B4 slice)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `@ReducerState` peer macro

**Files:**
- Modify: `Sources/Swiflow/Macros.swift` (add the `@ReducerState` decl)
- Create: `Sources/SwiflowMacrosPlugin/ReducerStateMacro.swift`
- Modify: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` (register)
- Test: `Tests/SwiflowMacrosTests/ReducerStateMacroTests.swift`

- [ ] **Step 1: Write the failing golden test.** Create `Tests/SwiflowMacrosTests/ReducerStateMacroTests.swift` mirroring `MutationStateMacroTests.swift` (check that file for the exact `import`/`testMacros` harness and copy its shape):

```swift
// Tests/SwiflowMacrosTests/ReducerStateMacroTests.swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiflowMacrosPlugin

@Suite("@ReducerState macro")
struct ReducerStateMacroTests {
    let macros: [String: any Macro.Type] = ["ReducerState": ReducerStateMacro.self]

    @Test("emits the runtime field and the $ projection")
    func emitsRuntimeAndProjection() {
        assertMacroExpansion(
            """
            @ReducerState var flow: Checkout
            """,
            expandedSource: """
            var flow: Checkout

            private let _flow_reducerRuntime = ReducerRuntime<Checkout>()

            var $flow: ReducerHandle<Checkout> {
                ReducerHandle(runtime: _flow_reducerRuntime, reducer: flow)
            }
            """,
            macros: macros)
    }
}
```

Note: match the EXACT expansion whitespace/format `assertMacroExpansion` produces (the peer decls follow the original `var flow: Checkout`). If the formatter differs, align `expandedSource` to the tool's actual output (as `MutationStateMacroTests` does) — do not fight the formatter; copy its output.

- [ ] **Step 2: Run to verify it fails.** `swift test --filter ReducerStateMacroTests` → FAIL (`cannot find 'ReducerStateMacro'`).

- [ ] **Step 3: Implement the macro.** Create `Sources/SwiflowMacrosPlugin/ReducerStateMacro.swift` (mirror `MutationStateMacro.swift`):

```swift
// Sources/SwiflowMacrosPlugin/ReducerStateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macro for `@ReducerState var flow: SomeReducer`. Emits a persistent
/// backing `_flow_reducerRuntime` and the `$flow` reactive handle projection.
/// `flow` itself stays a plain stored `var` holding the Reducer.
public struct ReducerStateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: ReducerStateDiagnostic.requiresVarWithType))
            return []
        }
        let name = identifier.text
        let reducerType = typeAnno.type.trimmedDescription

        let runtime: DeclSyntax = """
            private let _\(raw: name)_reducerRuntime = ReducerRuntime<\(raw: reducerType)>()
            """
        let projection: DeclSyntax = """
            var $\(raw: name): ReducerHandle<\(raw: reducerType)> {
                ReducerHandle(runtime: _\(raw: name)_reducerRuntime, reducer: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum ReducerStateDiagnostic: DiagnosticMessage {
    case requiresVarWithType
    var message: String {
        "@ReducerState requires a `var` with an explicit Reducer type annotation (e.g. `@ReducerState var flow: Checkout`)."
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 4: Register the macro.** In `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift`, add `ReducerStateMacro.self,` to `providingMacros` (next to `MutationStateMacro.self`).

- [ ] **Step 5: Add the public macro decl.** In `Sources/Swiflow/Macros.swift`, after the `@State` decl, add:

```swift
/// Declares a local, per-component reducer cell. The annotated `var`'s type is a
/// `Reducer`; the macro emits the backing runtime + a `$name` `ReducerHandle`
/// projection (`$name.state` to read, `$name.send(_:)` to dispatch). Wired at
/// mount by `@Component`. See `Reducer`.
@attached(peer, names: arbitrary)
public macro ReducerState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ReducerStateMacro")
```

- [ ] **Step 6: Run to verify it passes.** `swift test --filter ReducerStateMacroTests` → PASS.

- [ ] **Step 7: Commit.**

```bash
git add Sources/Swiflow/Macros.swift Sources/SwiflowMacrosPlugin/ReducerStateMacro.swift Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift Tests/SwiflowMacrosTests/ReducerStateMacroTests.swift
git commit -m "feat(reactivity): @ReducerState peer macro (B4 slice)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `@Component` wires + default-constructs `@ReducerState`

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`
- Test: `Tests/SwiflowMacrosTests/ComponentMacroReducerTests.swift`

- [ ] **Step 1: Write the failing golden tests.** Create `Tests/SwiflowMacrosTests/ComponentMacroReducerTests.swift`. Use the same `testMacros`/`assertMacroExpansion` harness as `ComponentMacroMutationTests.swift` (copy its imports + the `["Component": ComponentMacro.self, "ReducerState": ReducerStateMacro.self, "State": StateMacro.self]` macro map). Two tests:

```swift
    @Test("@Component wires + default-constructs a @ReducerState member")
    func wiresReducerCell() {
        assertMacroExpansion(
            """
            @Component
            final class Flowy {
                @ReducerState var flow: Checkout
                var body: VNode { .text("") }
            }
            """,
            expandedSource: /* the expansion: includes
               init() { self.flow = Checkout() }
               ... and bind { ...; _flow_reducerRuntime.wire(owner: owner, scheduler: scheduler) }
               plus the @ReducerState peer decls and the conformance extension */ "<FILL FROM TOOL OUTPUT>",
            macros: macros)
    }

    @Test("a @Component with no @ReducerState expands byte-identically to today")
    func noReducerByteIdentical() {
        // Expand a mutation-free, reducer-free component and assert the bind/init
        // body is unchanged from the pre-change golden (paste the existing
        // expected expansion from ComponentMacroTests for an equivalent class).
        assertMacroExpansion(
            """
            @Component
            final class Plain {
                @State var n: Int = 0
                var body: VNode { .text("") }
            }
            """,
            expandedSource: "<EXISTING GOLDEN — must be unchanged>",
            macros: macros)
    }
```

For both, generate the `expandedSource` by running the test once against the implemented macro (Step 3) and pasting the tool's actual output — but the `noReducerByteIdentical` expected MUST equal the pre-change expansion (compare against `ComponentMacroTests.swift`'s existing `@Component` + `@State` golden; if they differ, the change regressed reducer-free components — fix the macro, don't update the golden).

- [ ] **Step 2: Run to verify it fails.** `swift test --filter ComponentMacroReducerTests` → FAIL (the reducer member isn't wired yet; the wire line/init are missing).

- [ ] **Step 3: Implement the `ComponentMacro` change.** In `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`:

3a. After the `@MutationState` scan loop (which fills `mutationNames`/`mutationInits`), add a parallel scan for `ReducerState`:

```swift
        var reducerNames: [String] = []
        var reducerInits: [(name: String, type: String)] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isReducer = varDecl.attributes.contains { attr in
                guard let a = attr.as(AttributeSyntax.self),
                      let n = a.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
                return n == "ReducerState"
            }
            guard isReducer,
                  let b = varDecl.bindings.first,
                  let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier else { continue }
            reducerNames.append(id.text)
            if b.initializer == nil, let type = b.typeAnnotation?.type.trimmedDescription {
                reducerInits.append((id.text, type))
            }
        }
```

3b. In the `bind` body, append the reducer wire lines after the mutation ones:

```swift
        bindStmts += reducerNames.map { name in
            "_\(name)_reducerRuntime.wire(owner: owner, scheduler: scheduler)"
        }
```

3c. In the synthesized-`init` block, default-construct reducers too. Change the condition + assignments to use `mutationInits + reducerInits`:

```swift
        let allInits = mutationInits + reducerInits
        if !hasUserInit, !allInits.isEmpty {
            let assignments = allInits
                .map { "    self.\($0.name) = \($0.type)()" }
                .joined(separator: "\n")
            synthesizedInit = DeclSyntax(stringLiteral: "\(access)init() {\n\(assignments)\n}")
        }
```

(Leave everything else — `runtimeOwner`/`runtimeScheduler`/`stateCellsDecl`/`bindDecl` emission — unchanged. A component with no `@ReducerState` produces empty `reducerNames`/`reducerInits`, so `bind`/`init` are byte-identical.)

- [ ] **Step 4: Run to verify it passes** (fill the golden `expandedSource` from the tool output now): `swift test --filter ComponentMacroReducerTests` → PASS, and `noReducerByteIdentical` confirms reducer-free expansion is unchanged.

- [ ] **Step 5: Run the full macro test suite (no regressions).** `swift test --filter SwiflowMacrosTests` → PASS (existing `ComponentMacro`/`MutationState`/`AutoInit` golden tests unaffected).

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiflowMacrosPlugin/ComponentMacro.swift Tests/SwiflowMacrosTests/ComponentMacroReducerTests.swift
git commit -m "feat(reactivity): @Component wires @ReducerState cells (B4 slice)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: End-to-end integration test + wizard example

**Files:**
- Test: `Tests/SwiflowTests/Reactivity/ReducerComponentTests.swift`
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift` (add a wizard section)

- [ ] **Step 1: Write the integration test.** Create `Tests/SwiflowTests/Reactivity/ReducerComponentTests.swift` — a REAL `@Component` using `@ReducerState`, wired via the macro-emitted `bind`, exercising state + dispatch + re-render end to end:

```swift
// Tests/SwiflowTests/Reactivity/ReducerComponentTests.swift
import Testing
@testable import Swiflow

private struct Wizard: Reducer {
    struct State: Equatable { var step = 0 }
    enum Action { case next, back }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 2: s.step += 1
        case .back where s.step > 0: s.step -= 1
        default: break
        }
    }
}

@MainActor @Component
private final class WizardComp {
    @ReducerState var flow: Wizard
    var body: VNode { .text("step \($flow.state.step)") }
}

@Suite("Reducer + @Component integration")
@MainActor
struct ReducerComponentTests {
    @Test("send through a wired @ReducerState updates state and marks dirty")
    func endToEnd() {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let c = WizardComp()
        c.bind(owner: AnyComponent(c), scheduler: scheduler)   // macro-emitted wiring

        #expect(c.$flow.state.step == 0)
        c.$flow.send(.next)
        scheduler.flush()
        #expect(c.$flow.state.step == 1)
        #expect(marks >= 1)
        c.$flow.send(.back); c.$flow.send(.back)   // clamped at 0
        #expect(c.$flow.state.step == 0)
    }
}
```

- [ ] **Step 2: Run to verify it passes.** `swift test --filter ReducerComponentTests` → PASS. (Proves the macro-generated `init` default-constructs `flow`, `bind` wires the runtime, and `$flow.send`/`.state` work end to end.)

- [ ] **Step 3: Add the demo wizard section** (the worked human reference + the wasm compile gate; also shows effects-at-call-site). In `examples/SwiflowUIDemo/Sources/App/App.swift`, define a reducer + a `@Component` and add a `reducerWizardSection` referenced from `body` (mirror how other sections like `dataTableSection` are structured). The component demonstrates BOTH sync dispatch and an async effect at the call site:

```swift
struct SignupWizard: Reducer {
    struct State { var step = 0; var submitting = false; var done = false }
    enum Action { case next, back, submitStarted, submitFinished }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 1: s.step += 1
        case .back where s.step > 0: s.step -= 1
        case .submitStarted: s.submitting = true
        case .submitFinished: s.submitting = false; s.done = true
        default: break
        }
    }
}

@MainActor @Component
final class SignupWizardView {
    @ReducerState var wiz: SignupWizard
    var body: VNode {
        let s = $wiz.state
        return VStack(spacing: .md, align: .stretch) {
            h2("Reducer wizard")
            if s.done { p("Done ✓") }
            else {
                p("Step \(s.step + 1) of 2")
                HStack(spacing: .sm) {
                    Button("Back") { self.$wiz.send(.back) }
                    if s.step < 1 { Button("Next") { self.$wiz.send(.next) } }
                    else {
                        Button("Submit", disabled: s.submitting) {
                            // Effect at the call site: dispatch-await-dispatch (pure reducer).
                            self.$wiz.send(.submitStarted)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                self.$wiz.send(.submitFinished)
                            }
                        }
                    }
                }
            }
        }
        .padding(.lg)
    }
}
```

Add `SignupWizardView()` (embedded) as a `reducerWizardSection` in the demo's `body` alongside the existing sections. Confirm the exact `VStack`/`Button`/`embed` APIs against the surrounding demo code and adjust to match (e.g. how other `@Component`s are embedded into the demo body).

- [ ] **Step 4: Build the demo to wasm.** `swift build -c release --product swiflow` then `.build/release/swiflow build --path examples/SwiflowUIDemo` → both succeed (the reducer cell compiles for `wasm32` inside a real component).

- [ ] **Step 5: Full host suite.** `swift test` → green (the `ComponentMacro` change regresses nothing).

- [ ] **Step 6: Commit** (revert any build-regenerated example driver/SW first).

```bash
git checkout -- examples/SwiflowUIDemo/swiflow-driver.js examples/SwiflowUIDemo/swiflow-service-worker.js 2>/dev/null || true
git add Tests/SwiflowTests/Reactivity/ReducerComponentTests.swift examples/SwiflowUIDemo/Sources/App/App.swift
git commit -m "feat(reactivity): reducer @Component integration test + demo wizard (B4 slice)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `swift test` green (Reducer runtime, macro golden, `@Component` wiring + byte-identical, integration).
- [ ] `.build/release/swiflow build --path examples/SwiflowUIDemo` compiles (wasm).
- [ ] A `@Component` with no `@ReducerState` expands byte-identically (golden) — no regression to existing components.
- [ ] Working tree clean (no stray example driver/SW).
- [ ] Open a PR from `feat/reducer-state-slice` → `main` referencing B4. Note in the description that this is the **validation slice** (FSM docs, Toast refactor, global store, read-ergonomic sugar deferred) and call out the `$flow.state.x` read ergonomics as the thing to evaluate in use. **Do not merge** until the user says "merge it -- CI is green".

## Spec coverage check

- `Reducer` protocol + `ReducerRuntime`/`ReducerHandle` → Task 1.
- `@ReducerState` peer macro (runtime + `$` projection) → Task 2.
- `@Component` bind/init wiring + byte-identical guarantee → Task 3.
- Pure reduce; effects at call site (demo's submit) → Task 4 example.
- Tests: pure reducer, cell wiring, golden macro, no-regression, end-to-end, wasm build → Tasks 1–4.
