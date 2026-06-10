// Sources/Swiflow/Reactivity/HandlerAmbient.swift
//
// The active handler registry. Saved/restored by each render root around its
// render, exactly like `RenderObserverBox.current` and
// `SwiflowTaskRuntime.currentScope`. Core's event/binding modifiers
// (DSL/EventModifiers.swift) register handlers against this slot, so every
// renderer backend (SwiflowDOM's browser Renderer, SwiflowTesting's headless
// TestRenderer) gets the same modifier API — same registration path, same
// failure semantics — by installing its registry here.

package enum HandlerAmbient {
    @MainActor package static var current: HandlerRegistry?
}
