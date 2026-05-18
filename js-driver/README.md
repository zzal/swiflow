# js-driver

The Swiflow JavaScript driver. Vanilla JS, no build step.

## Contract

The driver exposes three operations under `window.swiflow`:

- `applyPatches(patches)` — accepts a `JSArray<JSObject>` produced by the
  Swift-side `PatchSerializer.encode(...) → JSAdapter.toJSValue(...)`
  pipeline. Iterates and executes each patch in arrival order against the
  driver-owned `Map<int, Node>`.
- `mount(rootHandle, selector)` — attaches the node identified by `rootHandle`
  into the DOM at `document.querySelector(selector)`. Called once per app
  during `Swiflow.render(_:into:)`.
- `registerDispatcher(fn)` — reserved, currently a no-op. The Swift dispatcher
  is published as `window.__swiflowDispatch` via JavaScriptKit's `JSClosure`.

## Wire format

Each patch is a plain JS object with an `op` string discriminator. Field names
are case-sensitive and must match the Swift-side `PatchSerializer.encode`
output exactly. See `Sources/Swiflow/PatchSerializer.swift` for the canonical
list of opcodes (17 total) and per-opcode fields.

## Event flow

When a DOM event fires on a node with a registered handler:

1. The driver's per-listener wrapper calls
   `window.__swiflowDispatch(handlerId, serializeEvent(event))`.
2. Swift's `DispatcherBridge` looks up `handlerId` in `HandlerRegistry` and
   invokes the closure.
3. If the closure mutates state and calls `Swiflow.rerender()`, a new diff
   pass produces a fresh `JSArray<JSObject>` and a single `applyPatches`
   call applies the batch.

## Security: the rawHTML escape hatch

The `parseRawHTML` helper is the single site in the driver that assigns
`innerHTML`. It is called only from the `createRawHTML` and `setRawHTML`
opcodes — `git grep "innerHTML" js-driver/` enumerates every match and
they all live inside this helper (plus a defensive rejection in the
generic `setProperty` case). The Swift side gates both opcodes via
`VNode.rawHTML(_:)`, so `git grep "rawHTML("` enumerates every place
where unescaped HTML can enter the DOM. XSS responsibility lies with
the caller; the framework guarantees no other path produces unescaped
HTML.

## Authoring

Edit the file directly. Do not introduce a build step (TypeScript, esbuild,
etc.) in Phase 2; the file is small enough that the cost outweighs the
benefit. If the file grows past ~400 lines, consider splitting by concern
(applyOne could move into its own module) before considering a build.

## Distribution

In Phase 2a the driver is loaded by hand into `examples/HelloWorld/public/`.
Phase 2b's `swiflow init` will embed it as a Swift `String` resource in the
CLI binary and write it to each scaffolded project's `public/` directory.
