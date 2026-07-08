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

// (The readPath truth table moved to RouterModeBehaviorTests — the read
// logic lives on RouterMode since audit IV Wave-2 #7.)

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
        #expect(nav.setHashCalls == ["#/about"],
                "push writes mode.url(for:) — the same canonical '#'-prefixed form as href and replace (the #7 convention fix)")
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
                "replace writes mode.url(for:) — one canonical construction shared with push and href")
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

// MARK: - Full stack: the environment Router's closures reach the navigator

@MainActor
private final class RouterBox {
    var value: Router?
}

@Component
private final class RouterGrabber {
    @Environment(\.router) var router
    let box: RouterBox
    init(box: RouterBox) { self.box = box }
    var body: VNode {
        // The documented capture-in-body ritual: @Environment is only live
        // during body, so the test (like any handler) uses the captured value.
        box.value = router
        return p(router.path)
    }
}

@Suite("RouterRoot full lifecycle headless")
struct RouterRootFullStackTests {

    @Test("navigate via the environment Router; external event re-renders; back reaches the navigator")
    @MainActor
    func fullStackThroughEnvironmentRouter() {
        let nav = MockNavigator()
        let box = RouterBox()
        let root = RouterRoot(mode: .hash, navigator: nav, routes: {
            RouteDefinition(pattern: RoutePattern("/"), factory: { _ in
                embed { RouterGrabber(box: box) }
            })
            RouteDefinition(pattern: RoutePattern("/about"), factory: { _ in .text("about-page") })
        }, notFound: nil)
        let h = render(root)
        #expect(h.find("p")?.text == "/")

        // The REAL body-built closure: @Sendable navigate → weak self →
        // push → navigator.setHash. Then the browser's half, scripted.
        box.value?.navigate("/about")
        nav.fireChange()
        h.renderer.scheduler.flush()
        #expect(h.allText.contains("about-page"))

        box.value?.back()
        #expect(nav.backCount == 1, "body's back closure reaches the navigator, not JS globals")
    }
}
