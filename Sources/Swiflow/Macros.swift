@attached(extension, conformances: Component)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")

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
@attached(peer, names: arbitrary)
public macro MacroState() = #externalMacro(module: "SwiflowMacrosPlugin", type: "StateMacro")
