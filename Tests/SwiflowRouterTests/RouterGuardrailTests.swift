// Tests/SwiflowRouterTests/RouterGuardrailTests.swift
//
// Audit IV Wave-3: router DEBUG guardrails — three silent-misuse shapes now
// warn via swiflowWarn (never trap; the router's warn-first stance from
// PR #174): an empty `:` param segment, sibling routes that shadow each
// other (matchList is first-wins), and navigation that matches no route.
import Testing
import Swiflow
@testable import SwiflowRouter
@testable import SwiflowTesting

@MainActor
private func captureWarnings(_ body: () -> Void) -> [String] {
    var captured: [String] = []
    let prior = _swiflowWarnOverride
    _swiflowWarnOverride = { captured.append($0) }
    defer { _swiflowWarnOverride = prior }
    body()
    return captured
}

@Suite("Empty :param segment warns")
struct EmptyParamGuardrailTests {

    @Test("Route(\"/users/:\") warns naming the pattern")
    @MainActor
    func emptyParamWarns() {
        let warnings = captureWarnings { _ = RoutePattern("/users/:") }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("/users/:"), "names the offending pattern")
        #expect((warnings.first ?? "").contains("empty"), "says what's wrong")
    }

    @Test("well-formed patterns stay silent")
    @MainActor
    func wellFormedSilent() {
        let warnings = captureWarnings {
            _ = RoutePattern("/")
            _ = RoutePattern("/users/:id")
            _ = RoutePattern("/files/*")
        }
        #expect(warnings.isEmpty)
    }
}

@Suite("Shadowed sibling routes warn")
struct RouteTableHazardTests {

    @MainActor
    private func routes(@RouteBuilder _ build: () -> [RouteDefinition]) -> [RouteDefinition] {
        build()
    }

    @Test("an exact duplicate sibling warns — first match wins, the second never matches")
    @MainActor
    func exactDuplicateWarns() {
        let table = routes {
            Route("/page") { PageA() }
            Route("/page") { PageB() }
        }
        let warnings = captureWarnings { warnRouteTableHazards(table) }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("/page"))
        #expect((warnings.first ?? "").contains("never match"))
    }

    @Test("params shadow by SHAPE — /users/:id vs /users/:slug collide despite the names")
    @MainActor
    func paramShapeShadows() {
        let table = routes {
            Route("/users/:id") { _ in PageA() }
            Route("/users/:slug") { _ in PageB() }
        }
        let warnings = captureWarnings { warnRouteTableHazards(table) }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("/users/:slug"), "names the unreachable route")
        #expect((warnings.first ?? "").contains("/users/:id"), "names the earlier sibling that wins")
    }

    @Test("a catch-all before other siblings warns — everything after is unreachable")
    @MainActor
    func catchAllNotLastWarns() {
        let table = routes {
            Route("*") { PageA() }
            Route("/about") { PageB() }
        }
        let warnings = captureWarnings { warnRouteTableHazards(table) }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("catch-all"))
    }

    @Test("nested children are scanned too")
    @MainActor
    func nestedChildrenScanned() {
        let table = routes {
            Route("/users") {
                Route("/:id") { _ in PageA() }
                Route("/:slug") { _ in PageB() }
            }
        }
        let warnings = captureWarnings { warnRouteTableHazards(table) }
        #expect(warnings.count == 1)
    }

    @Test("a healthy table stays silent — distinct routes, catch-all last")
    @MainActor
    func healthyTableSilent() {
        let table = routes {
            Route("/") { PageA() }
            Route("/users/:id") { _ in PageB() }
            Route("*") { PageA() }
        }
        let warnings = captureWarnings { warnRouteTableHazards(table) }
        #expect(warnings.isEmpty)
    }
}

@Suite("Unmatched navigation warns once per path")
struct UnmatchedPathGuardrailTests {

    @Test("an unmatched path warns once, not on every re-render; a new unmatched path warns again")
    @MainActor
    func unmatchedWarnsOncePerPath() {
        let nav = MockNavigator()
        nav.hash = "#/tpyo"   // typo'd deep link
        let root = RouterRoot(mode: .hash, navigator: nav, routes: {
            RouteDefinition(pattern: RoutePattern("/"), factory: { _ in .text("home") })
        }, notFound: nil)

        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }

        let h = render(root)
        #expect(captured.count == 1)
        #expect((captured.first ?? "").contains("/tpyo"), "names the unmatched path")

        root.push("/tpyo2")   // another unmatched path
        h.renderer.scheduler.flush()
        #expect(captured.count == 2, "a DIFFERENT unmatched path warns again")

        root.push("/")        // matched — silent
        h.renderer.scheduler.flush()
        #expect(captured.count == 2)
    }
}

// MARK: - Trivial page components for the tables above

@Component
private final class PageA { var body: VNode { .text("a") } }

@Component
private final class PageB { var body: VNode { .text("b") } }
