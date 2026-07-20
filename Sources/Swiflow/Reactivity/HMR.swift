// Sources/Swiflow/Reactivity/HMR.swift
//
// Phase 8 — HMR core types and mount-tree walkers.
//
// Lives in core (not SwiflowDOM) so the snapshot/restore logic is
// host-testable without JavaScriptKit. The JS bridge in
// `Sources/SwiflowDOM/HMR/HMRBridge.swift` (Task E) is a thin
// marshalling layer over these types.

/// Sentinel placed in a state map when a value is `Optional.none`.
///
/// On the **decode path** (JS → Swift): produced by `HMRBridge.decodeStateMap`
/// when a JS `null` arrives for a known Optional field; consumed by
/// `wireStateAndRestore`, routed to the macro-emitted
/// `StateCell.restoreNil` closure.
///
/// On the **encode path** (Swift → JS): emitted by macro-generated
/// `snapshot` closures when an Optional `@State` field is `.none` —
/// because Optional<T>.none stored in `Any` is type-erased (Swift can't
/// distinguish Optional<Bool>.none from Optional<Int>.none via type
/// cast), the macro normalizes `.none` to this sentinel at the source.
/// Downstream encoders dispatch on the sentinel rather than walking
/// Mirror to detect nil-Optionals.
///
/// Public because macro-emitted code in user modules references it.
public struct HMRNilSentinel: Sendable {
    public init() {}
}

/// One row in an HMR snapshot — captures the identifying triple and
/// the per-`@State` value map for a single Component in the mount
/// tree. Snapshot arrays are produced by `HMRWalker.snapshot(from:)`;
/// the indexed map is consumed by `wireStateAndRestore(...)` via the
/// `HMRRestoreInstall.stateFor` lookup at the diff's mount site.
///
/// `state[fieldName]` is the raw `Any` value produced by a state
/// cell's `snapshot(of:)` closure (macro-emitted by `@Component`).
/// The JS bridge later encodes the supported primitive subset; values
/// that don't make it across the bridge are simply absent on restore
/// (the field falls back to the declared initial value, with a debug
/// log).
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

/// Phase 7-style install slot. SwiflowDOM installs a closure at
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
/// index back into freshly-instantiated Components.
///
/// All functions are pure with respect to the tree shape — they
/// don't mutate `MountNode` or `Component` instances. The restore
/// applier writes through each `StateCell`'s `restore` closure
/// (macro-emitted), which is idempotent and safe to call multiple
/// times.
@MainActor
package enum HMRWalker {

    /// Aggregates snapshots across multiple render roots, in order. The HMR
    /// exporter walks every live root so a multi-root app preserves all roots'
    /// `@State` across a hot-swap (not just the last-mounted root).
    ///
    /// v1 limitation: snapshot identity is `(path, typeName, key)` relative to
    /// each root's own tree, so mounting the identical component type with
    /// identical structure at two selectors can collide. Distinct component
    /// types per selector — the normal case — never collide.
    package static func snapshot(fromRoots roots: [MountNode]) -> [ComponentSnapshot] {
        roots.flatMap { snapshot(from: $0) }
    }

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
        // Snapshot values come from `_ComponentRuntime.stateCells`
        // — an array of typed StateCell descriptors emitted by the
        // `@Component` macro. Hand-rolled `Component` conformances that
        // don't adopt `_ComponentRuntime` produce an empty state map,
        // which is exactly right (they have no `@State` to record).
        if let runtime = instance as? any _ComponentRuntime {
            for cell in type(of: runtime).stateCells {
                stateMap[cell.name] = cell.snapshot(of: runtime)
            }
        }

        return ComponentSnapshot(path: path, typeName: typeName, key: key, state: stateMap)
    }

    // MARK: - Restore (used by Tasks D/E)

    /// Build a lookup index from a snapshot array. SwiflowDOM's bridge
    /// calls this after decoding the JS-side snapshot payload.
    package static func indexSnapshots(_ snapshots: [ComponentSnapshot]) -> [SnapshotKey: [String: Any]] {
        var index: [SnapshotKey: [String: Any]] = [:]
        for snap in snapshots {
            let key = SnapshotKey(path: snap.path, typeName: snap.typeName, key: snap.key)
            index[key] = snap.state
        }
        return index
    }
}
