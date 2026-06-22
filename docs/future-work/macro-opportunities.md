# Macro opportunities — catalogue & recommendation

> **Status:** catalogue + progress (2026-06-22). A ranked survey of where Swiflow could use Swift macros
> more. The lead case is the Query/Mutation data layer (SwiftData's `@Query`/`@Model` ergonomics as the
> north star). **Both PURSUE items are now shipped:** #2 `@QueryType`/`@MutationType`/`@Key` (see
> `query-type-macro-design-spike.md`) and #1 `@MutationState` auto-init. The remaining rows stay as a
> forward-looking survey.

## Why this is on-strategy

Swiflow already ships `@Component` / `@State` / `@MutationState` / `#css` and a full Query/Mutation data
layer — yet the *declaration* of a query or mutation is still hand-written boilerplate, and
`@MutationState` forces a manual `init()`.

`WHY.md` makes macros **load-bearing**: the framework's thesis is "reactivity with **no ceremony**," and
macros are named as the mechanism (`count += 1` *is* the state update). So "use macros more" doubles down
on the core bet — *provided* each macro removes mechanical plumbing while keeping intent visible.

The boilerplate is real, not hypothetical:

- **Resync footgun** — `examples/QueryDemo/Sources/App/App.swift:55-62`: a manual
  `init() { self.rename = RenameUser(id: 1, …) }` **plus** a per-render
  `self.rename = RenameUser(id: userID, …)` carrying the comment *"Keep rename mutation in sync with the
  current userID."* Forget that line and the mutation silently targets the wrong user.
- **Pure-ceremony init** — `examples/TodoCRUD` *previously* hand-wrote
  `init() { self.add = AddTodo(); self.toggle = ToggleTodo(); self.remove = DeleteTodo() }` — every word
  re-stated a name already declared above. **Removed by #1**: `@Component` now synthesizes it.
- **Key encoding by hand** — `QueryKeyComponent` (`Sources/SwiflowQuery/Keys.swift`) is a closed 2-case
  enum (`.string`/`.int`); its own doc says non-Int/String types must "encode their identity into a
  `.string` or `.int` component." Today that encoding, and the whole `queryKey` accessor, is written out
  per query.

## Design bar (from `WHY.md` + the developer manifesto)

Any new macro must:

- **Kill mechanical ceremony**, not semantic intent.
- Keep **intent legible** — identity, dependencies, and fetch logic stay in source.
- Emit **errors-as-documentation** — precise diagnostics, never a cryptic expansion error.
- Be **one opinionated way**.
- **Preserve the defaulted-init test seam.**
- **Not break HMR `stateCells`** (the snapshot/restore descriptors `@Component` emits per `@State`).
- Stay **zero-cost**.

## Ranked catalogue

Ranked by (DX win × likelihood of success) ÷ (risk to ethos).

| # | Opportunity | Verdict | One-line rationale |
|---|-------------|---------|--------------------|
| 1 | `@MutationState` **auto-init** | ✅ **SHIPPED** | Removes the mandatory `init()` that only re-states names; extends the existing `@Component` scan; zero HMR/test impact |
| 2 | `@QueryType` + `@Key` (and `@MutationType`) **type-reducer** | ✅ **SHIPPED** | Synthesizes `queryKey` + memberwise `init` from the *already-proven* hand-written struct; call site & changing-key model untouched; test seam becomes **more** legible |
| 7 | `@Computed` / `@Memo` derived state | MAYBE-PURSUE | Real DX win, small surface — but **explicit-deps only** and **MUST be excluded from `stateCells`** (else HMR resurrects stale derived data) |
| 4 | Type-safe routes (`@Route` / typed params) | MAYBE (defer) | Nice (param typo → compile error) but params are all `String`; forces `RouterContext` churn; revisit after the data-layer macros |
| 5 | `@Form` / `@Field` struct-derived forms | MAYBE | Only genuine win is declarative validation; attribute-encoded rules are less debuggable than closures; spike only on measured pain |
| 3 | `@SwiflowComponent` (absorb `@MainActor`/`final`) | AVOID | A macro **cannot** add modifiers to the attached type's *own* decl — you'd still write `@MainActor`. Keep the clear diagnostics |
| 6 | `@Reducer` / state machine (roadmap B4) | AVOID (now) | B4's design is explicitly undecided; a macro would freeze an unsettled pattern. Macros must *follow* a proven runtime |
| 8 | `@Environment` as a macro | AVOID | Already a clean `@propertyWrapper`; no boilerplate to remove — macro-for-its-own-sake |
| 9 | `#query` consumption-side macro | AVOID | Endangers the changing-key model (tempts a stored-property form) and degrades error locality |

## PURSUE — details

### #1 — `@MutationState` auto-init

Synthesize a memberwise `init()` for zero-arg `@MutationState` properties **when the class declares none**
(mirror Swift's own memberwise-init suppression — if the user writes an `init`, they own it fully). Extend
the **existing** `@Component` member scan in `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`, which
already collects `@MutationState` names and types to build `bind`.

```swift
// BEFORE
@MutationState var add: AddTodo
@MutationState var toggle: ToggleTodo
@MutationState var remove: DeleteTodo
init() { self.add = AddTodo(); self.toggle = ToggleTodo(); self.remove = DeleteTodo() }

// AFTER — init synthesized for the zero-arg case
@MutationState var add: AddTodo
@MutationState var toggle: ToggleTodo
@MutationState var remove: DeleteTodo
```

Mutations aren't snapshotted, so there is **no HMR impact**; the test seam is untouched. Lowest cost,
daily-visible. *Capturing* mutations (`RenameUser(id:api:)`) keep a manual init — auto-inferring
`RenameUser(id: userID)` at init time would be wrong (the id changes); see Footguns.

> **Shipped.** `@Component` (`ComponentMacro`) gained a `memberAttribute`-free member: when a class has
> ≥1 `@MutationState` with no inline default **and** declares no `init`, it emits a zero-arg `init()` that
> default-constructs each (`self.add = AddTodo()`). A user-written init suppresses it entirely; `named(init)`
> was added to the `@Component` declaration so the synthesized member is accepted. `TodoCRUD` dropped its
> hand-written init; `QueryDemo` keeps one (its `RenameUser` captures `id`/`api`, so `RenameUser()` can't
> compile — the correct boundary). Covered by `ComponentAutoInitTests` (golden) + both example host-builds.

### #2 — `@QueryType` + `@Key` (flagship)

Reduce the **type definition**, never the **call site**:

```swift
@QueryType struct UserByID {
    @Key var id: Int            // identity → contributes .int(id) to queryKey
    var api = FakeAPI()         // non-@Key = captured dep + defaulted test seam
    func fetch() async throws -> User { await api.user(id) }
}
// SYNTHESIZED:
//   extension UserByID: Query {}
//   var queryKey: QueryKey { ["UserByID", .int(id)] }   // typeName prefix + @Key components, source order
//   init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
```

The call site is **unchanged** — `let u = query(UserByID(id: userID))` stays a per-render method call, so
the changing-key model is intact **by construction**: all the macro's work is at the *definition* site,
where there is no per-render dynamism to break. The test seam gets **clearer**, not murkier — `@Key` marks
identity, and defaulted non-`@Key` properties read unambiguously as "inject me in tests."

`@MutationType` (sibling) synthesizes `: Mutation` + the memberwise init, removing the `QueryDemo` /
`TodoCRUD` inits. `perform` / `optimistic` / `invalidations` stay hand-written — they encode business
logic and are deliberately out of macro scope.

**Three honesty guardrails (what keeps it on-ethos):**

1. **`@Key` directly supports only `Int` / `String`.** For any other type, require a
   **`QueryKeyConvertible`** conformance (`var keyComponents: [QueryKeyComponent]`) and emit a *clear*
   diagnostic when it's missing — never a cryptic expansion error.
2. **Never fight a hand-written `queryKey`** — an explicit one opts out of synthesis. Offer
   `@QueryType(prefix: "users")` for a custom key prefix.
3. **Never move the query to a stored property** (that is the rejected Shape B below).

## Deep-dive: the data layer

The fixed constraint: a query is parameterized by `@State` that **changes between renders**, and
`query(_:)` is **re-called each render**. The shapes evaluated against it:

- **Shape A — `@QueryType` type-reducer (RECOMMENDED).** Above. Removes typing, not transparency; the
  generated `queryKey` is mechanical and predictable; drop to a hand-written `queryKey` anytime.
- **Shape A′ — `@MutationType`.** Conformance + memberwise init only. Removes the inits; does *not* remove
  the `QueryDemo:62` resync — that is a genuine changing-dependency problem (see Footguns).
- **Shape B — consumption-side `@Query var u = …` stored wrapper (REJECTED).** A stored property **cannot
  see `userID` change**; it would either freeze the key at init (a latent correctness bug) or degenerate
  into a renamed method call. This is the one shape that *actively endangers* the design.
- **Shape C — `@Key`-only, no init synthesis (fallback).** Synthesize only `queryKey`, keep the init
  hand-written. More conservative; offer it if synthesized inits feel too magical (though Shape A makes the
  seam *more* visible, not less).

## Recommendation

**Both shipped** in the recommended order: #1 (`@MutationState` auto-init) first as a low-risk,
daily-visible win, then the `@QueryType` / `@MutationType` type-reducers (#2 / Shapes A + A′) as the
flagship — built on the `QueryKeyConvertible` prerequisite and the three guardrails above.

The sequence fit Swiflow specifically because it:

1. **Removes typing without removing transparency** — every deleted line is mechanical (re-stating names,
   hand-writing `.int(id)`, the memberwise init); the meaningful code (`fetch`, `perform`, the identity
   decision via `@Key`) stays in source.
2. **Makes the test seam *more* obvious** — identity is marked at the declaration; defaulted deps read as
   injection points.
3. **Follows the framework's own macro-genesis pattern** — `@State` codified a hand-written `State<T>`;
   `@Component` codified hand-written runtime wiring; `@QueryType` codifies the hand-written `Query` struct
   that *already appears identically* across `QueryDemo` and `TodoCRUD`. It removes keystrokes from a
   pattern already validated in production examples, rather than inventing one.

## Prerequisites & footguns

- **`QueryKeyConvertible` protocol** — the non-macro prerequisite that lets `@Key` handle non-Int/String
  identity honestly. The highest-value item adjacent to the flagship; `Keys.swift`'s own doc already
  anticipates it.
- **`@Key` source-order is a cache-identity contract** — `queryKey` must be `[prefix] + @Key-props in
  declaration order`. Reordering `@Key` properties silently changes cache slots (a footgun on par with the
  "embed props need re-key" gotcha). Document it; consider a warning / fix-it.
- **The mutation resync (`QueryDemo:62`) is a *runtime / API* question, not a macro one.** The real root
  cause is the stored `@MutationState` + manual resync for *capturing* mutations. No macro should
  auto-derive it. The more interesting thread is a possible `mutation(_:)` call mirroring `query(_:)` that
  takes a fresh mutation value each render — which would remove the stored property + resync entirely for
  capturing mutations.
- **Compile-time budget** — all PURSUE items are member/peer/extension macros on small decls; none
  approach the type-inference hot-spots that hurt build times. The one to watch is `@Computed` *if* it ever
  grows auto-dependency-tracking — keep it explicit-deps-only and it stays cheap.

## Next step

**→ This spike now exists:** [`query-type-macro-design-spike.md`](query-type-macro-design-spike.md) — the
full design for the flagship **`@QueryType` + `QueryKeyConvertible` (Shape A)**: macro signatures, the
`QueryKeyConvertible` uniform-dispatch + `_qkc` error helper, the init/access-control rule, the diagnostic
set, golden `assertMacroExpansion` tests, example migrations, and a phased implementation outline. When implementation
proceeds, verify with: golden expansion tests in `Tests/SwiflowMacrosTests/` (mirror
`ComponentMacroTests.swift`); local example builds via `swiflow build --path examples/<name>` (**CI skips
example builds**); the `SwiflowQuery` suite (`swift test`); and a check that generated `stateCells`
excludes any derived/`@Computed` cell.

---

*Produced via a brainstorming session: parallel codebase exploration + the `swift-innovator-expert` agent,
with the three load-bearing claims (the `QueryDemo` resync, the `TodoCRUD` ceremony init, and the
`Keys.swift` 2-case enum) read and confirmed against source before recording.*
