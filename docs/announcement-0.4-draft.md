# Presenting Swiflow (beta) — a frontend stack for the web in Swift → WASM. It works for me; should it exist for you?

*Draft — adaptable for forums.swift.org (Related Projects), a blog post, or HN. Trim the "stack" list for shorter venues.*

---

The honest question first: **does the web need a Swift frontend stack?** The JavaScript ecosystem is excellent — you can ship a superb SPA today without leaving it, and "but it's Swift" is not, by itself, a reason for this project to exist.

Here's where I've landed after building with it: it works — for me. **Swiflow** is not a UI library; it's a batteries-included frontend stack for single-page apps, written in Swift 6 and compiled to WebAssembly. The bet it tests: WebAssembly moves the work from runtime to compile time, and that buys ergonomics that are structurally hard to get in JS. ([The longer argument →](https://github.com/zzal/swiflow/blob/main/WHY.md)) The bet has paid off in my own apps; what I don't know is whether it generalizes to *your* toolbox. Today I'm releasing **0.4.2** — the first version I'm comfortable asking other people to try. If your reaction is "this shouldn't exist, and here's why," I want that review — it just carries more weight after the code sample than before it.

```swift
@Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @ReducerState var toasts: ToastQueue

    var body: VNode {
        div(.class("card")) {
            h1("Hello, \(greeting)!")
            p("Count: \(count)")
            Button("Increment") { self.count += 1 }
            Button("Show toast", variant: .secondary) {
                self.$toasts.send(.show(ToastItem("Saved!", variant: .success)))
            }
            TextField("Greeting", text: $greeting)
        }
        ToastStack(queue: $toasts)
    }
}
```

Real scaffold code, not a cleaned-up slide. No `@MainActor` boilerplate (the macro injects it), no lifecycle wiring, no template file.

## The spine: a virtual-DOM machine in Swift

Everything in Swiflow hangs off one core: `body` renders a typed `VNode` tree in wasm; a keyed diff (the same LIS reconciliation strategy as Vue/Inferno) computes the minimal patch set; one batched bridge call applies it to the real DOM. Three things make it fast in practice:

- **Scoped re-render** — a `@State` change re-diffs only the owning component's subtree, not the app.
- **`.memoKey`** — an equal key skips a subtree's reconciliation entirely (this is how the virtualized table recycles rows).
- **The batched bridge** — Swift↔JS crossings are per frame, not per DOM mutation.

Net effect: a 2,000-row virtualized `DataTable` re-renders moderate scrolls in under a frame. Components, the query cache, the router — all of them are just clients of this machine.

## The stack around it

- **Reactivity** — `@Component` / `@State`; `@ReducerState` for wizard/queue-style client state (pure reducers, effects at the call site); environment, refs, `.task` effects.
- **SwiflowUI** — token-driven components (forms, overlays, virtualized `DataTable`, coalescing toasts). Components read `--sw-*` tokens and never branch on dark mode or reduced motion — token layers do. `swiflow theme` generates WCAG-validated palettes from a brand color at build time.
- **SwiflowQuery** — server-state caching: SWR, dedup, optimistic updates with generation-guarded rollback, invalidation, retry/backoff. The hairy interleavings are fuzz-tested plus gated deterministic races.
- **Router / Store / Fetcher** — hash & history routing, IndexedDB persistence, typed JSON-over-`fetch`.
- **Real CSS** — the `#css` macro validates actual CSS at compile time and scopes it per component.
- **The CLI** — `swiflow init` scaffolds a working app; `swiflow dev` hot-reloads **while preserving your `@State`** (edit a color five levels deep in a wizard, stay on step five); `swiflow doctor` checks your toolchain.

## The part I'd like you to be skeptical about

Before this release I audited the entire framework — all 11 modules, three passes (correctness, Swift API practice, leftover cruft), every serious finding independently re-verified. It found real bugs: a CSS scoping leak, two async races in the query cache, a wasm trap reachable from page scripts, macro failures on idiomatic Swift. All fixed in 0.4, and [the full report ships in the repo](https://github.com/zzal/swiflow/blob/main/docs/reviews/2026-07-01-pre-launch-audit.md). I'd rather you read what was wrong than take my word that it's right.

What "beta" means: the API was deliberately reviewed and reshaped for this release and I expect it to hold — but this is pre-1.0, single-maintainer software with approximately zero production users. Know the trade-offs: **browser-only** (no SSR story yet), wasm binaries are bigger than a JS bundle (`wasm-opt` helps; physics is physics), and the runtime is single-threaded by platform design. ~1,300 tests at roughly 1:1 test-to-source, CI on macOS and Linux — but *your* app will find things mine didn't. That's the point of a beta.

## Try it

Requires Swift 6.3.2 + the WebAssembly SDK (two commands, [see the README](https://github.com/zzal/swiflow#readme)). Then:

```sh
# 0.4.x is a beta (pre-release), so pin it explicitly:
SWIFLOW_VERSION=0.4.2 sh -c "$(curl -fsSL https://raw.githubusercontent.com/zzal/swiflow/main/install.sh)"

swiflow init my-app
cd my-app && swiflow dev      # → http://localhost:3000
```

- Repo: https://github.com/zzal/swiflow (Apache 2.0) · [Release notes](https://github.com/zzal/swiflow/releases/tag/v0.4.2) · [Guides](https://github.com/zzal/swiflow/tree/main/docs/guides) · [The audit report](https://github.com/zzal/swiflow/blob/main/docs/reviews/2026-07-01-pre-launch-audit.md)

Issues, API pushback, "this broke on my machine," and reasoned "this niche is already served" cases are all welcome — the point of a beta with an audit trail is to have those arguments *before* 1.0 freezes the surface. Thanks for reading.
