# Reducer-native Toast (`ToastQueue`) — Design

**Goal:** Ship a public, opinionated Toast **queue** in SwiflowUI, built on the `@ReducerState`/`Reducer` primitive (roadmap B4 follow-up). It enforces a max-visible cap with FIFO overflow and **coalesces duplicate toasts into a single entry with a recurrence count** — invariants a plain app-owned `[ToastItem]` array can't express. Secondary purpose: **dogfood `@ReducerState` on a real shipped component** and surface its ergonomics.

**Honest scope note.** `@ReducerState` is **local per-component**. Both demos already hold their toast array at the App root, and a `@ReducerState var toasts: ToastQueue` at that same root has the *same* reach — children still receive `$toasts.send`, exactly as they receive the array/binding today. This refactor does **not** make toasts fireable from anywhere (that needs the deferred global store). Its real payoffs are: named actions, enforced cap/overflow/coalesce invariants in one pure place, and validation of `@ReducerState`.

**Decisions (locked in brainstorming):**
- Ship `ToastQueue: Reducer` as **public SwiflowUI API** (not demo-only), plus a `ToastStack(queue:)` overload.
- Queue semantics: **cap (`maxVisible`, default 3) + FIFO overflow + coalesce-with-count**.
- Dedup identity = **message + variant** (a success "Saved" ≠ an error "Saved").
- Recurrence does **not** reset the auto-dismiss timer (v1) — the count accumulates while the toast is alive; deferring "stay-alive-on-recurrence" (it risks a spammy toast never leaving).
- **Deprecate** the existing `ToastStack(toasts: Binding<[ToastItem]>)` (keep it functional) and **migrate both demos** (HelloWorld + SwiflowUIDemo) to the reducer.

---

## Architecture & files

- **New `Sources/SwiflowUI/ToastQueue.swift`** — `ToastQueue: Reducer` + the `ToastStack(queue:)` overload.
- **`Sources/SwiflowUI/Toast.swift`** (existing) — keeps `ToastItem`/`ToastVariant`/`ToastPlacement`/`ToastView`/styles; gains `ToastItem.count`/`dedupKey`, a `×N` count badge in `ToastView`, and the `@available(deprecated)` on `ToastStack(toasts:)`.

`ToastQueue` lives in SwiflowUI, which imports `Swiflow` (home of `Reducer`/`ReducerHandle`/`@ReducerState`). Apps write `@ReducerState var toasts: ToastQueue` in their own `@Component`. Reducer State has no `Equatable`/`Sendable` requirement; `Reducer.reduce` is `@MainActor`, so mutating the `@MainActor struct ToastItem` inside it is fine — no `ToastItem` isolation change.

---

## 1. `ToastItem` changes (`Toast.swift`)

Add a recurrence count and a dedup key. `count` is module-settable (the reducer bumps it) but publicly readable (the view renders it):

```swift
@MainActor
public struct ToastItem {
    public let id: String
    public let message: String
    public let variant: ToastVariant
    public let duration: Double
    public internal(set) var count: Int = 1   // recurrences; 1 = shown once

    public init(_ message: String, variant: ToastVariant = .info, duration: Double = 4) { ... } // unchanged; count defaults to 1

    /// Two toasts coalesce iff same message + variant.
    var dedupKey: String { "\(variant.modifierClass)|\(message)" }
}
```
`init` is unchanged (apps never pass `count`; it starts at 1). `count` is a `var` (was all-`let`) — the reducer mutates it in place inside `State`.

## 2. `ToastQueue: Reducer` (`ToastQueue.swift`)

Pure, synchronous, total — no timers, no I/O:

```swift
public struct ToastQueue: Reducer {
    public struct State {
        public var visible: [ToastItem] = []   // rendered, count ≤ maxVisible
        public var pending: [ToastItem] = []   // FIFO overflow, not rendered
        public init() {}
    }
    public enum Action {
        case show(ToastItem)
        case dismiss(String)   // by id
        case dismissAll
    }
    let maxVisible: Int
    public init(maxVisible: Int = 3) { self.maxVisible = maxVisible }
    public var initialState: State { .init() }

    public func reduce(into s: inout State, _ action: Action) {
        switch action {
        case .show(let item):
            // Coalesce first — a duplicate never consumes a slot.
            if let i = s.visible.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
                s.visible[i].count += 1
            } else if let j = s.pending.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
                s.pending[j].count += 1
            } else if s.visible.count < maxVisible {
                s.visible.append(item)
            } else {
                s.pending.append(item)
            }
        case .dismiss(let id):
            s.visible.removeAll { $0.id == id }
            s.pending.removeAll { $0.id == id }   // robust: also covers a pending id
            refill(&s)
        case .dismissAll:
            s.visible.removeAll(); s.pending.removeAll()
        }
    }

    /// Invariant restorer: promote pending → visible (FIFO) until full or drained.
    private func refill(_ s: inout State) {
        while s.visible.count < maxVisible, !s.pending.isEmpty {
            s.visible.append(s.pending.removeFirst())
        }
    }
}
```

**Cap default via synthesized init.** `@ReducerState var toasts: ToastQueue` → the `@Component` macro synthesizes `self.toasts = ToastQueue()` (default `maxVisible: 3`). An app wanting a different cap writes its own `init` and assigns `ToastQueue(maxVisible: 5)` — consistent with `@MutationState` default-construction.

## 3. `ToastStack(queue:)` overload + live count (`ToastQueue.swift`)

A stateless free function (matches the existing SwiflowUI control convention). Renders **only `visible`**; each toast keyed by id; dismiss dispatches to the reducer:

```swift
@MainActor
public func ToastStack(queue: ReducerHandle<ToastQueue>,
                       placement: ToastPlacement = .bottomTrailing) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-toast", toastStyleSheet)
    let children = queue.state.visible.map { item in
        embed(item.id) {
            ToastView(item: item,
                      recurrences: { queue.state.visible.first { $0.id == item.id }?.count ?? 1 },
                      onDismiss: { queue.send(.dismiss(item.id)) })
        }
    }
    return element("div",
                   attributes: [.class("sw-toast-stack sw-toast-stack--\(placement.modifierClass)")],
                   children: children)
}
```

**Why the `recurrences` closure (the one non-obvious bit).** `ToastView` is a **keyed `embed`**, so its factory runs once and `item` freezes at mount (`count == 1`); a later count bump in `State` won't reach the frozen view. Re-keying to force a refresh would unmount/remount → a jarring slide-out/in on every recurrence. Instead the count is fed **live** via a closure (mirroring how the existing `onDismiss` reads live): when a dup arrives → reducer bumps count → the App (owner of `@ReducerState`) is marked dirty → re-renders → `ToastView.body` re-runs → `recurrences()` reads the fresh count → the `×N` badge updates **in place**, no remount. (The reducer's `send` marks the App dirty via the standard scheduler path; scoped re-render keeps it to the App subtree.)

## 4. `ToastView` changes (`Toast.swift`)

- New init param `recurrences: @escaping () -> Int` (stored; read in `body`).
- Render a small count badge only when `recurrences() > 1`:
  ```swift
  // inside the toast, before/after the message span:
  // if recurrences() > 1 { element("span", [.class("sw-toast__count")], [text("×\(recurrences())")]) }
  ```
- **A11y:** since the visible message text doesn't change on a bump, set the toast's `aria-label` to include the count when > 1 (e.g. `"Saved (3 times)"`) so screen-reader users hear the recurrence.
- New `.sw-toast__count` style — a tiny discrete pill (token-driven; reads `--sw-*`). No timer/lifecycle change; `reschedule`/`onAppear`/`onDisappear`/`exitAnimation` are untouched.

## 5. Deprecation + demo migration

- `ToastStack(toasts: Binding<[ToastItem]>)` gains `@available(*, deprecated, message: "Use ToastStack(queue:) with @ReducerState var toasts: ToastQueue")`. Body + internal `removeToast(_:from:)` stay functional. With both demos migrated, no in-repo call site remains → no deprecation warnings in the build.
- **HelloWorld** (`examples/HelloWorld/Sources/App/App.swift`): `@State var toasts: [ToastItem] = []` → `@ReducerState var toasts: ToastQueue`; the "Show toast" firing → `self.$toasts.send(.show(ToastItem("Saved!", variant: .success)))`; `ToastStack(toasts: $toasts)` → `ToastStack(queue: $toasts)`.
- **SwiflowUIDemo** (`examples/SwiflowUIDemo/Sources/App/App.swift`): same migration for all fire sites (buttons, dropdown items, table-row); add a **"Clear all"** button (`self.$toasts.send(.dismissAll)`) to dogfood `.dismissAll`; the existing duplicate-variant buttons now demonstrate the `×N` coalesce badge (fire the same button repeatedly).
- Regenerate `Sources/SwiflowCLI/EmbeddedTemplates.swift` (both demos are embedded templates) via `swift scripts/embed-templates.swift`.

---

## Testing

- **Pure reducer unit tests (host — the headline win), no DOM:**
  - show under cap → in `visible`; show over cap → in `pending`.
  - dismiss a visible id with pending present → FIFO-promotes the pending head into `visible`.
  - dismiss with empty pending → `visible` just shrinks.
  - `dismissAll` → both cleared.
  - dismiss unknown id → no-op; survivor order preserved.
  - **coalesce:** same message+variant while visible → that item's `count == 2`, `visible.count` unchanged, no new entry; same while only in pending → the pending item's count bumps; same message + *different* variant → two distinct toasts; a 3rd dup → `count == 3`.
- **`ToastStack(queue:)` render test (VNode-level):** renders exactly `state.visible` (not `pending`), keyed by id; the dismiss handler is wired to `.dismiss(id)`; the `.sw-toast__count` badge node is present iff `recurrences() > 1`.
- **Host build + wasm build** of both migrated demos (`swiflow build --path examples/HelloWorld` and `.../SwiflowUIDemo`); revert the build-rewritten `swiflow-driver.js`/`swiflow-service-worker.js` before committing.
- **Required in-browser verification** (a unit test can't cover the live-count-through-frozen-embed reactivity): run the SwiflowUIDemo dev server and confirm:
  1. Firing the same toast 5× shows **one** toast whose badge updates `×2…×5` **in place** (no remount flicker).
  2. Firing 5 distinct toasts shows **3**; dismissing one promotes the 4th (FIFO).
  3. "Clear all" empties the stack.
  A formal Playwright spec is an optional follow-up; the reducer units + this in-browser check are the acceptance gate.

## Acceptance criteria

1. `ToastQueue: Reducer` (public) enforces cap `maxVisible` (default 3), FIFO overflow, and message+variant coalescing with a recurrence `count`; all covered by pure host unit tests.
2. `ToastStack(queue: ReducerHandle<ToastQueue>)` renders only visible toasts, dismiss dispatches `.dismiss(id)`, and a `×N` badge shows in place on recurrence with no remount.
3. `ToastStack(toasts:)` is deprecated (still compiles/works); both demos migrated to the reducer; `EmbeddedTemplates.swift` regenerated.
4. `swift build` + `swift test` green; both demos build to wasm; the in-browser cap/overflow/coalesce behavior is verified.

## Out of scope

- Global/shared toast store, "fire from anywhere" without threading `$toasts` (needs the deferred global store).
- Resetting the auto-dismiss timer on recurrence ("stay alive while recurring").
- A formal Playwright spec for SwiflowUIDemo (optional follow-up).
- Any change to `ToastView`'s timer/animation model, or to `@ReducerState`/`Reducer` themselves.
