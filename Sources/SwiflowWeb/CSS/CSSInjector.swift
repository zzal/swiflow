// Sources/SwiflowWeb/CSS/CSSInjector.swift
//
// Injects component-scoped <style> elements into the document <head>
// the first time each Component type is mounted. The injected CSS uses
// the component's `scopedStyles` sheet (if any), scoped to the class
// name "swiflow-<TypeName>" that Diff.swift adds to each component's
// body root element.

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

@MainActor
enum CSSInjector {
    private static var injected: Set<ObjectIdentifier> = []

    /// Wires `onComponentTypeMount` so that every new Component type
    /// that mounts gets its scoped styles injected into <head>.
    static func setup() {
        onComponentTypeMount = { componentType in
            CSSInjector.inject(for: componentType)
        }
    }

    /// Injects a <style> tag for `componentType` if one hasn't been
    /// injected yet and the type declares non-empty `scopedStyles`.
    static func inject(for componentType: any Component.Type) {
        let id = ObjectIdentifier(componentType)
        guard !injected.contains(id) else { return }
        injected.insert(id)

        guard let sheet = componentType.scopedStyles else { return }
        let typeName = String(describing: componentType)
        let scopeClass = "swiflow-\(typeName)"
        let css = sheet.cssString(scopeClass: scopeClass)
        guard !css.isEmpty else { return }

        let styleId = scopeClass
        // JSObject.global.document is a JSValue; property access via dynamic
        // member lookup on JSValue returns JSValue. Method calls on JSValue
        // use the typed subscript overloads which return non-optional
        // closures — no `!` needed. For JSObject properties (like .appendChild
        // on the result of .object!), the subscript is optional, requiring `!`.
        let document = JSObject.global.document

        // Skip if a <style> with this id already exists (e.g. HMR swap).
        let existing = document.getElementById(styleId)
        guard existing == .undefined || existing == .null else { return }

        let style = document.createElement("style").object!
        style.id = .string(styleId)
        style.textContent = .string(css)
        _ = document.head.object!.appendChild!(style)
    }

    /// Clears the injected-set so styles are re-injected on the next
    /// mount cycle. Used by tests and HMR reloads.
    static func reset() {
        injected = []
    }
}
#endif
