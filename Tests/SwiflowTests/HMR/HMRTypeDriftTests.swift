import Testing
@testable import Swiflow

@MainActor @Component
private final class HMRTD_NowString {
    @State var n: String = "initial"
    var body: VNode { .text("") }
}

@MainActor
@Suite("HMR type drift")
struct HMRTypeDriftTests {

    @Test("type-mismatched snapshot field leaves declared initial value untouched")
    func typeMismatchPreservesInitial() {
        // Snapshot says `n: Int = 7`, but the new module's class
        // declared `n: String`. Same typeName matches, but the
        // _hmrRestore type-check rejects the Int and leaves "initial".
        //
        // The applier emits a `swiflowDiagnostic` on rejection, which in
        // DEBUG builds traps via `fatalError`. Install the test override
        // so the call captures instead of trapping; restore on exit.
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: HMRTD_NowString.self),
            key: nil,
            state: ["n": 7]  // OLD-shape value (Int), new field is String
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = HMRTD_NowString()
        applyHMRRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.n == "initial")  // declared initial, not "7"
        // The applier should have reported the type mismatch.
        #expect(captured.contains { $0.contains("HMR restore: type mismatch") && $0.contains(".n") })
    }
}
