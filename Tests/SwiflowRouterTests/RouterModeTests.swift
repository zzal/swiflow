// Tests/SwiflowRouterTests/RouterModeTests.swift
import Testing
@testable import SwiflowRouter

@Suite
struct RouterModeTests {

    private func router(mode: RouterMode) -> Router {
        Router(path: "/", mode: mode, navigate: { _ in }, replace: { _ in }, back: {})
    }

    @Test("Hash-mode hrefs prefix the path with #") func hashModeHrefsCarryTheHashPrefix() {
        #expect(router(mode: .hash).href(forPath: "/about") == "#/about")
        #expect(router(mode: .hash).href(forPath: "/search?q=x") == "#/search?q=x")
    }

    @Test("History-mode hrefs are the bare path") func historyModeHrefsAreThePathItself() {
        #expect(router(mode: .history).href(forPath: "/about") == "/about")
    }

    @Test("The mode-less Router init keeps compiling and defaults to .hash") func defaultRouterModeIsHash() {
        // Backward compat: the 4-argument init (no mode) must keep compiling
        // and default to .hash, matching RouterRoot's default.
        let r = Router(path: "/", navigate: { _ in }, replace: { _ in }, back: {})
        #expect(r.mode == .hash)
    }
}

// Audit IV Wave-2 #7: RouterMode used to be behaviorless — the mode
// dispatch was open-coded at five sites and the URL conventions had
// drifted (push wrote bare paths, replace/href built "#"-prefixed).
// The behavior now lives on the mode; url(for:) is THE construction site.
@Suite("RouterMode behavior")
struct RouterModeBehaviorTests {

    @Test("changeEvent names the mode's external-URL-change event")
    func changeEventPerMode() {
        #expect(RouterMode.hash.changeEvent == "hashchange")
        #expect(RouterMode.history.changeEvent == "popstate")
    }

    @Test("url(for:) — hash prefixes '#', history is identity, queries pass through")
    func urlForTable() {
        #expect(RouterMode.hash.url(for: "/about") == "#/about")
        #expect(RouterMode.hash.url(for: "/search?q=x") == "#/search?q=x")
        #expect(RouterMode.history.url(for: "/about") == "/about")
        #expect(RouterMode.history.url(for: "/search?q=x") == "/search?q=x")
    }

    @Test("href(forPath:) and url(for:) are the SAME construction — no second site to drift")
    func hrefDelegatesToMode() {
        let r = Router(path: "/", mode: .hash, navigate: { _ in }, replace: { _ in }, back: {})
        #expect(r.href(forPath: "/about") == RouterMode.hash.url(for: "/about"))
    }

    @Test("readPath — hash mode: empty and bare-# normalize to /, #/x strips the #")
    @MainActor
    func readPathHashTruthTable() {
        let nav = MockNavigator()
        nav.hash = ""
        #expect(RouterMode.hash.readPath(from: nav) == "/")
        nav.hash = "#"
        #expect(RouterMode.hash.readPath(from: nav) == "/")
        nav.hash = "#/about"
        #expect(RouterMode.hash.readPath(from: nav) == "/about")
        nav.hash = "#/users/42"
        #expect(RouterMode.hash.readPath(from: nav) == "/users/42")
    }

    @Test("readPath — history mode: pathname + search join, preserving the query")
    @MainActor
    func readPathHistoryJoins() {
        let nav = MockNavigator()
        nav.pathname = "/search"
        nav.search = "?q=swift"
        #expect(RouterMode.history.readPath(from: nav) == "/search?q=swift")
        nav.search = ""
        #expect(RouterMode.history.readPath(from: nav) == "/search")
    }

    @Test("round-trip: what push writes via url(for:), readPath reads back — the converged convention")
    @MainActor
    func writeReadRoundTrip() {
        let nav = MockNavigator()
        nav.setHash(RouterMode.hash.url(for: "/users/42"))
        #expect(RouterMode.hash.readPath(from: nav) == "/users/42")
    }
}
