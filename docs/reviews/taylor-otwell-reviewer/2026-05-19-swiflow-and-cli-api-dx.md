# Swiflow API/DX Review — Taylor Otwell

**Date:** 2026-05-19
**Scope:** `Sources/Swiflow` (core framework) and `Sources/SwiflowCLI` (CLI surface)
**Reviewer:** taylor-otwell-reviewer agent (context id `a753a4ca5de833d60`)
**Focus:** Public API surface, naming, fluent interfaces, developer experience. Not internal implementation.

---

**First impressions.** The bones are good. The DSL has rhythm (`div { h1("Hello"); p("Count: \(count)") }`), the `@State` shape matches SwiftUI muscle memory, and the CLI surface (`init` / `build` / `dev`) is exactly the three verbs you want. But the **Hello World template** — the most important 30 lines in the whole project — drags the developer through `@unchecked Sendable`, `Swiflow.handlers.register { [weak self] _ in MainActor.assumeIsolated { … } }`, and a comment apologising for it. That's the headline DX problem. Everything else is polish.

## 1. Top 5 priorities

### 1. The Hello World handler is a horror show — `Templates.swift:107-128`

The first code a new user sees:

```swift
final class Counter: Component, @unchecked Sendable {
    @State var count: Int = 0
    var body: VNode {
        div(.class("container")) {
            h1("Hello, Swiflow!")
            p("Count: \(count)")
            button(
                "Increment",
                .on("click", Swiflow.handlers.register { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.count += 1
                    }
                })
            )
        }
    }
}
```

That `.on("click", Swiflow.handlers.register { [weak self] _ in MainActor.assumeIsolated { … } })` is the single line that decides whether a Swift developer falls in love or closes the tab. Six concepts (handler registry, escaping closure, weak self, MainActor, optional chain, ignored event) for *increment a counter*.

**Fix:** make `.on` accept a plain closure and absorb registration + actor isolation inside the framework. The registry is plumbing, not API.

```swift
button("Increment", .on(.click) { self.count += 1 })
```

`Swiflow.handlers` should be a `_`-prefixed internal symbol or removed from the public surface entirely. `[weak self]` is unnecessary because `Component` is owned by the mount tree, which is torn down before any captured `self` can outlive the handler. `MainActor.assumeIsolated` belongs in the dispatcher, not user code. `@unchecked Sendable` on `Counter` is then no longer needed — and that comment block disappears too.

If event-name strings are inevitable for forward-compat, at minimum ship `.click`, `.input`, `.submit` as enum cases so `"clik"` typos surface at compile time.

### 2. `component({ Counter() }, key: "a")` is the worst-named function in the framework — `ComponentDSL.swift:30`

```swift
component({ Counter() })           // unkeyed
component({ Counter() }, key: "a") // keyed
```

The lowercase `component`/uppercase `Component` collision is admitted in the doc comment, the factory has to be a closure, and the call site reads `component({ Counter() })` — two paired braces nested inside parens. That's not Swift; that's a riddle.

**Fix:** rename to `embed` (or `mount`, or just take a trailing closure on the existing factories), and drop the inner braces:

```swift
embed { Counter() }                 // unkeyed
embed("a") { Counter() }            // keyed
```

The function name carries the verb. The braces become trailing-closure sugar. The case collision evaporates. If you want to keep the noun, `node(Counter.self) { Counter() }` reads better than `component({ ... })`. A type-only overload would be ideal but Swift's generics make `component(Counter.self)` infer poorly with stateless inits — punt that.

### 3. `Attribute` cases feel like a config object, not a sentence — `Modifiers.swift:5`

```swift
div(.class("row"), .id("hero"), .style("padding", "1rem"), .on("click", handler)) { … }
```

The leading dots make this look like SwiftUI, but SwiftUI's modifiers chain *off the view* — `Text("Hi").padding().bold()`. Here they're crammed into a variadic argument list. The result reads sideways. Also, `.attr("data-foo", "x")` and `.prop("value", .string("hi"))` force the user to know the DOM-attribute-vs-property distinction (which most front-end devs don't think about until something breaks).

**Fix (low effort):** keep the variadic, but add `.attr` overloads that take `Int`, `Bool`, `Double` so callers don't manually stringify; add `.data("foo", "x")` for the `data-*` common case; and most importantly, **rename `.on` to take a typed `Event` enum** (see #1).

**Fix (higher ambition):** support post-fix chaining where it reads better — `p("Count: \(count)").class("muted")`. Then `Attribute` becomes the low-level primitive and the chained form is what users reach for. This is the SwiftUI mental model the README implicitly invokes.

### 4. `Swiflow.render(Counter(), into: "#app")` instantiates eagerly — `Templates.swift:134`, `SwiflowWeb.swift:64`

```swift
Swiflow.render(Counter(), into: "#app")
```

This passes a constructed instance, which mirrors what the README's "What's in the box" promises ("reactive class-bound components"). But `component { Counter() }` accepts a *factory* for the exact lifecycle reasons spelled out in `ComponentDescription`. Two entry points, two contracts. The root case happens to work because `render` only fires once, but a developer who reads both signatures will trip on the inconsistency the moment they try `Swiflow.render(MyApp(), into: ...)` and then refactor.

**Fix:** make the root accept the same factory shape, with a trailing closure:

```swift
Swiflow.render(into: "#app") { Counter() }
```

Reads left-to-right. Same mental model as `embed`. And `into:` belongs first because the closure naturally trails.

### 5. Lifecycle hook names mix tenses — `Component.swift:24-46`

`onMount`, `onUpdate(prev:)`, `onUnmount` — past-tense English ("mounted") expressed as imperative `mount`. That's fine on its own, but `prev: Self` as a parameter and the lengthy doc-block explaining existential-dispatch trampolines is a smell. 99% of `onUpdate` callers don't need `prev` — and the ones who do want a *snapshot of state*, not the same instance.

**Fix two things in priority order:**

- Drop the `prev: Self` parameter from the default protocol surface. Provide `onUpdate()` zero-arg; ship `onUpdate(prev:)` as an opt-in via a sibling protocol or @attached macro for the rare case. The 18-line doc comment about generic trampolines is a signal: if your defaulted method needs to explain how to call it, the API isn't done.
- Rename to match SwiftUI's verb-noun shape so muscle memory carries: `onAppear` / `onDisappear` instead of `onMount` / `onUnmount`. (SwiftUI users will reach for those names first; you'll catch every one of them.) Keep `onUpdate` as `onUpdate` — or rename to `onChange()` if state-change is the model.

```swift
public protocol Component: AnyObject {
    var body: VNode { get }
    func onAppear()
    func onChange()
    func onDisappear()
}
```

## 2. Smaller nits

- **`main_`** (`Elements.swift:223`) — ugly. Use `mainElement` or `mainTag`; the trailing underscore is the universal "I gave up" sigil.
- **`a(_ text: String, ...)`** (`Elements.swift:105`) — one-letter free function in the public namespace is a footgun (`let a = 1; a("hi")` confuses the type-checker and the human). Rename to `link`. Same for `p` → consider `paragraph` *only if* you don't lose the rhythm; I'd actually keep `p` for terseness, but `a` is worse because it's a noun-letter.
- **`PropertyValue.string("hi")`** for `.prop("value", ...)` — let `String`, `Bool`, `Int` adopt `ExpressibleByStringLiteral`/etc. so `.prop("value", "hi")` just works.
- **`HandlerRegistry.register(_:)`** is marked non-discardable for good reason but the public surface should not be touched by users at all once #1 lands. Mark `internal` or `_`-prefix.
- **`URLSanitizer.allowedSchemes`** as a global mutable `nonisolated(unsafe)` — fine for v1 but the name signals "settings bag." Wrap in `Swiflow.config.urlSanitizer.allowDataURLs = true` so the configuration surface has *one* address.
- **`swiflowDiagnostic`** — function-prefixed-with-the-module-name reads like `NSURL`-era Foundation. Just `assertSwiflow` or `swiftDebugFail`? Honestly: namespace it as `Swiflow.diagnose(...)`.
- **`applyAttributes(tag:_:children:)`** is `public` (`Modifiers.swift:59`) but nothing in user-space should ever call it. Make it `internal`. Public surface area is a liability.
- **`AnyComponent`** — exposing `typeID: ObjectIdentifier` and `instance: any Component` publicly invites users to poke at internals. Mark the *type* `public` but the fields `internal`. Same for `ComponentDescription`'s `factory` / `typeID`.
- **`buildBlock(_ components: [VNode]...)`** uses `components` as the parameter name — but a `component` is a *thing* in this framework. Rename to `children` to avoid the cross-talk: `buildBlock(_ children: [VNode]...)`.
- **`InProcessScheduler`** — the prefix `InProcess` makes a Swift dev think "out-of-process scheduler exists somewhere." It doesn't; the sibling is `RAFScheduler`. Rename `SyncScheduler` or `ImmediateScheduler`.
- **CLI `--path`** flag — three subcommands all take `--path` with identical semantics. Make it positional for `init` (`swiflow init <name> [parent-dir]`), positional-or-CWD for `build`/`dev`. Reduces the four-flag boilerplate in the README.
- **CLI error text** (`BuildCommand.swift:23`): "swift is not on PATH. Install Swift from https://swift.org/install" — good. But `"swift package js failed with exit code 1. See output above."` is a dead-end. Add a "Common causes" trailer for the common failures (missing WASM SDK product, mismatched Swift version).
- **`swiflow build` success message** prints `Serve: python3 -m http.server 3000` — but `swiflow dev` exists. Recommend `swiflow dev` first, mention `python3` only as a fallback.

## 3. What's working

- The **DSL element factories** read genuinely well. `div(.class("row")) { h1("Hi"); p("Body") }` is what a Swift developer wants. The text-only convenience overloads (`p("Count: \(count)")`) are the right shape and the right effort/payoff.
- **`@State`'s SwiftUI parity** — `@State var count = 0`, mutate, re-render — is exactly the muscle-memory hook this framework needs.
- **`URLSanitizer`** as a named, search-grep-able audit symbol with `.rawHTML` as the loud escape hatch is the kind of security ergonomics most frameworks don't bother with. Keep that.
- **The CLI verb set** — `init`, `build`, `dev` — is canonical and uncluttered. Help text is terse and useful.
- **`ChildrenBuilder`'s `for`-loop support** (`buildArray`) — quietly important; lots of result-builders forget this, and it would have made keyed lists awkward.

## Priority order

1. **Fix Hello World** — collapse `.on("click", Swiflow.handlers.register { … MainActor.assumeIsolated { … } })` to `.on(.click) { … }`. Until that line is one-liner-elegant, nothing else matters.
2. **Rename `component({ … })`** to `embed { … }` (or take a trailing closure). The current shape will be cited in every "Swiflow vs SwiftUI" comparison post.
3. **Align `Swiflow.render`** with the factory pattern: `Swiflow.render(into: "#app") { Counter() }`.
4. **Lifecycle hooks**: drop `prev: Self`, rename to `onAppear`/`onDisappear`.
5. **Audit the public surface**: `HandlerRegistry`, `applyAttributes`, `AnyComponent`'s fields, `ComponentDescription`'s fields — most should not be `public`.

Everything in §2 is polish that can land in a single tasteful afternoon once §1–§5 are settled.
