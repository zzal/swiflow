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
}
