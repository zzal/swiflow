// Tests/SwiflowRouterTests/RouterEnvironmentTests.swift
import Testing
import Swiflow
import SwiflowRouter
@testable import SwiflowTesting

/// Components that read @Environment(\.router) inside embed {} subtrees.
@Component
private final class RouterReader {
    @Environment(\.router) var router
    var body: VNode { p(router.path) }
}

@Component
private final class RouterHost {
    let injectedRouter: Router

    init(router: Router) { self.injectedRouter = router }

    var body: VNode {
        withEnvironment(\.router, injectedRouter) {
            embed { RouterReader() }
        }
    }
}

@Suite("Router @Environment propagation across embed {}")
struct RouterEnvironmentTests {

    @Test("@Environment(\\.router) inside embed {} reads the injected router path")
    @MainActor
    func readsInjectedRouterPath() {
        let customRouter = Router(
            path: "/dashboard",
            navigate: { _ in },
            replace: { _ in },
            back: {}
        )
        let h = render(RouterHost(router: customRouter))
        let node = h.find("p")
        #expect(node?.text == "/dashboard")
    }

    @Test("@Environment(\\.router) defaults to '/' when no RouterRoot is present")
    @MainActor
    func defaultsToRootPath() {
        let h = render(RouterReader())
        let node = h.find("p")
        #expect(node?.text == "/")
    }

    @Test("Different injected router path is read correctly")
    @MainActor
    func updatedRouterPathPropagates() {
        let h = render(RouterHost(router: Router(
            path: "/first",
            navigate: { _ in }, replace: { _ in }, back: {}
        )))
        #expect(h.find("p")?.text == "/first")
    }
}
