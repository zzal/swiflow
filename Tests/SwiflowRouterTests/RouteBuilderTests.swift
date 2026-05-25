// Tests/SwiflowRouterTests/RouteBuilderTests.swift
import Testing
import Swiflow
@testable import SwiflowRouter

/// Probe component used only as a route factory — it doesn't matter what
/// it renders for these tests, we only assert on the route tree's shape.
@MainActor private final class ProbePage: Component {
    var body: VNode { .text("probe") }
}

@Suite("RouteBuilder")
struct RouteBuilderTests {

    @Test("if condition { Route(...) } includes the route when condition is true")
    @MainActor
    func ifTrueIncludesRoute() {
        let routes: [RouteDefinition] = RouteBuilder.buildBlock(
            RouteBuilder.buildExpression(Route("/a") { ProbePage() }),
            RouteBuilder.buildOptional(
                RouteBuilder.buildExpression(Route("/b") { ProbePage() })
            )
        )
        #expect(routes.map { $0.pattern.original } == ["/a", "/b"])
    }

    @Test("if condition { Route(...) } omits the route when condition is false")
    @MainActor
    func ifFalseOmitsRoute() {
        let routes: [RouteDefinition] = RouteBuilder.buildBlock(
            RouteBuilder.buildExpression(Route("/a") { ProbePage() }),
            RouteBuilder.buildOptional(nil)
        )
        #expect(routes.map { $0.pattern.original } == ["/a"])
    }

    @Test("if/else routes pick the first branch")
    @MainActor
    func ifElseFirstBranch() {
        let routes: [RouteDefinition] = RouteBuilder.buildBlock(
            RouteBuilder.buildEither(first:
                RouteBuilder.buildExpression(Route("/first") { ProbePage() })
            )
        )
        #expect(routes.map { $0.pattern.original } == ["/first"])
    }

    @Test("if/else routes pick the second branch")
    @MainActor
    func ifElseSecondBranch() {
        let routes: [RouteDefinition] = RouteBuilder.buildBlock(
            RouteBuilder.buildEither(second:
                RouteBuilder.buildExpression(Route("/second") { ProbePage() })
            )
        )
        #expect(routes.map { $0.pattern.original } == ["/second"])
    }

    @Test("for-loop routes are flattened into the parent block")
    @MainActor
    func forLoopFlattensRoutes() {
        let segments = ["/a", "/b", "/c"]
        let routes: [RouteDefinition] = RouteBuilder.buildBlock(
            RouteBuilder.buildArray(segments.map { path in
                RouteBuilder.buildExpression(Route(path) { ProbePage() })
            })
        )
        #expect(routes.map { $0.pattern.original } == ["/a", "/b", "/c"])
    }
}
