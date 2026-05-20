// Tests/SwiflowTests/HMR/HMRBridgeRoundTripTests.swift
//
// Simulates the JS-bridge encode→decode round-trip for every supported
// primitive type. Tests construct state maps that match what
// `HMRBridge.decodeStateMap` would produce for each JS value, then
// verify that `applyRestore` correctly restores them.
//
// WHY THIS FILE EXISTS:
// The JS bridge (`encodeStateMap`/`decodeStateMap`) requires JavaScriptKit
// and cannot run in a macOS unit-test target. These tests simulate the
// bridge output to cover the type-coercion rules that live on the Swift
// side. The gaps that bugs 2 and 3 (Blocker 2: Int→Double coercion,
// Blocker 3: nil-Optional restore) exploited would have been caught
// immediately by tests like these.
//
// WHAT IS NOT TESTED HERE:
// The JSValue ↔ primitive conversion in `encodeStateMap`/`decodeStateMap`
// itself. A future WASM test target should add end-to-end bridge tests that
// actually call `HMRBridge.takePendingSnapshot()` after staging a mock
// `window.__swiflowPendingSnapshot`.

import Testing
@testable import Swiflow

@MainActor
@Suite("HMR bridge round-trip simulation")
struct HMRBridgeRoundTripTests {

    // MARK: - Helpers

    /// Build an index from a single-component snapshot at path "".
    private func index(typeName: String, state: [String: Any]) -> [SnapshotKey: [String: Any]] {
        HMRWalker.indexSnapshots([
            ComponentSnapshot(path: "", typeName: typeName, key: nil, state: state)
        ])
    }

    // MARK: - Bool (must be checked before Int — Swift bridges Bool to NSNumber)

    final class BoolHolder: Component {
        @State var flag: Bool = false
        var body: VNode { .text("") }
    }

    @Test("bridge: Bool true round-trips")
    func boolTrue() {
        let fresh = BoolHolder()
        let idx = index(typeName: String(reflecting: BoolHolder.self), state: ["flag": true])
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.flag == true)
    }

    @Test("bridge: Bool false round-trips")
    func boolFalse() {
        let fresh = BoolHolder()
        fresh.flag = true
        let idx = index(typeName: String(reflecting: BoolHolder.self), state: ["flag": false])
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.flag == false)
    }

    // MARK: - Int (decodeStateMap stores integral JS numbers as Int)

    final class IntHolder: Component {
        @State var count: Int = 0
        var body: VNode { .text("") }
    }

    @Test("bridge: Int round-trips as Int")
    func intRoundTrip() {
        let fresh = IntHolder()
        // decodeStateMap produces Int for integral JS numbers
        let idx = index(typeName: String(reflecting: IntHolder.self), state: ["count": Int(99)])
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.count == 99)
    }

    // MARK: - Double (decodeStateMap converts non-integral JS numbers to Double,
    //         but integral JS numbers become Int — requiring coercion on restore)

    final class DoubleHolder: Component {
        @State var price: Double = 0.0
        @State var fraction: Double = 0.0
        var body: VNode { .text("") }
    }

    @Test("bridge: integral Double arrives as Int, coerces to Double")
    func doubleIntegralCoercion() {
        // encodeStateMap: Double(42.0) → .number(42.0)
        // decodeStateMap: 42.0.truncatingRemainder == 0 → stored as Int(42)
        // _hmrRestoreImpl must coerce Int → Double (was Blocker 2)
        let fresh = DoubleHolder()
        let idx = index(
            typeName: String(reflecting: DoubleHolder.self),
            state: ["price": Int(42), "fraction": Double(3.14)]
        )
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.price == 42.0)
        #expect(fresh.fraction == 3.14)
    }

    // MARK: - String

    final class StringHolder: Component {
        @State var label: String = ""
        var body: VNode { .text("") }
    }

    @Test("bridge: String round-trips")
    func stringRoundTrip() {
        let fresh = StringHolder()
        let idx = index(typeName: String(reflecting: StringHolder.self), state: ["label": "hello"])
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.label == "hello")
    }

    // MARK: - Optional (nil → JS null → HMRNilSentinel)

    final class OptionalHolder: Component {
        @State var name: String? = nil
        @State var score: Int? = nil
        var body: VNode { .text("") }
    }

    @Test("bridge: JS null decodes to HMRNilSentinel, restores Optional to nil")
    func nullSentinelRestoresNil() {
        // encodeStateMap: Optional.none → .null
        // decodeStateMap: .null → HMRNilSentinel (was Blocker 3 when missed)
        // applyRestore: routes HMRNilSentinel to _hmrRestoreNil()
        let fresh = OptionalHolder()
        fresh.name = "before"
        fresh.score = 7
        let idx = index(
            typeName: String(reflecting: OptionalHolder.self),
            state: ["name": HMRNilSentinel(), "score": HMRNilSentinel()]
        )
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.name == nil)
        #expect(fresh.score == nil)
    }

    @Test("bridge: non-nil Optional<String> round-trips as String")
    func optionalSomeRoundTrip() {
        // encodeStateMap: Optional.some("x") → Optional payload → .string("x")
        // decodeStateMap: .string("x") → "x"
        // _hmrRestoreImpl: "x" as? String? matches via Swift's Any-to-Optional promotion
        let fresh = OptionalHolder()
        let idx = index(
            typeName: String(reflecting: OptionalHolder.self),
            state: ["name": "restored"]
        )
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.name == "restored")
    }

    @Test("bridge: non-nil Optional<Int> coerces from integral Double via bridge path")
    func optionalIntFromBridge() {
        // encodeStateMap: Optional.some(Int(5)) → Double(5.0) via .number(Double(i))
        // decodeStateMap: integral 5.0 → Int(5)
        // _hmrRestoreImpl: Int(5) as? Int? matches
        let fresh = OptionalHolder()
        let idx = index(
            typeName: String(reflecting: OptionalHolder.self),
            state: ["score": Int(5)]
        )
        HMRWalker.applyRestore(index: idx, to: AnyComponent(fresh), at: "", key: nil)
        #expect(fresh.score == 5)
    }
}
