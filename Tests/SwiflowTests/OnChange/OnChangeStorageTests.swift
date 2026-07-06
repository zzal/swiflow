// Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift
import Testing
@testable import Swiflow

@Component
private final class OnChange_Holder {
    @State var count: Int = 0
    @State var label: String = ""
    var body: VNode { .text("") }
}

@MainActor
@Suite("onChange(of:)")
struct OnChangeStorageTests {

    /// A holder guaranteed to have no `OnChangeStorage` entry. The table is a
    /// process-global keyed by `ObjectIdentifier` (the object's address), which
    /// the allocator recycles after deallocation — so under the parallel test
    /// runner a freshly created holder can land on an address a prior (already
    /// cleaned-up) holder used and inherit a stale value, breaking the
    /// "fresh component has no stored value" assumption. Clearing on creation
    /// makes each test hermetic. Production clears the same way on unmount
    /// (Diff.destroyComponent → OnChangeStorage.remove).
    private func makeCleanHolder() -> OnChange_Holder {
        let c = OnChange_Holder()
        OnChangeStorage.remove(for: ObjectIdentifier(c))
        return c
    }

    @Test("first call does not fire perform")
    func firstCallDoesNotFire() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        var fired = false
        c.onChange(of: 1, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("same value does not fire perform")
    func sameValueDoesNotFire() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("changed value fires with new value")
    func changedValueFires() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var received: Int? = nil
        c.onChange(of: 10, key: "k") { received = $0 }
        #expect(received == 10)
    }

    @Test("multiple keys tracked independently")
    func multipleKeysTrackedIndependently() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        c.onChange(of: 1, key: "count") { _ in }   // seed count
        c.onChange(of: "x", key: "label") { _ in } // seed label
        var countFired = false
        var labelFired = false
        c.onChange(of: 2, key: "count") { _ in countFired = true }
        c.onChange(of: "x", key: "label") { _ in labelFired = true }
        #expect(countFired == true)
        #expect(labelFired == false)
    }

    @Test("remove clears all entries for component")
    func removeClearsAllEntries() {
        let c = makeCleanHolder()
        c.onChange(of: 5, key: "k") { _ in }  // seed
        OnChangeStorage.remove(for: ObjectIdentifier(c))
        // After remove, next call is treated as first → no fire even if value is same
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    // MARK: - Default-key collision (two omitted-key call sites in one method)
    //
    // Both `onChange(of:)` expressions below live as direct statements in
    // ONE shared local function — mirroring a real `onChange()` override,
    // where two calls are siblings in the same method body, called again on
    // every render. `#function` for both resolves to that one enclosing
    // function's name regardless of line (reproducing the old collision);
    // `fileID:line` differs per statement while staying stable each time the
    // shared function re-runs (each simulated render), which is exactly the
    // property being tested. Two call sites each wrapped in their OWN local
    // function would give them different `#function` values too, silently
    // sidestepping the very collision under test.
    private func render(_ c: OnChange_Holder, a: Int, b: Int, onA: (Int) -> Void, onB: (Int) -> Void) {
        c.onChange(of: a, perform: onA)
        c.onChange(of: b, perform: onB)
    }

    /// Two DIFFERENT call sites, each omitting `key:`, must not share a
    /// storage slot: call site A's own unchanged value must not fire just
    /// because sibling call site B legitimately changed in between. Under
    /// the old `key: String = #function` default, both statements in the
    /// same method resolve to the identical key — this reproduces the exact
    /// collision that default was replaced to fix.
    @Test("call site A's unchanged value does not fire when a sibling call site's value changes")
    func sharedKeyDoesNotCauseFalsePositiveFire() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }

        var aFired = false
        render(c, a: 1, b: 100, onA: { _ in aFired = true }, onB: { _ in })   // render 1: seed both
        render(c, a: 1, b: 200, onA: { _ in aFired = true }, onB: { _ in })   // render 2: A unchanged, B changed

        #expect(aFired == false)
    }

    /// Mirror of the above: each call site's OWN real change must still be
    /// detected independently, with no explicit `key:` at either site.
    @Test("two omitted-key call sites each detect their own change independently")
    func differentCallSitesTrackChangesIndependently() {
        let c = makeCleanHolder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }

        var aFired = false
        var bFired = false
        render(c, a: 1, b: 100, onA: { _ in aFired = true }, onB: { _ in bFired = true })  // render 1: seed both
        render(c, a: 2, b: 200, onA: { _ in aFired = true }, onB: { _ in bFired = true })  // render 2: both changed

        #expect(aFired == true)
        #expect(bFired == true)
    }
}
