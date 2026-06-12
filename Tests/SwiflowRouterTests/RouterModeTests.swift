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
