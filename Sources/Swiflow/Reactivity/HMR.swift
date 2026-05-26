// Sources/Swiflow/Reactivity/HMR.swift
//
// Phase 8 — HMR core types and mount-tree walkers.
//
// Lives in core (not SwiflowWeb) so the snapshot/restore logic is
// host-testable without JavaScriptKit. The JS bridge in
// `Sources/SwiflowWeb/HMR/HMRBridge.swift` (Task E) is a thin
// marshalling layer over these types.

/// Sentinel placed in a decoded state map when the corresponding JS value
/// was `null`. Signals that the `@State` field was `Optional.none` at
/// snapshot time and should be restored to nil rather than left at the
/// declared initial value.
///
/// Produced by `HMRBridge.decodeStateMap` (JS null → `HMRNilSentinel`);
/// consumed by `HMRWalker.applyRestore` (routes to `_hmrRestoreNil()`
/// instead of `_hmrRestore(_:)`). The pure-Swift path (no JS bridge)
/// never produces this sentinel — Swift's own `Optional<T>.none as Any`
/// round-trips correctly through `as? Value` without needing it.
package struct HMRNilSentinel: Sendable {
    package init() {}
}

/// One row in an HMR snapshot — captures the identifying triple and
/// the per-`@State` value map for a single Component in the mount
/// tree. Snapshot arrays are produced by `HMRWalker.snapshot(from:)`
/// and consumed by `HMRWalker.applyRestore(...)`.
///
/// `state[fieldName]` is the raw `Any` value pulled from a
/// `StateWireable._hmrSnapshotValue()` call. The JS bridge later
/// encodes the supported primitive subset; values that don't make
/// it across the bridge are simply absent on restore (the field
/// falls back to the declared initial value, with a debug log).
package struct ComponentSnapshot {
    package let path: String
    /// Fully-qualified type name produced by `String(reflecting:)`,
    /// e.g. `"MyApp.Counter"`. Because it includes the Swift module
    /// name, **renaming the module invalidates all HMR snapshots for
    /// its components** — they will fall back to declared initial
    /// values on the next hot-swap. This is intentional for v1:
    /// a mismatched name likely means an incompatible state shape.
    package let typeName: String
    package let key: String?
    package let state: [String: Any]

    package init(path: String, typeName: String, key: String?, state: [String: Any]) {
        self.path = path
        self.typeName = typeName
        self.key = key
        self.state = state
    }
}

/// Lookup key used by HMRRestore to find a snapshot for a freshly-
/// instantiated Component. Two `ComponentSnapshot`s with the same
/// path+typeName+key are treated as the same logical Component.
package struct SnapshotKey: Hashable {
    package let path: String
    package let typeName: String
    package let key: String?

    package init(path: String, typeName: String, key: String?) {
        self.path = path
        self.typeName = typeName
        self.key = key
    }
}

/// Phase 7-style install slot. SwiflowWeb installs a closure at
/// `Swiflow.render(into:_:)` entry time. Diff calls this at the
/// mount-wire site to look up snapshot data; when no swap is pending,
/// the slot is nil and the call is a single nil-check.
///
/// Parameters: (path, typeName, key) → optional state map.
/// - `path`: dot-joined child-index path in the new mount tree (same
///   format produced by `HMRWalker.snapshot(from:)`).
/// - `typeName`: `String(reflecting: type(of: instance))` for the
///   component. Must match what the snapshot recorded — module-qualified,
///   so a module rename invalidates all snapshots for its components.
/// - `key`: the component's `.key` from its `ComponentDescription`
///   (nil for unkeyed components).
///
/// Returning the state map (rather than applying it) lets the diff fuse
/// the owner-wiring Mirror walk and the restore walk into one pass.
///
/// `nonisolated(unsafe)`: closures are not Sendable; the slot is
/// only read/written from `@MainActor` contexts. Mirrors
/// `RefResolverInstall` from Phase 7.
package enum HMRRestoreInstall {
    package nonisolated(unsafe) static var stateFor: (@MainActor (String, String, String?) -> [String: Any]?)?
}

/// Mount-tree HMR helpers. The walker traverses a `MountNode` tree
/// and produces snapshots; the restore applier reads a snapshot
/// index back into freshly-instantiated Components via Mirror.
///
/// All functions are pure with respect to the tree shape — they
/// don't mutate `MountNode` or `Component` instances. The restore
/// applier writes through `StateWireable._hmrRestore(_:)`, which is
/// idempotent and safe to call multiple times.
@MainActor
package enum HMRWalker {

    /// Walk `tree` in document order and produce one
    /// `ComponentSnapshot` per Component-bearing `MountNode`.
    ///
    /// Path is dot-joined child indices from the root. Top-level
    /// path is the empty string `""`. A node's `componentBody` is
    /// topologically a continuation of the current path (it's "the
    /// body of this component", not a separately-indexed child).
    /// Regular `children` add their index to the path.
    package static func snapshot(from tree: MountNode) -> [ComponentSnapshot] {
        var out: [ComponentSnapshot] = []
        walk(tree, path: "", into: &out)
        return out
    }

    private static func walk(
        _ node: MountNode,
        path: String,
        into out: inout [ComponentSnapshot]
    ) {
        if let anyC = node.component {
            out.append(makeSnapshot(for: anyC, path: path, vnode: node.vnode))
        }
        // Component anchors hold their rendered body in `componentBody`.
        // Recurse into it at the SAME path — the body is the component,
        // topologically; it doesn't add an index level.
        if let body = node.componentBody {
            walk(body, path: path, into: &out)
        }
        // Regular children extend the path with their child index.
        for (i, child) in node.children.enumerated() {
            let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
            walk(child, path: childPath, into: &out)
        }
    }

    private static func makeSnapshot(
        for anyC: AnyComponent,
        path: String,
        vnode: VNode
    ) -> ComponentSnapshot {
        let instance = anyC.instance
        // String(reflecting:) produces a module-qualified name such as
        // "MyApp.Counter". A module rename will break HMR state matching
        // for all components in that module (they fall back to initial
        // values). See ComponentSnapshot.typeName for the design rationale.
        let typeName = String(reflecting: type(of: instance))
        let key: String?
        if case .component(let desc) = vnode {
            key = desc.key
        } else {
            key = nil
        }

        var stateMap: [String: Any] = [:]
        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard let wireable = child.value as? StateWireable else { continue }
            // Property-wrapper-backed labels are `_count`, `_label`, etc.
            // Strip the leading underscore to recover the user-visible name.
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            stateMap[fieldName] = wireable._hmrSnapshotValue()
        }

        return ComponentSnapshot(path: path, typeName: typeName, key: key, state: stateMap)
    }

    // MARK: - Restore (used by Tasks D/E)

    /// Build a lookup index from a snapshot array. SwiflowWeb's bridge
    /// calls this after decoding the JS-side snapshot payload.
    package static func indexSnapshots(_ snapshots: [ComponentSnapshot]) -> [SnapshotKey: [String: Any]] {
        var index: [SnapshotKey: [String: Any]] = [:]
        for snap in snapshots {
            let key = SnapshotKey(path: snap.path, typeName: snap.typeName, key: snap.key)
            index[key] = snap.state
        }
        return index
    }

    /// Look up a matching snapshot and apply it to a freshly-instantiated
    /// Component. Match is by (path, typeName, key). Per-field type
    /// mismatches are skipped (the field keeps its declared initial value)
    /// and reported via `swiflowDiagnostic`.
    ///
    /// `path` is the same dot-joined child-index format produced by
    /// `snapshot(from:)`. `key` is the component's `.key` from its
    /// `ComponentDescription` (nil for unkeyed components). The caller
    /// (Diff's mount path) is responsible for supplying both.
    ///
    /// State fields whose decoded value is `HMRNilSentinel` are routed to
    /// `_hmrRestoreNil()` instead of `_hmrRestore(_:)` — this covers the
    /// JS-bridge path where `Optional.none` becomes JS `null` then back.
    package static func applyRestore(
        index: [SnapshotKey: [String: Any]],
        to component: AnyComponent,
        at path: String,
        key: String?
    ) {
        let instance = component.instance
        let typeName = String(reflecting: type(of: instance))
        let lookupKey = SnapshotKey(path: path, typeName: typeName, key: key)
        guard let stateMap = index[lookupKey] else { return }

        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard let wireable = child.value as? StateWireable else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard let newValue = stateMap[fieldName] else { continue }
            let ok: Bool
            if newValue is HMRNilSentinel {
                // JS `null` decoded as sentinel — restore Optional to .none.
                ok = wireable._hmrRestoreNil()
            } else {
                ok = wireable._hmrRestore(newValue)
            }
            if !ok {
                swiflowDiagnostic(
                    "HMR restore: type mismatch on \(typeName).\(fieldName) at path '\(path)'. Field reset to its declared initial value."
                )
            }
        }
    }
}
