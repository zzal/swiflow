// Tests/SwiflowTests/Reactivity/RenderContextTests.swift
import Testing
@testable import Swiflow

@MainActor
private final class RecordingObserver: RenderObserver {
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) {}
    func didEvaluate() {}
    func componentDidUnmount(_ owner: AnyComponent) {}
}

@Suite("installRenderContext / uninstallRenderContext")
@MainActor
struct RenderContextTests {
    @Test("install sets all three ambients; uninstall resets all three to nil")
    func installSetsAndUninstallResetsAllThreeAmbients() {
        defer {
            HandlerAmbient.current = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }

        let handlers = HandlerRegistry()
        let scope = TaskScope()
        let observer = RecordingObserver()

        installRenderContext(handlers: handlers, taskScope: scope, observer: observer)
        #expect(HandlerAmbient.current === handlers)
        #expect(SwiflowTaskRuntime.currentScope === scope)
        #expect(RenderObserverBox.current === observer)

        uninstallRenderContext()
        #expect(HandlerAmbient.current == nil)
        #expect(SwiflowTaskRuntime.currentScope == nil)
        #expect(RenderObserverBox.current == nil)
    }

    @Test("install accepts a nil observer, leaving the observer ambient nil")
    func installAcceptsNilObserver() {
        defer {
            HandlerAmbient.current = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }

        let handlers = HandlerRegistry()
        let scope = TaskScope()

        installRenderContext(handlers: handlers, taskScope: scope, observer: nil)
        #expect(HandlerAmbient.current === handlers)
        #expect(SwiflowTaskRuntime.currentScope === scope)
        #expect(RenderObserverBox.current == nil)
    }

    @Test("install records the observer in lastRendered; uninstall leaves it (handler-time fallback)")
    func lastRenderedSurvivesUninstall() {
        defer { uninstallRenderContext(); RenderObserverBox.lastRendered = nil }
        let observer = RecordingObserver()
        installRenderContext(handlers: HandlerRegistry(), taskScope: TaskScope(), observer: observer)
        uninstallRenderContext()
        #expect(RenderObserverBox.current == nil)
        #expect(RenderObserverBox.lastRendered === observer,
                "handlers run between renders and resolve the client through lastRendered")
    }

    @Test("an observer-less install does not clobber another root's lastRendered")
    func nilObserverDoesNotClobberLastRendered() {
        defer { uninstallRenderContext(); RenderObserverBox.lastRendered = nil }
        let observer = RecordingObserver()
        installRenderContext(handlers: HandlerRegistry(), taskScope: TaskScope(), observer: observer)
        uninstallRenderContext()

        installRenderContext(handlers: HandlerRegistry(), taskScope: TaskScope(), observer: nil)
        uninstallRenderContext()
        #expect(RenderObserverBox.lastRendered === observer)
    }

    @Test("lastRendered is weak: a torn-down root's observer self-clears")
    func lastRenderedIsWeak() {
        defer { uninstallRenderContext(); RenderObserverBox.lastRendered = nil }
        do {
            let observer = RecordingObserver()
            installRenderContext(handlers: HandlerRegistry(), taskScope: TaskScope(), observer: observer)
            uninstallRenderContext()
            #expect(RenderObserverBox.lastRendered === observer)
        }
        // The observer's last strong reference is gone — the slot must not
        // have kept it alive.
        #expect(RenderObserverBox.lastRendered == nil)
    }
}
