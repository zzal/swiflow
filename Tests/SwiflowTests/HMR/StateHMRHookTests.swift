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
}
