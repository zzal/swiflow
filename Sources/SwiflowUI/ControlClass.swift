// Sources/SwiflowUI/ControlClass.swift
//
// Shared helpers for stateless skinned controls — Button, the form controls
// (TextField/Toggle/Select/RadioGroup), Card/Badge/Spinner. Every SwiflowUI
// control installs its stylesheet through `installControlSheet`; these helpers
// are the class-merge and keyed-embed plumbing those free functions share.
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

/// `embed` with an optional caller-supplied key. With a `key`, the component is
/// re-created with fresh init props whenever the key *changes* — the escape hatch the
/// overlay facades expose as `key:` for content that must update while the overlay is
/// mounted. Without one (the default), the instance is reused and its init props are
/// frozen at first mount (see each overlay's doc note). Keeps the `key != nil` branch in
/// one place so every facade behaves identically.
@MainActor
func embedKeyed<C: Component>(_ key: String?, contentKey: String? = nil,
                              _ factory: @escaping () -> C) -> VNode {
    if let key { return embed(key, contentKey: contentKey, factory) }
    return embed(contentKey: contentKey, factory)
}

/// `embedKeyed` with a `refresh:` prop-push — the overlays that thread their
/// display props LIVE into the reused instance (Alert/Prompt) route here. Same
/// plain-`var`-never-`@State` contract as `embed(_:refresh:)`.
@MainActor
func embedKeyed<C: Component>(_ key: String?, _ factory: @escaping () -> C,
                              refresh: @escaping (C) -> Void) -> VNode {
    if let key { return embed(key, factory, refresh: refresh) }
    return embed(factory, refresh: refresh)
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
