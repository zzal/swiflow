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

    /// Held for ownership clarity / idempotency-checking (see
    /// `installSnapshotExporter` below), mirroring `DispatcherBridge.installed`
    /// — not because it's what keeps the closure callable. `JSClosure.init`
    /// self-registers into JavaScriptKit's static `sharedClosures` table, so
    /// `window.__swiflow.hmrSnapshot` stays invocable regardless of this field.
    @MainActor private static var snapshotClosure: JSClosure?

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
        // Same runtime gate as `DevAPI.installAll()`: only the dev server
        // injects `window.SWIFLOW_DEV=true` (DevModeInjection), and only its
        // driver performs hot swaps — so a debug wasm served outside
        // `swiflow dev` (static server, copied outputs) exposes no
        // `__swiflow.hmrSnapshot`. Without this, debug builds presented an
        // inconsistent namespace: hmrSnapshot present, tree/state/perf absent.
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }
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

        // Held for ownership clarity / the idempotency guard above — the
        // JSClosure itself is already kept invocable by JavaScriptKit's
        // internal registration, independent of this field.
        snapshotClosure = snapshotFn
    }

    // MARK: - Teardown hook (Swift → JS)

    /// Same retention/idempotency role as `snapshotClosure` above.
    @MainActor private static var teardownClosure: JSClosure?

    /// Install `window.__swiflow.hmrTeardown = () => …` exactly once per
    /// module instance. The JS driver calls it during a hot swap — after
    /// taking the state snapshot, before clearing its node/listener maps —
    /// to deactivate THIS (about-to-be-orphaned) module: `unmountAll` tears
    /// down every live root, which stops the query-revalidation interval,
    /// removes window/document listeners via each component's
    /// `onDisappear`, and nils the RAF scheduler. Without this, the old
    /// module kept re-rendering after the swap; its patch failures against
    /// the cleared maps triggered full resync remounts that repainted the
    /// old UI over the new module's DOM (and destroyed the new module's
    /// driver-map entries, since both modules allocate handles from the
    /// same numeric base) — an endless multi-instance remount war.
    @MainActor
    package static func installTeardownHook(unmountAll: @escaping @MainActor () -> Void) {
        // Same runtime gate as `installSnapshotExporter`: hot swaps only
        // happen under `swiflow dev`, which injects SWIFLOW_DEV.
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }
        // Idempotent per module instance; a fresh module after a hot swap
        // starts with `teardownClosure == nil` and installs its own hook
        // over the (now-dead) previous module's.
        guard teardownClosure == nil else { return }

        let teardownFn = JSClosure { _ in
            unmountAll()
            return .undefined
        }

        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }
        ns.hmrTeardown = .object(teardownFn)

        teardownClosure = teardownFn
    }

    // MARK: - Pending snapshot consumer (JS → Swift)

    /// Parsed pending-restore index for THIS module instance. A fresh module
    /// after a hot-swap starts with `pendingRead == false`, so the first
    /// `pendingRestoreIndex()` re-parses `window.__swiflowPendingSnapshot`.
    @MainActor private static var pendingIndex: [SnapshotKey: [String: Any]]?
    @MainActor private static var pendingRead = false

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

        // Int(exactly:) — `__swiflowPendingSnapshot` is a global any script can
        // set; a `{length: NaN}` (or a wasm32-overflowing number) must not trap.
        guard let array = pending.object,
              let lengthValue = array.length.number,
              let length = Int(exactly: lengthValue),
              length > 0 else {
            return nil
        }

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

    @MainActor
    private static func encodeToJS(_ snapshots: [ComponentSnapshot]) -> JSValue {
        let array = JSObject.global.Array.function!.new()
        for (i, snap) in snapshots.enumerated() {
            let obj = JSObject.global.Object.function!.new()
            obj.path = .string(snap.path)
            obj.typeName = .string(snap.typeName)
            obj.key = snap.key.map { JSValue.string($0) } ?? .null
            obj.state = encodeStateMapToJS(snap.state)
            array[i] = .object(obj)
        }
        return .object(array)
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
        // Real `Object.keys` arrays always have a valid uint32 length; guarded
        // narrow anyway for consistency with the sites above (never trap on JS input).
        guard let len = Int(exactly: lenValue) else { return [:] }
        for i in 0..<len {
            guard let k = keys[i].string else { continue }
            // Classification lives in `JSScalar(jsValue:)`: booleans/strings map
            // directly; a JS number becomes Int when integral (so `@State var
            // count: Int` round-trips) else Double; JS null → `HMRNilSentinel`
            // (which the macro-emitted `restoreNil` closure turns into
            // `Optional.none` for Optional fields). Unsupported JS values
            // (objects/functions/undefined) classify as nil and are skipped.
            //
            // `_hmrCoerce` adds a COMPLEMENTARY restore-side Double↔Int layer:
            // a `@State var price: Double` whose current value is integral
            // arrives here biased to Int, and the restore closure corrects it.
            if let scalar = JSScalar(jsValue: obj[k]) {
                out[k] = scalar.stateValue
            }
        }
        return out
    }
}

#endif  // !SWIFLOW_RELEASE

#endif  // canImport(JavaScriptKit)
