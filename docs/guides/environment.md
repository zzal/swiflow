# Environment & @Environment

`@Environment` gives components a first-class way to read cross-tree values (locale, color scheme, custom theme, etc.) without prop-drilling or global singletons.

---

## Reading an environment value

```swift
@Environment(\.locale) var locale
```

`@Environment` reads from the in-tree environment during `body`. Access it like any stored property:

```swift
final class LocaleLabel: Component {
    @Environment(\.locale) var locale
    var body: VNode { p("Locale: \(locale)") }
}
```

**Important:** `@Environment` is only valid during `body`. If you need the value in `onAppear` or `onChange`, capture it into a stored property:

```swift
final class LocaleLabel: Component {
    @Environment(\.locale) var locale
    private var currentLocale = ""

    var body: VNode {
        currentLocale = locale   // capture during body
        return p(currentLocale)
    }

    override func onAppear() {
        print("Locale at mount: \(currentLocale)")
    }
}
```

---

## Overriding environment for a subtree

```swift
var body: VNode {
    div {
        withEnvironment(\.locale, "fr") {
            embed { Sidebar() }
        }
    }
}
```

For multiple overrides, nest calls:

```swift
withEnvironment(\.locale, "fr") {
    withEnvironment(\.colorScheme, .dark) {
        embed { Sidebar() }
    }
}
```

---

## Built-in keys

| Key | Type | Default |
|-----|------|---------|
| `\.locale` | `String` | `"en"` |
| `\.colorScheme` | `ColorScheme` | `.light` |

`ColorScheme` is `public enum ColorScheme { case light, dark }`.

---

## Adding a custom key

```swift
// 1. Declare a key type (file-private is fine)
private enum ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

// 2. Add a computed property to EnvironmentValues
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// 3. Read in a component
final class ThemedCard: Component {
    @Environment(\.theme) var theme
    var body: VNode { div(.attr("class", theme.cardClass)) }
}

// 4. Override for a subtree
withEnvironment(\.theme, Theme.dark) {
    embed { ThemedCard() }
}
```

---

## `onChange(of:)` — deps-aware lifecycle hook

Call from your `onChange()` override to react only when a specific value changes:

```swift
final class Counter: Component {
    @State var count = 0

    var body: VNode {
        button(.on("click") { self.count += 1 }) { text("\(count)") }
    }

    override func onChange() {
        onChange(of: count, key: "count") { newCount in
            print("Count changed to \(newCount)")
        }
    }
}
```

**Multiple watched values** require explicit `key:` strings:

```swift
override func onChange() {
    onChange(of: count, key: "count") { ... }
    onChange(of: label, key: "label") { ... }
}
```

The `key:` defaults to `#function`, which is the same string for every call site in the same method. Always supply explicit keys when watching more than one value.

The side table is cleared automatically when the component unmounts.

---

## Reading `@Environment` in lifecycle hooks

`@Environment` reads `AmbientEnvironment.current`, which the diff sets only
while a component's `body` is being evaluated. Reading `@Environment` from
`onAppear`, `onChange(of:)`, or `onDisappear` returns the **default value**
for the key, not the in-tree override.

To use an environment value in a lifecycle hook, capture it during `body`:

```swift
final class Greeter: Component {
    @Environment(\.locale) var locale
    private var capturedLocale = ""

    var body: VNode {
        capturedLocale = locale  // captured while body is running
        return p("Hello in \(capturedLocale)!")
    }

    func onAppear() {
        // Use capturedLocale, not locale directly.
        print("mounted with locale: \(capturedLocale)")
    }
}
```

`SwiflowRouter`'s `Link` component follows this exact pattern for
`router.navigate` — see [the router guide](router.md#why-capture-during-body).
