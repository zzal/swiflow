// Tests/SwiflowRouterTests/RouterRootNavigatorTests.swift
//
// Audit IV Wave-2 #6: the Navigator seam. RouterRoot's URL machine used to
// be force-unwrapped JS globals — host tests covered only pure matching.
// These tests drive the full lifecycle (initial read, event listening,
// navigate/replace/back, teardown) through a recording MockNavigator.
import Testing
import Swiflow
@testable import SwiflowRouter
@testable import SwiflowTesting

@Suite("RouterRoot.readPath over Navigator primitives")
struct ReadPathTests {

    @Test("hash mode: empty and bare-# hashes normalize to /, #/x strips the #")
    @MainActor
    func hashTruthTable() {
        let nav = MockNavigator()
        nav.hash = ""
        #expect(RouterRoot.readPath(mode: .hash, from: nav) == "/")
        nav.hash = "#"
        #expect(RouterRoot.readPath(mode: .hash, from: nav) == "/")
        nav.hash = "#/about"
        #expect(RouterRoot.readPath(mode: .hash, from: nav) == "/about")
        nav.hash = "#/users/42"
        #expect(RouterRoot.readPath(mode: .hash, from: nav) == "/users/42")
    }

    @Test("history mode: pathname + search join, preserving the query")
    @MainActor
    func historyJoinsPathnameAndSearch() {
        let nav = MockNavigator()
        nav.pathname = "/search"
        nav.search = "?q=swift"
        #expect(RouterRoot.readPath(mode: .history, from: nav) == "/search?q=swift")
        nav.search = ""
        #expect(RouterRoot.readPath(mode: .history, from: nav) == "/search")
    }
}
