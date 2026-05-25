// Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift
import Testing
@testable import Swiflow

// MARK: - Shared helpers (used by E3 and E4 tests)

@MainActor private final class DeepEnvReader: Component {
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    var capturedLocale: String = ""
    var capturedScheme: ColorScheme = .light

    var body: VNode {
        capturedLocale = locale
        capturedScheme = colorScheme
        let schemeStr = colorScheme == .dark ? "dark" : "light"
        return p("locale=\(locale) colorScheme=\(schemeStr)")
    }
}

@MainActor
@Suite("Environment threading through diff")
struct EnvironmentThreadingTests {

    final class LocaleReader: Component {
        @Environment(\.locale) var locale
        var capturedLocale: String = ""
        var body: VNode {
            capturedLocale = locale
            return .text(locale)
        }
    }

    @Test("component reads default locale when no override")
    func defaultLocale() {
        let reader = LocaleReader()
        let desc = ComponentDescription(LocaleReader.self, key: nil) { reader }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(.component(desc), into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedLocale == "en")
    }

    @Test("environmentOverride node sets locale for wrapped component")
    func overrideReachesComponent() {
        let reader = LocaleReader()
        let desc = ComponentDescription(LocaleReader.self, key: nil) { reader }
        var overrides = EnvironmentValues()
        overrides.locale = "fr"
        let vnode = VNode.environmentOverride(overrides, .component(desc))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedLocale == "fr")
    }

    @Test("sibling outside override reads default locale")
    func siblingOutsideOverrideReadsDefault() {
        let readerA = LocaleReader()
        let readerB = LocaleReader()
        let descA = ComponentDescription(LocaleReader.self, key: "a") { readerA }
        let descB = ComponentDescription(LocaleReader.self, key: "b") { readerB }
        var overrides = EnvironmentValues()
        overrides.locale = "ja"
        let vnode = VNode.element(ElementData(
            tag: "div",
            children: [
                .environmentOverride(overrides, .component(descA)),
                .component(descB)
            ]
        ))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(readerA.capturedLocale == "ja")
        #expect(readerB.capturedLocale == "en")
    }

    @Test("nested overrides merge correctly")
    func nestedOverridesMerge() {
        final class SchemeReader: Component {
            @Environment(\.colorScheme) var colorScheme
            var capturedScheme: ColorScheme = .light
            var body: VNode {
                capturedScheme = colorScheme
                return .text("")
            }
        }
        let reader = SchemeReader()
        let desc = ComponentDescription(SchemeReader.self, key: nil) { reader }
        var outer = EnvironmentValues()
        outer.locale = "de"
        var inner = EnvironmentValues()
        inner.colorScheme = .dark
        let vnode = VNode.environmentOverride(outer, .environmentOverride(inner, .component(desc)))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedScheme == .dark)
    }

    @Test("withEnvironment threads correctly through 6 levels of nesting with alternating keys")
    func deepNestingAlternatingKeys() {
        // Six levels deep, alternating locale and colorScheme overrides at each level.
        // The innermost reader should see the values set by the closest enclosing
        // withEnvironment for each key, regardless of depth.
        let reader = DeepEnvReader()
        let desc = ComponentDescription(DeepEnvReader.self, key: nil) { reader }

        // Build the 6-level override chain manually using EnvironmentValues,
        // mirroring the withEnvironment nesting pattern:
        //   L1: locale="L1"  L2: colorScheme=.dark  L3: locale="L3"
        //   L4: colorScheme=.light  L5: locale="L5"  L6: colorScheme=.dark
        var l1 = EnvironmentValues(); l1.locale = "L1"
        var l2 = EnvironmentValues(); l2.colorScheme = .dark
        var l3 = EnvironmentValues(); l3.locale = "L3"
        var l4 = EnvironmentValues(); l4.colorScheme = .light
        var l5 = EnvironmentValues(); l5.locale = "L5"
        var l6 = EnvironmentValues(); l6.colorScheme = .dark

        let vnode = VNode.environmentOverride(l1,
            .environmentOverride(l2,
                .environmentOverride(l3,
                    .environmentOverride(l4,
                        .environmentOverride(l5,
                            .environmentOverride(l6,
                                .component(desc)))))))

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)

        // Innermost overrides win for both keys.
        #expect(reader.capturedLocale == "L5")
        #expect(reader.capturedScheme == .dark)
    }
}
