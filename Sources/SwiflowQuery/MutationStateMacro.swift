// Sources/SwiflowQuery/MutationMacro.swift

/// Declares a mutation on a `@Component` class. The decorated `var` stays the
/// stored `Mutation`; the macro emits a `$name` reactive handle projection plus
/// a persistent backing `MutationRuntime`. `@Component` wires the runtime's
/// `QueryClient` at mount (spec §8). Mirrors `@State`'s name/`$name` split.
@attached(peer, names: arbitrary)
public macro MutationState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "MutationStateMacro")
