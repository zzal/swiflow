# SwiflowTesting

`SwiflowTesting` is a headless unit-test renderer for Swiflow components. It
runs components synchronously (no `requestAnimationFrame`), so tests are
deterministic and need no `async`/`await`.

## Quick start

```swift
import Testing
import Swiflow
import SwiflowTesting

@Component
private final class Counter {
    @State var count = 0
    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
        }
    }
}

@Suite("Counter")
@MainActor
struct CounterTests {
    @Test func incrementsOnClick() {
        let h = render(Counter())
        #expect(h.find("p")?.text == "Count: 0")
        h.click("button", text: "Increment")
        #expect(h.find("p")?.text == "Count: 1")
    }
}
```

> **Note on `@Component` vs direct conformance.** You can declare test
> components either way:
>
> - `@Component final class Foo { ... }` (macro — preferred)
> - `@MainActor final class Foo: Component { ... }` (direct conformance)
>
> A bare `@Component` is isolation-complete: the macro injects `@MainActor`
> onto the class's members itself, so no explicit annotation is needed.
> Only direct conformance (no macro) still requires you to write
> `@MainActor` yourself.
>
> Either pattern requires the class to live at **file scope** — Swift does
> not allow extension declarations inside function or struct bodies, and the
> macro emits one. Mark the class `private` if it should only be visible
> inside the test file.

## `render(_:)`

```swift
@MainActor func render<C: Component>(_ component: C) -> TestHarness
```

Mounts `component` into a headless virtual DOM and returns a `TestHarness`.
All state mutations triggered by event dispatch flush synchronously before the
matching harness method returns.

## Querying the rendered tree

### `find(_ tag: text:) -> TestNode?`

Returns the first element matching `tag`, optionally filtered by subtree text
content (substring match).

```swift
h.find("p")                        // first <p>
h.find("button", text: "Save")     // first <button> whose subtree text contains "Save"
```

### `findAll(_ tag: text:) -> [TestNode]`

Returns every matching element in document order.

```swift
let inputs = h.findAll("input")
let buttons = h.findAll("button")
#expect(buttons[0].text == "Increment")
#expect(buttons[1].text == "Show toast")
```

### `find(role: label:)` / `findAll(role: label:)`

Query by **ARIA role** — the way a user (or screen reader) perceives the
element, robust against markup shuffles that break tag-position queries:

```swift
h.find(role: "button", label: "Save")
h.find(role: "textbox", label: "Email")
h.findAll(role: "checkbox")
h.find(role: "heading")
```

The effective role is the explicit `role` attribute if present, else the
implicit WAI-ARIA mapping for the tag: `button` → button, `a[href]` → link,
`input` → textbox/checkbox/radio/slider/spinbutton/searchbox by `type`,
`textarea` → textbox, `select` → combobox, `h1`–`h6` → heading, landmark
tags (`nav`/`main`/`header`/`footer`/`aside`/`section`/`form`), table parts,
`ul`/`ol` → list, `li` → listitem, `dialog`, `progress` → progressbar, and
`fieldset` → group.

`label` filters by **accessible label** (contains-match, like `text:`),
resolved in precedence order: `aria-label` → a `<label for=id>` naming the
element's `id` → a wrapping ancestor `<label>` (the SwiflowUI form-control
pattern) → the element's own subtree text (a button names itself).
`aria-labelledby` is *not* resolved — this is a pragmatic subset of accname
computation, not the full algorithm.

### `find(label:)` / `findAll(label:)`

Accessible-label query with no role filter:

```swift
h.find(label: "Accept terms")
```

### `find(class:)` / `findAll(class:)`

Matches a **token** of the element's class list (never a substring —
`sw-err` does not match `sw-error`):

```swift
h.find(class: "sw-field__error")
```

### `exists(_ tag: text:) -> Bool`

Convenience predicate. True iff at least one matching element exists.

```swift
#expect(h.exists("button") == true)
#expect(h.exists("h1") == false)
```

### `allText -> String`

All text content in the tree, concatenated depth-first. Useful for broad
smoke tests where you want to assert "the word `Welcome` appears somewhere".

```swift
#expect(h.allText.contains("Count: 0"))
```

### `expect(text:)` / `expect(_ tag: text:)`

`#expect(h.find(...) != nil)` failures say "expected non-nil" and nothing
else. The `expect` matchers assert the same things but record failures that
**include the rendered tree**, so the message shows what actually rendered:

```swift
h.expect(text: "Count: 1")            // allText contains
h.expect("button", text: "Sign in")   // an element matches
```

```
expected text "Count: 1" — not found. Rendered tree:
▸ Counter
  <div>
    <p>
      "Count: 0"
    <button on:[click]>
      "Increment"
```

### `debug()`

Prints and returns the same tree dump for ad-hoc inspection while writing a
test: one line per node — elements as `<tag attrs on:[events]>`, quoted text
nodes, `▸ ComponentName` anchors.

```swift
let h = render(Counter())
h.debug()
```

## `TestNode` — a live element handle

`find`/`findAll` return **live** handles to rendered elements, not
snapshots: reads reflect the current tree after every re-render, actions
dispatch on *this* element (never re-queried, never "first in document
order"), and queries scope to its subtree.

| Member | Type | Description |
|--------|------|-------------|
| `tag` | `String` | HTML tag name (e.g. `"div"`, `"input"`) |
| `text` | `String` | Subtree text content, current as of the last render |
| `attributes` | `[String: String]` | HTML attributes set via `.attr(...)`, `.class(...)`, `.id(...)` |
| `properties` | `[String: String]` | DOM properties set via `.value(...)`, `.checked(...)`, `.prop(...)`. Each `PropertyValue` is stringified: `.string(s)` → `s`, `.bool(b)` → `"true"` / `"false"`, `.int(n)` → decimal string, `.double(d)` → Swift `String(d)` representation. |
| `isAttached` | `Bool` | Whether the element is still part of the rendered tree |
| `find` / `findAll` | | The tag+text queries, scoped to this node's subtree |
| `click()` `type(_:)` `blur()` `change(value:)` `check(_:)` `press(key:)` `fire(_:)` | | Actions on this element — strict and chainable (each returns the node) |

```swift
h.find(role: "textbox", label: "Email")!.type("x").blur()

let banner = h.find(class: "banner")!
#expect(banner.find("button")?.text == "Dismiss")
```

If a re-render removes the element, the handle is *detached*: reads return
its last committed state, and actions record a test Issue telling you to
re-query for the current element.

`attributes` covers HTML attributes (`element.setAttribute(name, value)`),
while `properties` covers typed DOM property assignments (`element[name] = value`).
For most tests you'll want one or the other depending on which bag the modifier
wrote to.

```swift
// .attr(...)  → node.attributes
input(.attr("type", "email"))
// → node.attributes["type"] == "email"

// .prop(...)  → node.properties
input(.prop("value", .string("hello")))
// → node.properties["value"] == "hello"
```

## Interactions

**Interactions are strict:** if a call dispatches nothing — no element matches
the selector, the index is out of range, or the matched element has no handler
for the event — the harness records a test **Issue at the call site**, naming
the reason and the candidates (tags present in the tree, or handlers present
on the matched element). A typo'd selector fails loudly on the line that made
it, not three lines later with a bare "expected non-nil".

When a no-op is *intentional* — e.g. asserting that a control is inert while a
form is invalid — use the `IfPresent` variants (`clickIfPresent`,
`inputIfPresent`, `blurIfPresent`, `changeIfPresent`, `checkIfPresent`), which
take the same arguments and silently do nothing when there is no target.

### `click(_ tag: text:)`

Fires a `click` event on the first matching element and flushes any state
mutations synchronously.

```swift
h.click("button", text: "Sign in")
```

Records an Issue if no matching element exists or the element has no `click`
handler; `clickIfPresent` is the silent variant.

### `input(_ tag: at: value:)`

Fires an `input` event on the element at `index` among all elements matching
`tag` (default `"input"`) and flushes.

```swift
h.input("input", at: 0, value: "user@example.com")

// tag defaults to "input", at defaults to 0:
h.input(value: "World")
```

The event's `targetValue` is set to the provided `value` string.

### `blur(_ tag: at:)`

Fires a `blur` event on the element at `index` among all elements matching
`tag` (default `"input"`) and flushes.

```swift
h.blur("input", at: 1)

// tag defaults to "input", at defaults to 0:
h.blur()
```

Useful for testing form-validation flows that surface errors on blur.

### `change(_ tag: at: value:)`

Fires a `change` event on the element at `index` among all elements matching
`tag` (default `"select"`) and flushes. Use for `<select>` and `<textarea>`
elements with `.on(.change)` handlers.

```swift
h.change("select", value: "opt2")

// tag defaults to "select", at defaults to 0:
h.change(value: "opt2")
```

The event's `targetValue` is set to the provided `value` string. For
`<input>` elements that use `.on(.input)`, use `input(...)` instead.

### `check(_ tag: at: checked:)`

Simulates toggling a checkbox/radio: fires a `change` event whose
`targetChecked` is `checked` (mirroring the browser driver's payload) on the
element at `index` among all elements matching `tag` (default `"input"`) and
flushes.

```swift
h.check(at: 0, checked: true)     // tick the first checkbox
h.check(at: 0, checked: false)    // untick it
```

### `press(_ tag: key: at:)`

Fires a `keydown` event carrying `key` on the element at `index` among all
elements matching `tag` (default `"input"`) and flushes. The event's
`targetValue`/`targetChecked` snapshot the element's current properties, the
same way the browser driver serializes them.

```swift
h.press(key: "ArrowDown")             // keydown on the first <input>
h.press(key: "Enter")
h.press("div", key: "Escape")         // a keydown handler on a container
```

Use this for keyboard-navigation specs (autocomplete highlight movement,
Escape-to-dismiss) instead of digging handlers out of the rendered tree.

### `fire(_ event: on: text: at:)`

The general escape hatch: fires an arbitrary event type on a matching element
and flushes. `click`/`input`/`press`/… are conveniences over this.

```swift
h.fire("focusin", on: "input")
h.fire("pointerenter", on: "li", at: 2)
```

The payload carries the element's current `value`/`checked` snapshot; events
needing richer payloads (mouse coordinates, dataTransfer) are outside the
harness's fidelity boundary — see [Limitations](#limitations).

### `unmount()`

Unmounts the rendered tree, firing `onDisappear` parent-first — mirrors
`Swiflow.unmount(into:)` in the browser. Queries after unmount read the
last-rendered tree and are unspecified; calling `unmount()` again is a no-op.

## Recipes

### Click interaction

State updates flush synchronously when triggered through harness methods, so
you can assert state-derived rendering immediately after the event:

```swift
@Test func incrementsOnClick() {
    let h = render(Counter())
    h.click("button", text: "Increment")
    #expect(h.find("p")?.text == "Count: 1")  // no waiting, no async
}

@Test func threeClicks() {
    let h = render(Counter())
    h.click("button", text: "Increment")
    h.click("button", text: "Increment")
    h.click("button", text: "Increment")
    #expect(h.find("p", text: "Count: 3") != nil)
}
```

### Conditional rendering

```swift
@Test func toastAppearsOnClick() {
    let h = render(Counter())
    #expect(h.exists("div", text: "Saved!") == false)
    h.click("button", text: "Show toast")
    #expect(h.exists("div", text: "Saved!"))
}
```

### Form input binding

```swift
@Test func inputUpdatesGreeting() {
    let h = render(Counter())
    #expect(h.find("h1", text: "Hello, Swiflow!") != nil)
    h.input(value: "World")
    #expect(h.find("h1", text: "Hello, World!") != nil)
}
```

### Form validation with blur

Pair `input(...)` with `blur(...)` to trigger validation:

```swift
@Test func invalidEmailShowsError() {
    let h = render(SignIn())
    h.input(at: 0, value: "notanemail")
    h.blur(at: 0)
    #expect(h.find("p", text: "Invalid email address") != nil)
}

@Test func validCredentialsSignsIn() {
    let h = render(SignIn())
    h.input(at: 0, value: "good@test.com")
    h.blur(at: 0)
    h.input(at: 1, value: "secret99")
    h.blur(at: 1)
    h.click("button", text: "Sign In")
    #expect(h.find("p", text: "Signed in as good@test.com!") != nil)
}
```

### Injecting `@Environment` values

Use `withEnvironment(_:_:)` or the `.environment(_:_:)` VNode modifier inside
your component's `body` to inject test values. The harness reads ambient
environment values during `body` evaluation:

```swift
@Component
private final class LocaleHost {
    var body: VNode {
        withEnvironment(\.locale, "fr") {
            embed { Greeting() }
        }
    }
}

@Test func frenchGreeting() {
    let h = render(LocaleHost())
    #expect(h.exists("p", text: "Bonjour"))
}
```

## Notes

- All `TestHarness` methods and the `render()` function require `@MainActor`.
  Annotate your test `struct` with `@MainActor` to avoid repeating it on every
  `@Test` function.
- `@State` is wired the same way as in production; mutations trigger
  synchronous re-renders via `SyncScheduler` (the test-only scheduler that
  replaces production's `RAFScheduler`).
- **Re-renders are scoped exactly like the browser's.** A flush whose only
  dirty component is a non-root child re-renders just that child's subtree
  (the same `planRerender`/`scopedRerender` production runs) — the parent's
  `body` is **not** re-evaluated, so a parent reading shared mutable state a
  child changed will not refresh until something dirties the parent. If your
  test relied on that propagation, so did your app: lift the state or pass a
  callback.
- **Uncontrolled inputs behave like the DOM.** Typing via `type(_:)`/
  `input(...)` updates the element's live value even when no render declares
  a `.value` property and no handler listens; later events (`blur`, `press`)
  snapshot the typed value, and a render that assigns `.value` overwrites it
  — the browser's exact write order. For this reason `input`/`change` on a
  listener-less element is *not* a strict failure (the DOM write is the
  behavior); every other unhandled event still records an Issue.
- `text` matching in `find`/`findAll`/`exists`/`click` is a **substring**
  check on the element's full subtree text. Pass a more specific string if
  multiple elements could match.

## Limitations

### The fidelity boundary

The harness runs the **real** diff, lifecycle, handler wiring, and scheduler —
but nothing is ever applied to a DOM. It asserts what the component tree
**declares**, never what a browser **does** with the declaration. Everything
on the far side of the patch stream is invisible here:

- patch serialization and the JS driver's application of it,
- imperative, JS-gated effects (`showModal()`, focus management, scrolling),
- CSS — what a style or token *resolves to*,
- real browser event semantics (bubbling, default actions, `Event` payloads
  beyond `value`/`checked`/`key`).

A bug in *applying* a correct declaration (the class that shipped the
`.style()` custom-property miss) cannot be caught at this layer. Assert
declarations with the harness; verify browser behavior with js-driver tests
and the Playwright suites.

### Other limitations

- **`TestHarness` is synchronous-only.** Components using `.task` effects or
  SwiflowQuery need `AsyncTestHarness` instead — same query/interaction
  surface plus deterministic async control: `settle()`, `flush()`,
  `advance(by:)`, and `focus()`. See the
  [async tasks guide](async-tasks.md) and the [query guide](query.md).
- **Event payloads are `value`/`checked`/`key` only.** `press(key:)` covers
  keyboard events and `fire(_:on:)` covers arbitrary event *types*, but
  payloads with mouse coordinates, modifiers, or `dataTransfer` aren't
  representable in `EventInfo`.
