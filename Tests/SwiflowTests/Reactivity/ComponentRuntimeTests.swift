import Testing
import Foundation
@testable import Swiflow

@Suite("ComponentRuntime + StateCell")
struct ComponentRuntimeTests {

    @Test("StateCell witness dispatches through the typed closures")
    @MainActor
    func witnessDispatch() throws {
        @MainActor final class Owner: Component {
            var box: Int = 7
            var body: VNode { .text("") }
        }
        let cell = StateCell<Owner>(
            name: "box",
            snapshot: { $0.box as Any },
            restore: { o, v in
                guard let i = v as? Int else { return false }
                o.box = i
                return true
            },
            restoreNil: { _ in false }
        )
        let inst = Owner()
        let any: any AnyStateCell = cell

        #expect(any.name == "box")
        #expect(any.snapshot(of: inst) as? Int == 7)
        #expect(any.restore(on: inst, value: 42) == true)
        #expect(inst.box == 42)
        #expect(any.restore(on: inst, value: "wrong type") == false)
        #expect(any.restoreNil(on: inst) == false)
    }

    @Test("_ComponentRuntime adoption keeps Component working for non-adopters")
    @MainActor
    func runtimeOptional() throws {
        @MainActor final class NoRuntime: Component {
            var body: VNode { .text("plain") }
        }
        let inst = NoRuntime()
        let asComponent: any Component = inst
        // Hand-rolled Component conformances simply don't conform.
        #expect((asComponent as? any _ComponentRuntime) == nil)
    }
}
