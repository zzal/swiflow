# Swiflow Devtools

The `window.__swiflow` browser console API is available in dev-server builds
(started with `swiflow dev`). It is absent in production builds.

## Opening devtools

Open your browser's developer console (F12) while `swiflow dev` is running.
You'll see the live API on `window.__swiflow`.

## tree()

Prints an indented view of the live component tree.

```js
__swiflow.tree()
```

Example output:

```
App ""
  Sidebar ""
    NavItem "0"
    MainArea "1"
      Counter "1.0"
      Counter "1.1"
```

Each line shows the component's **short type name** and its **path** (the
dot-joined child-index string the framework uses internally). Components
whose direct rendered body is another component show `[body→]` to indicate
they share the same path.

Use `tree()` to find the path you need before calling `state()`.

## state(path)

Returns the current `@State` values for the component at `path`.

```js
__swiflow.state("1.0")
// → { count: 5, label: "clicks" }
```

Returns `null` if no component exists at the given path. The path is the
string shown in `tree()` output, including the quotes — but pass it without
quotes in the call: `state("1.0")` not `state('"1.0"')`.

Supported value types: `Int`, `Double`, `String`, `Bool`, `Optional` of those
types (`null` for `Optional.none`). Custom types are omitted.

## handlers()

Reports how many event handlers are currently registered, broken down by
component path scope.

```js
__swiflow.handlers()
// → { total: 14, byScope: { "": 2, "1.0": 6, "1.1": 4, "1.2": 2 } }
```

A scope whose count grows unboundedly across re-renders (visible if you call
`handlers()` several times) indicates a handler leak.

## perf()

Reports render performance metrics for the most recent render cycle.

```js
__swiflow.perf()
// → { renders: 7, lastPatchCount: 3, lastRenderMs: 1.2 }
```

- **renders**: total number of `renderOnce()` calls since page load.
- **lastPatchCount**: number of DOM patches applied in the last render.
- **lastRenderMs**: wall-clock duration of the last render, in milliseconds.

A high `lastPatchCount` on a simple state change usually points to a
missing key on a list of sibling components.
