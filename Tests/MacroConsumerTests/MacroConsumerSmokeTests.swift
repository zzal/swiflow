// Tests/MacroConsumerTests/MacroConsumerSmokeTests.swift
//
// Cross-module runtime smoke over the compiled macro-consumer target
// (audit III Wave-2 #9). Deliberately NOT @testable — the whole point is
// exercising the emitted code's real access levels from another module.
// The heavy lifting is the COMPILATION of MacroConsumerChecks itself;
// these assertions prove the emitted members are reachable and behave.

import Testing
import MacroConsumerChecks
import SwiflowQuery

@Suite("Macro consumer (cross-module, no @testable)")
struct MacroConsumerSmokeTests {

    @Test("a public @State projection is readable and writable cross-module")
    @MainActor
    func publicStateProjection() {
        let counter = PublicCounter()
        counter.bump()
        #expect(counter.count == 1)
        counter.$count.set(counter.$count.get() + 4)
        #expect(counter.count == 5)
    }

    @Test("cross-actor access to emitted @MainActor members goes through await")
    func crossActor() async {
        let value = await crossActorBump()
        #expect(value == 1)
    }

    @Test("@Component synthesized init() for a defaultless @MutationState; the handle is public")
    @MainActor
    func mutationHolderSynthesis() {
        let holder = makeMutationHolder()
        #expect(holder.$save.isIdle)
        #expect(!holder.$save.isPending)
    }

    @Test("a package-access @ReducerState projection is readable from the same package")
    @MainActor
    func packageReducerProjection() {
        let host = makeReducerHost()
        #expect(host.$flow.state.step == 0)
    }

    @Test("@Key drives cache identity: same id same key, different id different key")
    @MainActor
    func keyMacroIdentity() {
        #expect(ThingByID(id: 1).queryKey == ThingByID(id: 1).queryKey)
        #expect(ThingByID(id: 1).queryKey != ThingByID(id: 2).queryKey)
    }
}
