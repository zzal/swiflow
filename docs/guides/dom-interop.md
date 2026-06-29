# DOM interop: unmanaged children

Swiflow reconciles every element's children against its own virtual tree on each render. When an
element's interior is owned by *something else* — a custom element that builds its own shadow/light
DOM, a `<canvas>` painted by a foreign WASM module, or a third-party widget (chart, date picker,
map) that injects nodes — that reconciliation would stomp the foreign DOM. `.unmanagedChildren()`
is the escape hatch.

```swift
// A <canvas> a foreign module paints. Swiflow owns the element; the module owns the pixels.
let canvas = Ref<JSObject>()
element("canvas", attributes: [.attr("width", 640), .attr("height", 480)])
    .ref(canvas)
    .unmanagedChildren()
// in onAppear: hand `canvas.wrappedValue` to the draw loop.

// A custom element that builds its own shadow DOM.
element("my-widget", attributes: [.attr("kind", kind)]).unmanagedChildren()

// A third-party widget, with a placeholder until it loads.
element("div", children: [Spinner()]).ref(host).unmanagedChildren()
// in onAppear: thirdPartyChart(host.wrappedValue)  — replaces the spinner; Swiflow won't touch it.
```

## Semantics

Swiflow mounts the element and any **initially-declared** children exactly once. After that it keeps
reconciling the element **shell** — its attributes, properties, style, and handlers update reactively
— but **never reconciles the children** again. Foreign-added DOM is invisible to the diff and
survives every re-render. Unmounting the element removes the whole subtree natively.

## Contract

- **Keep it stable.** Give an unmanaged element a stable position (and a `key:` among siblings) so a
  sibling diff never destroys and remounts it — a remount re-runs your foreign init and loses foreign
  state.
- **Re-declared children are ignored.** Only the first mount's children are placed by Swiflow;
  everything after is the foreign owner's responsibility.
- **Don't toggle the flag** for an element position; keep it constant.
- **The shell stays reactive** — only the children are hands-off.
