// Sources/Swiflow/Reactivity/State.swift
//
// Phase 15 — `@State` is now an attached macro (see `Macros.swift` and
// `SwiflowMacrosPlugin/StateMacro.swift`). The previous `State<T>` /
// `Box<T>` / `StateWireable` machinery is deleted; per-cell wiring is
// now driven by `_ComponentRuntime.stateCells` emitted by `@Component`.
//
// What survives: the `Binding<T>` value type that `@State`'s peer-macro
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
/// Consumers ship in `SwiflowWeb.AttributeModifiers`: `.value(_:)`,
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
