// Sources/Swiflow/DSL/VNodeModifiers.swift

/// Returns a new VNode with a mutation applied to its `ElementData`.
/// Non-element VNodes (`.text`, `.component`, `.rawHTML`) trigger a diagnostic
/// in DEBUG and pass through unchanged.
private func mergeAttribute(_ vnode: VNode, _ apply: (inout ElementData) -> Void) -> VNode {
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
        mergeAttribute(self) { $0.style[property] = value }
    }

    /// Adds (or overwrites) an HTML attribute (string value).
    ///
    /// URL-bearing attribute names (`href`, `src`, `action`, `formaction` —
    /// case-insensitive) route through `URLSanitizer.sanitize(_:)`, exactly
    /// like the prefix `Attribute` path: a rejected value drops the attribute.
    func attr(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { data in
            if URLSanitizer.urlAttributeNames.contains(name.lowercased()) {
                if let sanitized = URLSanitizer.sanitize(value) {
                    data.attributes[name] = sanitized
                } else {
                    #if DEBUG
                    print("[Swiflow] URLSanitizer rejected \(name)=\"\(value)\" — attribute dropped. Use VNode.rawHTML for the rare case where unsanitized URLs are intentional.")
                    #endif
                }
            } else {
                data.attributes[name] = value
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
}
