// Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift
import Testing
@testable import Swiflow

@Suite("EnvironmentValues")
struct EnvironmentValuesTests {

    @Test("default locale is en")
    func defaultLocale() {
        #expect(EnvironmentValues().locale == "en")
    }

    @Test("default colorScheme is light")
    func defaultColorScheme() {
        #expect(EnvironmentValues().colorScheme == .light)
    }

    @Test("custom key round-trips through subscript")
    func customKeyRoundTrip() {
        enum MyKey: EnvironmentKey { static let defaultValue = 42 }
        var env = EnvironmentValues()
        env[MyKey.self] = 99
        #expect(env[MyKey.self] == 99)
    }

    @Test("unset custom key returns defaultValue")
    func unsetKeyReturnsDefault() {
        enum MyKey: EnvironmentKey { static let defaultValue = "hello" }
        #expect(EnvironmentValues()[MyKey.self] == "hello")
    }

    @Test("merging overlays overridden keys and preserves others")
    func mergingOverlaysAndPreserves() {
        var base = EnvironmentValues()
        base.locale = "en"
        base.colorScheme = .light
        var overrides = EnvironmentValues()
        overrides.locale = "fr"
        let merged = base.merging(overrides)
        #expect(merged.locale == "fr")
        #expect(merged.colorScheme == .light)
    }

    @Test("later merging wins on conflicting keys")
    func mergingLeafWins() {
        var first = EnvironmentValues()
        first.locale = "en"
        var second = EnvironmentValues()
        second.locale = "de"
        var third = EnvironmentValues()
        third.locale = "fr"
        let merged = first.merging(second).merging(third)
        #expect(merged.locale == "fr")
    }
}
