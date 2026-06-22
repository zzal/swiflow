// Sources/SwiflowQuery/QueryTypeMacro.swift
//
// Public macro declarations for the @QueryType family. The implementations live
// in SwiflowMacrosPlugin; this file is the user-facing surface in SwiflowQuery.
// (Phase 1 ships only @Key; @QueryType / @MutationType land in later phases.)

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
