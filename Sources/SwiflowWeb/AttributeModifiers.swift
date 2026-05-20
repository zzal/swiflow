// Sources/SwiflowWeb/AttributeModifiers.swift
#if canImport(JavaScriptKit)
@_exported import Swiflow

/// Registers `invoke` with the ambient renderer's handler registry. Called
/// internally by the `.on(_:perform:)` modifier overloads below. Traps if
/// no renderer is mounted — only possible if a modifier is constructed
/// outside a render cycle, which is a programmer error.
@MainActor
func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let renderer = ambientRenderer else {
        fatalError(
            "Swiflow modifier .on(_:perform:) was used before Swiflow.render(into:_:) was called. "
            + "Event handlers must be constructed inside a Component body that the renderer is "
            + "actively building — typically this means you're calling a Swiflow factory at module scope."
        )
    }
    return renderer.handlers.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}

public extension Attribute {
    /// Attaches an event listener for `event`. The closure runs on the main
    /// actor when the DOM event fires. Handler lifetime is tied to the
    /// owning component — closures may capture `self` strongly.
    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> Attribute {
        .handler(event: event.domName, value: _registerAmbientHandler { _ in action() })
    }

    /// Attaches an event listener for `event` that receives the runtime DOM
    /// event payload (`EventInfo`).
    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> Attribute {
        .handler(event: event.domName, value: _registerAmbientHandler(action))
    }
}
#endif
