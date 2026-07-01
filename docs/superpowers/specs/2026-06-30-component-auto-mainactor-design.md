# `@Component` auto-injects `@MainActor` — Design

**Goal:** Let users write a bare `@Component final class Foo` instead of `@MainActor @Component final class Foo`, with identical isolation semantics. The macro isolates the type to the main actor itself, so the `@MainActor` boilerplate disappears from every component.

**Issue / origin:** DX follow-up from the `Scheduler` MainActor isolation work (#92, PR #98). That change made a `@State`-bearing `@Component` require `@MainActor` (its `didSet` calls the now-isolated `markDirty`); the template/examples/Sources were already annotated, and "`@Component` auto-injects `@MainActor`" was recorded as the natural next DX step.

**Rollout (decided):** *Add + sweep* — ship the auto-injection AND remove the now-redundant `@MainActor` from the `swiflow new` template, all `examples/**`, and `Sources/**` components, so a freshly scaffolded app shows the clean `@Component final class` form.

---

## Why the boilerplate exists today

`Component` and `_ComponentRuntime` are **already `@MainActor` protocols** (`Sources/Swiflow/Reactivity/Component.swift:17,62`). Yet a bare `@Component final class` is *not* main-actor isolated, because `@Component` synthesizes conformance through a **generated extension** (`extension Foo: Component, _ComponentRuntime {}`), and — as documented in `Sources/SwiflowMacrosPlugin/MainActorWitnessIsolation.swift` — Swift does **not** infer a protocol's global actor onto the primary type when the conformance is added by a generated extension (unlike a hand-written `class Foo: Component`, where primary-declaration conformance *does* infer it). So the user's own members (`body`, `@State` `didSet`, methods, event handlers) stay nonisolated unless the user hand-writes `@MainActor` on the type.

`@Query` / `@Mutation` hit the identical problem and solved it with an `@attached(memberAttribute)` role (`MainActorWitnessIsolation`) that stamps `@MainActor` onto the members that need it. **`@Component` adopts the same mechanism** — this is a macro-plugin change only; no protocol, runtime, or scheduler change.

---

## Design

### 1. New `memberAttribute` role on `ComponentMacro`

`ComponentMacro` gains a `MemberAttributeMacro` conformance, and the macro declaration in `Sources/Swiflow/Macros.swift` gains `@attached(memberAttribute)`:

```swift
@attached(extension, conformances: Component, _ComponentRuntime)
@attached(member, names: /* existing list */)
@attached(memberAttribute)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")
```

The role's `expansion(of:attachedTo:providingAttributesFor:in:)` returns `["@MainActor"]` for members that should be isolated, `[]` otherwise. Unlike `@Query`/`@Mutation` (which isolate only a *witness subset* because a `Query`/`Mutation` is a value type passed across actors), `@Component` isolates **all** members — a component is an inherently main-actor reference type, so the faithful mirror of `@MainActor class` is to isolate everything.

**Stamping rules (in order):**

1. **Whole-type skip.** If the attached class already declares an explicit global actor (`@MainActor`, or any other `@SomeGlobalActor`), return `[]` for **every** member. This preserves byte-identical expansion for existing `@MainActor @Component` code and avoids redundant-attribute diagnostics. (`attachedTo declaration` carries the class's attributes.)
2. **Non-class / non-final skip.** If the attached decl isn't a `final class`, return `[]` (the extension/member roles already emit `requiresClass`/`requiresFinal`).
3. **Per-member skips** — return `[]` for a member that is:
   - a nested type declaration (`struct` / `class` / `enum` / `actor`),
   - a `typealias` (or `associatedtype`),
   - a `deinit`,
   - already carrying an isolation attribute (`@MainActor` or any `@…Actor`) **or** a `nonisolated` modifier.
4. **Otherwise** return `["@MainActor"]`. This includes instance methods, computed & stored properties (`var`/`let`), `init`s the user wrote, subscripts, and `static let`/`static var` — matching `@MainActor class`, under which static members are main-actor isolated too.

### 2. Synthesized members carry explicit `@MainActor`

A `memberAttribute` role only sees **user-written** members, not macro-synthesized ones. Today the member-macro output relies on the type being `@MainActor` for isolation of its synthesized decls; once the type is bare, they must isolate themselves. Currently only `stateCells` is annotated (`ComponentMacro.swift:149,153`). Add explicit `@MainActor` to the remaining synthesized decls:

- the synthesized `init()` (`ComponentMacro.swift:227`),
- `func bind(owner:scheduler:)` (`ComponentMacro.swift:213`),
- the `runtimeOwner` / `runtimeScheduler` stored properties (`ComponentMacro.swift:235,236`).

Explicit `@MainActor` on a member of an already-`@MainActor` type is legal and already in use (`stateCells`), so this is safe whether or not the user also writes `@MainActor` on the type.

### 3. Sweep the redundant annotations

Remove `@MainActor` from `@Component` declarations that no longer need it:

- the `swiflow new` scaffold template (and its embedded copy in `Sources/SwiflowCLI/EmbeddedTemplates.swift` — regenerate via `swift scripts/embed-templates.swift`),
- all `examples/**` components,
- all `Sources/**` components.

Any component that keeps `@MainActor` for an unrelated reason (none expected) is left as-is and simply hits the whole-type-skip path.

---

## Edge cases

| Case | Behavior |
|------|----------|
| Type already `@MainActor` (or other global actor) | Whole-type skip → **byte-identical** to today; no double-stamp. |
| `nonisolated func helper()` on a bare `@Component` | Not stamped → stays callable off-main. **The opt-out escape hatch.** |
| Member already `@MainActor` / on another actor | Skipped (no redundant attribute). |
| Nested `struct`/`enum`/`class`/`actor`, `typealias` | Not stamped — `@MainActor class` doesn't isolate nested types either; `@MainActor` isn't valid on `typealias`. |
| `deinit` | Not stamped — isolated-deinit is a separate feature we don't force. |
| `static let` / `static var` | Stamped — matches `@MainActor class` (static members are isolated). |
| Non-final / non-class | `memberAttribute` returns `[]`; existing `requiresFinal`/`requiresClass` diagnostics unchanged. |

---

## Testing

**Golden macro-expansion (`assertMacroExpansion`, whitespace-exact):**
1. **Bare `@Component final class`** with a `@State`, a method, and `body` → user members and all synthesized decls (`bind`, `init`, storage, `stateCells`) come out `@MainActor`-stamped. (Headline new behavior.)
2. **`@MainActor @Component final class`** → **byte-identical to current expansion** (whole-type skip). Regression guard the existing mutation/reducer golden tests already rely on.
3. **`nonisolated` member** on a bare `@Component` → that member is not stamped; siblings are.
4. **Nested `struct`/`enum` + `typealias`** inside a bare `@Component` → not stamped.
5. **`static let` / `static var`** → stamped.

**Host build (authoritative — golden tests diverge from the real compiler):**
- Full `swift build` + `swift test` with the template/examples/`Sources` swept to bare `@Component`. This is what actually proves isolation holds end-to-end (per the recurring lesson that `assertMacroExpansion` accepts things the compiler rejects and vice-versa).

**Example wasm builds:** `swiflow build --path examples/SwiflowUIDemo` (plus the other swept examples compile) — confirms `wasm32` isolation is satisfied.

**e2e smoke:** the existing `run-e2e`-gated Playwright suite still passes — no runtime change, pure isolation.

**Sweep verification:** after the sweep, `grep -rn "@MainActor @Component"` (and the two-line `@MainActor` / `@Component` form) across `templates/`, `examples/`, `Sources/` returns nothing.

---

## Acceptance criteria

1. A bare `@Component final class` with `@State`/methods compiles and is main-actor isolated with **no** hand-written `@MainActor` (host + wasm).
2. An existing `@MainActor @Component final class` expands **byte-identically** to today (golden test) and still compiles.
3. `nonisolated` on a member opts that member out of the auto-isolation.
4. The `swiflow new` template, all `examples/**`, and all `Sources/**` components drop the redundant `@MainActor`; `EmbeddedTemplates.swift` regenerated.
5. `swift build`, `swift test`, and the demo wasm build are green; the `run-e2e` suite (when run) passes.

## Out of scope

- Any protocol/runtime/scheduler change (`Component`/`_ComponentRuntime` are already `@MainActor`).
- Changing `@Query`/`@Mutation`/`MainActorWitnessIsolation` (their witness-subset policy is deliberately different — a value type crossing actors — and stays as-is; `@Component` gets its own all-members rule).
- Supporting `@Component` on a custom (non-`MainActor`) global actor as the *auto-injected* actor — the injection is always `@MainActor`; a user wanting a different actor writes it explicitly (whole-type skip).
