// Sources/Swiflow/Reactivity/State.swift
//
// `@State` is an attached macro (see `Macros.swift` and
// `SwiflowMacrosPlugin/StateMacro.swift`); per-cell wiring is driven by
// `_ComponentRuntime.stateCells` emitted by `@Component`.
//
// This file holds the `Binding<T>` value type that `@State`'s peer-macro
// expansion uses for the `$name` projection.

/// Two-way binding shaped like SwiftUI's. Returned from a `@State` var's
/// `$`-prefix projection:
///
/// ```swift
/// @State var text: String = ""
/// // ...
/// input(.value($text))         // .input event, text round-trip
/// ```
///
/// Consumers ship in core's `DSL/EventModifiers.swift`: `.value(_:)`,
/// `.checked(_:)`, and `.selection(_:)` — all in both prefix
/// (`Attribute` static) and postfix (`VNode` method) shapes.
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}
