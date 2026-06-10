// Sources/Swiflow/CSS/StyleInjectionRegistry.swift
//
// Process-global "inject this stylesheet exactly once" guard, shared by
// CSSInjector (per-component scoped sheets) and SwiflowUI (its base token
// sheet). The guard + once-semantics live here in pure Swiflow so they're
// host-testable; the actual DOM emit is a closure SwiflowDOM registers at
// startup (mirrors the `onComponentTypeMount` / CSSMountHook pattern).

/// Tracks which style ids have been injected and routes the emit through a
/// swappable sink. `@MainActor` because all rendering — and therefore all
/// injection — happens on the main actor (single-threaded WASM).
@MainActor
public enum StyleInjectionRegistry {
    /// Ids already injected this session.
    private static var injectedIDs: Set<String> = []

    /// Emits recorded while no sink was installed. Flushed (in record order)
    /// the moment `emit` is set, so installing styles before
    /// `Swiflow.render(into:_:)` wires the DOM sink is safe — the CSS is
    /// buffered, not lost.
    private static var pending: [(id: String, css: String)] = []

    /// The emit sink. SwiflowDOM sets this to append a `<style>` to `<head>`.
    /// `nil` on a host with no DOM (tests/headless): `injectOnce` records the
    /// id AND buffers the css; setting the sink flushes the buffer.
    /// emits recorded before the sink is set are buffered and flushed when it arrives.
    public static var emit: ((_ id: String, _ css: String) -> Void)? {
        didSet {
            guard let emit, !pending.isEmpty else { return }
            let flush = pending
            pending = []
            for entry in flush { emit(entry.id, entry.css) }
        }
    }

    /// Injects `css` under `id` exactly once. The `css` builder runs only on
    /// the first call for an id (so repeat renders don't rebuild the string).
    /// Returns `true` iff this call performed the (first) injection.
    @discardableResult
    public static func injectOnce(id: String, css: () -> String) -> Bool {
        guard !injectedIDs.contains(id) else { return false }
        injectedIDs.insert(id)
        if let emit {
            emit(id, css())
        } else {
            pending.append((id: id, css: css()))
        }
        return true
    }

    /// Forgets all injected ids AND drops any buffered emits, so the next
    /// `injectOnce` re-emits fresh. Tests/HMR.
    public static func reset() {
        injectedIDs = []
        pending = []
    }
}
