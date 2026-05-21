// Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift
import Testing
@testable import Swiflow

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
}
