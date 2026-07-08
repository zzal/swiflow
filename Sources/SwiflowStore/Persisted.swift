// Sources/SwiflowStore/Persisted.swift

/// Persistent reactive state on a `@Component` class: behaves exactly like
/// `@State` (dirty-marking writes, `$name` binding) and additionally
/// hydrates from `PersistentStore` on mount and saves on every write.
///
/// ```swift
/// @Persisted var magnitude: String = "2.5"            // key "QuakesPage.magnitude"
/// @Persisted("legacy-key") var window: String = "day" // key "legacy-key"
/// ```
///
/// The declared default paints first; the stored value (if any) arrives on
/// the mount hydration pass and re-renders. Values must be `Codable`.
/// Keys auto-namespace by the owning component's type name — pass an
/// explicit key to share state across components or migrate old data.
///
/// **Requires:** a `var` with an explicit type annotation on a
/// `@Component final class` (same rules as `@State`).
@attached(accessor, names: named(didSet))
@attached(peer, names: arbitrary)
public macro Persisted() = #externalMacro(module: "SwiflowMacrosPlugin", type: "PersistedMacro")

/// Explicit-key variant — see `Persisted()`. The key must be a static
/// string literal (it is baked into the emitted storage calls).
@attached(accessor, names: named(didSet))
@attached(peer, names: arbitrary)
public macro Persisted(_ key: String) = #externalMacro(module: "SwiflowMacrosPlugin", type: "PersistedMacro")
