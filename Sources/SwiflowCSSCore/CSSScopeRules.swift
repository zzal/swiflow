// Sources/SwiflowCSSCore/CSSScopeRules.swift
//
// The single source of truth for which CSS selectors escape component scoping.
// Shared by BOTH scope-deciding paths so they can never drift:
//   - the runtime CSS DSL (`Swiflow.CSSSheet.scopedSelector`, wasm)
//   - the compile-time `#css` parser (`SwiflowMacrosPlugin.CSSStructuralParser`)
//
// This is a zero-dependency leaf module (plain String work) so it compiles for
// both the wasm runtime and the host compiler plugin. If it ever grows a
// dependency, the macro plugin's host build will break loudly — keep it pure.

public enum CSSScopeRules {
    /// `true` when a selector (or block prelude) targets the document root and
    /// so must NOT be rewritten under the component's scope class — `:root`,
    /// `html`, and `body` rules are emitted verbatim/hoisted. Everything else
    /// is scoped to the component.
    ///
    /// Owns the case-folding so no caller can forget it.
    public static func escapesComponentScoping(_ selector: String) -> Bool {
        let lower = selector.lowercased()
        return lower.hasPrefix(":root") || lower.hasPrefix("html") || lower.hasPrefix("body")
    }
}
