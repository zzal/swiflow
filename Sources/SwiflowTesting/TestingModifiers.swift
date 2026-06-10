// Sources/SwiflowTesting/TestingModifiers.swift
import Swiflow

/// Set by `TestRenderer` before every `diff` call; cleared after.
/// Provides `.on()` extensions with the same signature as SwiflowDOM,
/// so test components can register handlers without importing JavaScriptKit.
@MainActor
var _testAmbientHandlers: HandlerRegistry? = nil

public extension Attribute {
    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> Attribute {
        guard let registry = _testAmbientHandlers else { return .skip }
        let h = registry.register { _ in MainActor.assumeIsolated { action() } }
        return .handler(event: event.domName, value: h)
    }

    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> Attribute {
        guard let registry = _testAmbientHandlers else { return .skip }
        let h = registry.register { info in MainActor.assumeIsolated { action(info) } }
        return .handler(event: event.domName, value: h)
    }
}

public extension VNode {
    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> VNode {
        guard case .element(var data) = self,
              let registry = _testAmbientHandlers else { return self }
        data.handlers[event.domName] = registry.register { _ in
            MainActor.assumeIsolated { action() }
        }
        return .element(data)
    }

    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> VNode {
        guard case .element(var data) = self,
              let registry = _testAmbientHandlers else { return self }
        data.handlers[event.domName] = registry.register { info in
            MainActor.assumeIsolated { action(info) }
        }
        return .element(data)
    }
}
