import Testing
@testable import Swiflow

@Suite("State HMR hooks")
struct StateHMRHookTests {

    @Test("_hmrSnapshotValue returns the current wrapped value")
    func snapshotReadsCurrentValue() {
        let s = State<Int>(wrappedValue: 0)
        s.wrappedValue = 42
        #expect((s._hmrSnapshotValue() as? Int) == 42)
    }

    @Test("_hmrSnapshotValue captures String values")
    func snapshotStringValue() {
        let s = State<String>(wrappedValue: "")
        s.wrappedValue = "hello"
        #expect((s._hmrSnapshotValue() as? String) == "hello")
    }

    @Test("_hmrSnapshotValue captures Bool values")
    func snapshotBoolValue() {
        let s = State<Bool>(wrappedValue: false)
        s.wrappedValue = true
        #expect((s._hmrSnapshotValue() as? Bool) == true)
    }

    @Test("_hmrSnapshotValue captures Double values")
    func snapshotDoubleValue() {
        let s = State<Double>(wrappedValue: 0)
        s.wrappedValue = 3.14
        #expect((s._hmrSnapshotValue() as? Double) == 3.14)
    }

    @Test("_hmrSnapshotValue captures Optional<String> values")
    func snapshotOptionalStringValue() {
        let s = State<String?>(wrappedValue: nil)
        s.wrappedValue = "set"
        #expect((s._hmrSnapshotValue() as? String?) == "set")
    }

    @Test("_hmrRestore writes a matching-type value and returns true")
    func restoreMatchingTypeSucceeds() {
        let s = State<Int>(wrappedValue: 0)
        let ok = s._hmrRestore(99)
        #expect(ok == true)
        #expect(s.wrappedValue == 99)
    }

    @Test("_hmrRestore rejects a type-mismatched value and returns false")
    func restoreTypeMismatchFails() {
        let s = State<Int>(wrappedValue: 7)
        let ok = s._hmrRestore("not an int")
        #expect(ok == false)
        #expect(s.wrappedValue == 7)  // unchanged
    }

    @Test("_hmrRestore on Optional<String> accepts nil")
    func restoreOptionalStringAcceptsNil() {
        let s = State<String?>(wrappedValue: "before")
        let ok = s._hmrRestore(String?.none as Any)
        #expect(ok == true)
        #expect(s.wrappedValue == nil)
    }

    // BLOCKED (Phase 15 Task 1): Swift runtime erases the concrete type of
    // Optional<T>.none when stored in Any — all .none values become
    // indistinguishable and match the first Optional-typed `as T?` pattern
    // encountered, regardless of T. The exhaustive type-switch design in the
    // Phase 15 plan cannot distinguish Int?.none from Bool?.none without Mirror.
    // Mirror.displayStyle is still required for the .none branch.
    // This test documents the proven constraint; see plan for redesign notes.
    @Test("Optional<T>.none stored as Any loses concrete type — Mirror required for .none detection")
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

        // .some cases preserve concrete type — no Mirror needed for these.
        let someInt: Int? = 5
        #expect(classify(someInt as Any) == "int=5")
        #expect(classify(5 as Any) == "int=5")
        #expect(classify("hi" as Any) == "string=hi")
        #expect(classify(true as Any) == "bool=true")

        // .none cases lose concrete type — all match the first Optional arm (Bool?).
        // This is the proven constraint: exhaustive switch cannot route .none
        // to the correct arm; Mirror.displayStyle remains necessary for .none.
        let noneBool: Bool? = nil
        let noneInt: Int? = nil
        let noneString: String? = nil
        let noneDouble: Double? = nil
        #expect(classify(noneBool as Any) == "boolopt.none")   // correct arm
        #expect(classify(noneInt as Any) == "boolopt.none")    // wrong arm — type erased
        #expect(classify(noneString as Any) == "boolopt.none") // wrong arm — type erased
        #expect(classify(noneDouble as Any) == "boolopt.none") // wrong arm — type erased
    }
}
