// Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift
import Testing
@testable import Swiflow

@Suite("withEnvironment DSL")
struct EnvironmentDSLTests {

    @Test("withEnvironment produces an environmentOverride VNode")
    func producesEnvironmentOverride() {
        let vnode = withEnvironment(\.locale, "fr") { VNode.text("hello") }
        guard case let .environmentOverride(env, child) = vnode else {
            Issue.record("Expected .environmentOverride, got \(vnode)")
            return
        }
        #expect(env.locale == "fr")
        if case .text(let t) = child {
            #expect(t == "hello")
        } else {
            Issue.record("Expected .text child, got \(child)")
        }
    }

    @Test("nested withEnvironment produces two-level override chain")
    func nestedWithEnvironment() {
        let inner = withEnvironment(\.colorScheme, .dark) { VNode.text("x") }
        let outer = withEnvironment(\.locale, "ja") { inner }
        guard case let .environmentOverride(outerEnv, outerChild) = outer else {
            Issue.record("Expected outer .environmentOverride")
            return
        }
        #expect(outerEnv.locale == "ja")
        guard case let .environmentOverride(innerEnv, _) = outerChild else {
            Issue.record("Expected inner .environmentOverride")
            return
        }
        #expect(innerEnv.colorScheme == .dark)
    }
}
