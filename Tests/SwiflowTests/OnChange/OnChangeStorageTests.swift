// Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("onChange(of:)")
struct OnChangeStorageTests {

    final class Holder: Component {
        @State var count = 0
        @State var label = ""
        var body: VNode { .text("") }
    }

    @Test("first call does not fire perform")
    func firstCallDoesNotFire() {
        let c = Holder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        var fired = false
        c.onChange(of: 1, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("same value does not fire perform")
    func sameValueDoesNotFire() {
        let c = Holder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("changed value fires with new value")
    func changedValueFires() {
        let c = Holder()
        defer { OnChangeStorage.remove(for: ObjectIdentifier(c)) }
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var received: Int? = nil
        c.onChange(of: 10, key: "k") { received = $0 }
        #expect(received == 10)
    }

    @Test("multiple keys tracked independently")
    func multipleKeysTrackedIndependently() {
        let c = Holder()
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
        let c = Holder()
        c.onChange(of: 5, key: "k") { _ in }  // seed
        OnChangeStorage.remove(for: ObjectIdentifier(c))
        // After remove, next call is treated as first → no fire even if value is same
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }
}
