# Async Task Effects

Phase 20 adds first-class async effects to Swiflow components. Two postfix
`VNode` modifiers declare lifecycle-bound async work:

- `.task { … }` — runs once when the decorated node mounts; cancels on unmount.
- `.task(rerunOn: someEquatable) { … }` — runs on mount; cancels and restarts
  whenever `rerunOn` changes between renders; cancels on unmount.

The closure type is `TaskBody = @MainActor @Sendable () async -> Void` —
non-throwing, runs on the main actor.

> **Browser prerequisite.** `Swiflow.render(into:)` installs
> `JavaScriptEventLoop.installGlobalExecutor()` once before the first
> render. Without the global executor, `Task`/`await` silently hang in the
> browser even though they work in host-Swift tests. No action required — the
> wiring is automatic.

## Canonical example

Below is the central pattern: a component that fetches a user profile whenever
`userID` changes, holding the result in a simple `Loadable` enum.

```swift
import SwiflowDOM

enum Loadable<T>: Equatable where T: Equatable {
    case idle, loading, success(T), failure(String)
}

@Component
final class ProfileCard {
    @State var userID: Int
    @State var user: Loadable<String> = .idle

    init(userID: Int) { self.userID = userID }

    var body: VNode {
        div {
            switch user {
            case .idle:              p("–")
            case .loading:           p("Loading…")
            case .success(let name): p(name)
            case .failure(let msg):  p("Error: \(msg)", .class("error"))
            }
        }
        .task(rerunOn: userID) {
            user = .loading
            do {
                user = .success(try await fetchUser(userID))
            } catch {
                user = .failure(error.localizedDescription)
            }
        }
    }
}
```

Notice that the call site carries **only the domain `do/catch`** — no
`guard !Task.isCancelled`, no `catch is CancellationError`. The runtime drops
writes from superseded or dead tasks before they reach `@State` storage.
That correctness is in the bedrock, not at every call site.

See `examples/AsyncFetch/` for a runnable demo.

## Lifecycle and restart semantics

Tasks ride the diff's existing node create / update / remove signals — the same
path `.on(.click)` event handlers already use.

| Event | `.task { }` | `.task(rerunOn: v) { }` |
|---|---|---|
| Node mounts | Start | Start |
| Node re-renders, `v` unchanged | Leave running | Leave running |
| Node re-renders, `v` changed (`!=`) | — | Cancel + start fresh |
| Node unmounts | Cancel | Cancel |

**Bare `.task { }` never restarts.** It is for setup that depends only on the
component's presence — subscribing to a notification, starting a timer loop,
connecting a WebSocket.

**`rerunOn:` fires on `!=`.** The comparison is type-checked and synthesized
(not an untyped `Object.is`). This is the same Equatable-keyed, fire-on-change
contract as `onChange(of:perform:)` in
`Sources/Swiflow/Reactivity/OnChangeStorage.swift`. The two live in the same
family: one for synchronous post-render side effects, one for async effects.

## Purity — the closure is not executed during render

The `.task` closure is *declared* inside `body`, but it is not called there.
`body` evaluates synchronously and returns a `VNode` tree; the diff collects
any `.task` closures attached to element nodes; the runtime then spawns them on
the main actor, outside the render cycle.

This keeps `body` synchronous and side-effect-free — the Swift requirement for
a render function. The task closure is the *intentionally effectful* async
site: it runs after the render is committed to the DOM, has access to current
`self` state, and may perform any `await`-based work.

## The write-guard guarantee

**Stale writes are dropped automatically.** The runtime stamps each task with a
`@TaskLocal` token carrying a `(slotID, generation)` pair. Every `@State`
write checks this token at the mutation point. If the token's generation no
longer matches the slot's live generation — because the task was superseded by
a `rerunOn` change, or the owning node was unmounted — the write is reverted
to the prior value and `markDirty` does not fire. Neither stale state nor a
stale re-render can reach the component.

The practical consequence: a `CancellationError` or any other error that
arrives inside a cancelled task's `do/catch` would set `.failure(…)`, but that
write itself is dropped by the guard. **You do not need to special-case
cancellation.** Write only the domain success/failure mapping:

```swift
.task(rerunOn: query) {
    results = .loading
    do {
        results = .success(try await search(query))
    } catch {
        results = .failure(error.localizedDescription)
    }
}
```

If a new `query` arrives while this task is mid-flight, the old task is
cancelled, a new task starts, and the old task's eventual `.failure` write is
silently discarded by the runtime. The user sees the new task's result, not the
old one's error.

## Dependencies (`rerunOn:`)

`rerunOn:` is an **explicit re-run trigger**, not an exhaustive dependency
audit. The distinction matters:

- React's `useEffect(fn, [a, b])` requires you to list every value the closure
  reads; a linter enforces this and violations cause stale closures.
- `.task(rerunOn: v)` lists only what should *cause* a re-run. The closure
  reads current `self` values freely; only `v` decides restarts.

The honest trade-off: if the closure's result depends on a value you did not
put in `rerunOn:`, it will not re-run when that value changes. This is your
explicit choice, not a silently-wrong lint situation.

**One dependency** — any `Equatable` works:

```swift
.task(rerunOn: userID) { … }      // Int
.task(rerunOn: searchQuery) { … } // String
.task(rerunOn: sortOrder) { … }   // an enum
```

**Several dependencies** — compose into one `Equatable` value. The recommended
idiom is a struct key with synthesized `Equatable`:

```swift
struct FeedKey: Equatable {
    let userID: Int
    let page: Int
    let filter: FeedFilter
}

.task(rerunOn: FeedKey(userID: userID, page: page, filter: filter)) { … }
```

A struct key is type-safe, self-documenting, and foreshadows the future query
library where the dependency *is* a query key.

An **array** works for the homogeneous case:

```swift
.task(rerunOn: [categoryID, subcategoryID]) { … }  // [Int] conforms to Equatable
```

A raw **tuple does not work**. Tuples cannot conform to `Equatable` in Swift
even though `==` exists for small arities. Use a struct instead.

A variadic-generic form (`.task(rerunOn: a, b, c) { }`) is a possible future
addition; v1 ships the single-`Dependency` signature, which struct and array
already cover for all practical cases.

## The stable-slot rule

Multiple `.task`s may decorate one node and are identified by declaration
order on that node. The number of `.task`s on a given node **must not change
between renders** — conditional presence causes slot-index drift, which would
silently mis-identify which task to restart. This is the same constraint event
handlers and attributes carry.

In DEBUG builds, `swiflowDiagnostic` fires when a node's `.task` count changes
between renders. The diagnostic is compiled out of release builds. Guard your
component structure so the count is always the same:

```swift
// Good — one task, always present.
div { … }
    .task(rerunOn: mode) {
        if mode == .active { … } else { /* nothing */ }
    }

// Bad — varying task count.
var body: VNode {
    if condition {
        div { … }.task { … }        // sometimes 1 task
    } else {
        div { … }                   // sometimes 0 tasks
    }
}
```

The right fix is to keep the `.task` constant and put the condition inside the
closure.

## Testing async tasks

Use `AsyncTestHarness` from `SwiflowTesting` for deterministic async test
coverage. `settle()` drives all in-flight tasks to completion and flushes the
resulting re-renders in a loop until the component reaches a fixed point.

```swift
import Testing
import Swiflow
import SwiflowTesting

@Component
private final class Profile {
    @State var userID: Int
    let fetch: @Sendable (Int) async -> String
    @State var state: Loadable<String> = .idle

    init(userID: Int, fetch: @escaping @Sendable (Int) async -> String) {
        self.userID = userID
        self.fetch = fetch
    }

    var body: VNode {
        div { … }
            .task(rerunOn: userID) {
                state = .loading
                let name = await fetch(userID)
                state = .success(name)
            }
    }
}

@Suite("Profile")
@MainActor
struct ProfileTests {

    @Test func fetchDisplaysName() async throws {
        let h = AsyncTestHarness(Profile(userID: 1) { id in "User#\(id)" })
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }

    @Test func changingIDRefetches() async throws {
        let vm = Profile(userID: 1) { id in "User#\(id)" }
        let h = AsyncTestHarness(vm)
        try await h.settle()                // task A completes
        #expect(h.allText.contains("User#1"))

        vm.userID = 2                        // change the dependency
        h.flush()                            // reconcile: cancel A, start B
        try await h.settle()                 // task B completes
        #expect(h.allText.contains("User#2"))
    }
}
```

`settle()` loops:
1. Await all currently in-flight `Task` handles.
2. Flush the scheduler synchronously (apply any `@State` writes those tasks
   produced).
3. If a flush triggered a `rerunOn` change, new tasks are spawned — loop again.
4. Stop when no task is in flight and no component is dirty.

`flush()` applies a synchronous `@State` mutation (made directly from test
code) before `settle()` so the diff has a chance to reconcile the new
dependency and spawn the next task:

```swift
vm.userID = 2   // mutate from test code
h.flush()       // reconcile renders the new body, sees rerunOn changed, starts task B
try await h.settle()
```

`settle()` throws `AsyncTestHarness.SettleError` if it cannot reach a fixed
point within `maxRounds` (default 100). A component whose task always changes
its own `rerunOn` dependency hits the cap and surfaces as a clear test failure
rather than a hang.

The full worked suite is `Tests/SwiflowTestingTests/AsyncTaskTests.swift`.

### Test isolation

Each `AsyncTestHarness` owns its render root's `TaskScope`, so `settle()` awaits
only *its own* tasks. Suites are isolated from one another even under parallel
`swift test`, with no global state to reset — just build a harness per test:

```swift
@Suite @MainActor
struct MyAsyncTests {
    @Test func loads() async throws {
        let h = AsyncTestHarness(MyComponent())
        try await h.settle()
        #expect(h.allText.contains("…"))
    }
}
```

Do **not** call `SwiflowTaskRuntime._resetForTesting()` from a suite `init()`:
it clears the process-global generation map, which would race a concurrently
running suite. Isolation comes from per-harness scopes, not global resets.

## Example

`examples/AsyncFetch/` contains a minimal runnable demo: a component that
loads a simulated user on mount and re-fetches on each "Load next user" button
click by bumping the `userID` dependency. Run it with `swiflow dev` from the
example directory.
