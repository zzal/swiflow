// Sources/SwiflowDOM/HMR/HMRBridge.swift
//
// Phase 8 — JS bridge for HMR snapshot extraction and restore.
//
// The mount-tree walker and restore applier live in core
// (`Sources/Swiflow/Reactivity/HMR.swift`). This file is the WASM-
// only marshalling layer that:
//   - Installs `window.__swiflow.hmrSnapshot()` which returns a
//     JS array of {path, typeName, key, state} objects.
//   - Reads `window.__swiflowPendingSnapshot` (set by the JS driver
//     before re-importing the new module) and decodes it into a
//     Swift-side index that the diff consults via
//     `HMRRestoreInstall.restore`.

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

// HMR is a dev-only feature (no hot-swap in a release build), and its only
// callers — `Swiflow.render(into:)`'s snapshot-export + restore blocks — are
// `#if !SWIFLOW_RELEASE`-gated. Gating the whole type too means the JS
// marshalling code (and its `hmrSnapshot` / `__swiflowPendingSnapshot`
// property-name literals) is not compiled into the release wasm at all, not
// merely left unreferenced for the linker to maybe-strip.
#if !SWIFLOW_RELEASE

package enum HMRBridge {

    // MARK: - Closure retention

    /// Strong reference holding the snapshot exporter `JSClosure` so
    /// it isn't deallocated. Mirrors `DispatcherBridge.installed` —
    /// JSClosure-with-Swift-callback must outlive every invocation,
    /// and the JS-side reference (under `window.__swiflow.hmrSnapshot`)
    /// is a weak handle that won't keep the Swift closure alive.
    nonisolated(unsafe) private static var snapshotClosure: JSClosure?

    // MARK: - Snapshot exporter (Swift → JS)

    /// Install `window.__swiflow.hmrSnapshot = () => [...]` exactly once per
    /// module instance. The exported function walks EVERY live root's mount
    /// tree at call time (via the provider, which closes over the stable global
    /// root set), aggregates with `HMRWalker.snapshot(fromRoots:)`, and
    /// JS-encodes the result. Closing over the global root set — rather than
    /// capturing a single root weakly per render — is what makes multi-root HMR
    /// preserve every root's state, and lets us install just once: roots
    /// mounted later are picked up because the provider re-reads the live set
    /// at call time.
    @MainActor
    package static func installSnapshotExporter(rootsProvider: @escaping @MainActor () -> [MountNode]) {
        // Idempotent: the closure reads the live global root set at call time,
        // so a single install covers every present-and-future root. A fresh
        // module after a hot-swap starts with `snapshotClosure == nil` and
        // re-installs.
        guard snapshotClosure == nil else { return }

        let snapshotFn = JSClosure { _ in
            let snaps = HMRWalker.snapshot(fromRoots: rootsProvider())
            return encodeToJS(snaps)
        }

        // Place the function under the existing `window.__swiflow`
        // namespace. Create the namespace object if it doesn't exist
        // yet (the very first render after a fresh page load).
        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }
        ns.hmrSnapshot = .object(snapshotFn)

        // Strong reference so the JSClosure outlives every invocation (the
        // JS-side handle under `window.__swiflow.hmrSnapshot` is weak).
        snapshotClosure = snapshotFn
    }

    // MARK: - Pending snapshot consumer (JS → Swift)

    /// Parsed pending-restore index for THIS module instance. A fresh module
    /// after a hot-swap starts with `pendingRead == false`, so the first
    /// `pendingRestoreIndex()` re-parses `window.__swiflowPendingSnapshot`.
    nonisolated(unsafe) private static var pendingIndex: [SnapshotKey: [String: Any]]?
    nonisolated(unsafe) private static var pendingRead = false

    /// The restore index every root's first render consults. Parsed exactly
    /// once per module instance (reading + nil-ing the JS global on the first
    /// call), then CACHED — so a second/third root's `render(into:)` still sees
    /// the index instead of nil. Returns nil when no swap is pending.
    @MainActor
    package static func pendingRestoreIndex() -> [SnapshotKey: [String: Any]]? {
        if !pendingRead {
            pendingRead = true
            pendingIndex = parsePendingSnapshot()
        }
        return pendingIndex
    }

    /// Read `window.__swiflowPendingSnapshot`. Returns nil when no
    /// swap is pending (initial page load). On any decode error,
    /// returns nil — the new mount will start with declared initial
    /// values, which is strictly better than a full reload.
    @MainActor
    private static func parsePendingSnapshot() -> [SnapshotKey: [String: Any]]? {
        let pending = JSObject.global.__swiflowPendingSnapshot
        // Clear the global immediately so a subsequent render in the
        // same session (e.g. a manual rerender) doesn't accidentally
        // re-consume it.
        JSObject.global.__swiflowPendingSnapshot = .null

        guard let array = pending.object,
              let lengthValue = array.length.number else {
            return nil
        }
        let length = Int(lengthValue)
        guard length > 0 else { return nil }

        var snapshots: [ComponentSnapshot] = []
        for i in 0..<length {
            let entry = array[i]
            guard let path = entry.path.string,
                  let typeName = entry.typeName.string else {
                continue
            }
            let key = entry.key.string  // nil for JS null / non-string
            // `entry.state` collides via JavaScriptKit's two `subscript(dynamicMember:)`
            // overloads (one returns a callable, one returns JSValue). Reach
            // through `.object` and use the JSObject string subscript to pick
            // the JSValue branch unambiguously.
            let stateValue: JSValue = entry.object?["state"] ?? .undefined
            let stateMap = decodeStateMap(stateValue)
            snapshots.append(
                ComponentSnapshot(path: path, typeName: typeName, key: key, state: stateMap)
            )
        }
        return HMRWalker.indexSnapshots(snapshots)
    }

    // MARK: - JS encode / decode

    private static func encodeToJS(_ snapshots: [ComponentSnapshot]) -> JSValue {
        let array = JSObject.global.Array.function!.new()
        for (i, snap) in snapshots.enumerated() {
            let obj = JSObject.global.Object.function!.new()
            obj.path = .string(snap.path)
            obj.typeName = .string(snap.typeName)
            obj.key = snap.key.map { JSValue.string($0) } ?? .null
            obj.state = encodeStateMap(snap.state)
            array[i] = .object(obj)
        }
        return .object(array)
    }

    private static func encodeStateMap(_ state: [String: Any]) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        for (k, v) in state {
            // Phase 15: HMR snapshot values are either
            //   - a concrete primitive (Bool/Int/Double/String) — from a
            //     non-Optional @State or an Optional .some(payload) the
            //     macro unwrapped at the source via `.map { $0 as Any }`,
            //   - or an `HMRNilSentinel` — for Optional .none, which the
            //     `@Component` macro normalizes at the source because
            //     Optional<T>.none stored in `Any` is type-erased and
            //     cannot be distinguished by exhaustive `as?` checks here.
            // We never see a raw `Optional<T>.none` — the macro guarantees
            // it. Bool is checked before Int because Swift bridges Bool to
            // NSNumber and `v as? Int` succeeds for Bool values.
            if v is HMRNilSentinel {
                obj[k] = .null
            } else if let b = v as? Bool {
                obj[k] = .boolean(b)
            } else if let s = v as? String {
                obj[k] = .string(s)
            } else if let i = v as? Int {
                obj[k] = .number(Double(i))
            } else if let d = v as? Double {
                obj[k] = .number(d)
            }
            // Other unsupported types — skip (v1 limitation).
        }
        return .object(obj)
    }

    private static func decodeStateMap(_ js: JSValue) -> [String: Any] {
        guard let obj = js.object else { return [:] }
        var out: [String: Any] = [:]

        // JSObject doesn't expose key iteration directly; use
        // `Object.keys` via the JS global. `JSObject.global.Object`
        // resolves to the JS `Object` constructor as a JSValue; its
        // `keys` member is a callable JSFunction we invoke directly
        // — no `!` needed (the dynamic-member access already returns
        // a non-optional callable).
        let keysValue = JSObject.global.Object.keys(JSValue.object(obj))
        guard let keys = keysValue.object,
              let lenValue = keys.length.number else {
            return [:]
        }
        let len = Int(lenValue)
        for i in 0..<len {
            guard let k = keys[i].string else { continue }
            let v = obj[k]
            if let b = v.boolean {
                out[k] = b
            } else if let s = v.string {
                out[k] = s
            } else if let n = v.number {
                // JS numbers are doubles; preserve Int when integral so
                // the macro-emitted restore closure for `@State var count: Int`
                // accepts the value. The restore-side `as? Int` cast won't
                // match a Double, so we synthesize.
                // Note: `_hmrCoerce` adds a Double↔Int coercion layer for
                // `@State var price: Double = 0` whose current value happens
                // to be integral (arrives here as Int). The two layers are
                // complementary — this side biases toward Int for the
                // common counter case; restore-side corrects for Double
                // fields.
                if n.truncatingRemainder(dividingBy: 1) == 0 && n.isFinite
                    && n >= Double(Int.min) && n <= Double(Int.max) {
                    out[k] = Int(n)
                } else {
                    out[k] = n
                }
            } else if case .null = v {
                // JS null → sentinel. The macro-emitted `restoreNil`
                // closure on the target @State field will write
                // `Optional.none` if `Value` is Optional; non-Optional
                // fields return false and emit a diagnostic (shouldn't
                // happen unless the snapshot is from a mismatched build).
                out[k] = HMRNilSentinel()
            }
            // Other JS values (objects, functions, undefined) — skip.
        }
        return out
    }
}

#endif  // !SWIFLOW_RELEASE

#endif  // canImport(JavaScriptKit)
