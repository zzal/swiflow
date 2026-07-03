# Swiflow

[![CI](https://github.com/zzal/swiflow/actions/workflows/ci.yml/badge.svg)](https://github.com/zzal/swiflow/actions/workflows/ci.yml)
![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)
![Platform: WebAssembly](https://img.shields.io/badge/platform-WebAssembly-lightgrey.svg)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

## Why Swiflow?

React was the right answer to a constraint that no longer holds.
WebAssembly lets the work move from runtime to compile time, and Swiflow is a bet
on what that makes possible — reactivity with no ceremony, a typed UI with no
template language, hot reload that keeps your state, and a batched bridge that
keeps it fast, with ergonomics bought from compile-time power that's structurally
hard to copy. 2026 is a fair time to ask whether the old defaults are still the
best we can do. Swiflow is one answer worth a look.

**[Why Swiflow exists — a case for re-questioning the defaults →](WHY.md)**

> Swiflow is an independent project, built and maintained by one person as a
hands-on exploration of Swift on the web. It's **pre-1.0 and experimental** —
see the [changelog](CHANGELOG.md) for where things stand.

## Highlights

- **State-preserving HMR** — `swiflow dev` hot-swaps the running WASM on every save; `@State` survives, the page never reloads.
- **Reactive components** — `@Component` + `@State`, with `onAppear` / `onChange` / `onDisappear` lifecycle hooks firing across the whole tree.
- **Typed event DSL & bindings** — `.on(.click) { … }`; two-way `.value($text)`, `.checked($flag)`, `.selection($choice)`.
- **CSS-in-Swift** — a `css { }` builder, scoped `<style>` per component, and exit animations.
- **Routing** — `SwiflowRouter`: hash + history mode, `RouterRoot` / `Route` / `Link`, `@Environment(\.router)`.
- **Data layer** — `SwiflowQuery`: declarative data fetching with caching, request dedup, and stale-while-revalidate.
- **Forms** — `FormController` / `Field` with blur-triggered validation.
- **UI kit** — `SwiflowUI`: accessible, token-driven components that adapt to dark mode / contrast / reduced motion with no component code.
- **Testing** — `SwiflowTesting` headless harness (`render` / `click` / `input`); deterministic async via `AsyncTestHarness`.
- **DevTools** — a read-only browser **DevTools panel** (Chrome side panel + Safari Web Inspector) that x-rays the live component tree and `@State`; sideload it from [`devtools/`](devtools/).
- **Safe by default** — `URLSanitizer` scrubs `javascript:` / `data:` / `blob:` URLs at the DSL fold; `rawHTML(_:)` is the loud escape hatch.

## A component

```swift
import Swiflow
import SwiflowDOM

@Component
final class Counter {
    @State var count = 0

    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment").on(.click) { self.count += 1 }
        }
    }
}

@main
struct App {
    @MainActor static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}
```

A `@State` mutation schedules a re-render; the diff turns the new tree into one
batched patch list and ships it across the bridge in a single crossing.

## Quick start

You need **Swift 6.3.2** and the **WebAssembly Swift SDK 6.3.2** — the SDK's
stdlib must match the host compiler exactly. Get the host toolchain first:

- **macOS (15.6+):** install **Xcode 26.2 or newer**, which bundles Swift 6.3.2.
  Don't reach for swiftly or a standalone swift.org toolchain here — their macOS
  builds omit the static stdlib, so compiling an app's macros fails to link.
- **Linux:** use [swiftly](https://www.swift.org/install/): `swiftly install 6.3.2`.

Note that swiftly installs the *toolchain*; the WebAssembly SDK is a separate
cross-compilation target, added with `swift sdk install` (step 1) on either OS.

```bash
# 1. Install the WASM SDK (once) — needed at build time, binary or source
swift sdk install \
  https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c

# 2. Install the swiflow CLI (prebuilt: macOS arm64 / Linux x86_64)
# 0.4.x is a beta (pre-release), so pin it explicitly — the plain installer
# resolves the latest *stable* release:
SWIFLOW_VERSION=0.4.2 sh -c "$(curl -fsSL https://raw.githubusercontent.com/zzal/swiflow/main/install.sh)"

# 3. Scaffold and run, with state-preserving hot reload on every save
swiflow init my-app
cd my-app && swiflow dev      # → http://localhost:3000
```

The installer detects your platform, verifies the download's checksum, and drops
the binary in `/usr/local/bin` (override with `SWIFLOW_INSTALL_DIR`). Without
`SWIFLOW_VERSION` it installs the latest **stable** release — GitHub's
`releases/latest` excludes pre-releases, which is why the beta above is pinned.
Prefer to build from source — or on an unlisted host like an Intel Mac? Skip step 2 and run `swift build -c release --product
swiflow`, then invoke the CLI from `./.build/release/swiflow`. Either way the
binary isn't fully standalone: it shells out to your Swift 6.3.2 toolchain and the
WASM SDK from step 1 to build your app.

Run `swiflow doctor` to verify your toolchain. Hacking on Swiflow itself? Add
`--swiflow-source $(pwd)` to `init` so the new project depends on your local clone
instead of a published release.

## The ecosystem

| Module | What it is |
| --- | --- |
| `Swiflow` | Pure-Swift VDOM core: `VNode`, the patch diff, `@State` / `@Component`, and the `@resultBuilder` DSL. |
| `SwiflowDOM` | WASM-only renderer + JavaScriptKit bridge. |
| `SwiflowRouter` | Hash- and history-mode routing. |
| `SwiflowQuery` | Async data layer — caching, dedup, stale-while-revalidate. |
| `SwiflowFetcher` | Thin `fetch` wrapper for requests from Swift. |
| `SwiflowStore` | Persisted app state (IndexedDB). |
| `SwiflowUI` | Token-driven, accessible component library. |
| `SwiflowTesting` | Headless test harness. |
| `swiflow` (CLI) | `init` scaffolds · `build` wraps `swift package js` · `dev` runs the HMR server. |

## Examples

Browse [`examples/`](examples/). These double as `swiflow init --template` starters:

- **HelloWorld** — the starter: a counter, SwiflowUI controls, a native `<dialog>`, a popover, and toasts.
- **SwiflowUIDemo** — a gallery of the SwiflowUI components and theming.
- **TodoCRUD** — list CRUD with bindings and forms.
- **QueryDemo** — `SwiflowQuery` fetching and caching.
- **MissionControl** — a larger app: routing, and geolocated data with `SwiflowStore` persistence.
- **EdgeCases** — a runtime/diff stress harness.

A few more exist for reading, not scaffolding: **MiniRouter** (`SwiflowRouter` in isolation), **AsyncFetch** (`.task` async effects in isolation), and **RegionDemo** (embedding foreign wasm). Serve any example with `swiflow dev` from its directory.

## Docs

Guides live in [`docs/guides/`](docs/guides/): [SwiflowUI](docs/guides/swiflowui.md) ·
[theming](docs/guides/swiflowui-theming.md) · [router](docs/guides/router.md) ·
[query](docs/guides/query.md) · [forms](docs/guides/forms.md) ·
[async tasks](docs/guides/async-tasks.md) · [testing](docs/guides/testing.md) ·
[styling](docs/guides/styling.md) · [environment](docs/guides/environment.md) ·
[DevTools](docs/guides/devtools.md) · [debugging WASM](docs/guides/debugging.md).

A read-only **DevTools panel** (live component tree + `@State`) lives in
[`devtools/`](devtools/) — a Chrome side panel (sideload via
`chrome://extensions` → *Load unpacked*) and a Safari Web Inspector build
([`devtools/safari/`](devtools/safari/) needs an Xcode conversion).

## Performance & costs

- **First visit:** ~1.8 MB gzipped WASM on the wire (a loading-percent overlay shows during the download) — comparable to a modest single-page app. Every PR enforces a bundle-size budget in CI.
- **Repeat visits:** ~0 bytes — a service worker caches the WASM + JS runtime by content hash until you rebuild.
- **Hot rebuild:** ~8 s WASM rebuild → HMR swap, with `@State` preserved.

Measured on an Apple M1 Max with Swift 6.3 / WASM SDK 6.3.2 — run the commands
locally to calibrate for your hardware.

## Testing

```bash
swift test                   # ~1,000 Swift tests, 200+ suites (e2e auto-skips without the WASM SDK)
(cd js-driver && npm test)   # 42 jsdom tests: driver, dev reload, service worker
```

Playwright e2e (counter, router, progress overlay, SW cache) lives in
[`Tests/playwright/`](Tests/playwright/) and is opt-in.

## Contributing & license

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under
**Apache 2.0** ([LICENSE](LICENSE)).
