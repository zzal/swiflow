// Sources/SwiflowUI/ControlClass.swift
//
// Shared helpers for stateless skinned controls (Button now; Card/Badge/Spinner
// next). Stateful @Component controls (M4 TextField/Toggle/Select/RadioGroup)
// use the framework's `scopedStyles`/`CSSInjector` seam instead and do NOT use
// these.
import Swiflow

/// Splits caller-supplied attributes into (their `class` values, everything
/// else) so a skinned control can MERGE its own classes with the caller's
/// rather than be clobbered.
///
/// `applyAttributes` is last-write-wins per attribute key, so a caller
/// `.class("mine")` would otherwise wipe a control's `sw-btn …` skin classes.
/// Skinned controls call this, prepend their own classes to `classes`, and apply
/// `rest` last so the caller still wins on every *other* attribute (e.g.
/// overriding `type`). Recurses into `.compound` (the framework's composite
/// modifier) so a class nested there is merged too rather than flattened last;
/// empty class strings are dropped so the result never gains a stray separator.
func splitClasses(_ attributes: [Attribute]) -> (classes: [String], rest: [Attribute]) {
    var classes: [String] = []
    var rest: [Attribute] = []
    for attribute in attributes {
        switch attribute {
        case let .attribute(name, value) where name == "class":
            if !value.isEmpty { classes.append(value) }
        case let .compound(inner):
            let (innerClasses, innerRest) = splitClasses(inner)
            classes.append(contentsOf: innerClasses)
            if !innerRest.isEmpty { rest.append(.compound(innerRest)) }
        default:
            rest.append(attribute)
        }
    }
    return (classes, rest)
}

/// Injects a stateless control's global utility-class sheet into `<head>` exactly
/// once (per the `StyleInjectionRegistry` once-guard). `scopeClass: ""` because
/// these `.sw-*` classes are deliberately unscoped — SwiflowUI reserves the
/// `sw-` class prefix; apps must not author CSS under it. The one styling seam
/// every stateless skinned control shares.
@MainActor
func installControlSheet(id: String, _ sheet: CSSSheet) {
    StyleInjectionRegistry.injectOnce(id: id) { sheet.cssString(scopeClass: "") }
}
