import Testing
@testable import SwiflowRouter
import Swiflow

@Suite("Router + EnvironmentValues")
struct RouterTests {

    @Test("default Router path is /")
    func defaultRouterPath() {
        let env = EnvironmentValues()
        #expect(env.router.path == "/")
    }

    @Test("default Router navigate is a no-op")
    func defaultNavigateIsNoOp() {
        let env = EnvironmentValues()
        // Should not crash
        env.router.navigate("/test")
    }

    @Test("default Router replace is a no-op")
    func defaultReplaceIsNoOp() {
        let env = EnvironmentValues()
        env.router.replace("/test")
    }

    @Test("default Router back is a no-op")
    func defaultBackIsNoOp() {
        let env = EnvironmentValues()
        env.router.back()
    }

    @Test("EnvironmentValues router can be overridden")
    func routerCanBeOverridden() {
        var env = EnvironmentValues()
        let customRouter = Router(path: "/custom", navigate: { _ in }, replace: { _ in }, back: {})
        env.router = customRouter
        #expect(env.router.path == "/custom")
    }
}
