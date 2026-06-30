# B4 (minimal slice) — `@ReducerState` local reducer cell — Design

**Goal:** Add a local, per-component **reducer** primitive for app-level *client* state with several fields + many actions sharing invariants (wizards, multi-step flows, queues) — the gap between per-component `@State` (local UI) and the SwiflowQuery cache (server state). This is a **minimal validation slice**: ship the primitive + one worked example + tests, to feel it in real use before expanding.

**Decisions (locked in brainstorming):**
- **Scope:** local per-component, modeled exactly on `@MutationState` (a persistent per-component reactive cell wired at mount).
- **Effects:** the reducer is **pure, synchronous, total** — no I/O, no async. Side effects live at the call site / existing mutation/`.task` machinery (dispatch a "started" action, await outside, dispatch a "result" action). One async story, not two.

**Explicitly deferred (follow-ups, only if the slice feels good):**
- The FSM-as-a-pattern docs + wizard cookbook.
- A reducer-native `ToastStack` overload / refactoring Toast onto a reducer.
- A global/shared store; any TCA-style Effect system; ergonomic state-read sugar (see "Known ergonomic trade-off").

---

## Existing pattern this mirrors (verified)

`@MutationState var add: AddTodo` (`SwiflowQuery`/`SwiflowMacrosPlugin`):
- `MutationStateMacro` (`@attached(peer)`) emits `private let _add_mutationRuntime = MutationRuntime<AddTodo>()` and `var $add: MutationHandle<AddTodo> { MutationHandle(runtime: _add_mutationRuntime, mutation: add) }`. `add` stays a plain stored `var` holding the definition.
- `ComponentMacro` scans members for the `MutationState` attribute (by name string), emits one `_<name>_mutationRuntime.wire(owner:scheduler:client:)` line in `bind(owner:scheduler:)`, and includes default-constructible mutations in the synthesized `init()`. Mutation-free components emit a byte-identical `bind` body.
- `MutationRuntime` calls `scheduler.markDirty(owner)` on state change — the same path `@State`'s `didSet` uses.

`@ReducerState` follows this 1:1.

---

## Design

### 1. `Reducer` protocol (core `Swiflow`)
```swift
@MainActor
public protocol Reducer {
    associatedtype State
    associatedtype Action
    /// The state a fresh cell starts at.
    var initialState: State { get }
    /// Pure, synchronous, total: mutate `state` for `action`. No I/O, no async.
    func reduce(into state: inout State, _ action: Action)
}
```
A conformer is a value type (may hold captured-dependency stored properties, like `Query`/`Mutation`). An FSM is just `State = enum of phases` + a `reduce` that only writes valid transitions (a documented pattern later, not API now).

### 2. `ReducerRuntime<R: Reducer>` (core `Swiflow`)
A `@MainActor final class` (persistent across renders, like `MutationRuntime`):
- `private var _state: R.State?` — lazily seeded from `reducer.initialState` (the runtime is constructed parameterless by the macro *before* the reducer instance is assigned in the synthesized `init`, so seeding is deferred to first access, which carries the reducer).
- `private weak var owner: AnyComponent?`, `private var scheduler: (any Scheduler)?`.
- `public func wire(owner: AnyComponent, scheduler: any Scheduler)` — injected at mount.
- `func seededState(_ reducer: R) -> R.State` — `if _state == nil { _state = reducer.initialState }; return _state!`.
- `func send(_ reducer: R, _ action: R.Action)` — seed if needed, `reducer.reduce(into: &_state!, action)`, then `if let owner, let scheduler { scheduler.markDirty(owner) }`.

### 3. `ReducerHandle<R: Reducer>` (core `Swiflow`)
The `$`-projection value (parallel to `MutationHandle`):
```swift
@MainActor public struct ReducerHandle<R: Reducer> {
    let runtime: ReducerRuntime<R>
    let reducer: R
    public var state: R.State { runtime.seededState(reducer) }
    public func send(_ action: R.Action) { runtime.send(reducer, action) }
}
```

### 4. `@ReducerState` macro
- Decl in core `Swiflow`: `@attached(peer, names: arbitrary) public macro ReducerState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ReducerStateMacro")`.
- `ReducerStateMacro` (in `SwiflowMacrosPlugin`, mirroring `MutationStateMacro`) for `@ReducerState var counter: CounterReducer` emits:
  ```swift
  private let _counter_reducerRuntime = ReducerRuntime<CounterReducer>()
  var $counter: ReducerHandle<CounterReducer> {
      ReducerHandle(runtime: _counter_reducerRuntime, reducer: counter)
  }
  ```
  `counter` stays a plain stored `var` holding the `CounterReducer` (set by the synthesized `init`). Same `requires a var with an explicit type` diagnostic as `@MutationState`.

### 5. `@Component` `bind` + `init` extension (`ComponentMacro`)
Add a second member scan for the `ReducerState` attribute (by name string, mirroring the `MutationState` scan):
- In `bind(owner:scheduler:)`, emit one `_<name>_reducerRuntime.wire(owner: owner, scheduler: scheduler)` line per `@ReducerState` (no query client — reducers don't touch it).
- Include default-constructible `@ReducerState` vars in the synthesized `init()` (`self.<name> = <Type>()`), exactly like mutations.
- **Invariant:** a component with no `@ReducerState` emits a byte-identical `bind`/`init` (the new lines are conditional on the scan finding cells) — same guarantee the mutation path already provides. (Golden macro-expansion tests assert this.)

### Usage (the feel)
```swift
struct Checkout: Reducer {
    struct State { var step = 0; var email = ""; var agreed = false }
    enum Action { case next, back, setEmail(String), toggleAgree }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 2: s.step += 1
        case .back where s.step > 0: s.step -= 1
        case .setEmail(let e): s.email = e
        case .toggleAgree: s.agreed.toggle()
        default: break   // invalid transition → no-op
        }
    }
}

@MainActor @Component
final class CheckoutFlow {
    @ReducerState var flow: Checkout
    var body: VNode {
        VStack {
            h2("Step \($flow.state.step + 1) of 3")
            HStack {
                Button("Back") { self.$flow.send(.back) }
                Button("Next") { self.$flow.send(.next) }
            }
        }
    }
}
```
`useReducer(reducer, init)` ≈ `@ReducerState var flow: Checkout`; `dispatch(a)` ≈ `$flow.send(a)`; `state` ≈ `$flow.state`.

### Known ergonomic trade-off (a thing the slice validates)
Reads go through `$flow.state.step` (the unprojected `flow` is the *reducer*, mirroring `@MutationState` where unprojected `add` is the *mutation*). That's consistent and low-risk but more verbose than React's `state.step`. If the slice feels too clunky, a v2 ergonomic pass (sugar so the unprojected value reads as `State`) is a follow-up — deliberately not in this slice.

---

## Testing

- **Reducer logic — pure unit tests** (the headline testability win), no component/scheduler: `var s = Checkout().initialState; var r = Checkout(); r.reduce(into: &s, .next); #expect(s.step == 1)`. Cover valid transitions + an invalid-transition no-op.
- **Cell wiring** (mirror `MutationState` wiring tests): construct a `ReducerRuntime`, `wire(owner:scheduler:)` with a `SyncScheduler`, `send`, assert (a) state updated and (b) `markDirty` fired (scheduler mark observed). Seeding-on-first-access covered.
- **Macro expansion (golden):** `assertMacroExpansion` for `@ReducerState` (runtime field + `$` projection) and for `@Component` with a `@ReducerState` member (bind wire line + synthesized init). Plus a `@Component` with **no** `@ReducerState` expands byte-identically to today (the no-regression invariant).
- **Host build of the example** + the full `swift test` suite green (the `ComponentMacro` change must not regress existing components).
- **Example builds to wasm** (`swiflow build --path examples/...`) so the demo section compiles.

## Acceptance criteria
1. `@ReducerState var x: SomeReducer` compiles; `$x.state` reads, `$x.send(.action)` dispatches and re-renders the owner.
2. The reducer is pure/synchronous; effects are demonstrated at the call site in the example (a dispatch-await-dispatch async step), not inside `reduce`.
3. A `@Component` with no `@ReducerState` expands byte-identically (golden test); all existing tests green.
4. Pure-reducer unit tests + cell-wiring test + golden macro tests pass; the example builds (host + wasm).

## Out of scope
- FSM cookbook/docs, Toast reducer overload, global store, Effect system, state-read ergonomic sugar — all deferred follow-ups.
- Any change to `@State`, `@MutationState`, or the scheduler beyond the additive `ComponentMacro` scan.
