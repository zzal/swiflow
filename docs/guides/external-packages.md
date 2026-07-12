# Using external packages

A Swiflow app is an ordinary SwiftPM package — adding a third-party library
is the same `.package(url:)` line it would be anywhere else, with no
Swiflow-specific registry or tooling step. Whether the package then *works*
is decided by the wasm32 target, and you can check that up front. Nothing
in this guide is guessed: the numbers come from a six-package compatibility
survey plus a full integration spike wiring an actor-based state-machine
library ([SwiftXState](https://github.com/gistya/SwiftXState)) into a
component, both run in July 2026 against the Swift 6.3.2 wasm SDK.

## Adding a package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.6.0"),
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "SwiflowDOM", package: "Swiflow"),
            .product(name: "Collections", package: "swift-collections"),
        ]
    )
]
```

`swiflow dev` and `swiflow build` resolve and cross-compile it like any
other target. That's the whole mechanic — the rest of this guide is about
choosing packages that will build, and knowing what they cost.

## The three checks

Three properties of a package decide the outcome far more reliably than
its popularity or polish. All three are visible in its source before you
depend on it.

### 1. Does it import Foundation? — a ~41.5 MB cliff, paid once

On wasm there is no system Foundation: importing it links swift-foundation
plus ICU internationalization data into your binary. Measured against a
5.4 MB baseline app, three unrelated Foundation-importing libraries
(SwiftXState, swift-markdown, swift-crypto) each added **+41.5–41.6 MB of
optimized wasm (~18.5 MB over the wire, gzipped)** — regardless of how
much of the library was actually used (using more of SwiftXState after
linking it cost 7 KB).

Two things follow:

- **It's a cliff, not a slope.** The tax is a flat step function triggered
  by the first `import Foundation` anywhere in your dependency graph.
- **It's paid once.** Linking swift-markdown *and* swift-crypto together
  cost 43.4 MB, not 83 MB — they share one Foundation. If your app is
  already over the cliff, a second Foundation-coupled package is nearly
  free.

To check: search the package's non-Apple code path for
`import Foundation` (or `import FoundationEssentials`). ~18.5 MB gzipped
is workable for internal tools and dashboards; for a public-facing site it
is prohibitive today.

### 2. Does it link a *system* library? — won't build

The wasm sysroot contains no system libraries — no libsqlite3, no libcurl,
no system OpenSSL. A package that wraps one via a module map fails at
compile with a legible error. GRDB, for example:

```
Sources/GRDBSQLite/shim.h:1:10: error: 'sqlite3.h' file not found
error: could not build C module 'GRDBSQLite'
```

There is no app-side workaround. Look instead for packages that *bundle*
their C dependency as source (see "Non-issue" below), or move that concern
to the JS side of the boundary (a JS widget owning part of the page is
covered in [DOM interop](dom-interop.md)).

### 3. Do its platform guards know about wasm? — the wildcard

Swift packages branch on platform with `#if canImport(Darwin)` /
`canImport(Glibc)`. A package whose guards have no wasm branch fails to
compile even if everything else about it is fine. Yams 6.2.2:

```
Sources/Yams/Representer.swift:342:45: error: cannot find 'DBL_DECIMAL_DIG' in scope
```

`DBL_DECIMAL_DIG` comes from the platform's `<float.h>`, and Yams'
conditional imports cover Darwin and Glibc but not WASILibc. This is
usually a one-line upstream fix (`#elseif canImport(WASILibc)`) and worth
a PR to the package — but you cannot fix it from your app. To check: grep
the package for `canImport(Glibc)` and see whether a `WASILibc` (or
`wasm32`) sibling exists.

### Non-issue: bundled C source

C code compiled *from source* as part of the package is not a red flag.
The survey compiled two substantial C bodies clean under the wasm SDK on
the first try: BoringSSL (vendored by swift-crypto) and cmark-gfm (under
swift-markdown).

## What it costs — measured

Release builds (`swiflow build`: DWARF stripped + wasm-opt), each package
added to the same 5,412,425-byte baseline app and exercised with a live
API call. July 2026, latest stable versions at the time:

| package | outcome | added wasm (release) | app over the wire (gzip) |
|---|---|---|---|
| swift-collections 1.6.0 | builds | +776 KB | 2.2 MB |
| swift-algorithms 1.2.1 | builds | +424 KB | 2.1 MB |
| swift-markdown 0.8.0 | builds | +41.5 MB | 18.5 MB |
| swift-crypto 4.5.0 | builds | +41.6 MB | 18.5 MB |
| SwiftXState 1.1.0 | builds | +41.6 MB | 18.5 MB |
| Yams 6.2.2 | fails: no wasm import guard | — | — |
| GRDB 7.11.1 | fails: system sqlite3 | — | — |
| markdown + crypto + collections + algorithms together | builds | +43.4 MB | 19.1 MB |

Pure-Swift, Foundation-free packages land in the hundreds of kilobytes —
that half of the ecosystem is essentially open. The baseline app ships at
1.9 MB gzipped.

## Wiring a library into a component

Most libraries are plain synchronous Swift and need nothing special. The
interesting case is a library with its own concurrency — actors, async
streams, callback subscriptions. The SwiftXState spike is the worked
example; the same shape applies to any actor-based library.

**The one gotcha:** `@Component` isolates your class's *members* on the
main actor, but not the type itself — so the class is not `Sendable`, and
handing `self` to a library's `@Sendable` callback fails:

```
error: capture of 'self' with non-Sendable type 'ToggleDemo' in a '@Sendable' closure
```

The fix is one line — put an explicit `@MainActor` on the class:

```swift
import SwiftXState

@MainActor            // required: makes the class Sendable for the library's callback
@Component
final class ToggleDemo {
    @State var stateLabel = "starting…"
    private var machine: Actor<EmptyContext>?      // not @State: no re-render on set
    private var subscription: Subscription?

    var body: VNode {
        div {
            p("Machine state: \(stateLabel)")
            Button(stateLabel == "active" ? "Turn off" : "Turn on") {
                guard let machine = self.machine else { return }
                Task { await machine.send(Event("toggle")) }
            }
        }
    }

    func onAppear() {
        let actor = createActor(makeToggleMachine(),
                                options: ActorOptions(useMainExecutor: true))
        machine = actor
        Task {                                      // inherits @MainActor
            _ = await actor.start()
            self.subscription = await actor.subscribe { snapshot in
                let label = snapshot.matches("active") ? "active" : "inactive"
                Task { @MainActor in self.stateLabel = label }   // library → render hop
            }
        }
    }

    func onDisappear() {
        subscription?.cancel(); subscription = nil
        if let machine { Task { await machine.stop() } }
        machine = nil
    }
}
```

The pattern in three rules:

- **Own the library object's lifecycle in `onAppear`/`onDisappear`** —
  create and subscribe on mount, cancel and stop on unmount.
- **Hop onto the main actor before touching `@State`.** Library callbacks
  arrive on the library's execution context; `Task { @MainActor in ... }`
  moves the value onto the render actor, and the `@State` write re-renders
  as usual.
- **Keep the library object out of `@State`.** It isn't render state —
  storing it in a plain property avoids a pointless re-render when it's
  assigned.

This wiring is verified end-to-end in the browser: subscription fires on
mount, round-trips re-render correctly, and an actor configured with
`useMainExecutor: true` schedules fine on wasm's single-threaded event
loop.

## Checking what you shipped

After adding a package, release-build and look at the real artifact:

```sh
swiflow build
ls -l .build/plugins/PackageToJS/outputs/Package/App.wasm
gzip -9 -c .build/plugins/PackageToJS/outputs/Package/App.wasm | wc -c   # over-the-wire size
```

Measure after `swiflow build`, not `swiflow dev` — the dev server serves
an unoptimized build many times the release size.
