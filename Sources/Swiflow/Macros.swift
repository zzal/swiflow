/// Conforms a `final class` to `Component` and emits the
/// `_ComponentRuntime` runtime infrastructure: stored properties for
/// owner/scheduler refs, the `bind(owner:scheduler:)` hook, and a
/// `stateCells` array describing each `@State`-decorated member.
@attached(extension, conformances: Component, _ComponentRuntime)
@attached(member, names:
    named(runtimeOwner),
    named(runtimeScheduler),
    named(stateCells),
    named(bind)
)
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
@attached(accessor, names: named(didSet))
@attached(peer, names: arbitrary)
public macro State() = #externalMacro(module: "SwiflowMacrosPlugin", type: "StateMacro")

/// Real CSS in Swift. Validates the literal's *structure* at compile time
/// (balanced braces, `property: value` shape) and expands to a `CSSSheet`
/// scoped via native CSS nesting — property names, values, and selectors
/// pass through to the browser verbatim, so new CSS features work the day
/// a browser ships them.
///
/// Scoping contract: `:host` (or top-level `&`) styles the component root;
/// every other selector matches descendants; `:root`/`html`/`body` rules and
/// non-nestable at-rules (`@keyframes`, `@font-face`, `@property`) escape the
/// scope wrapper.
///
/// **Requires:** a static string literal — no interpolation. Pass dynamic
/// values through CSS custom properties:
/// `div(...).style("--badge-color", value)` + `color: var(--badge-color)`.
@freestanding(expression)
public macro css(_ source: String) -> CSSSheet =
    #externalMacro(module: "SwiflowMacrosPlugin", type: "CSSMacro")
