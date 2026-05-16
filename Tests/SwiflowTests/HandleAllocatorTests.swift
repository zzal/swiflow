// Tests/SwiflowTests/HandleAllocatorTests.swift
import Testing
@testable import Swiflow

@Suite("HandleAllocator")
struct HandleAllocatorTests {
    @Test("First handle is 0 by default")
    func firstHandleIsZero() {
        let a = HandleAllocator()
        #expect(a.next() == 0)
    }

    @Test("Handles are monotonically increasing")
    func monotonic() {
        let a = HandleAllocator()
        let h0 = a.next()
        let h1 = a.next()
        let h2 = a.next()
        #expect(h0 < h1)
        #expect(h1 < h2)
        #expect(h0 + 1 == h1)
        #expect(h1 + 1 == h2)
    }

    @Test("Custom starting handle respected")
    func customStart() {
        let a = HandleAllocator(start: 100)
        #expect(a.next() == 100)
        #expect(a.next() == 101)
    }

    @Test("Independent allocators do not share state")
    func independent() {
        let a = HandleAllocator()
        let b = HandleAllocator()
        _ = a.next()
        _ = a.next()
        #expect(b.next() == 0)
    }
}
