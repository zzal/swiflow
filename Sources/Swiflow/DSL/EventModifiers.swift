// Sources/Swiflow/DSL/EventModifiers.swift

/// Registers `invoke` with the ambient handler registry installed by the
/// active render root (SwiflowDOM's browser Renderer or SwiflowTesting's
/// TestRenderer). Called internally by the `.on(_:perform:)` and binding
/// modifiers below. Traps if no render root is active — only possible when a
/// modifier is constructed outside a render cycle, which is a programmer error.
@MainActor
func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let registry = HandlerAmbient.current else {
        preconditionFailure(
            "Swiflow modifier .on(_:perform:) was used outside a render cycle. "
            + "Event handlers must be constructed inside a Component body while a render root "
            + "is actively building the tree — Swiflow.render(into:_:) in the browser, "
            + "SwiflowTesting.render(_:) in tests."
        )
    }
    return registry.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}

public extension VNode {
    /// Attaches an event listener for `event` to this VNode. The closure runs
    /// on the main actor when the DOM event fires.
    /// Non-element VNodes trigger a diagnostic in DEBUG and pass through unchanged.
    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> VNode {
        if case .element(var data) = self {
            let handler = _registerAmbientHandler { _ in action() }
            data.handlers[event.domName] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .on(_:perform:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Attaches an event listener for `event` that receives the runtime DOM
    /// event payload (`EventInfo`).
    /// Non-element VNodes trigger a diagnostic in DEBUG and pass through unchanged.
    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> VNode {
        if case .element(var data) = self {
            let handler = _registerAmbientHandler(action)
            data.handlers[event.domName] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .on(_:perform:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
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

    /// Two-way binding for `<input>` or `<textarea>` text content.
    /// Reads `binding.get()` into the element's `value` property on
    /// every render and registers an `.input` handler that writes
    /// `eventInfo.targetValue ?? ""` back into `binding.set(...)`.
    ///
    /// Emits `Attribute.compound([…])` so a single modifier produces
    /// both bag effects in one go; `applyAttributes` flattens the
    /// composite during the fold.
    @MainActor
    static func value(_ binding: Binding<String>) -> Attribute {
        let handler = _registerAmbientHandler { info in
            binding.set(info.targetValue ?? "")
        }
        return .compound([
            .property(name: "value", value: .string(binding.get())),
            .handler(event: "input", value: handler),
        ])
    }

    /// Two-way binding for an `Int`-valued input (typically
    /// `<input type="number">`). Parse failure leaves the binding
    /// unchanged; the user's malformed text stays in the DOM until
    /// they fix it.
    @MainActor
    static func value(_ binding: Binding<Int>) -> Attribute {
        let handler = _registerAmbientHandler { info in
            if let parsed = info.targetIntValue { binding.set(parsed) }
        }
        return .compound([
            .property(name: "value", value: .string(String(binding.get()))),
            .handler(event: "input", value: handler),
        ])
    }

    /// Two-way binding for a `Double`-valued input. Parse failure
    /// leaves the binding unchanged.
    @MainActor
    static func value(_ binding: Binding<Double>) -> Attribute {
        let handler = _registerAmbientHandler { info in
            if let parsed = info.targetDoubleValue { binding.set(parsed) }
        }
        return .compound([
            .property(name: "value", value: .string(String(binding.get()))),
            .handler(event: "input", value: handler),
        ])
    }

    /// Two-way binding for `<input type="checkbox">`. The element's
    /// `checked` property is written to `binding.get()` on every render;
    /// a `.change` event handler reads `eventInfo.targetChecked` and
    /// writes it back through `binding.set(...)`.
    @MainActor
    static func checked(_ binding: Binding<Bool>) -> Attribute {
        let handler = _registerAmbientHandler { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        return .compound([
            .property(name: "checked", value: .bool(binding.get())),
            .handler(event: "change", value: handler),
        ])
    }

    /// Two-way binding for `<select>`. The element's `value` property is
    /// written to `binding.get()` on every render (so the matching
    /// `<option>` is selected); a `.change` handler reads
    /// `eventInfo.targetValue` and writes it back through `binding.set(...)`.
    /// Multi-select (`<select multiple>`) lands in Phase 12.
    @MainActor
    static func selection(_ binding: Binding<String>) -> Attribute {
        let handler = _registerAmbientHandler { info in
            binding.set(info.targetValue ?? "")
        }
        return .compound([
            .property(name: "value", value: .string(binding.get())),
            .handler(event: "change", value: handler),
        ])
    }

    /// Binds this element's DOM node to `ref`. After mount,
    /// `ref.wrappedValue` returns the live `JSObject`; after unmount, it
    /// returns `nil`.
    ///
    /// Use this when you need to call an imperative DOM API from Swift —
    /// `focus()`, `scrollIntoView()`, reading uncontrolled `value`, etc.
    /// For controlled inputs, prefer `.value(_:Binding<...>)` instead.
    ///
    /// ```swift
    /// let nameInput = Ref<JSObject>()
    /// input(.value($name), .ref(nameInput))
    /// // …in onAppear: if let el = nameInput.wrappedValue { _ = el.focus!() }
    /// ```
    static func ref<E>(_ ref: Ref<E>) -> Attribute {
        .refBinding(AnyRefBinding(ref))
    }
}

public extension VNode {
    /// Postfix variant of `.value(_:Binding<String>)`. Writes both the
    /// `value` property and the `.input` handler directly into the
    /// element's bags. Non-element VNodes trigger a DEBUG diagnostic
    /// and pass through unchanged.
    @MainActor
    func value(_ binding: Binding<String>) -> VNode {
        if case .element(var data) = self {
            data.properties["value"] = .string(binding.get())
            let handler = _registerAmbientHandler { info in
                binding.set(info.targetValue ?? "")
            }
            data.handlers["input"] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .value(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Postfix variant of `.value(_:Binding<Int>)`. Parse failure on
    /// `.input` events leaves the binding unchanged.
    @MainActor
    func value(_ binding: Binding<Int>) -> VNode {
        if case .element(var data) = self {
            data.properties["value"] = .string(String(binding.get()))
            let handler = _registerAmbientHandler { info in
                if let parsed = info.targetIntValue { binding.set(parsed) }
            }
            data.handlers["input"] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .value(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Postfix variant of `.value(_:Binding<Double>)`. Parse failure on
    /// `.input` events leaves the binding unchanged.
    @MainActor
    func value(_ binding: Binding<Double>) -> VNode {
        if case .element(var data) = self {
            data.properties["value"] = .string(String(binding.get()))
            let handler = _registerAmbientHandler { info in
                if let parsed = info.targetDoubleValue { binding.set(parsed) }
            }
            data.handlers["input"] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .value(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Postfix variant of `.checked(_:Binding<Bool>)`. Writes both the
    /// `checked` property and the `.change` handler directly into the
    /// element's bags. Non-element VNodes trigger a DEBUG diagnostic
    /// and pass through unchanged.
    @MainActor
    func checked(_ binding: Binding<Bool>) -> VNode {
        if case .element(var data) = self {
            data.properties["checked"] = .bool(binding.get())
            let handler = _registerAmbientHandler { info in
                if let c = info.targetChecked { binding.set(c) }
            }
            data.handlers["change"] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .checked(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Postfix variant of `.selection(_:Binding<String>)`. Writes both
    /// the `value` property and the `.change` handler directly into the
    /// element's bags. Non-element VNodes trigger a DEBUG diagnostic
    /// and pass through unchanged.
    @MainActor
    func selection(_ binding: Binding<String>) -> VNode {
        if case .element(var data) = self {
            data.properties["value"] = .string(binding.get())
            let handler = _registerAmbientHandler { info in
                binding.set(info.targetValue ?? "")
            }
            data.handlers["change"] = handler
            return .element(data)
        }
        swiflowDiagnostic("Postfix .selection(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }

    /// Postfix variant of `.ref(_:)`. Appends a `Ref<E>` binding to the
    /// element's out-of-band `refBindings` slot; consumed by Diff at
    /// mount and destroy. Non-element VNodes trigger a DEBUG diagnostic
    /// and pass through unchanged.
    func ref<E>(_ ref: Ref<E>) -> VNode {
        if case .element(var data) = self {
            data.refBindings.append(AnyRefBinding(ref))
            return .element(data)
        }
        swiflowDiagnostic("Postfix .ref(_:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        return self
    }
}
