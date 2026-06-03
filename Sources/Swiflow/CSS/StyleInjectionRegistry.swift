// Sources/Swiflow/CSS/StyleInjectionRegistry.swift
//
// Process-global "inject this stylesheet exactly once" guard, shared by
// CSSInjector (per-component scoped sheets) and SwiflowUI (its base token
// sheet). The guard + once-semantics live here in pure Swiflow so they're
// host-testable; the actual DOM emit is a closure SwiflowWeb registers at
// startup (mirrors the `onComponentTypeMount` / CSSMountHook pattern).

/// Tracks which style ids have been injected and routes the emit through a
/// swappable sink. `@MainActor` because all rendering — and therefore all
/// injection — happens on the main actor (single-threaded WASM).
@MainActor
public enum StyleInjectionRegistry {
    /// Ids already injected this session.
    private static var injectedIDs: Set<String> = []

    /// The emit sink. SwiflowWeb sets this to append a `<style>` to `<head>`.
    /// `nil` on a host with no DOM (tests/headless): `injectOnce` still records
    /// the id (preserving once-semantics) but emits nothing.
    public static var emit: ((_ id: String, _ css: String) -> Void)?

    /// Injects `css` under `id` exactly once. The `css` builder runs only on
    /// the first call for an id (so repeat renders don't rebuild the string).
    /// Returns `true` iff this call performed the (first) injection.
    @discardableResult
    public static func injectOnce(id: String, css: () -> String) -> Bool {
        guard !injectedIDs.contains(id) else { return false }
        injectedIDs.insert(id)
        emit?(id, css())
        return true
    }

    /// Forgets all injected ids so the next `injectOnce` re-emits. Tests/HMR.
    public static func reset() { injectedIDs = [] }
}
