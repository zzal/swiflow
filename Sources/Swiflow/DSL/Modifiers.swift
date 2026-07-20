// Sources/Swiflow/DSL/Modifiers.swift

/// A single modifier passed to an element factory (e.g. `div(.class("row"))`).
/// Each case maps directly to one of `ElementData`'s bags.
#if DEBUG
/// DEBUG seam: installed by SwiflowUI to validate `--sw-*`
/// token references inside stringly `.style` VALUES against its typed
/// vocabulary — a `var(--sw-surfce)` typo otherwise fails SILENT in CSS.
/// Core stays vocabulary-agnostic; nil (the default) = no validation.
/// Same single-threaded seam discipline as `_swiflowWarnOverride`.
nonisolated(unsafe) public var _swiflowStyleValueValidator: ((String) -> Void)?
#endif

public enum Attribute {
    /// An HTML attribute (`setAttribute`).
    case attribute(name: String, value: String)
    /// A DOM property (typed; assigned directly on the node).
    case property(name: String, value: PropertyValue)
    /// An inline-style declaration.
    case style(name: String, value: String)
    /// An event-listener registration.
    case handler(event: String, value: EventHandler)
    /// A stable identity used by the keyed children diff.
    case key(String)
    /// Internal sentinel produced by overloads that need to *omit* an
    /// attribute given a runtime condition (e.g. `attr(_:_:Bool)` with
    /// `false`). `applyAttributes` drops these during the fold; they
    /// never reach `ElementData`. Not for general use.
    case skip
    /// Composite of multiple attribute effects produced by a single modifier
    /// (e.g. `.value($text)` writes both a `value` property AND an `.input`
    /// handler). `applyAttributes` recursively flattens these during the
    /// fold; composites never reach `ElementData`.
    case compound([Attribute])
    /// Binds the host element's DOM-side handle into a `Ref<Element>` at
    /// mount time and clears it at destroy. Stored on
    /// `ElementData.refBindings` and consumed out-of-band by Diff; never
    /// folded into the four normal bags. Produced by the `.ref(_:)`
    /// modifier in SwiflowDOM.
    case refBinding(AnyRefBinding)

    // Convenience factories.

    /// Shorthand for `.attribute(name:value:)`.
    public static func attr(_ name: String, _ value: String) -> Attribute {
        .attribute(name: name, value: value)
    }

    /// Sets an HTML attribute with an `Int` value (stringified).
    public static func attr(_ name: String, _ value: Int) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Sets an HTML attribute with a `Double` value (stringified).
    public static func attr(_ name: String, _ value: Double) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Sets an HTML boolean attribute. HTML boolean attributes are
    /// presence-or-absent (`disabled`, `checked`, `readonly`). Emits a
    /// presence-only attribute (empty-string value) when `value` is
    /// `true`; omits the attribute entirely when `value` is `false`.
    /// Matches HTML semantics — no call-site gating required.
    public static func attr(_ name: String, _ value: Bool) -> Attribute {
        value ? .attribute(name: name, value: "") : .skip
    }

    /// Convenience for `data-*` attributes. `.data("user-id", "42")` emits
    /// `data-user-id="42"`.
    public static func data(_ name: String, _ value: String) -> Attribute {
        .attribute(name: "data-\(name)", value: value)
    }

    /// Sets the `class` attribute. Backticks because `class` is a Swift
    /// keyword.
    public static func `class`(_ value: String) -> Attribute {
        .attribute(name: "class", value: value)
    }

    /// Sets the `id` attribute.
    public static func id(_ value: String) -> Attribute {
        .attribute(name: "id", value: value)
    }

    // MARK: - Typed attribute helpers
    //
    // Named factories for the handful of attributes every app reaches for,
    // where the stringly `.attr("href", …)` form makes a typo a silent no-op.
    // Additive: `.attr(_:_:)` remains the long-tail escape hatch for anything
    // not covered here.

    /// Sets `href` (anchors, `<link>`). Pair with `.newTab()` for external links.
    public static func href(_ value: String) -> Attribute {
        .attribute(name: "href", value: value)
    }

    /// Sets `target` (e.g. `"_blank"`, `"_self"`). For external links prefer
    /// `.newTab()`, which also sets the `rel` guard.
    public static func target(_ value: String) -> Attribute {
        .attribute(name: "target", value: value)
    }

    /// Sets `rel` (e.g. `"noopener noreferrer"`, `"stylesheet"`).
    public static func rel(_ value: String) -> Attribute {
        .attribute(name: "rel", value: value)
    }

    /// Opens the link in a new tab **safely**: emits `target="_blank"` together
    /// with `rel="noopener noreferrer"`, so the opened page can't reach back
    /// through `window.opener` (reverse tabnabbing) or read the referrer. Use
    /// this instead of a bare `.target("_blank")` for any external link.
    public static func newTab() -> Attribute {
        .compound([
            .attribute(name: "target", value: "_blank"),
            .attribute(name: "rel", value: "noopener noreferrer"),
        ])
    }

    /// Sets `src` (`<img>`, `<script>`, `<source>`, …).
    public static func src(_ value: String) -> Attribute {
        .attribute(name: "src", value: value)
    }

    /// Sets `alt` — the text alternative for an `<img>`. Pass `""` for a purely
    /// decorative image (which correctly hides it from assistive tech).
    public static func alt(_ value: String) -> Attribute {
        .attribute(name: "alt", value: value)
    }

    /// Sets the intrinsic `width` **attribute** (in CSS pixels) — e.g. on
    /// `<img>`/`<canvas>`. Reserves layout space to avoid content shift; this is
    /// the HTML attribute, not a CSS `width` (use `.style("width", …)` for CSS).
    public static func width(_ value: Int) -> Attribute {
        .attribute(name: "width", value: String(value))
    }

    /// Sets the intrinsic `height` **attribute** (in CSS pixels). See `.width(_:)`.
    public static func height(_ value: Int) -> Attribute {
        .attribute(name: "height", value: String(value))
    }

    /// Sets `placeholder` (`<input>`, `<textarea>`).
    public static func placeholder(_ value: String) -> Attribute {
        .attribute(name: "placeholder", value: value)
    }

    /// Sets the `<input>` `type` from the typed `InputType`, e.g. `.type(.email)`.
    public static func type(_ value: InputType) -> Attribute {
        .attribute(name: "type", value: value.htmlValue)
    }

    /// Sets the `name` attribute (form controls; radio-group membership).
    public static func name(_ value: String) -> Attribute {
        .attribute(name: "name", value: value)
    }

    /// Sets a `<label>`'s `for` attribute, associating it with the control whose
    /// `id` matches. Backticked because `for` is a Swift keyword.
    public static func `for`(_ value: String) -> Attribute {
        .attribute(name: "for", value: value)
    }

    /// Sets the `title` attribute (native tooltip / accessible name of last resort).
    public static func title(_ value: String) -> Attribute {
        .attribute(name: "title", value: value)
    }

    /// Shorthand for `.property(name:value:)`.
    public static func prop(_ name: String, _ value: PropertyValue) -> Attribute {
        .property(name: name, value: value)
    }

    /// Shorthand for `.style(name:value:)`.
    public static func style(_ name: String, _ value: String) -> Attribute {
        #if DEBUG
        _swiflowStyleValueValidator?(value)
        #endif
        return .style(name: name, value: value)
    }

    public static func transition(_ value: String) -> Attribute {
        .style(name: "transition", value: value)
    }

    public static func animation(_ value: String) -> Attribute {
        .style(name: "animation", value: value)
    }

    public static func cssVar(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }

    // No explicit `static func key(_:)` is needed — `case key(String)`
    // auto-synthesizes a constructor with the same call-site syntax
    // (`Attribute.key("k1")`). Declaring one explicitly is a redeclaration
    // error.
}

/// Applies a single `Attribute` (recursively flattening `.compound`) onto an
/// already-built `ElementData`'s bags. Shared by `applyAttributes` below
/// (initial element construction, folding a whole `[Attribute]` list) and the
/// VNode postfix modifiers in `VNodeModifiers.swift`/`EventModifiers.swift`
/// (mutating one bag on an already-mounted-shape element) so the two paths
/// can't drift on what a given `Attribute` case does.
func applyAttribute(_ attribute: Attribute, to data: inout ElementData) {
    switch attribute {
    case .attribute(let name, let value):
        // URL-bearing attributes (href, src, action, formaction) route
        // through URLSanitizer before reaching the bag (case-insensitive
        // on the name); non-URL attributes pass through. A rejected URL
        // returns nil and the attribute is dropped — see
        // URLSanitizer.resolvedAttributeValue.
        if let resolved = URLSanitizer.resolvedAttributeValue(name: name, value: value) {
            data.attributes[name] = resolved
        }
    case .property(let name, let value):
        data.properties[name] = value
    case .style(let name, let value):
        data.style[name] = value
    case .handler(let event, let value):
        data.handlers[event] = value
    case .key(let value):
        data.key = value
    case .skip:
        return
    case .compound(let inner):
        for child in inner { applyAttribute(child, to: &data) }
    case .refBinding(let binding):
        // Refs are stashed on ElementData out-of-band — they don't
        // belong in any of the four bags and never become patches.
        // Diff.mount/destroy consume them directly via
        // `data.refBindings`.
        data.refBindings.append(binding)
    }
}

/// Folds a list of `Attribute`s into the four bags + key of an `ElementData`.
/// Later attributes of the same key override earlier ones — this matches the
/// "last write wins" intuition of standard DOM property assignment.
func applyAttributes(
    tag: String,
    _ attributes: [Attribute],
    children: [VNode] = []
) -> ElementData {
    var data = ElementData(tag: tag, children: children)
    for attribute in attributes {
        applyAttribute(attribute, to: &data)
    }
    return data
}
