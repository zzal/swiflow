// Tests/SwiflowTests/HMR/StateHMRHookTests.swift
//
// Phase 15: the per-cell `_hmrSnapshotValue` / `_hmrRestore` hooks that
// used to live on `State<T>` are gone. The closures emitted by the
// `@Component` macro now play that role and are exercised end-to-end
// by `HMRRoundTripTests` / `HMRBridgeRoundTripTests` / `ComponentRuntimeTests`.
//
// The Optional<T>.none-in-Any test below documents a permanent Swift
// runtime constraint (Phase 15 Task 1 finding) — the macro normalizes
// .none to HMRNilSentinel at the source precisely because exhaustive
// `as?` checks can't recover the concrete type after type-erasure.

import Testing
@testable import Swiflow

@Suite("Optional<T>.none in Any — runtime constraint")
struct OptionalNoneInAnyConstraintTests {
    // BLOCKED (Phase 15 Task 1): Swift runtime erases the concrete type of
    // Optional<T>.none when stored in Any — all .none values become
    // indistinguishable and match the first Optional-typed `as T?` pattern
    // encountered, regardless of T. The macro-emitted snapshot closures
    // normalize .none to HMRNilSentinel at the source for this reason.
    @Test("Optional<T>.none stored as Any loses concrete type — sentinel required")
    func optionalNoneInAnySwitchErasesType() throws {
        func classify(_ v: Any) -> String {
            switch v {
            case let b as Bool:    return "bool=\(b)"
            case let s as String:  return "string=\(s)"
            case let i as Int:     return "int=\(i)"
            case let d as Double:  return "double=\(d)"
            case let b as Bool?:   return b.map { "boolopt.some=\($0)" } ?? "boolopt.none"
            case let s as String?: return s.map { "stropt.some=\($0)" } ?? "stropt.none"
            case let i as Int?:    return i.map { "intopt.some=\($0)" } ?? "intopt.none"
            case let d as Double?: return d.map { "doubleopt.some=\($0)" } ?? "doubleopt.none"
            default: return "unknown"
            }
        }

        // .some cases preserve concrete type — no Mirror / sentinel needed.
        let someInt: Int? = 5
        #expect(classify(someInt as Any) == "int=5")
        #expect(classify(5 as Any) == "int=5")
        #expect(classify("hi" as Any) == "string=hi")
        #expect(classify(true as Any) == "bool=true")

        // .none cases lose concrete type — all match the first Optional arm.
        let noneBool: Bool? = nil
        let noneInt: Int? = nil
        let noneString: String? = nil
        let noneDouble: Double? = nil
        #expect(classify(noneBool as Any) == "boolopt.none")
        #expect(classify(noneInt as Any) == "boolopt.none")    // wrong arm — type erased
        #expect(classify(noneString as Any) == "boolopt.none") // wrong arm — type erased
        #expect(classify(noneDouble as Any) == "boolopt.none") // wrong arm — type erased
    }
}
