// Sources/SwiflowWeb/HMR/HMRBridge.swift
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
import Foundation
import JavaScriptKit
import Swiflow

package enum HMRBridge {

    // MARK: - Closure retention

    /// Strong reference holding the snapshot exporter `JSClosure` so
    /// it isn't deallocated. Mirrors `DispatcherBridge.installed` —
    /// JSClosure-with-Swift-callback must outlive every invocation,
    /// and the JS-side reference (under `window.__swiflow.hmrSnapshot`)
    /// is a weak handle that won't keep the Swift closure alive.
    nonisolated(unsafe) private static var snapshotClosure: JSClosure?

    // MARK: - Snapshot exporter (Swift → JS)

    /// Install `window.__swiflow.hmrSnapshot = () => [...]`. The
    /// exported function consults the renderer's live mount tree at
    /// call time, walks it with `HMRWalker.snapshot(...)`, and
    /// JS-encodes the result.
    @MainActor
    package static func installSnapshotExporter(treeProvider: @escaping @MainActor () -> MountNode?) {
        let snapshotFn = JSClosure { _ in
            guard let tree = treeProvider() else {
                return JSValue.object(JSObject.global.Array.function!.new())
            }
            let snaps = HMRWalker.snapshot(from: tree)
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

        // Retain across re-installs. If a previous closure was alive
        // (idempotent re-installs in dev), replacing the static drops
        // its reference and lets ARC reclaim the prior JSClosure.
        snapshotClosure = snapshotFn
    }

    // MARK: - Pending snapshot consumer (JS → Swift)

    /// Read `window.__swiflowPendingSnapshot`. Returns nil when no
    /// swap is pending (initial page load). On any decode error,
    /// returns nil — the new mount will start with declared initial
    /// values, which is strictly better than a full reload.
    @MainActor
    package static func takePendingSnapshot() -> [SnapshotKey: [String: Any]]? {
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
            // Bool MUST be checked BEFORE Int because Swift bridges Bool
            // to NSNumber, and `v as? Int` succeeds for Bool values
            // (true → 1, false → 0). Swapping order would encode every
            // checkbox as a number on the wire.
            if let b = v as? Bool {
                obj[k] = .boolean(b)
            } else if let s = v as? String {
                obj[k] = .string(s)
            } else if let i = v as? Int {
                obj[k] = .number(Double(i))
            } else if let d = v as? Double {
                obj[k] = .number(d)
            } else {
                // Try Optional<primitive> via Mirror displayStyle.
                let mirror = Mirror(reflecting: v)
                if mirror.displayStyle == .optional {
                    if mirror.children.isEmpty {
                        // Optional.none — explicitly write JS null so
                        // restore-side can map back to nil.
                        obj[k] = .null
                    } else {
                        // Optional.some(payload) — recurse on the
                        // unwrapped payload by re-running the same
                        // type checks. Build a single-entry map so we
                        // can reuse encodeStateMap. Less efficient than
                        // inline branches, but v1 only handles
                        // Optional<{String,Int,Double,Bool}> so the
                        // recursion depth is bounded at 1.
                        let payload = mirror.children.first!.value
                        if let b = payload as? Bool {
                            obj[k] = .boolean(b)
                        } else if let s = payload as? String {
                            obj[k] = .string(s)
                        } else if let i = payload as? Int {
                            obj[k] = .number(Double(i))
                        } else if let d = payload as? Double {
                            obj[k] = .number(d)
                        }
                        // Other Optional payloads — skip (v1 limitation).
                    }
                }
                // Other unsupported types — skip (v1 limitation).
            }
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
                // `_hmrRestore` on `@State var count: Int` accepts the
                // value. The restore-side `as? Int` cast won't match a
                // Double, so we synthesize.
                // Note: `_hmrRestoreImpl` adds a Double↔Int coercion layer
                // for `@State var price: Double = 0` whose current value
                // happens to be integral (arrives here as Int). The two
                // layers are complementary — this side biases toward Int
                // for the common counter case; restore-side corrects for
                // Double fields.
                if n.truncatingRemainder(dividingBy: 1) == 0 && n.isFinite
                    && n >= Double(Int.min) && n <= Double(Int.max) {
                    out[k] = Int(n)
                } else {
                    out[k] = n
                }
            } else if case .null = v {
                // JS null → sentinel. `_hmrRestoreNil()` on the target
                // @State field will write `Optional.none` if `Value` is
                // Optional; non-Optional fields return false and emit a
                // diagnostic (shouldn't happen unless the snapshot is
                // from a mismatched build).
                out[k] = HMRNilSentinel()
            }
            // Other JS values (objects, functions, undefined) — skip.
        }
        return out
    }
}

#endif
