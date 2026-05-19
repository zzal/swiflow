// Tests/SwiflowTests/DiffTests/HandlerDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — handlers")
@MainActor
struct HandlerDiffTests {

    @Test("Adding a handler emits addHandler and updates handlerIds")
    func addHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button")),
            handles: handles,
            handlers: handlers
        )

        let h = handlers.register { _ in }
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [
            .addHandler(handle: 0, event: "click", handlerId: h.id),
        ])
        #expect(update.newMountTree.handlerIds["click"] == h.id)
    }

    @Test("Removing a handler emits removeHandler and drops from registry")
    func removeHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )

        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button")),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [.removeHandler(handle: 0, event: "click")])
        #expect(update.newMountTree.handlerIds["click"] == nil)
        #expect(handlers.handler(forID: h.id) == nil, "removed handlers must be dropped from the registry")
    }

    @Test("Swapping a handler emits removeHandler then addHandler")
    func swapHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h1 = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h1])),
            handles: handles,
            handlers: handlers
        )

        let h2 = handlers.register { _ in }
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h2])),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [
            .removeHandler(handle: 0, event: "click"),
            .addHandler(handle: 0, event: "click", handlerId: h2.id),
        ])
        #expect(update.newMountTree.handlerIds["click"] == h2.id)
        #expect(handlers.handler(forID: h1.id) == nil)
        #expect(handlers.handler(forID: h2.id) != nil)
    }

    @Test("Unchanged handler ID emits no patches")
    func unchangedNoPatches() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        #expect(update.patches.isEmpty)
    }
}
