# Why Swiflow exists — a case for re-questioning the defaults

## A fair question to ask in 2026

For a decade, building for the web was a settled matter. A JavaScript library —
React, then its many descendants — gave you a component model, declarative UI,
and a virtual DOM that turned your intentions into efficient updates. It was the
right answer. Not a fashion, not a mistake: given the constraints of its moment,
it was close to the best design anyone could have drawn.

But every great tool is shaped by a constraint, and this one's was fundamental:
**JavaScript was the only language the browser could run.** So all the cleverness
had to happen at *runtime* — state tracked by hooks as the app runs, your UI
written in a dialect the engine re-interprets every render, type safety (when you
reached for it) erased before a single line executes. Nobody *chose* that
ceremony. The constraint did.

That constraint is lifting. WebAssembly lets the browser run real compiled code,
which means the work no longer has to wait for runtime — it can move to *compile
time*, where a strong language and its compiler do it for you, once, and
correctly. The momentum of 2026 seems to be shifting toward tools that try to
turn that new freedom into better, faster results. Swiflow is one such bet — a
small one — on what you might build when the old constraint is gone.

## What the old default quietly asks you to accept

The JavaScript-library model is so familiar it reads as the nature of the web
rather than a set of choices made under pressure. Step back and the costs are
visible:

- **Ceremony around state** — setters, reducers, dependency arrays — so a
  runtime can track what changed on your behalf.
- **A UI described through indirection** — JSX or templates, `className` strings,
  DOM attributes that nothing fully checks — re-interpreted on every render.
- **Type safety that stops at the runtime's edge.** Even with TypeScript, the
  types erase before the browser runs; the seam where your UI meets the DOM
  stays dynamic, and that's where the Tuesday-afternoon bug lives.
- **State you lose on save**, because hot reload can't always hold onto it.
- **Accessibility and theming as per-component busywork** — dark mode, focus
  rings, contrast, re-implemented file after file.

None of this is anyone's fault. It was *optimal under the constraint*. The honest
question for 2026 is simply whether the constraint still holds — and it doesn't.

## What becomes possible when the work moves to compile time

Swiflow builds reactive frontends in **Swift**, compiled to **WebAssembly**. The
language choice isn't tribal; it's instrumental — Swift's compiler does three
things a browser runtime can't:

- **Macros** rewrite your code as it compiles, so `count += 1` *is* the state
  update. No setter, no reducer, no dependency array.
- **Result builders** make `div { … }` real, type-checked code — not a template,
  not JSX, not a string the engine re-parses.
- **A real type system** with no `any` to leak. If it compiles, the shapes line
  up — and you find that out at your desk, not from a user.

```swift
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
```

The whole counter. `count += 1` schedules the re-render; `div { }` is checked by
the compiler; there is no second file and no template language. The everyday wins
fall out of the same root:

- **Two-way binding without a change handler** — `input().value($text)`.
- **Hot reload that keeps your place** — `swiflow dev` hot-swaps the running app
  on every save with `@State` preserved; the page never reloads.
- **Accessible and adaptive for free** — the `SwiflowUI` kit is token-driven, so
  dark mode, contrast, reduced motion, and reduced transparency are handled by
  design tokens, not by branches you repeat in every component.
- **Safe by default** — `javascript:` / `data:` / `blob:` URLs are scrubbed where
  you build the node; `rawHTML(_:)` is the loud, opt-in exception.

## Fast by architecture, not by accident

There's a real reason "language X in the browser" usually disappoints: the DOM
lives in JavaScript-land, your compiled code lives in WASM-land, and **every DOM
change crosses a bridge** that costs something. Naively, a render touching a
thousand nodes pays that toll a thousand times.

Swiflow takes React's best idea — reconciliation — and re-engineers it for the
new substrate. On a state change it diffs the tree, collects *every* DOM mutation
into a single list, ships it across the bridge **once per render**, and a tight
JS loop replays it. One crossing, however much changed.

To be honest about where the speed is and isn't: for painting the DOM, the DOM is
the bottleneck — Swiflow won't out-render a well-tuned JS app there. The speed it
genuinely buys lives elsewhere — application *logic* runs as compiled WASM, the
compiler deletes whole classes of bug before they ship, and a compile-checked,
state-preserving dev loop is simply faster to iterate in. Better results, and
faster ones, just not from the place the marketing usually points.

## Why this one is hard to copy

In a field that churns through a framework a season, the fair worry is that this
is merely the next one. So it's worth knowing what sits underneath.

We costed out rebuilding Swiflow's ergonomics in a friendlier, TypeScript-shaped
language that also targets WASM (AssemblyScript). The finding *is* the point: the
two features that make Swiflow feel light to use — macro-driven `@State` and the
`div { }` builder — depend on compile-time macros and result builders, which
those languages don't have. Rebuild it there and you fall back to `count.value =
x` ceremony and `h("div", …)` hyperscript, or you sign up to maintain a fragile
whole-program compiler plugin to fake the feel. The state-preserving hot reload,
nearly free here, has to be reinvented by hand anywhere else.

So the niceness isn't a coat of paint a faster clone scrapes off next quarter.
It's **load-bearing** — bought with compile-time language power, and not cheap to
reproduce. That's not a boast about Swiflow so much as an observation about where
the ergonomics come from: the reason it's pleasant to use is the same reason it
would be a chore to clone.

## And no, it isn't Tokamak or Carton

Inside the Swift world the neighbors are easy to confuse. **Carton** /
`swift package js` is a build tool — compile and serve, nothing about the bridge.
**Tokamak / Elementary** are UI libraries — components, but you bring your own
dev loop, and each change tends to be its own bridge call. Swiflow is the
renderer *and* the tooling, designed together around the batched bridge:
**"Vite for Swift on the web,"** with the one trick neither neighbor has — a
single crossing per render.

## Where we honestly are

Swiflow is well past the counter demo: a VDOM core with batched patches and
`@State` reactivity, wrapped in routing (`SwiflowRouter`), data fetching with
caching and stale-while-revalidate (`SwiflowQuery`), persisted state
(`SwiflowStore`), a token-driven accessible UI kit (`SwiflowUI`), and a headless
test harness (`SwiflowTesting`) — real software with roughly a thousand tests
behind it.

It is also **pre-1.0 and experimental** — one person's hands-on exploration of
Swift on the web. The [README](README.md) and [CHANGELOG](CHANGELOG.md) track
where things actually stand, warts included. Today you can `swiflow init` a real
project, `swiflow dev` to compile-serve-hot-reload with `@State` preserved, write
a `@Component` that just works, and x-ray the live component tree from a
[DevTools panel](devtools/) with Swift DWARF symbols that point a trap back to
your own `.swift` line.

**TL;DR:** React was the right answer to a constraint that no longer holds.
WebAssembly lets the work move from runtime to compile time, and Swiflow is a bet
on what that makes possible — reactivity with no ceremony, a typed UI with no
template language, hot reload that keeps your state, and a batched bridge that
keeps it fast, with ergonomics bought from compile-time power that's structurally
hard to copy. 2026 is a fair time to ask whether the old defaults are still the
best we can do. Swiflow is one answer worth a look.
