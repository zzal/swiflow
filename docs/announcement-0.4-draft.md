# Swiflow 0.4 (beta) — a Swift frontend stack for the web. It works for me; should it exist for you?

*Draft — adaptable for forums.swift.org (Related Projects), a blog post, or HN. Trim the "What's in the box" list for shorter venues.*

---

Let me open with the honest question instead of the pitch: **does the web need a Swift frontend stack?** The JavaScript ecosystem is excellent and I'm not here to pretend otherwise — you can ship a superb SPA today without ever leaving it, and "but it's Swift" is not, by itself, a reason for this project to exist.

Here's where I've landed after building with it: it works — for me. **Swiflow** is not a UI library; it's a batteries-included frontend stack for single-page apps, written in Swift 6 and compiled to WebAssembly: components and reactivity, server-state caching, routing, persistence, theming, forms, and a CLI with state-preserving hot reload — one coherent, strictly-concurrent ecosystem instead of five npm packages and a config file. It's built on one specific bet: WebAssembly lets the work move from runtime to compile time, and that buys ergonomics that are structurally hard to get in JS — reactivity with no ceremony, a typed UI with no template language, a batched DOM bridge that keeps it fast. ([The longer version of the argument →](https://github.com/zzal/swiflow/blob/main/WHY.md))

That bet has paid off in my own apps. What I don't know yet is whether it generalizes — whether it earns a place in *your* toolbox against defaults this entrenched. Today I'm releasing **0.4.1**, the first version I'm comfortable asking other people to try — a beta, in the sense I'll spell out below. If your reaction after reading is "this shouldn't exist, and here's why," that's a review I want — it just carries more weight after the code sample than before it.

Here's what a component looks like — this is real code from the scaffold, not a cleaned-up slide:

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

No `@MainActor` boilerplate (the macro injects it), no lifecycle wiring, no template file. `@State` changes re-render just that component's subtree — the diff engine is scoped, keyed, and memoizable, and a 2,000-row virtualized table re-renders moderate scrolls in under a frame.

## What's in the box

The "stack, not a library" claim, itemized:

- **Reactivity** — `@Component` / `@State` macros; `@ReducerState` for wizard/queue-style client state (pure reducers, effects at the call site); an environment system; refs; `.task` async effects.
- **SwiflowUI** — a token-driven component library (buttons, form controls, overlays, a virtualized `DataTable`, toasts with cap/overflow/coalescing). Theming is media-feature-first: components read `--sw-*` CSS tokens and never branch on dark mode or reduced motion — the token layers do. A build-time `swiflow theme` command generates WCAG-validated palettes from a brand color.
- **SwiflowQuery** — server-state caching with SWR, request dedup, optimistic updates with generation-guarded rollback, invalidation, and retry/backoff. The hairy interleavings are covered by a seeded fuzz suite plus deterministic race gates.
- **Router, Store, Fetcher** — hash/history routing, an IndexedDB-backed persistent store, and a typed JSON-over-`fetch` client.
- **Real CSS** — the `#css` macro validates actual CSS at compile time and scopes it per component; no CSS-in-Swift DSL to learn (though a small typed builder exists if you prefer one).
- **A CLI worth using** — `swiflow init` scaffolds a working app; `swiflow dev` gives you **hot reload that preserves your `@State`** across file saves — edit a color while five levels deep in a wizard and stay on step five; `swiflow doctor` diagnoses your toolchain.

## The part I'd like you to be skeptical about

A framework announcement is easy to inflate, so here is the honest version.

**Before this release I audited the entire framework** — all 11 modules, three passes (correctness, Swift API practice, and leftover cruft), every serious finding independently re-verified. The audit found real bugs: a CSS scoping leak, two async races in the query cache, a wasm trap reachable from page scripts, macro failures on idiomatic Swift. All of them are fixed in 0.4, and [the full report ships in the repo](https://github.com/zzal/swiflow/blob/main/docs/reviews/2026-07-01-pre-launch-audit.md) — findings, severities, and the fix ledger. I'd rather you read what was wrong than take my word that it's right.

**What "beta" means here:** the public API was deliberately reviewed and reshaped for this release, and I expect it to hold — but this is pre-1.0, single-maintainer software with (as of today) approximately zero production users. You should also know the structural trade-offs before investing: it's **browser-only** (no SSR story yet), wasm binaries are bigger than a JS bundle (the CLI runs `wasm-opt`, but physics is physics), and the runtime is single-threaded by platform design. The test suite is ~1,300 tests at roughly 1:1 test-to-source, and CI covers macOS and Linux — but *your* app will find things mine didn't. That's rather the point of a beta.

## Try it

Requires Swift 6.3.2 + the WebAssembly SDK (two commands, [see the README](https://github.com/zzal/swiflow#readme)). Then:

```sh
# 0.4.x is a beta (pre-release), so pin it explicitly:
SWIFLOW_VERSION=0.4.1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/zzal/swiflow/main/install.sh)"

swiflow init my-app
cd my-app && swiflow dev      # → http://localhost:3000
```

- Repo: https://github.com/zzal/swiflow (Apache 2.0)
- Release notes: https://github.com/zzal/swiflow/releases/tag/v0.4.1
- Guides: components, theming, query, router, forms, testing — in [`docs/guides/`](https://github.com/zzal/swiflow/tree/main/docs/guides)
- The audit report: [`docs/reviews/2026-07-01-pre-launch-audit.md`](https://github.com/zzal/swiflow/blob/main/docs/reviews/2026-07-01-pre-launch-audit.md)

I'd genuinely value issues, API pushback, "this broke on my machine" reports — and, per the opening question, reasoned cases that this niche is already served and Swiflow shouldn't exist. The whole point of a beta with an audit trail is to have those arguments *before* 1.0 freezes the surface, while changing course is still cheap. Thanks for reading.
