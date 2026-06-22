// Sources/SwiflowQuery/QueryTypeMacro.swift
//
// Public macro declarations for the @QueryType type-reducer family (@Key,
// @QueryType, @MutationType). The implementations live in SwiflowMacrosPlugin;
// this file is the user-facing surface in SwiflowQuery.

/// Marks a stored property as part of a `@QueryType`'s identity (`queryKey`).
///
/// `@Key` is a pure marker: on its own it expands to nothing. The enclosing
/// `@QueryType` reads it from the syntax tree, in source order, to derive
/// `queryKey` as `["<prefix>"] + _qkc(eachKey)`. Apply it to a `let` or `var`
/// stored property whose type conforms to `QueryKeyConvertible` (`Int`, `String`,
/// `Bool`, and `RawRepresentable` enums conform out of the box).
///
/// `names: arbitrary` is a formality: a peer macro must declare a names
/// specifier and an empty list (`names: []`) isn't valid Swift — `@Key` itself
/// emits no peers (see `KeyMacro`). This matches how `@State`/`@MutationState`
/// declare their peer role.
@attached(peer, names: arbitrary)
public macro Key() = #externalMacro(module: "SwiflowMacrosPlugin", type: "KeyMacro")

/// Synthesizes `Query` conformance for a `struct`: derives `queryKey` from the
/// `@Key`-marked stored properties (in source order, prefixed by the type name,
/// or by a custom `prefix:`) and emits a memberwise initializer that preserves
/// each property's default value (the test seam) at the struct's access level.
/// `fetch()` stays hand-written.
///
/// - A hand-written `queryKey` or `init` suppresses synthesis of that member —
///   the macro never fights an explicit declaration.
/// - Zero `@Key` properties yields a static key: just the prefix component.
/// - `@Key` properties' types must conform to `QueryKeyConvertible` (`Int`,
///   `String`, `Bool`, and `RawRepresentable` enums conform out of the box).
/// - `Query` is `@MainActor`. The macro isolates the witnesses (`fetch`, plus any
///   `static` state) to `@MainActor` for you, so a bare `@QueryType struct Foo`
///   conforms safely with no `: Query` and no hand-written `@MainActor` — even
///   when `fetch` touches `@MainActor` state. An explicit `: Query` still works.
///
/// ```swift
/// @QueryType struct UserByID {
///     @Key let id: Int
///     var api: FakeAPI = FakeAPI()
///     func fetch() async throws -> User { await api.user(id) }
/// }
/// ```
@attached(extension, conformances: Query)
@attached(member, names: named(queryKey), arbitrary)
@attached(memberAttribute)
public macro QueryType(prefix: String? = nil) =
    #externalMacro(module: "SwiflowMacrosPlugin", type: "QueryTypeMacro")

/// Synthesizes `Mutation` conformance for a `struct` plus a memberwise
/// initializer that preserves each captured dependency's default value (the test
/// seam) at the struct's access level. `perform` — and the optional `optimistic` /
/// `invalidations` — stay hand-written.
///
/// The thin sibling of `@QueryType`: a mutation has no cache identity, so there is
/// no `queryKey` / `@Key` / `prefix`. A hand-written `init` suppresses synthesis,
/// and an explicit `: Mutation` conformance is never double-declared.
///
/// `Mutation` is `@MainActor`. The macro isolates the witnesses (`perform` /
/// `optimistic` / `invalidations`, plus any `static` state) to `@MainActor` for
/// you, so a bare `@MutationType struct Foo` conforms safely with no `: Mutation`
/// and no hand-written `@MainActor` — even though `optimistic` calls the
/// `@MainActor` `OptimisticEdit.update`. An explicit `: Mutation` still works.
///
/// ```swift
/// @MutationType struct RenameUser {
///     let id: Int
///     let api: FakeAPI
///     func perform(_ newName: String) async throws -> User {
///         try await api.renameUser(id, name: newName)
///     }
/// }
/// ```
@attached(extension, conformances: Mutation)
@attached(member, names: named(init))
@attached(memberAttribute)
public macro MutationType() =
    #externalMacro(module: "SwiflowMacrosPlugin", type: "MutationTypeMacro")
