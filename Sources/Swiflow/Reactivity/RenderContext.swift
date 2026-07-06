// Sources/Swiflow/Reactivity/RenderContext.swift
//
// Installs the three ambients every render root must set before running a
// synchronous diff pass and restore afterward: `HandlerAmbient.current`,
// `SwiflowTaskRuntime.currentScope`, `RenderObserverBox.current`. Forgetting
// one breaks that ambient's consumers silently (handlers register into no
// scope, `.task`/`query()` can't reach this root, or the query client never
// learns about a component unmount) rather than failing loudly, and the
// three used to be set/restored by hand at four separate call sites.
//
// Deliberately NOT closure-based (`withRenderContext { ... }`):
// `TestRenderer.init` must install this context before `self.mountTree` — a
// non-optional stored property — is assigned, and Swift forbids capturing
// `self` in a closure until every stored property is set. A closure-taking
// helper would be unusable at exactly that call site. `installRenderContext`
// takes only already-initialized values (no `self` capture); `uninstall`
// takes none at all — both are safe to call before `self` is fully formed.

@MainActor
package func installRenderContext(
    handlers: HandlerRegistry,
    taskScope: TaskScope,
    observer: (any RenderObserver)?
) {
    HandlerAmbient.current = handlers
    SwiflowTaskRuntime.currentScope = taskScope
    RenderObserverBox.current = observer
}

@MainActor
package func uninstallRenderContext() {
    HandlerAmbient.current = nil
    SwiflowTaskRuntime.currentScope = nil
    RenderObserverBox.current = nil
}
