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

@MainActor
private func makeRoot(mode: RouterMode, nav: MockNavigator) -> RouterRoot {
    RouterRoot(mode: mode, navigator: nav, routes: {
        RouteDefinition(pattern: RoutePattern("/"), factory: { _ in .text("home") })
        RouteDefinition(pattern: RoutePattern("/about"), factory: { _ in .text("about") })
    }, notFound: nil)
}

@Suite("RouterRoot lifecycle through the Navigator seam")
struct RouterRootNavigatorTests {

    @Test("init reads the initial path from the navigator — hash mode")
    @MainActor
    func initialPathHash() {
        let nav = MockNavigator()
        nav.hash = "#/about"
        let h = render(makeRoot(mode: .hash, nav: nav))
        #expect(h.allText.contains("about"))
    }

    @Test("init reads pathname+search — history mode (query preserved through matching)")
    @MainActor
    func initialPathHistory() {
        let nav = MockNavigator()
        nav.pathname = "/about"
        nav.search = "?tab=1"
        let h = render(makeRoot(mode: .history, nav: nav))
        #expect(h.allText.contains("about"), "matcher strips the query; the route still matches")
    }

    @Test("hash navigate is EVENT-DRIVEN: setHash recorded, path unchanged until the event")
    @MainActor
    func hashNavigateWaitsForEvent() {
        let nav = MockNavigator()
        let root = makeRoot(mode: .hash, nav: nav)
        let h = render(root)
        #expect(h.allText.contains("home"))

        root.push("/about")
        h.renderer.scheduler.flush()
        #expect(nav.setHashCalls == ["/about"])
        #expect(h.allText.contains("home"),
                "no imperative update in hash mode — the browser event drives sync (the asymmetry #8 unifies)")

        nav.fireChange() // the browser's half; mock.hash was updated by setHash
        h.renderer.scheduler.flush()
        #expect(h.allText.contains("about"))
    }

    @Test("history navigate is IMPERATIVE: pushState + immediate path update, no event")
    @MainActor
    func historyNavigateIsImperative() {
        let nav = MockNavigator()
        let root = makeRoot(mode: .history, nav: nav)
        let h = render(root)

        root.push("/about")
        h.renderer.scheduler.flush()
        #expect(nav.pushedURLs == ["/about"])
        #expect(h.allText.contains("about"), "history mode updates currentPath itself")
    }

    @Test("replace pins today's URL conventions: '#'+path in hash mode, bare path in history")
    @MainActor
    func replaceConventionsPinned() {
        let hashNav = MockNavigator()
        let hashRoot = makeRoot(mode: .hash, nav: hashNav)
        let h1 = render(hashRoot)
        hashRoot.replacePath("/about")
        h1.renderer.scheduler.flush()
        #expect(hashNav.replacedURLs == ["#/about"],
                "the drifted convention (push assigns bare hash, replace prefixes '#') — frozen here, fixed in #7")
        #expect(h1.allText.contains("about"), "replacePath updates currentPath imperatively in BOTH modes")

        let histNav = MockNavigator()
        let histRoot = makeRoot(mode: .history, nav: histNav)
        let h2 = render(histRoot)
        histRoot.replacePath("/about")
        h2.renderer.scheduler.flush()
        #expect(histNav.replacedURLs == ["/about"])
    }

    @Test("onAppear listens to the mode's event; unmount stops listening")
    @MainActor
    func lifecycleListenerWiring() {
        let hashNav = MockNavigator()
        let h1 = render(makeRoot(mode: .hash, nav: hashNav))
        #expect(hashNav.listeningTo == "hashchange")
        h1.unmount()
        #expect(hashNav.listeningTo == nil)
        #expect(hashNav.stopListeningCount == 1)

        let histNav = MockNavigator()
        let h2 = render(makeRoot(mode: .history, nav: histNav))
        #expect(histNav.listeningTo == "popstate")
        h2.unmount()
        #expect(histNav.stopListeningCount == 1)
    }
}
