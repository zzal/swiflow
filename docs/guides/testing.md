# SwiflowTesting

`SwiflowTesting` is a headless unit-test renderer for Swiflow components. It
runs components synchronously (no `requestAnimationFrame`), so tests are
deterministic and need no `async`/`await`.

## Quick start

```swift
import Testing
import Swiflow
import SwiflowTesting

@MainActor
private final class Counter: Component {
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
> components either way: `final class Foo: Component { ... }` (direct
> conformance) or `@Component final class Foo { ... }` (macro). When using the
> `@Component` macro the class must live at **file scope** — the macro emits an
> `extension Foo: Component {}` declaration, and Swift does not allow extensions
> inside function or struct bodies. Mark the class `private` if it should only
> be visible inside the test file.

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

## `TestNode` fields

| Field | Type | Description |
|-------|------|-------------|
| `tag` | `String` | HTML tag name (e.g. `"div"`, `"input"`) |
| `text` | `String` | Subtree text content of this node |
| `attributes` | `[String: String]` | HTML attributes set via `.attr(...)`, `.class(...)`, `.id(...)` |
| `properties` | `[String: String]` | DOM properties set via `.value(...)`, `.checked(...)`, `.prop(...)`. Each `PropertyValue` is stringified: `.string(s)` → `s`, `.bool(b)` → `"true"` / `"false"`, `.int(n)` → decimal string, `.double(d)` → Swift `String(d)` representation. |

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

### `click(_ tag: text:)`

Fires a `click` event on the first matching element and flushes any state
mutations synchronously.

```swift
h.click("button", text: "Sign in")
```

No-op if no matching element exists or the element has no `click` handler.

### `input(_ tag: at: value:)`

Fires an `input` event on the element at `index` among all elements matching
`tag` (default `"input"`) and flushes.

```swift
h.input("input", at: 0, value: "user@example.com")

// tag defaults to "input", at defaults to 0:
h.input(value: "World")
```

The event's `targetValue` is set to the provided `value` string. No-op if
out-of-bounds or the element has no `input` handler.

### `blur(_ tag: at:)`

Fires a `blur` event on the element at `index` among all elements matching
`tag` (default `"input"`) and flushes.

```swift
h.blur("input", at: 1)

// tag defaults to "input", at defaults to 0:
h.blur()
```

Useful for testing form-validation flows that surface errors on blur.

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
@MainActor
private final class LocaleHost: Component {
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
- `text` matching in `find`/`findAll`/`exists`/`click` is a **substring**
  check on the element's full subtree text. Pass a more specific string if
  multiple elements could match.

## Limitations

- **No async/await support.** `task {}` lifecycle hooks (pre-1.0 feature) are
  not exercised by `TestHarness`. An `AsyncTestRenderer` is planned.
- **No `change` event support.** `<select>` and `<textarea>` `onChange`
  handlers cannot currently be dispatched. Use `input` as a workaround where
  the host element accepts it.
- **No keyboard or mouse-position events.** Only `click`, `input`, and `blur`
  are supported. Other DOM events would need direct dispatch through the
  underlying `HandlerRegistry`.
