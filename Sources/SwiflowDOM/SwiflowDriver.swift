// Sources/SwiflowDOM/SwiflowDriver.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The typed Swift-side view of the `window.swiflow` JS driver contract
/// (defined in `js-driver/swiflow-driver.js`). Every Swift → driver call goes
/// through this ONE surface, so the `window.swiflow` global is resolved — and
/// its absence diagnosed — in a single place, instead of the
/// `JSObject.global.swiflow.object!` + force-unwrapped-method chain being
/// re-derived at each call site (`Renderer.mount`/`applyPatches`, the
/// `Ref` resolver). The protocol is also the seam a future BridgeJS-backed or
/// server/edge driver would implement, keeping the blast radius small.
///
/// Scope is deliberately just the driver contract — generic browser globals
/// (`setTimeout`, `requestAnimationFrame`, `document`, `performance`) are a
/// separate concern and stay where they are.
@MainActor
protocol SwiflowDriver {
    /// Attach the freshly-mounted root node (by handle) into the DOM at
    /// `selector`. Called once, on first mount.
    func mount(rootHandle: Int, selector: String)

    /// Ship a batch of patches to the DOM. Returns whether **every** patch
    /// applied without error — the driver catches failures per-patch (see
    /// `applyPatches` in the JS driver), so `false` means the DOM and the
    /// caller's mount tree may have diverged and a resync is warranted.
    /// Marshalling the patches into the JS array is the driver's job, not the
    /// renderer's.
    @discardableResult
    func applyPatches(_ patches: [Patch]) -> Bool

    /// Resolve a Swiflow handle to its live DOM node, or `nil` for an unknown
    /// handle (e.g. an anchor handle or a post-destroy handle). Powers
    /// `Ref<Element>.wrappedValue`.
    func nodeForHandle(_ handle: Int) -> JSObject?

    /// Detach the root mounted at `selector` from the DOM and drop the
    /// driver's record of it. Called after `Swiflow.unmount(into:)` tears the
    /// tree down, so an unmounted-and-never-remounted selector doesn't pin
    /// its detached root. No-op for a selector that was never mounted.
    func unmount(selector: String)
}

/// The production `SwiflowDriver`, backed by the `window.swiflow` global.
///
/// Stateless: it resolves the global on each call (a cheap property lookup) via
/// the single guarded `global` accessor below, which traps with a **named
/// cause** if the driver script never installed `window.swiflow`. The driver is
/// a required dependency — nothing renders without it — so a missing one is a
/// dead page in every build; this just makes the crash say *why* instead of a
/// bare "unexpectedly found nil" from a force-unwrap.
@MainActor
struct JSDriver: SwiflowDriver {
    /// The `window.swiflow` object, or a fatal error naming the cause. Resolved
    /// fresh per call — the WASM module boots only after the driver script runs,
    /// so in a correct deployment this never fails; a failure means
    /// `swiflow-driver.js` did not load, loaded after the WASM booted, or was
    /// removed. `fatalError` (not `swiflowDiagnostic`, which compiles out in
    /// release) so the message survives into release builds.
    private var global: JSObject {
        guard let object = JSObject.global.swiflow.object else {
            fatalError(
                "Swiflow: the `window.swiflow` driver was not found. The driver "
                + "script (swiflow-driver.js) did not load before the app, loaded "
                + "after the WASM module booted, or was removed. Ensure it is "
                + "served and included ahead of the WASM bundle."
            )
        }
        return object
    }

    func mount(rootHandle: Int, selector: String) {
        _ = global.mount!(JSValue.number(Double(rootHandle)), JSValue.string(selector))
    }

    @discardableResult
    func applyPatches(_ patches: [Patch]) -> Bool {
        // Marshal Swift patches into a JS array (the driver-boundary detail the
        // renderer used to open-code identically in two places).
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in patches.enumerated() {
            jsArray[index] = JSAdapter.toJSValue(PatchSerializer.encode(patch))
        }
        // `.boolean ?? true` — an unexpected non-boolean return (a JS-interop
        // shape change) is treated as success rather than triggering a resync
        // storm on ambiguous data. See Renderer.resyncFullRemount.
        return global.applyPatches!(jsArray).boolean ?? true
    }

    func nodeForHandle(_ handle: Int) -> JSObject? {
        // A missing driver traps via `global`; a resolved-but-unknown handle
        // returns JS `null`, whose `.object` is `nil` — the legitimate
        // "ref not currently bound" outcome.
        global.nodeForHandle!(JSValue.number(Double(handle))).object
    }

    func unmount(selector: String) {
        _ = global.unmount!(JSValue.string(selector))
    }
}
#endif
