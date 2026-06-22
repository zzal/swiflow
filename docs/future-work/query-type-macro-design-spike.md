# Design Spike: `@QueryType` / `@MutationType` macros + `QueryKeyConvertible`

Status: design spike (implementation-ready design, not finished code)
Audience: senior Swift / Swiflow maintainers
Targets: `SwiflowMacrosPlugin` (impl), `SwiflowQuery` (protocol + macro decls), `Tests/SwiflowMacrosTests`

---

## 1. Goal & scope

### The boilerplate we're eliminating

A `Query` today is hand-written like this (`examples/QueryDemo/Sources/App/App.swift`):

```swift
struct UserByID: Query {
    let id: Int
    let api: FakeAPI
    var queryKey: QueryKey { ["users", .int(id)] }
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }

    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}
```

Three things here are pure ceremony, mechanically derivable from the type's shape:

1. **`queryKey`** — a prefix component plus one component per identity field.
2. **The memberwise init with a defaulted dependency** (`api: FakeAPI = FakeAPI()`) — the *test seam*. The query is constructed at every render (`query(UserByID(id: userID))`), so the dependency must be injectable for tests but defaulted for callers.
3. The visual noise of separating *identity* (`id`) from *captured dependency* (`api`) — the distinction that drives both the key and `Sendable`/equality reasoning, but which is invisible in the source.

The target API makes the identity/dependency split *declarative* and derives the rest:

```swift
@QueryType struct UserByID {
    @Key var id: Int            // identity → queryKey component
    var api = FakeAPI()         // non-@Key → captured dep + defaulted test seam
    func fetch() async throws -> User { await api.user(id) }
}
```

The call site is **unchanged** — still a per-render method call parameterized by `@State` that changes between renders:

```swift
let u = query(UserByID(id: userID))
```

### In scope

- `QueryKeyConvertible` protocol + library conformances (`Int`, `String`, `Bool`, `RawRepresentable where RawValue: QueryKeyConvertible`).
- `@QueryType` attached macro: synthesizes `Query` conformance, `queryKey`, and (conditionally) the memberwise init.
- `@Key` marker macro: read by `@QueryType` from the syntax tree.
- `@MutationType` attached macro (sibling): synthesizes `Mutation` conformance + memberwise init. **Recommendation inside: ship it, but it is thin.**
- A compile-time diagnostic set with exact message text.
- Golden `assertMacroExpansion` tests mirroring `Tests/SwiflowMacrosTests`.

### Explicit non-goals

- **No consumption-side macro.** `query(_:)` / `@MutationState` stay exactly as they are. The macro never touches the call site, and never moves a query into a stored property (it *must not* — the query is parameterized by changing `@State`; see `examples/QueryDemo` line 60).
- **No auto-resync.** `@QueryType` does not generate the `self.rename = RenameUser(id: userID, …)` resync line in `body`. That's render-time application logic, out of scope.
- **No business-logic synthesis.** `fetch()` (queries) and `perform`/`optimistic`/`invalidations` (mutations) are always hand-written. The macro only synthesizes *identity and construction* plumbing.
- **No new runtime behavior.** Generated `queryKey` produces a `QueryKey` byte-for-byte equivalent to a hand-written one; the cache, prefix-cascade, and GC are untouched.
- **No `@Component`/`stateCells` interaction.** Queries and mutations are value types observed through `query(_:)`; they are not state cells. See §7.

---

## 2. `QueryKeyConvertible`

### Why a protocol at all (subtlety #1: macros see *syntax*, not types)

`@Key var id: Int` looks like it's an `Int`, but the macro cannot rely on that. Swift macros operate on the **syntax tree before type resolution**. The annotation could be:

- `@Key var id: Int` — obvious.
- `@Key var id: Swift.Int` — fully qualified.
- `@Key var id: UserID` where `typealias UserID = Int`.
- `@Key var id = 5` — *no annotation at all*; the type is inferred at compile time, invisible to the macro.
- `@Key var slug: Category` where `enum Category: String { … }`.

The `@Component` macro already establishes this discipline: `ComponentMacro.isOptionalType(_:)` refuses to string-match `hasSuffix("?")` and instead inspects `OptionalTypeSyntax` / `IdentifierTypeSyntax(name: "Optional")` because the audit caught `hasSuffix` mis-classifying `Optional<Int>`. We carry the same principle further: **the macro must not branch on the field's type at all.**

The escape hatch is a protocol the *type system* dispatches, not the macro:

```swift
// Sources/SwiflowQuery/QueryKeyConvertible.swift

/// A type whose identity can be encoded into `QueryKey` components.
///
/// `QueryKeyComponent` is deliberately a closed 2-case enum (`.string` /
/// `.int`) — the type-safe alternative to `AnyHashable` (no Int/Int64/String
/// confusion, debuggable, prefix-cascadable). Any type used as a `@Key` in a
/// `@QueryType` must therefore *project its identity* into those two cases.
///
/// `@QueryType` emits a uniform `.keyComponents` dispatch over every `@Key`
/// property in source order, so the macro never needs to know a property's
/// concrete type — the conformance carries that knowledge. Most keys are a
/// single component; the array return supports composite identities
/// (e.g. a `struct Coordinate` keying as `[.int(lat), .int(lon)]`).
@MainActor
public protocol QueryKeyConvertible {
    var keyComponents: [QueryKeyComponent] { get }
}
```

Note `@MainActor`: `Query` is `@MainActor`-isolated, so the generated `queryKey` getter is main-actor isolated, and the `keyComponents` it calls must be reachable from there. Marking the protocol `@MainActor` keeps the witness callable without an isolation hop and matches the rest of `SwiflowQuery`. (A non-isolated protocol would also work since the conformances are pure value reads, but matching the module's actor stance avoids `nonisolated` annotations leaking into user enum conformances.)

### Library conformances

```swift
// Sources/SwiflowQuery/QueryKeyConvertible.swift  (continued)

extension Int: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.int(self)] }
}

extension String: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.string(self)] }
}

/// Bool keys as a stable string so the key is debuggable ("done", "true")
/// rather than `.int(1)` colliding with a real integer id at the same
/// position. Two distinct, never-aliasing components.
extension Bool: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.string(self ? "true" : "false")] }
}

/// Enums with a convertible raw value key by their raw value for free:
///
///     enum Window: String, QueryKeyConvertible { case hour, day, week }
///     @Key var window: Window     // → .string("day")
///
/// The conformance is opt-in (the enum declares `: QueryKeyConvertible`), so
/// it never silently swallows a `RawRepresentable` the author didn't intend
/// as a key. `RawValue: QueryKeyConvertible` covers String- and Int-raw enums.
extension RawRepresentable where RawValue: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { rawValue.keyComponents }
}
```

Design decisions, justified:

- **`Bool` → `.string("true"/"false")`, not `.int(0/1)`.** A `Bool` and an `Int` key at the same position must never collide. `["todos", .int(1)]` (todo #1) and a hypothetical `["todos", false-as-int(0)]` staying distinct is exactly the confusion the closed enum exists to prevent. Strings are also more debuggable in cache dumps.
- **`RawRepresentable` is constrained, not blanket.** We do *not* write `extension RawRepresentable: QueryKeyConvertible` — that would force every `RawValue` to be convertible and conflict if a user enum has a `RawValue` we don't cover. The conditional `where RawValue: QueryKeyConvertible` plus opt-in (`enum Foo: String, QueryKeyConvertible`) means the conformance only activates where the author asked.
- **`Int64`/`UInt`/`Double` are intentionally *not* conformed.** Per `wasm32-int-32bit` memory: on wasm32 `Int` is 32-bit and `Int(_:)` traps on values beyond ±2³¹. We will not paper over that with a lossy `Int64 → .int(Int(truncating:))`. A 64-bit id should key as `.string(String(bigID))`. We surface this as a *documented gap with a clear fix*, not a silent trap — see the `requiresConvertibleKey` diagnostic in §6, which fires the standard "conform to QueryKeyConvertible" error and the doc note points the author at the `String` route.

### The uniform-dispatch rationale

Because every `@Key` value goes through `.keyComponents`, the generated `queryKey` is **type-agnostic and uniform** — the same emitted shape regardless of whether the key is `Int`, an enum, or a user struct:

```swift
var queryKey: QueryKey {
    ["UserByID"] + _qkc(id)          // prefix component + each @Key, in order
}
```

For multiple keys it concatenates in source order:

```swift
// from @Key var magnitude: String; @Key var window: Window
var queryKey: QueryKey {
    ["QuakeFeedQuery"] + _qkc(magnitude) + _qkc(window)
}
```

This is the whole point: the macro emits *one* code shape and lets the type system resolve each `_qkc(...)` call. No string-matching, no per-type branches, no fragility under typealiases or inference.

### The error-quality helper `_qkc` (subtlety #2: errors-as-documentation)

Errors-as-documentation is a Swiflow pillar (see the deliberately instructive messages in `StateMacroDiagnostic`, `ComponentMacroDiagnostic`). If the macro emitted a bare member access:

```swift
var queryKey: QueryKey { ["UserByID"] + id.keyComponents }   // ← DON'T
```

…then a non-conforming key type yields the compiler's generic, location-confusing:

> `value of type 'Foo' has no member 'keyComponents'`

— pointing *inside generated code* the user can't see, naming a member they never wrote. That's a terrible first-use experience.

Instead, emit calls to a generic free function whose constraint *is* the diagnostic:

```swift
// Sources/SwiflowQuery/QueryKeyConvertible.swift  (continued)

/// Underscored: an implementation detail of `@QueryType`'s expansion, not API.
/// Its generic constraint converts a missing conformance into the canonical
/// "requires that 'Foo' conform to 'QueryKeyConvertible'" diagnostic, anchored
/// to the user's `@Key var foo: Foo` rather than to invisible generated code.
@inlinable
@MainActor
public func _qkc<T: QueryKeyConvertible>(_ value: T) -> [QueryKeyComponent] {
    value.keyComponents
}
```

A non-conforming `@Key var bad: Foo` now produces:

> `global function '_qkc' requires that 'Foo' conform to 'QueryKeyConvertible'`

which is *actionable*: it names the offending type and the protocol to adopt. We sharpen this further with a `@QueryType`-side pre-check (§6, `requiresConvertibleKey`) that we *cannot* fully enforce (the macro doesn't know the type) but *can* hint when the spelling is recognizably non-conforming — but `_qkc` is the type-system backstop that always fires correctly.

Decision: **`_qkc` it is.** `@inlinable` so the indirection is free in `-O` (queries are constructed every render); `@MainActor` to match the protocol and `Query`'s isolation; underscore-prefixed and SPI-flavored so it doesn't pollute autocomplete. It lives in `SwiflowQuery` (public) so macro-emitted code in *user* modules can reach it — exactly as `ComponentMacro` relies on `_hmrCoerce` / `HMRNilSentinel` being public in the runtime module.

---

## 3. `@QueryType`

### What it reads from syntax

1. The decl must be a `struct` (diagnostic otherwise — §6).
2. Each stored property's attributes, scanned for `@Key` (string-match the attribute *name* `"Key"`, the same way `ComponentMacro` scans for `"State"`/`"MacroState"`). `@Key` properties, **in source order**, become key components.
3. For init synthesis: every stored property's name, type annotation (if any), default-value initializer expression (if any), and `let`/`var` binding specifier.
4. The macro's own argument list: `prefix:` (optional) — see §3.4.
5. Whether the user already declared `queryKey`, `tags`, or an `init` — to *suppress* synthesizing those (§3.3, §3.4).

It does **not** read or care about: `fetch()`, `Value`, computed properties, methods, nested types. Those pass through untouched.

### Macro declaration

```swift
// Sources/SwiflowQuery/QueryTypeMacro.swift   (public decls live in SwiflowQuery)

/// Synthesizes `Query` conformance for a `struct`: derives `queryKey` from the
/// `@Key`-marked stored properties (in source order, prefixed by the type name
/// or a custom `prefix:`) and emits a memberwise initializer that preserves
/// each property's default value (the test seam) at the struct's own access
/// level. `fetch()` stays hand-written.
///
/// - A hand-written `queryKey`, `tags`, or `init` suppresses synthesis of that
///   one member — the macro never fights an explicit declaration.
/// - Zero `@Key` properties yields a static key: just the prefix component,
///   e.g. `["users"]`.
///
/// **Requires:** a `struct`. `@Key` properties' types must conform to
/// `QueryKeyConvertible` (`Int`, `String`, `Bool`, and `RawRepresentable`
/// enums conform out of the box).
@attached(extension, conformances: Query)
@attached(member, names: named(queryKey), named(init(_:)))
public macro QueryType(prefix: String? = nil) =
    #externalMacro(module: "SwiflowMacrosPlugin", type: "QueryTypeMacro")
```

Notes on the attached roles (subtlety #7):

- **`@attached(extension, conformances: Query)`** mirrors `@Component`'s `@attached(extension, conformances: Component, _ComponentRuntime)`. The conformance goes in an extension so it works on a `public` type without forcing the user to write `: Query`. The extension body is empty (`extension UserByID: Query {}`); members go via the member role.
- **`@attached(member, names: named(queryKey), named(init(_:)))`.** We must declare the names the member macro introduces. `queryKey` is fixed. The init is the subtle one: swift-syntax requires we declare init names, and an unparameterized `named(init)` is **not** accepted for initializers with parameters. The pragmatic, plugin-proven choice used across the ecosystem is `named(init(_:))` *plus* `arbitrary` as a safety net, because the exact parameter labels vary per query. We deliberately avoid `arbitrary` if we can enumerate, but since init labels are data-dependent we will declare:

  ```swift
  @attached(member, names: named(queryKey), arbitrary)
  ```

  `arbitrary` is already the precedent in this codebase — `@State` and `@MutationState` both use `@attached(peer, names: arbitrary)` because they emit `$name`-derived names. Using `arbitrary` for the member role here is consistent and avoids brittle label enumeration. `queryKey` stays named so the common case is precise and the compiler can short-circuit. **Decision: `names: named(queryKey), arbitrary`.**

### 3.1 The full generated expansion of `UserByID`

Source:

```swift
@QueryType struct UserByID {
    @Key var id: Int
    var api: FakeAPI = FakeAPI()
    func fetch() async throws -> User { await api.user(id) }
}
```

Expansion (member macro adds members to the struct; extension macro adds conformance):

```swift
struct UserByID {
    @Key var id: Int
    var api: FakeAPI = FakeAPI()
    func fetch() async throws -> User { await api.user(id) }

    // --- synthesized by @QueryType (member role) ---
    var queryKey: QueryKey {
        ["UserByID"] + _qkc(id)
    }

    init(id: Int, api: FakeAPI = FakeAPI()) {
        self.id = id
        self.api = api
    }
}

// --- synthesized by @QueryType (extension role) ---
extension UserByID: Query {
}
```

Key observations:

- `@Key` remains in the expanded source. It is a **marker peer macro that expands to nothing** (§4); it survives only as a syntactic annotation that `@QueryType` read. (Cf. how `@State` survives in the `@Component` expansion in `ComponentMacroTests.testEmitsRuntimeMembers`.)
- `queryKey` is the uniform `["<prefix>"] + _qkc(<key>)` shape. `["UserByID"]` is a `QueryKey` (array) via `ExpressibleByStringLiteral` on `QueryKeyComponent` + array literal; `+ _qkc(id)` appends `[.int(id)]`. Result: `["UserByID", .int(id)]`. (Note this differs from the hand-written `["users", .int(id)]` — the *default* prefix is the type name; the migration uses `prefix: "users"` to preserve the existing key — see §8.)
- The init defaults `api` to `FakeAPI()` by **copying the default-value expression from the member syntax** (`var api = FakeAPI()` → `api: FakeAPI = FakeAPI()`). This is the test seam, synthesized for free.
- `tags` is **not** synthesized (no `@Key`-equivalent for tags; protocol default is `[]`). To set tags, the user writes `var tags: Set<QueryTag> { ["users"] }` by hand — and the macro skips nothing because it never tries to emit `tags`. (We considered a `tags:` macro arg; rejected — see §3.5.)

### 3.2 How the init carries types, defaults, and access level (subtlety #3)

This is the crux, and it requires precise analysis of what Swift gives us for free.

**The free memberwise init.** If `@QueryType` added *no* stored properties and *no* init, the Swift compiler would synthesize an **`internal`** memberwise initializer — and crucially, it *does* preserve property defaults. So `var api = FakeAPI()` already yields a free `init(id: Int, api: FakeAPI = FakeAPI())`. For an `internal` query in the same module, **we'd need to synthesize nothing.**

So when is macro init-synthesis actually needed? Two cases:

1. **`public` query types.** Swift's *free* memberwise init is `internal`. A `public struct UserByID` constructed from another module (or, in Swiflow's case, the common pattern where queries live in a library target and components in the app target) needs a **`public init`**. Swift will not synthesize a public memberwise init; you must write one. This is the real motivation.
2. **Guaranteeing the test seam regardless of access.** Even for `internal` types, the contract "every `@QueryType` is constructible with its dependencies defaulted" should be *explicit and stable*, not dependent on the user remembering not to write a stored `let` without a default (which would suppress Swift's free init's default for that field). Synthesizing the init makes the seam a guarantee of the macro, not an accident of Swift's synthesis rules.

**Decision: `@QueryType` always synthesizes the memberwise init** (unless the user wrote their own — see below). Rationale: it costs nothing for the common case, it's *required* for `public` types, and it makes the test-seam contract explicit. This matches how `ComponentMacro` always emits `bind`/`stateCells` rather than relying on defaults.

**How the synthesized init carries each piece, all from syntax:**

- **Parameter list = stored properties in source order.** We iterate `structDecl.memberBlock.members`, keep `VariableDeclSyntax`s that are stored (binding has no `accessorBlock`, or only an `accessorBlock` that is a `didSet`/`willSet` — but for queries we expect plain stored props; computed `var x: Int { … }` and `let`-with-getter are skipped). `static`/`class` properties are skipped.
- **Each parameter's type.** Prefer the explicit annotation `binding.typeAnnotation.type.trimmedDescription` (the same accessor `MutationStateMacro` and `StateMacro` use). **If there is no annotation** (`var api = FakeAPI()` *can* omit it; `@Key var id = 5` omits it) we cannot always synthesize a typed parameter — see the inference subtlety below.
- **Each parameter's default.** If the binding has an initializer clause (`= FakeAPI()`), copy `binding.initializer.value.trimmedDescription` verbatim into the parameter default. This is exactly how the test seam (`= FakeAPI()`) is preserved. Properties with no initializer (`@Key var id: Int`) get a non-defaulted parameter.
- **Access level.** Detect the struct's access modifier the same way `ComponentMacro` does (`classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) || .keyword(.open) }`). A `public`/`open` struct → `public init`; otherwise no leading keyword (internal). This directly mirrors `ComponentMacro`'s `isPublic` → `public func bind` logic.
- **Body.** One `self.<name> = <name>` per parameter, in order.

**The no-annotation inference subtlety (and its resolution).** Consider:

```swift
@QueryType struct Foo {
    @Key var id = 5            // inferred Int, no annotation
    var api = FakeAPI()        // inferred FakeAPI, no annotation
}
```

The macro cannot write `init(id: <?>, api: <?>)` because it doesn't know the inferred types. Two viable strategies:

- **(A) Require annotations on stored properties** and diagnose a missing one (`@QueryType` properties need explicit types). Clean, but slightly more ceremony, and `var api = FakeAPI()` *is* the headline example — forcing `var api: FakeAPI = FakeAPI()` is mildly annoying.
- **(B) Emit the init only for *annotated* properties and fall back to Swift's free init when any stored property lacks an annotation.** Fragile: silently downgrades to `internal`, breaking `public` types with an inferred field.

**Decision: (A) for `@Key`, (B-relaxed) for dependencies — concretely:**

- **`@Key` properties:** keep the headline ergonomic by allowing inference where it's unambiguous, BUT for the *init* we need the type. Resolution: if a `@Key` (or any stored property we must put in the init) has **no type annotation and a default we can't type**, we *do not* attempt to type the parameter — we emit the parameter as `<name>: <inferred-via-default-expr>` only when the default is a trivially-typed literal we recognize is risky. Rather than do brittle literal inference, we choose the clean rule:

  > **Rule (crisp): every stored property in a `@QueryType` that participates in the init must have an explicit type annotation OR a default-value expression.**
  > - With an annotation: parameter type = the annotation; default = the initializer if present.
  > - With a default but no annotation: we **cannot** name the type, so we emit the parameter using the *declared default as the only construction path* — i.e. we omit that property from the parameter list and assign it from its own default in the body **only if it has no `@Key`** (a defaulted dependency like `var api = FakeAPI()`); a `@Key` with no annotation is a **diagnostic** (`keyNeedsType`, §6), because a key *must* appear in the init for tests to vary it.

  In practice this means:
  - `var api = FakeAPI()` (defaulted dep, no annotation): the *cleanest* handling is to still expose it in the init with a default. Since we can't name the type, we instead emit `api: FakeAPI = FakeAPI()` **only if annotated**; if unannotated we drop it from the parameter list and rely on the property's own default initializer (the stored `var api = FakeAPI()` keeps its initializer in the expanded struct, so it's initialized without an init parameter). The test seam for *that specific field* is then lost (you can't inject `api` in tests), which is acceptable for a field the author chose not to annotate, and is documented.
  - `@Key var id` with no annotation and no default → diagnostic (a key with no type and no value is meaningless).
  - `@Key var id = 5` (no annotation, has default) → diagnostic `keyNeedsType`: a `@Key` must be init-injectable, which requires a known type. Fix-it: add `: Int`.

  This keeps the **headline example honest**: the minimal `var api = FakeAPI()` (as in §1) compiles — an unannotated dependency is initialized inline from its own default and *omitted* from the synthesized init, so it is not injectable. To make a dependency injectable in tests, annotate it (`var api: FakeAPI = FakeAPI()`) and the macro emits it as a defaulted init parameter (`init(id: Int, api: FakeAPI = FakeAPI())`); the canonical expansions in §3.1/§5 use the annotated form for exactly this reason. `@Key` properties always require an annotation (diagnostic `keyNeedsType`).

  > Practical refinement worth prototyping: because `var api = FakeAPI()` retains its initializer in the expanded struct, we *can* always include it as `api: <T> = FakeAPI()` **when annotated**, and when *not* annotated simply leave the stored initializer to do the work and omit the parameter. This gives the demo-perfect `var api = FakeAPI()` (no init param, initialized inline) and the test-seam-perfect `var api: FakeAPI = FakeAPI()` (init param defaulted). Both compile; the difference is only whether tests can override `api`.

- **Suppressing synthesis when the user wrote their own init.** Scan members for any `InitializerDeclSyntax`. If present, **skip init synthesis entirely** (emit only `queryKey` + the conformance). Rule: *any* user-declared `init` suppresses the synthesized one — we do not try to merge or detect "the memberwise one specifically," because that's ambiguous and surprising. This mirrors Swift's own rule (a user init suppresses the free memberwise init) and is the least-surprising behavior. (`examples/QueryDemo`'s hand-written `init(id:api:)` would suppress synthesis — which is exactly right for the additive-migration story in §8.)

**Crisp statement of the init rule:**

> `@QueryType` synthesizes a memberwise `init` at the struct's access level, one parameter per stored property in source order, copying each property's default-value expression as the parameter default. It is suppressed entirely if the struct declares any `init`. A `@Key` property must have an explicit type annotation (diagnostic `keyNeedsType` otherwise). A non-`@Key` stored property without an annotation is initialized from its own default and omitted from the init parameter list (so it is not injectable); annotate it to make it an injectable, defaulted parameter (the test seam).

### 3.3 Not fighting hand-written `queryKey` / `tags`

Before emitting `queryKey`, scan members for a `queryKey` declaration (a `VariableDeclSyntax` whose binding pattern identifier is `queryKey`). If present, **skip emitting `queryKey`** — the user's explicit one wins, and the macro only contributes the `Query` conformance + (maybe) the init. Same principle as the init suppression. `tags` is never synthesized, so there's nothing to skip there.

This makes the macro *purely additive on top of a partially-hand-written query*, which is the property that makes §8's migration non-breaking: a fully hand-written `Query` that adds `@QueryType` gets only the (suppressed-because-already-present) members skipped and a redundant-but-harmless `extension … : Query {}`. (We special-case: if the type already conforms via its own `: Query`, the `@attached(extension, conformances:)` role is a no-op the compiler dedups — same as re-stating a conformance.)

### 3.4 Prefix / opt-out (subtlety #5)

- **Default prefix** = the type-name string component: `["UserByID", …]`. Read `structDecl.name.text`.
- **Custom prefix** via `@QueryType(prefix: "users")` → `["users", …]`. Parse the macro's argument list (`node.arguments`), find the `prefix:` labeled argument, require it to be a **static string literal** (a `StringLiteralExprSyntax` with a single string segment — same rigor as `CSSMacro` requiring a static literal). Use its text as the prefix component. A non-literal (`prefix: someVar`) → diagnostic `prefixMustBeLiteral` (§6), because the key must be statically derivable for the cache.
- The prefix is always exactly **one** `.string` component. (Multi-component static prefixes — `["users", "active"]` — are the zero-`@Key` case below, handled by letting the user write `queryKey` by hand, OR by a future `prefix:` accepting an array; out of scope for v1. Decision: v1 `prefix:` is a single `String`.)

### 3.5 Should `tags:` be a macro argument?

**Decision: No.** Leave `tags` hand-written. Reasons:

- The protocol default is `[]`; most queries that need tags need exactly one or two, and `var tags: Set<QueryTag> { ["users"] }` is already terse and reads clearly.
- A `tags:` macro arg would have to accept an array literal of strings and re-emit it — pure pass-through with no derivation value, unlike `queryKey` (which *derives* from `@Key`). Macros earn their keep by deriving, not by relocating literals.
- It keeps the macro surface minimal (one optional `prefix:` arg), which is easier to teach and matches the "macro derives identity + construction, human writes everything else" boundary.

### 3.6 The zero-`@Key` case (subtlety #4)

A static-key query has no identity fields:

```swift
@QueryType struct TodoList {
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }
    func fetch() async throws -> [Todo] { try await api.get("/todos", as: [Todo].self) }
}
```

With zero `@Key` properties, the key is **just the prefix component**:

```swift
var queryKey: QueryKey {
    ["TodoList"]
}
```

To get the existing `["todos"]` key, use the prefix: `@QueryType(prefix: "todos") struct TodoList { … }` → `var queryKey: QueryKey { ["todos"] }`.

For a genuinely multi-component static key like `["users", "active"]`, v1 has the author write `queryKey` by hand (the macro skips it per §3.3) — or we extend `prefix:` to an array in a follow-up. The init synthesis still applies (here it'd be a zero-parameter `init()` — useful so `TodoList()` is `public` if the struct is `public`; otherwise the free `init()` already exists, so synthesis is harmless and consistent).

---

## 4. `@Key` — the marker (subtlety #4)

### What it is

```swift
// Sources/SwiflowQuery/QueryTypeMacro.swift  (continued)

/// Marks a stored property as part of a `@QueryType`'s identity (`queryKey`).
/// Read by `@QueryType` from the syntax tree; expands to nothing on its own.
/// Applies to `let` or `var`. The property's type must conform to
/// `QueryKeyConvertible`.
@attached(peer, names: arbitrary)
public macro Key() = #externalMacro(module: "SwiflowMacrosPlugin", type: "KeyMacro")
```

The implementation is a no-op peer macro:

```swift
// Sources/SwiflowMacrosPlugin/KeyMacro.swift
public struct KeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate placement; emit no peers. @Key is a marker read by @QueryType.
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindings.first?.accessorBlock == nil else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: KeyDiagnostic.requiresStoredProperty))
            return []
        }
        return []
    }
}
```

### Why a marker macro and not the alternatives

- **vs. property wrapper (`@Key var id: Int`).** A property wrapper would *change the stored type* to `Key<Int>`, forcing unwrapping at every use (`fetch()` would see `id.wrappedValue`), break `Equatable`/`Sendable` derivation, and add runtime overhead to a value constructed every render. The marker leaves `id` a plain `Int`. **Decisive reason: the property must stay its natural type for `fetch()` and for the synthesized init parameter.** This is the same reason `@State` is an accessor+peer macro, not a wrapper class (the Phase-15 migration in `ComponentMacro` *removed* the old `State<T>` wrapper class precisely for this).
- **vs. a naming convention** (e.g. "properties before the first `var api` are keys"). Implicit, position-fragile, unteachable. Rejected.
- **vs. a macro argument listing key names** (`@QueryType(keys: ["id"])`). Stringly-typed, decoupled from the declaration, no autocomplete, easy to typo. Rejected. The annotation lives *on* the property — discoverable, refactor-safe.
- **The chosen design mirrors SwiftData `@Attribute`/`@Relationship`**: marker macros on stored properties, read by the type-level `@Model` macro. Familiar to the audience.

`@Key` is declared `@attached(peer, names: arbitrary)` and emits **no** peers. (An empty `names: []` would express the no-op intent better, but it is *not* valid Swift — *"introduced name argument should be a name"* — so the marker reuses the same `arbitrary` form `@State`/`@MutationState` use for their real `$name` peers. Discovered during Phase 1 implementation.)

### `let` vs `var`

Both supported. The `KeyMacro` no-op doesn't care; `@QueryType`'s reader treats `let id: Int` and `var id: Int` identically for key derivation. For the init, a `let` key still becomes an init parameter (a `let` stored property is settable exactly once, in `init`). The headline uses `var id: Int`; the existing `examples/QueryDemo` uses `let id: Int` — both must work, and do.

### Zero `@Key` allowed

Yes — that's §3.6. The reader simply finds no `@Key` properties and emits the prefix-only key.

---

## 5. `@MutationType` (subtlety #6)

### The shape

Mutations have **no key**. `Mutation`'s requirements are `perform` (always hand-written business logic), `optimistic` + `invalidations` (defaulted, usually hand-written), and `Input`/`Output` associated types (inferred from `perform`). There is *nothing to derive* except the conformance and the test-seam init.

```swift
@MutationType struct RenameUser {
    let id: Int
    var api: FakeAPI = FakeAPI()
    func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
    func optimistic(_ newName: String) -> [OptimisticEdit] { … }
    func invalidations(input: String, output: User) -> [Invalidation] { … }
}
```

Expansion:

```swift
struct RenameUser {
    let id: Int
    var api: FakeAPI = FakeAPI()
    func perform(_ newName: String) async throws -> User { … }
    func optimistic(_ newName: String) -> [OptimisticEdit] { … }
    func invalidations(input: String, output: User) -> [Invalidation] { … }

    // --- synthesized by @MutationType ---
    init(id: Int, api: FakeAPI = FakeAPI()) {
        self.id = id
        self.api = api
    }
}

extension RenameUser: Mutation {
}
```

Macro declaration (no `prefix:`, no key, just the init + conformance):

```swift
@attached(extension, conformances: Mutation)
@attached(member, names: arbitrary)   // init labels are data-dependent
public macro MutationType() =
    #externalMacro(module: "SwiflowMacrosPlugin", type: "MutationTypeMacro")
```

Implementation note: `MutationTypeMacro` is **literally `@QueryType` minus key/prefix derivation** — same struct-check, same init-synthesis routine, same access-level logic, same "suppress if user wrote an init." So the two share an `InitSynthesis` helper in the plugin (a free function taking the `StructDeclSyntax` and returning the `init` `DeclSyntax?`), and `MutationTypeMacro` just omits the `queryKey` member and points the extension at `Mutation`.

### Ship or skip?

**Recommendation: ship it, but it is deliberately thin — and document its single value proposition clearly.**

The honest tension: a `Mutation` author who writes their own `init` (or whose mutation has no stored deps, like `AddTodo`/`ToggleTodo`/`DeleteTodo` in `examples/TodoCRUD`, which use the free `init()`) gets *zero* benefit from `@MutationType` — Swift's free memberwise init already covers them. The macro earns its keep in exactly one scenario:

- **A `public` mutation with stored dependencies** that needs a `public` defaulted init for cross-module construction + test injection (`public struct RenameUser` with `var api = FakeAPI()`). Here, as with queries, Swift's free init is only `internal`, so the macro is genuinely load-bearing.

Given that, the decision is **ship for symmetry and the public-mutation case, but lead documentation with: "for mutations with no stored dependencies, just conform `: Mutation` and use the free initializer — `@MutationType` is for `public` mutations that capture dependencies."** Shipping it also keeps the mental model uniform (`@QueryType` / `@MutationType` as a pair), which has real teaching value even when one is thin. The cost is ~30 lines of plugin code reusing the shared `InitSynthesis` helper, so the maintenance burden is negligible.

Concretely: in `examples/TodoCRUD`, `AddTodo`/`ToggleTodo`/`DeleteTodo` would **stay `: Mutation`** (no `@MutationType`) because they have no captured deps — and the spike's migration (§8) does exactly that, demonstrating the recommended boundary in the canonical example.

---

## 6. Diagnostic set

All diagnostics follow the existing pattern: an enum conforming to `DiagnosticMessage` with `MessageID(domain: "SwiflowMacros", id:)` and `.error` severity, emitted via `context.diagnose(Diagnostic(node:message:))` anchored at the most specific syntax node (the type keyword, the attribute, the binding). Message text is instructive (errors-as-documentation), matching `ComponentMacroDiagnostic`/`StateMacroDiagnostic` tone.

| # | When | Anchor node | Exact message | Fix-it |
|---|------|-------------|---------------|--------|
| 1 | `@QueryType` / `@MutationType` on a non-`struct` (class/enum/actor) | the type keyword (`class`/`enum`/`actor`), via the `ComponentMacro` keyword-extraction pattern | `@QueryType requires a struct — queries are value types constructed every render.` (mutation variant: `@MutationType requires a struct — mutations are value types.`) | — (no safe automatic fix) |
| 2 | `@Key` on a non-stored property (has a getter/`accessorBlock`) | the variable decl | `@Key marks a stored property; computed properties cannot be query-key components.` | — |
| 3 | `@Key` used outside a `@QueryType` | the `@Key` attribute | `@Key has no effect outside a @QueryType — move it onto a stored property of a @QueryType struct, or remove it.` | remove `@Key` |
| 4 | `@Key var id` with no type annotation (and we need it for the init) | the variable decl | `@Key requires an explicit type annotation so the key can be injected in tests (e.g. @Key var id: Int).` | insert `: <Type>` placeholder |
| 5 | `@QueryType(prefix:)` argument is not a static string literal | the argument expression | `@QueryType(prefix:) requires a string literal — the key prefix must be statically known for the cache.` | — |
| 6 | A `@Key` property's type does not conform to `QueryKeyConvertible` | (see note) | (see note) | — |

Notes:

- **Diagnostic #3 (`@Key` outside `@QueryType`)** is subtle: `@Key`'s own peer macro runs without knowing its enclosing type. The cleanest enforcement is *passive*: `@Key` expands to nothing and is harmless anywhere; if it's on a struct that *isn't* `@QueryType`, nothing reads it and it's a silent no-op — arguably fine. But errors-as-documentation favors catching the mistake. Resolution: `KeyMacro` can inspect `context` for the lexical parent is **not** reliably available in swift-syntax 600.x peer-macro expansion (peer macros don't get the enclosing decl). **Decision: we do *not* emit #3 from `KeyMacro`** (we can't see the parent). Instead, `@Key`'s doc comment states it's only meaningful inside `@QueryType`, and the *absence* of effect is benign. We keep #3 in this table as a known limitation, not a shipped diagnostic. (If a future swift-syntax exposes lexical context to peer macros, we add it.)

- **Diagnostic #6 (non-conforming key type)** is the one the macro *cannot* fully enforce, by design (subtlety #1: it doesn't know the type). We do **not** emit a macro diagnostic for it. Instead, the `_qkc` generic helper (§2) makes the *natural Swift conformance error* land correctly:

  > `global function '_qkc' requires that 'Foo' conform to 'QueryKeyConvertible'`

  This is the deliberate division of labor: **identity-derivation correctness is enforced by the type system via `_qkc`, not by syntactic guessing in the macro.** This is the same philosophy as leaving "missing `fetch()`" to the natural `Query` conformance error (below).

- **Left to natural Swift conformance errors (intentionally not macro diagnostics):**
  - **Missing `fetch()`** → the `extension … : Query {}` makes the compiler emit `type 'UserByID' does not conform to protocol 'Query'` / `protocol requires function 'fetch()'…`. This is already a good error; re-implementing it as a macro diagnostic would be redundant and could drift from the real protocol. The same applies to a `Value` that isn't `Equatable & Sendable`, and to `Mutation`'s missing `perform`.
  - **Non-`QueryKeyConvertible` `@Key` type** → via `_qkc`, as above.

This split — *the macro diagnoses what it can see in syntax (shape, placement, literal-ness); the type system diagnoses what requires type resolution (conformances)* — is the principled answer to subtlety #2, and exactly mirrors how `@Component` leans on the natural `Component` conformance error for a missing `body`.

---

## 7. HMR & macro-kind confirmation (subtlety #7)

- **No `stateCells` interaction.** `stateCells` exists only for `@Component` classes, to snapshot/restore `@State` across hot reloads (`ComponentMacro` member expansion). `@QueryType`/`@MutationType` produce **value types** observed via `query(_:)` / `@MutationState`; they hold no `@State`, are reconstructed every render, and never participate in HMR snapshotting. `@QueryType` emits **no** `stateCells`, `bind`, `runtimeOwner`, or `runtimeScheduler`. The HMR machinery is entirely orthogonal.
- **The `@MutationState`/`MutationRuntime` plumbing is untouched.** `@QueryType`/`@MutationType` change *how a `Query`/`Mutation` value type is declared*, not how it's *used*. `@MutationState var rename: RenameUser` and `MutationRuntime<RenameUser>()` keep working byte-for-byte — `RenameUser` is still a `Mutation`, just one whose conformance + init were synthesized.
- **Exact attached-macro roles** (the deliverable's checklist):
  - `@QueryType`: `@attached(extension, conformances: Query)` + `@attached(member, names: named(queryKey), arbitrary)`. Two roles.
  - `@MutationType`: `@attached(extension, conformances: Mutation)` + `@attached(member, names: arbitrary)`. Two roles.
  - `@Key`: `@attached(peer, names: arbitrary)`. One role, no-op.
  - `names:` list rationale: `named(queryKey)` is the one fixed member; `arbitrary` covers the init whose parameter labels are data-dependent (precedent: `@State`/`@MutationState` both use `arbitrary` for their peer role).
- **Plugin registration** (`SwiflowMacrosPlugin.swift`): add `QueryTypeMacro.self`, `MutationTypeMacro.self`, `KeyMacro.self` to `providingMacros`.

---

## 8. Golden tests

Mirroring the two existing styles in `Tests/SwiflowMacrosTests` (`MutationStateMacroTests` uses swift-testing `@Suite`/`@Test`; `ComponentMacroTests` uses `XCTestCase`). New tests follow `ComponentMacroTests`' `XCTestCase` + `assertMacroExpansion` style since `@QueryType` is a multi-role macro like `@Component`. The macro dictionary registers all three so cross-macro expansion (`@Key` surviving inside `@QueryType`) is exercised.

```swift
// Tests/SwiflowMacrosTests/QueryTypeMacroTests.swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

final class QueryTypeMacroTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "QueryType": QueryTypeMacro.self,
        "Key": KeyMacro.self,
    ]

    // Test 1 — canonical parameterized query: one @Key, one defaulted dep.
    // Verifies: prefix = type name, uniform `_qkc` dispatch, synthesized
    // public-absent (internal) init that preserves the `= FakeAPI()` default,
    // @Key surviving as a no-op marker, empty `: Query` extension.
    func testCanonicalQuery() {
        assertMacroExpansion(
            """
            @QueryType struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                func fetch() async throws -> User { await api.user(id) }

                var queryKey: QueryKey {
                    ["UserByID"] + _qkc(id)
                }

                init(id: Int, api: FakeAPI = FakeAPI()) {
                    self.id = id
                    self.api = api
                }
            }

            extension UserByID: Query {
            }
            """,
            macros: macros
        )
    }

    // Test 2 — static-key / zero-@Key query with a custom prefix.
    // Verifies: zero @Key → prefix-only key; custom `prefix:` arg; a
    // zero-parameter init synthesized (harmless, public-consistent).
    func testStaticKeyWithPrefix() {
        assertMacroExpansion(
            """
            @QueryType(prefix: "todos") struct TodoList {
                var tags: Set<QueryTag> { ["todos"] }
                func fetch() async throws -> [Todo] { try await api.get("/todos", as: [Todo].self) }
            }
            """,
            expandedSource: """
            struct TodoList {
                var tags: Set<QueryTag> { ["todos"] }
                func fetch() async throws -> [Todo] { try await api.get("/todos", as: [Todo].self) }

                var queryKey: QueryKey {
                    ["todos"]
                }

                init() {
                }
            }

            extension TodoList: Query {
            }
            """,
            macros: macros
        )
    }

    // Test 3 — diagnostic: @QueryType on a non-struct.
    // Anchored at the `class` keyword (ComponentMacro keyword-extraction
    // pattern); no members or extension emitted.
    func testNonStructDiagnostic() {
        assertMacroExpansion(
            """
            @QueryType final class UserByID {
                @Key var id: Int
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            final class UserByID {
                @Key var id: Int
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@QueryType requires a struct — queries are value types constructed every render.",
                    line: 1,
                    column: 18   // the `class` keyword
                )
            ],
            macros: macros
        )
    }

    // Test 4 (optional, recommended) — user-written init suppresses synthesis;
    // hand-written queryKey is not fought. Proves the additive-migration story:
    // a fully hand-written Query that adds @QueryType still compiles, the macro
    // only contributing the (idempotent) `: Query` conformance.
    func testHandWrittenMembersSuppressSynthesis() {
        assertMacroExpansion(
            """
            @QueryType struct UserByID {
                let id: Int
                let api: FakeAPI
                var queryKey: QueryKey { ["users", .int(id)] }
                func fetch() async throws -> User { await api.user(id) }
                init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
            }
            """,
            expandedSource: """
            struct UserByID {
                let id: Int
                let api: FakeAPI
                var queryKey: QueryKey { ["users", .int(id)] }
                func fetch() async throws -> User { await api.user(id) }
                init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
            }

            extension UserByID: Query {
            }
            """,
            macros: macros
        )
    }
}
```

(A `MutationTypeMacroTests` mirrors Test 1 with the `Mutation` conformance and no `queryKey` — omitted here for brevity but part of the deliverable.)

Note on `assertMacroExpansion` whitespace: the existing `ComponentMacroTests` documents (Tests 7–9) that SwiftSyntax's pretty-printer splits/indents emitted closures and arrays in specific ways. The golden strings above are the *intended* shape; during implementation we will run the tests and pin the *actual* pretty-printer output (e.g. exact indentation of the `init` body), exactly as the existing tests were pinned against real output.

---

## 9. Migration (additive, non-breaking)

The macros are **purely additive**: every existing hand-written `Query`/`Mutation` keeps compiling unchanged (a hand-written conformance + init is precisely what the macro *suppresses synthesizing*; §3.3). Migration is opt-in, file-by-file.

### `examples/QueryDemo` — `UserByID`

Before (lines 21–29):

```swift
struct UserByID: Query {
    let id: Int
    let api: FakeAPI
    var queryKey: QueryKey { ["users", .int(id)] }
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }

    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}
```

After:

```swift
@QueryType(prefix: "users") struct UserByID {
    @Key var id: Int
    var api: FakeAPI = FakeAPI()
    var tags: Set<QueryTag> { ["users"] }   // tags stay hand-written (protocol default is [])
    func fetch() async throws -> User { await api.user(id) }
}
```

- `prefix: "users"` preserves the existing `["users", .int(id)]` key **byte-for-byte** — critical, because the cache slot, the prefix-cascade, and `RenameUser.invalidations`' `[.exact(["users", .int(id)])]` all depend on this exact key. (Without the prefix, the default key would become `["UserByID", .int(id)]` and silently miss the cache / break invalidation — a migration footgun called out explicitly here.)
- `queryKey` and the `init` are now synthesized; `id` becomes `@Key var`; `api` becomes a defaulted dependency. `tags` stays.
- Net: 9 lines → 6, and the identity/dependency split is now declarative.

### `examples/QueryDemo` — `RenameUser`

Before (lines 31–47):

```swift
struct RenameUser: Mutation {
    let id: Int
    let api: FakeAPI
    func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
    func optimistic(_ newName: String) -> [OptimisticEdit] { … }
    func invalidations(input: String, output: User) -> [Invalidation] { … }
}
```

After:

```swift
@MutationType struct RenameUser {
    let id: Int
    var api: FakeAPI = FakeAPI()
    func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
    func optimistic(_ newName: String) -> [OptimisticEdit] { … }
    func invalidations(input: String, output: User) -> [Invalidation] { … }
}
```

- `RenameUser` has a captured dependency (`api`) but its construction in `QueryDemo` (`RenameUser(id: 1, api: FakeAPI())`, lines 56 & 62) currently passes `api` explicitly. After migration, those call sites can drop to `RenameUser(id: 1)` thanks to the synthesized default — though leaving them explicit also compiles. (The component's resync line `self.rename = RenameUser(id: userID, api: FakeAPI())` stays application logic; the macro doesn't touch it.)
- This is the *exact* public/dependency case where `@MutationType` earns its keep — though note `RenameUser` here is `internal`, so strictly the free init would suffice; the macro makes the seam explicit and the migration symmetric with `UserByID`.

### `examples/TodoCRUD` — mutations stay `: Mutation`

`AddTodo`, `ToggleTodo`, `DeleteTodo` (lines 31–67) have **no stored dependencies** (they call the module-level `let api`). Per §5's recommendation, they **do not** migrate to `@MutationType` — they keep `: Mutation` and the free `init()`. This demonstrates the documented boundary in the canonical example: *use `@MutationType` only when a mutation captures dependencies and needs a defaulted/public init.*

`TodoList` (lines 20–27), a zero-`@Key` query, *can* migrate:

```swift
@QueryType(prefix: "todos") struct TodoList {
    var tags: Set<QueryTag> { ["todos"] }
    var refetchInterval: Duration? { .seconds(5) }
    func fetch() async throws -> [Todo] { try await api.get("/todos", as: [Todo].self) }
}
```

— preserving `["todos"]` via the prefix.

### `examples/MissionControl` — `QuakeFeedQuery` (multi-key)

A good multi-`@Key` showcase (two string keys):

```swift
@QueryType(prefix: "quakes") struct QuakeFeedQuery {
    @Key var magnitude: String
    @Key var window: String
    var tags: Set<QueryTag> { ["quakes"] }
    var refetchInterval: Duration? { .seconds(30) }
    var staleTime: Duration { .seconds(30) }
    func fetch() async throws -> QuakeFeed { … }
}
```

→ `queryKey` synthesizes to `["quakes"] + _qkc(magnitude) + _qkc(window)` = `["quakes", .string(magnitude), .string(window)]`, byte-identical to the hand-written key.

### Non-breaking guarantee

Because (a) synthesis of `queryKey`/`init` is suppressed when hand-written, and (b) re-stating a `Query`/`Mutation` conformance in an extension is idempotent, a fully hand-written conformance that *adds* `@QueryType` compiles unchanged. So migration can proceed incrementally, and a half-migrated file (some queries macro'd, some not) is fine. CI builds the library targets; per the `ci-skips-example-builds` memory, the **example apps are not built in CI**, so each migrated example must be built locally (`swiflow build --path examples/QueryDemo`, `examples/TodoCRUD`, `examples/MissionControl`) before merge to catch key-prefix regressions the type system can't.

---

## 10. Risks & open questions

1. **Pretty-printer whitespace pinning.** `assertMacroExpansion` compares exact strings, and SwiftSyntax's pretty-printer has its own indentation rules (the existing tests 7–9 are evidence). The golden strings in §8 are intent; the first implementation pass must pin them to actual output. **Mitigation:** standard — write the test, run it, paste the real expansion. Low risk, known cost.
2. **`names: arbitrary` for the init.** Using `arbitrary` (vs. enumerating `named(init(...))`) is the safe, precedent-backed choice but slightly loosens the compiler's name-introduction contract. **Mitigation:** it's exactly what `@State`/`@MutationState` already do; no new risk.
3. **The no-annotation dependency case** (`var api = FakeAPI()` with no type annotation) loses *that field's* test-seam (it's initialized from its own default, not an init parameter). **Open question:** do we (a) accept it and document "annotate deps to make them injectable," or (b) diagnose unannotated non-`@Key` deps too? Spike's recommendation: **(a)** — the headline example reads best with `var api = FakeAPI()`, and most deps don't need per-test override (the *type* is the seam: swap `FakeAPI` for a test double at the type level). Revisit if real usage wants per-instance dep injection without annotations.
4. **Default-prefix surprise.** The default prefix is the *type name*, which differs from the conventional lowercase resource name (`"UserByID"` vs `"users"`). Every existing example uses a lowercase resource prefix, so **every migration needs `prefix:`**. **Open question:** should the default instead be the lowercased type name, or should `prefix:` be effectively mandatory? Recommendation: keep type-name default (it's *correct and unique* out of the box — two query types never collide), document that `prefix:` aligns the key with a REST resource, and make the migration examples model it. A lowercasing heuristic ("UserByID" → "userByID"? "user"? ) is guess-y and would itself surprise.
5. **`Mutation` has no `Equatable`/key, so `@MutationType` truly only saves the init.** Already addressed in §5 (ship-but-thin). Risk is *over*-selling it; mitigated by documentation that steers no-dependency mutations to plain `: Mutation`.
6. **Composite-key ordering stability.** `queryKey` order = source order of `@Key` properties. Reordering `@Key` declarations silently changes the cache key. **Mitigation:** document that `@Key` order is significant (it already is for any hand-written `queryKey`); consider a future lint. Low risk (reordering stored properties is rare and already semantically loaded).
7. **`prefix:` as a single string only (v1).** Multi-component static keys (`["users", "active"]`) fall back to hand-written `queryKey`. **Open question:** add `prefix: ["users", "active"]` overload later? Defer until a real case appears.

---

## 11. Phased implementation outline

**Phase 0 — `QueryKeyConvertible` (no macros).** Land `Sources/SwiflowQuery/QueryKeyConvertible.swift`: the protocol, the four conformances (`Int`/`String`/`Bool`/`RawRepresentable`), and `_qkc`. Pure library, fully unit-testable without any macro. *Verify:* unit tests asserting `5.keyComponents == [.int(5)]`, `"x".keyComponents == [.string("x")]`, `true.keyComponents == [.string("true")]`, and an enum `Window.day.keyComponents == [.string("day")]`. This de-risks the whole design (subtlety #1/#2) before touching swift-syntax.

**Phase 1 — `@Key` no-op marker.** `KeyMacro` + its `@attached(peer, names: arbitrary)` decl + plugin registration. *Verify:* a golden test asserting `@Key var id: Int` expands to itself (no peers) and the placement diagnostic (#2) fires on a computed property.

**Phase 2 — shared `InitSynthesis` helper.** A plugin-internal free function: `(StructDeclSyntax, isPublic: Bool) -> DeclSyntax?` returning the memberwise init (or `nil` if a user init exists). This is the riskiest syntax logic (default-expr copying, access level, annotation rules from §3.2), so build and test it in isolation first via the `@QueryType` golden tests' init lines. *Verify:* the canonical-query test (§8 Test 1) and the suppression test (Test 4).

**Phase 3 — `@QueryType`.** `QueryTypeMacro` as `ExtensionMacro` + `MemberMacro`: struct-check + diagnostics (§6 #1, #4, #5), `@Key` scanning (source order), `queryKey` emission (prefix + `_qkc` concat), `queryKey`-suppression (§3.3), `prefix:` arg parsing, and reuse of `InitSynthesis`. *Verify:* §8 Tests 1–4 green; then locally migrate + build `examples/QueryDemo` and `examples/MissionControl` and confirm the rendered key matches (the apps still load users/quakes — the only real test that the *prefix* is right, since the type system can't catch a wrong-but-valid key).

**Phase 4 — `@MutationType`.** `MutationTypeMacro` = struct-check + `Mutation` extension + `InitSynthesis` reuse, no key. *Verify:* a `MutationTypeMacroTests` mirror of Test 1; migrate `examples/QueryDemo`'s `RenameUser`; build locally and exercise rename (optimistic update + invalidation still fire).

**Phase 5 — docs + example migration.** Migrate `QueryDemo`/`TodoCRUD`/`MissionControl` per §9, update the `examples/QueryDemo/README.md` query snippet, and write the macro doc comments leading with the §5 guidance (no-dep mutations stay `: Mutation`). *Verify:* `swiflow build --path …` for each migrated example (CI won't — `ci-skips-example-builds`); run the QueryDemo/TodoCRUD e2e suites locally if touched (`run-e2e-locally-before-push`).

**Build order rationale:** library-only (Phase 0) → no-op macro (Phase 1, lowest macro risk) → the hard syntax (Phase 2, isolated) → the two real macros on top (Phases 3–4) → integration (Phase 5). Each phase is independently verifiable, and the type-system backstop (`_qkc`) from Phase 0 means even an incomplete macro can't ship an incorrect key without a compile error.
