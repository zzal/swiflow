// Sources/Swiflow/DSL/VNodeModifiers.swift

/// Returns a new VNode with a mutation applied to its `ElementData`.
/// Non-element VNodes (`.text`, `.component`, `.rawHTML`) trigger a diagnostic
/// in DEBUG and pass through unchanged. Internal (not `private`) so
/// `EventModifiers.swift`'s postfix binding modifiers share the same
/// non-element guard instead of re-implementing it.
func mergeAttribute(_ vnode: VNode, _ apply: (inout ElementData) -> Void) -> VNode {
    if case .element(var data) = vnode {
        apply(&data)
        return .element(data)
    }
    swiflowDiagnostic("Postfix VNode modifier applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
    return vnode
}

public extension VNode {
    /// Adds (or overwrites) the `class` attribute.
    func `class`(_ name: String) -> VNode {
        mergeAttribute(self) { $0.attributes["class"] = name }
    }

    /// Adds (or overwrites) the `id` attribute.
    func id(_ name: String) -> VNode {
        mergeAttribute(self) { $0.attributes["id"] = name }
    }

    /// Adds (or overwrites) an inline-style declaration.
    func style(_ property: String, _ value: String) -> VNode {
        #if DEBUG
        _swiflowStyleValueValidator?(value)
        #endif
        return mergeAttribute(self) { $0.style[property] = value }
    }

    /// Adds (or overwrites) an HTML attribute (string value).
    ///
    /// URL-bearing attribute names (`href`, `src`, `action`, `formaction` —
    /// case-insensitive) route through the URL allowlist, exactly like the
    /// prefix `Attribute` path: a rejected value drops the attribute. Shared
    /// implementation: `URLSanitizer.resolvedAttributeValue(name:value:)`.
    func attr(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { data in
            if let resolved = URLSanitizer.resolvedAttributeValue(name: name, value: value) {
                data.attributes[name] = resolved
            }
        }
    }

    /// Adds (or overwrites) an HTML attribute (integer value, stringified).
    func attr(_ name: String, _ value: Int) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = String(value) }
    }

    /// Adds (or overwrites) a presence-only HTML boolean attribute when
    /// `value` is `true`; omits the attribute entirely when `false`.
    func attr(_ name: String, _ value: Bool) -> VNode {
        guard value else { return self }
        return mergeAttribute(self) { $0.attributes[name] = "" }
    }

    /// Adds (or overwrites) an HTML attribute (double value, stringified).
    func attr(_ name: String, _ value: Double) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = String(value) }
    }

    /// Adds a `data-*` attribute. `.data("user-id", "42")` writes `data-user-id="42"`.
    func data(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.attributes["data-\(name)"] = value }
    }

    func transition(_ value: String) -> VNode {
        mergeAttribute(self) { $0.style["transition"] = value }
    }

    func animation(_ value: String) -> VNode {
        mergeAttribute(self) { $0.style["animation"] = value }
    }

    func cssVar(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.style[name] = value }
    }

    /// Marks this element as managing its own children: Swiflow mounts the initially-declared
    /// children once, then never reconciles inside it again (the element shell — attributes,
    /// properties, style, handlers — is still reconciled). Pair with `.ref(_:)` to populate the
    /// element imperatively (custom elements, a foreign-painted `<canvas>`, third-party widgets).
    /// A no-op on non-element nodes (the standard postfix-modifier diagnostic path).
    func unmanagedChildren() -> VNode {
        mergeAttribute(self) { $0.managesOwnChildren = true }
    }

    /// Tags this element with a memoization token. When the diff compares this
    /// element against a previously-mounted element of the same tag and both
    /// carry an equal, non-nil `memoKey`, the entire subtree is skipped (no
    /// reconstruction work is saved by this tag alone — pair it with caching the
    /// VNode so `body` doesn't rebuild it either). Caller's contract: equal key
    /// ⇒ equal element + children. A no-op on non-element nodes.
    func memoKey(_ key: AnyHashable) -> VNode {
        mergeAttribute(self) { $0.memoKey = key }
    }
}
