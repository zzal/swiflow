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
    /// Wires the registry's emit sink to a real `<head>` `<style>` append, then
    /// installs the component-mount hook that injects each type's scoped sheet.
    static func setup() {
        StyleInjectionRegistry.emit = { id, css in
            appendStyle(id: id, css: css)
        }
        onComponentTypeMount = { componentType in
            CSSInjector.inject(for: componentType)
        }
    }

    /// Injects a `<style>` for `componentType` if it declares non-empty
    /// `scopedStyles`. De-duplication is owned by `StyleInjectionRegistry`.
    static func inject(for componentType: any Component.Type) {
        guard let sheet = componentType.scopedStyles else { return }
        let typeName = String(describing: componentType)
        let scopeClass = "swiflow-\(typeName)"
        StyleInjectionRegistry.injectOnce(id: scopeClass) {
            sheet.cssString(scopeClass: scopeClass)
        }
    }

    /// Appends a `<style id=...>` to `<head>` carrying `css`. Skips when a
    /// `<style>` with that id already exists in the document (e.g. an HMR swap
    /// re-running setup) or when `css` is empty.
    private static func appendStyle(id: String, css: String) {
        guard !css.isEmpty else { return }
        // JSObject.global.document is a JSValue; property access via dynamic
        // member lookup on JSValue returns JSValue. Method calls on JSValue
        // use the typed subscript overloads which return non-optional
        // closures — no `!` needed. For JSObject properties (like .appendChild
        // on the result of .object!), the subscript is optional, requiring `!`.
        let document = JSObject.global.document

        // Skip if a <style> with this id already exists (e.g. HMR swap).
        let existing = document.getElementById(id)
        guard existing == .undefined || existing == .null else { return }

        let style = document.createElement("style").object!
        style.id = .string(id)
        style.textContent = .string(css)
        _ = document.head.object!.appendChild!(style)
    }

    /// Clears the registry guard so styles re-inject on the next mount. Tests/HMR.
    static func reset() { StyleInjectionRegistry.reset() }
}
#endif
