# SwiflowStore — persistence

`SwiflowStore` persists app state to the browser's IndexedDB: asynchronous,
main-thread-friendly, and far roomier than `localStorage`'s ~5 MB string cap.
It ships two layers — the `@Persisted` property macro for component state
that should survive navigation *and* reload, and the `PersistentStore`
key/value class underneath it for imperative use.

## Installation

Add `SwiflowStore` to your app's `Package.swift`:

```swift
.executableTarget(
    name: "App",
    dependencies: [
        .product(name: "SwiflowDOM", package: "Swiflow"),
        .product(name: "SwiflowStore", package: "Swiflow"),
    ]
)
```

## @Persisted

Persistent reactive state, zero ritual. It behaves exactly like `@State` —
writes mark the component dirty and re-render, `$name` gives you a two-way
binding — and additionally hydrates from IndexedDB on mount and saves on
every write:

```swift
import Swiflow
import SwiflowStore

@Component
final class QuakesPage {
    @Persisted var magnitude: String = "2.5"
    @Persisted var window: String = "day"

    var body: VNode {
        Select("Magnitude", selection: $magnitude, options: ...)   // binds like @State
    }
}
```

That's the whole feature. No store instance, no key constants, no hydrate
task, no save handlers.

### Hydration semantics

- **The declared default paints first.** Hydration is asynchronous — the
  component renders immediately with its default, and re-renders when the
  stored value arrives (usually within the same frame). A missing key, or a
  stored value that no longer decodes as the declared type, keeps the
  default.
- **Hydration never writes back.** Restoring a stored value does not itself
  trigger a save — only your writes do.

### Keys

Keys auto-namespace by the owning component's type name, so two components
can both have a `filter` property without colliding:

```swift
@Persisted var magnitude: String = "2.5"     // stored as "QuakesPage.magnitude"
```

Pass an explicit key to share one value across components, or to keep
reading data an older version of your app stored:

```swift
@Persisted("legacy-window") var window: String = "day"   // stored as "legacy-window"
```

The explicit key must be a static string literal. Renaming a component (or
switching between bare and explicit keys) orphans the old entry — the value
resets to its default once.

### Requirements

Same rules as `@State` — a `var` with an explicit type annotation on a
`@Component final class` — plus the value type must be `Codable` (values
are stored as JSON). Save failures (e.g. storage quota) are silent; the
in-memory value is still correct for the session.

## PersistentStore

The imperative layer under `@Persisted` — reach for it when persistence
isn't tied to one component's property (bulk data, explicit lifecycle,
values shared across pages):

```swift
let store = PersistentStore()
try await store.save(pinnedCities, forKey: "pinned-cities")
let restored = try await store.load([City].self, forKey: "pinned-cities")   // nil if absent
try await store.remove(forKey: "pinned-cities")
```

### Typed keys

`StoreKey<Value>` declares the key name and value type together, so the
type can't drift between the save site and the load sites (with stringly
keys, every `load(SomeType.self, forKey:)` restates it, and a mismatch
reads as "nothing stored"):

```swift
static let pinnedKey = StoreKey<[City]>("pinned-cities")

try await store.save(pinned, for: Self.pinnedKey)
let restored = try await store.load(Self.pinnedKey)   // [City]? — inferred
try await store.remove(Self.pinnedKey)
```

### Notes

- Values are `Codable`, written as JSON.
- `load` returns `nil` for a missing key and throws `StoreError.decoding`
  if a stored value can't be decoded as the requested type.
- The database name defaults to the document title (your app's name shows
  up in the browser's storage inspector); pass `PersistentStore(database:store:)`
  to pin it — note a changed name starts a fresh, empty database.
- Multi-tab safe: if another tab upgrades or deletes the database, the
  store closes its connection (so the other tab isn't blocked) and reopens
  on the next operation; a dead connection surfaces as a thrown `StoreError`,
  never a crash. DEBUG builds log every failed IndexedDB request — useful
  since fire-and-forget saves usually `try?` them away.

On non-browser platforms (host tests, tooling) the API is present but inert:
`load` yields `nil`, writes are no-ops.
