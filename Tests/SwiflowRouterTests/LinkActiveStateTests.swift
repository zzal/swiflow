// Tests/SwiflowRouterTests/LinkActiveStateTests.swift
//
// Audit IV Wave-1 #2: Link never compared its destination against the
// ambient router's path, so both example nav bars were dead-flat — no
// "you are here", no styling hook, no a11y signal. An active Link now
// emits `aria-current="page"` (the web's standard current-page marker,
// stylable as `a[aria-current="page"]`) plus a stable `.sw-link-active`
// class, with an exact-vs-prefix matching option.
import Testing
import Swiflow
import SwiflowRouter
@testable import SwiflowTesting

// MARK: - Pure matcher rules

@Suite("LinkActiveMatch — pure path matching")
struct LinkActiveMatchTests {

    @Test("exact: equal paths match, everything else doesn't")
    func exactRules() {
        #expect(LinkActiveMatch.exact.isActive(linkPath: "/users", currentPath: "/users"))
        #expect(!LinkActiveMatch.exact.isActive(linkPath: "/users", currentPath: "/users/42"))
        #expect(!LinkActiveMatch.exact.isActive(linkPath: "/users", currentPath: "/"))
    }

    @Test("prefix: matches itself and segment children")
    func prefixMatchesChildren() {
        #expect(LinkActiveMatch.prefix.isActive(linkPath: "/users", currentPath: "/users"))
        #expect(LinkActiveMatch.prefix.isActive(linkPath: "/users", currentPath: "/users/42"))
        #expect(LinkActiveMatch.prefix.isActive(linkPath: "/users", currentPath: "/users/42/posts"))
    }

    @Test("prefix is segment-aware — a lexical prefix that crosses a segment does NOT match")
    func prefixRespectsSegmentBoundaries() {
        #expect(!LinkActiveMatch.prefix.isActive(linkPath: "/users", currentPath: "/users2"))
        #expect(!LinkActiveMatch.prefix.isActive(linkPath: "/u", currentPath: "/users"))
    }

    @Test("prefix on the root path matches only the root — never the whole app")
    func prefixOnRootStaysExact() {
        #expect(LinkActiveMatch.prefix.isActive(linkPath: "/", currentPath: "/"))
        #expect(!LinkActiveMatch.prefix.isActive(linkPath: "/", currentPath: "/about"),
                "a Home link marked .prefix must not light up on every page")
    }
}

// MARK: - Rendered attributes

@Component
private final class NavHost {
    let injectedRouter: Router
    let activeMatch: LinkActiveMatch

    init(router: Router, match: LinkActiveMatch = .exact) {
        self.injectedRouter = router
        self.activeMatch = match
    }

    var body: VNode {
        withEnvironment(\.router, injectedRouter) {
            embed { Link("/users", "Users", active: self.activeMatch) }
        }
    }
}

private func router(path: String) -> Router {
    Router(path: path, navigate: { _ in }, replace: { _ in }, back: {})
}

@Suite("Link active state — rendered attributes")
struct LinkActiveStateTests {

    @Test("the current page's Link carries aria-current=page and the styling class")
    @MainActor
    func activeLinkMarks() {
        let h = render(NavHost(router: router(path: "/users")))
        let a = h.find("a")
        #expect(a?.attributes["aria-current"] == "page")
        // The class MERGES with the framework's component-scope class
        // (`swiflow-Link`) rather than clobbering it.
        #expect(a?.attributes["class"]?.split(separator: " ").contains("sw-link-active") == true)
        #expect(a?.attributes["href"] == "#/users", "the active marking must not disturb the href")
    }

    @Test("a Link to another page carries neither marker")
    @MainActor
    func inactiveLinkStaysClean() throws {
        let h = render(NavHost(router: router(path: "/about")))
        let a = try #require(h.find("a"))
        #expect(a.attributes["aria-current"] == nil)
        // The framework's scope class remains; only the active marker must
        // be absent.
        #expect(a.attributes["class"]?.split(separator: " ").contains("sw-link-active") != true)
    }

    @Test("prefix matching lights the section link up on a child route")
    @MainActor
    func prefixActivatesOnChildRoute() {
        let h = render(NavHost(router: router(path: "/users/42"), match: .prefix))
        #expect(h.find("a")?.attributes["aria-current"] == "page")
    }

    @Test("default matching is exact — a child route does not activate the link")
    @MainActor
    func defaultIsExact() {
        let h = render(NavHost(router: router(path: "/users/42")))
        #expect(h.find("a")?.attributes["aria-current"] == nil)
    }
}
