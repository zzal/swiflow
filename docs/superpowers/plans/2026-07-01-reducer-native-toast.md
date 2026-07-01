# Reducer-native Toast (`ToastQueue`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a public `ToastQueue: Reducer` (cap + FIFO overflow + coalesce-with-count) and a `ToastStack(queue:)` overload in SwiflowUI, deprecate the `Binding`-based `ToastStack`, and migrate both demos.

**Architecture:** New `Sources/SwiflowUI/ToastQueue.swift` holds the reducer + overload. `Toast.swift` gains `ToastItem.count`/`dedupKey`, a live `×N` count badge in `ToastView`, and the deprecation. The reducer is pure/synchronous (host-unit-testable); the per-toast auto-dismiss timer stays in `ToastView` unchanged (pending toasts aren't rendered, so their timers never start).

**Tech Stack:** Swift 6.3, Swiflow macros (`@ReducerState`/`Reducer`/`ReducerHandle`), swift-testing (`import Testing`, `@Test`, `#expect`), `swiflow build` (wasm).

## Global Constraints

- **Swift 6.3.2**; CI skips example builds → build both demos to wasm **locally**.
- `swiflow build`/`dev` REWRITE tracked `examples/**/swiflow-driver.js` + `swiflow-service-worker.js` — `git checkout --` them before committing.
- Demos are embedded templates → after editing `examples/**`, regenerate `Sources/SwiflowCLI/EmbeddedTemplates.swift` via `swift scripts/embed-templates.swift` (an `embed-freshness` CI gate enforces it).
- `@ReducerState var x: ToastQueue` → the `@Component` macro synthesizes `self.x = ToastQueue()` (default `maxVisible: 3`); a custom cap needs a user `init`.
- Commit messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: `ToastItem` coalesce fields + `ToastView` count badge

**Files:**
- Modify: `Sources/SwiflowUI/Toast.swift` (`ToastItem`, `ToastView`, the toast stylesheet, and the existing `ToastStack(toasts:)` call site)
- Test: `Tests/SwiflowUITests/ToastTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ToastItem` gains `public internal(set) var count: Int = 1` and `var dedupKey: String` (internal).
  - `ToastView.init(item:recurrences:onDismiss:)` — new middle param `recurrences: @escaping () -> Int`.
  - CSS class `.sw-toast__count`.

- [ ] **Step 1: Write failing tests for the count field + badge**

Add to `Tests/SwiflowUITests/ToastTests.swift` (swift-testing; the file already has `el`/`allText`/`firstWithClass` helpers):

```swift
@Suite("Toast coalesce badge")
@MainActor
struct ToastCoalesceBadgeTests {
    @Test("ToastItem starts at count 1; dedupKey combines variant + message")
    func itemDefaults() {
        let a = ToastItem("Saved", variant: .success)
        #expect(a.count == 1)
        let b = ToastItem("Saved", variant: .danger)
        #expect(a.dedupKey != b.dedupKey)          // variant distinguishes
        let c = ToastItem("Saved", variant: .success)
        #expect(a.dedupKey == c.dedupKey)          // same message+variant coalesce
    }

    @Test("ToastView renders ×N badge only when recurrences > 1")
    func badgeVisibility() {
        let one = ToastView(item: ToastItem("Hi"), recurrences: { 1 }, onDismiss: {})
        #expect(firstWithClass(el(one.body)!, "sw-toast__count") == nil)

        let many = ToastView(item: ToastItem("Hi"), recurrences: { 3 }, onDismiss: {})
        let badge = firstWithClass(el(many.body)!, "sw-toast__count")
        #expect(badge != nil)
        #expect(allText(.element(badge!)).contains("3"))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --filter ToastCoalesceBadgeTests 2>&1 | tail -20`
Expected: FAIL — `ToastItem` has no `count`/`dedupKey`; `ToastView.init` has no `recurrences:`.

- [ ] **Step 3: Add `count` + `dedupKey` to `ToastItem`**

In `Sources/SwiflowUI/Toast.swift`, change the `ToastItem` stored properties + add `dedupKey` (leave `init` as-is — `count` defaults to 1):

```swift
public struct ToastItem {
    public let id: String
    public let message: String
    public let variant: ToastVariant
    public let duration: Double   // seconds before auto-dismiss
    public internal(set) var count: Int = 1   // recurrences; 1 = shown once

    public init(_ message: String, variant: ToastVariant = .info, duration: Double = 4) {
        self.id = nextSwID("sw-toast")
        self.message = message
        self.variant = variant
        self.duration = duration
    }

    /// Two toasts coalesce iff same message + variant.
    var dedupKey: String { "\(variant.modifierClass)|\(message)" }
}
```

- [ ] **Step 4: Add `recurrences` to `ToastView` + render the badge**

In `ToastView`: add the stored closure + init param, and insert the badge child. Change the init:

```swift
    private let item: ToastItem
    private let recurrences: () -> Int
    private let onDismiss: () -> Void
    // ... existing isHovered/isFocused/dismissTimer ...

    init(item: ToastItem, recurrences: @escaping () -> Int, onDismiss: @escaping () -> Void) {
        self.item = item
        self.recurrences = recurrences
        self.onDismiss = onDismiss
    }
```

Then in `body`, replace the `children:` array with a conditionally-built one (message → optional badge → close):

```swift
        let n = recurrences()
        var kids: [VNode] = [
            element("span", attributes: [.class("sw-toast__message")], children: [text(item.message)]),
        ]
        if n > 1 {
            // Real child (not aria-hidden) so the live region re-announces on a bump;
            // its aria-label makes SR read "3 times" rather than "×3".
            kids.append(element("span", attributes: [
                .class("sw-toast__count"),
                .attr("aria-label", "\(n) times"),
            ], children: [text("×\(n)")]))
        }
        kids.append(element("button", attributes: [
            .class("sw-toast__close"),
            .attr("type", "button"),
            .attr("aria-label", "Dismiss"),
            .on(.click) { self.onDismiss() },
        ], children: [text("\u{00D7}")]))
        return element("div", attributes: [ /* unchanged attribute list */ ], children: kids)
```

(Keep the existing `.class`/`role`/`aria-live`/`mouseenter`/`mouseleave`/`focusin`/`focusout` attributes exactly as they are.)

- [ ] **Step 5: Add `.sw-toast__count` style**

In the `toastStyleSheet` `raw("""..."""`) block in `Toast.swift`, add after the `.sw-toast__message` rule:

```css
    .sw-toast__count {
      flex: 0 0 auto;
      font-size: 0.75em;
      font-weight: 600;
      line-height: 1;
      padding: 0.1em 0.4em;
      border-radius: 999px;
      background-color: color-mix(in srgb, currentColor 16%, transparent);
      color: inherit;
    }
```

- [ ] **Step 6: Update the existing `ToastStack(toasts:)` call site**

Its `ToastView(...)` call now needs the `recurrences:` arg. The `Binding` path has no coalescing, so pass a constant 1. In `ToastStack(toasts:)`:

```swift
            ToastView(item: item, recurrences: { 1 }, onDismiss: { removeToast(item.id, from: toasts) })
```

- [ ] **Step 7: Run the tests + full SwiflowUI suite**

Run: `swift test --filter ToastCoalesceBadgeTests 2>&1 | tail -20` → PASS.
Run: `swift test --filter SwiflowUITests 2>&1 | tail -15` → all pass (existing `ToastTests` still green; the `ToastView` signature change is contained to `Toast.swift`).

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowUI/Toast.swift Tests/SwiflowUITests/ToastTests.swift
git commit -m "feat(swiflowui): ToastItem recurrence count + ToastView ×N badge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ToastQueue` reducer + `ToastStack(queue:)` + deprecate the Binding API

**Files:**
- Create: `Sources/SwiflowUI/ToastQueue.swift`
- Modify: `Sources/SwiflowUI/Toast.swift` (add `@available(deprecated)` on `ToastStack(toasts:)`)
- Test: `Tests/SwiflowUITests/ToastQueueTests.swift` (new)

**Interfaces:**
- Consumes: Task 1's `ToastItem.count`/`dedupKey` and `ToastView(item:recurrences:onDismiss:)`.
- Produces:
  - `public struct ToastQueue: Reducer` with `State { var visible: [ToastItem]; var pending: [ToastItem] }`, `Action { case show(ToastItem); case dismiss(String); case dismissAll }`, `init(maxVisible: Int = 3)`.
  - `public func ToastStack(queue: ReducerHandle<ToastQueue>, placement:) -> VNode`.

- [ ] **Step 1: Write failing pure-reducer tests**

Create `Tests/SwiflowUITests/ToastQueueTests.swift`:

```swift
// Tests/SwiflowUITests/ToastQueueTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let d)? = node { return d }; return nil
}

@Suite("ToastQueue reducer")
@MainActor
struct ToastQueueReducerTests {
    private func reduced(_ q: ToastQueue, _ start: ToastQueue.State,
                         _ actions: [ToastQueue.Action]) -> ToastQueue.State {
        var s = start
        for a in actions { q.reduce(into: &s, a) }
        return s
    }

    @Test("show under cap goes visible; over cap goes pending")
    func capAndOverflow() {
        let q = ToastQueue(maxVisible: 2)
        let s = reduced(q, q.initialState, [
            .show(ToastItem("a")), .show(ToastItem("b")), .show(ToastItem("c")),
        ])
        #expect(s.visible.map(\.message) == ["a", "b"])
        #expect(s.pending.map(\.message) == ["c"])
    }

    @Test("dismissing a visible toast FIFO-promotes the pending head")
    func promoteOnDismiss() {
        let q = ToastQueue(maxVisible: 2)
        let a = ToastItem("a"); let b = ToastItem("b"); let c = ToastItem("c")
        var s = reduced(q, q.initialState, [.show(a), .show(b), .show(c)])
        s = reduced(q, s, [.dismiss(a.id)])
        #expect(s.visible.map(\.message) == ["b", "c"])   // c promoted
        #expect(s.pending.isEmpty)
    }

    @Test("dismiss with empty pending just shrinks; unknown id is a no-op")
    func dismissEdges() {
        let q = ToastQueue(maxVisible: 3)
        let a = ToastItem("a"); let b = ToastItem("b")
        var s = reduced(q, q.initialState, [.show(a), .show(b)])
        s = reduced(q, s, [.dismiss("nope")])
        #expect(s.visible.count == 2)
        s = reduced(q, s, [.dismiss(a.id)])
        #expect(s.visible.map(\.message) == ["b"])
    }

    @Test("dismissAll clears both queues")
    func clearAll() {
        let q = ToastQueue(maxVisible: 1)
        var s = reduced(q, q.initialState, [.show(ToastItem("a")), .show(ToastItem("b"))])
        s = reduced(q, s, [.dismissAll])
        #expect(s.visible.isEmpty && s.pending.isEmpty)
    }

    @Test("same message+variant coalesces into count without a new slot")
    func coalesceVisible() {
        let q = ToastQueue(maxVisible: 3)
        let s = reduced(q, q.initialState, [
            .show(ToastItem("Saved", variant: .success)),
            .show(ToastItem("Saved", variant: .success)),
            .show(ToastItem("Saved", variant: .success)),
        ])
        #expect(s.visible.count == 1)
        #expect(s.visible[0].count == 3)
    }

    @Test("coalesce bumps a pending duplicate; different variant is distinct")
    func coalescePendingAndVariant() {
        let q = ToastQueue(maxVisible: 1)
        var s = reduced(q, q.initialState, [
            .show(ToastItem("x", variant: .info)),     // visible
            .show(ToastItem("y", variant: .info)),     // pending
            .show(ToastItem("y", variant: .info)),     // coalesce into pending y
        ])
        #expect(s.visible.count == 1 && s.pending.count == 1)
        #expect(s.pending[0].count == 2)
        s = reduced(q, s, [.show(ToastItem("x", variant: .danger))])  // same msg, diff variant → new
        #expect(s.pending.count == 2)
    }
}

@Suite("ToastStack(queue:) rendering")
@MainActor
struct ToastStackQueueTests {
    private func handle(_ q: ToastQueue) -> ReducerHandle<ToastQueue> {
        ReducerHandle(runtime: ReducerRuntime<ToastQueue>(), reducer: q)
    }

    @Test("renders only visible toasts, keyed, and not pending")
    func rendersVisibleOnly() {
        let h = handle(ToastQueue(maxVisible: 2))
        h.send(.show(ToastItem("a"))); h.send(.show(ToastItem("b"))); h.send(.show(ToastItem("c")))
        let root = el(ToastStack(queue: h))!
        #expect(root.children.count == 2)   // c is pending, not rendered
    }
}
```

NOTE: `ReducerHandle`/`ReducerRuntime` are in core `Swiflow` (already `@testable import`ed). `handle.send` without wiring still mutates state (it only skips `markDirty` when owner/scheduler are nil) — fine for a static VNode inspection.

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --filter ToastQueue 2>&1 | tail -20`
Expected: FAIL — no `ToastQueue` / no `ToastStack(queue:)`.

- [ ] **Step 3: Create `Sources/SwiflowUI/ToastQueue.swift`**

```swift
// Sources/SwiflowUI/ToastQueue.swift
import Swiflow

/// A managed Toast queue as a `Reducer` (use with `@ReducerState var toasts: ToastQueue`).
/// Shows at most `maxVisible` toasts; extras wait in a FIFO `pending` queue and are
/// promoted as visible ones dismiss. Duplicate toasts (same message + variant) coalesce
/// into a single entry with a recurrence `count` instead of stacking. Pure & synchronous —
/// the per-toast auto-dismiss timer lives in `ToastView` (a pending toast isn't rendered,
/// so its timer never starts until promoted).
public struct ToastQueue: Reducer {
    public struct State {
        public var visible: [ToastItem] = []   // rendered, ≤ maxVisible
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
            s.pending.removeAll { $0.id == id }
            refill(&s)
        case .dismissAll:
            s.visible.removeAll()
            s.pending.removeAll()
        }
    }

    /// Promote pending → visible (FIFO) until full or drained.
    private func refill(_ s: inout State) {
        while s.visible.count < maxVisible, !s.pending.isEmpty {
            s.visible.append(s.pending.removeFirst())
        }
    }
}

/// Renders a `ToastQueue`'s visible toasts. Mount once (e.g. app root):
///
///     @ReducerState var toasts: ToastQueue
///     …
///     Button("Save") { self.$toasts.send(.show(ToastItem("Saved!", variant: .success))) }
///     ToastStack(queue: $toasts)
///
/// Only `state.visible` renders; each toast auto-dismisses (or via ✕) and dispatches
/// `.dismiss(id)`, which promotes the next pending toast. Duplicates show a live `×N` badge.
@MainActor
public func ToastStack(queue: ReducerHandle<ToastQueue>,
                       placement: ToastPlacement = .bottomTrailing) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-toast", toastStyleSheet)
    let children = queue.state.visible.map { item in
        // Keyed by id so the instance + its dismiss timer survive re-renders. The count
        // is fed LIVE (not from the frozen `item`) so a coalesce bump updates the badge
        // in place — re-keying would remount and flicker.
        embed(item.id) {
            ToastView(
                item: item,
                recurrences: { queue.state.visible.first { $0.id == item.id }?.count ?? 1 },
                onDismiss: { queue.send(.dismiss(item.id)) }
            )
        }
    }
    return element("div",
                   attributes: [.class("sw-toast-stack sw-toast-stack--\(placement.modifierClass)")],
                   children: children)
}
```

- [ ] **Step 4: Deprecate the `Binding`-based `ToastStack`**

In `Sources/SwiflowUI/Toast.swift`, add the attribute immediately above `public func ToastStack(toasts:`:

```swift
@available(*, deprecated, message: "Use ToastStack(queue:) with @ReducerState var toasts: ToastQueue")
@MainActor
public func ToastStack(toasts: Binding<[ToastItem]>, placement: ToastPlacement = .bottomTrailing) -> VNode {
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter ToastQueue 2>&1 | tail -20` → PASS.
Run: `swift test --filter SwiflowUITests 2>&1 | tail -15` → all pass. If the existing `ToastTests` (which calls the now-deprecated `ToastStack(toasts:)`) emits deprecation *warnings*, that's fine (warnings, not failures); leave that host test as coverage of the deprecated path — silence it with `// swiftlint`-style comments only if the build treats warnings as errors (it does not here).

- [ ] **Step 6: Full host build + test (authoritative)**

Run: `swift build 2>&1 | tail -10 && swift test 2>&1 | tail -15`
Expected: build clean; full suite green. (Examples still use the old API at this point — Task 3 migrates them. Deprecation of `ToastStack(toasts:)` only warns at call sites, so examples still compile.)

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowUI/ToastQueue.swift Sources/SwiflowUI/Toast.swift Tests/SwiflowUITests/ToastQueueTests.swift
git commit -m "feat(swiflowui): ToastQueue reducer + ToastStack(queue:); deprecate Binding API

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Migrate both demos + regenerate templates + verify wasm/in-browser

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift`
- Regenerate: `Sources/SwiflowCLI/EmbeddedTemplates.swift`

**Interfaces:**
- Consumes: Task 2's `ToastQueue` + `ToastStack(queue:)`.
- Produces: no API — dogfood + template refresh.

- [ ] **Step 1: Migrate HelloWorld**

In `examples/HelloWorld/Sources/App/App.swift`:
- Replace `@State var toasts: [ToastItem] = []` with `@ReducerState var toasts: ToastQueue`.
- Replace the fire site `self.toasts.append(ToastItem("Saved!", variant: .success))` with `self.$toasts.send(.show(ToastItem("Saved!", variant: .success)))`.
- Replace `ToastStack(toasts: $toasts)` with `ToastStack(queue: $toasts)`.
- If the App `@Component` has no user `init`, the macro synthesizes `self.toasts = ToastQueue()` — verify no other stored property forces a hand-written init (if one exists, it must also assign `self.toasts = ToastQueue()`).

- [ ] **Step 2: Migrate SwiflowUIDemo**

In `examples/SwiflowUIDemo/Sources/App/App.swift`:
- Replace `@State var toasts: [ToastItem] = []` with `@ReducerState var toasts: ToastQueue`.
- Replace every `self.toasts.append(ToastItem(...))` (buttons, dropdown items ~lines 210-223, table-row ~line 319) with `self.$toasts.send(.show(ToastItem(...)))` (same `ToastItem(...)` argument).
- Replace `ToastStack(toasts: $toasts)` (~line 248) with `ToastStack(queue: $toasts)`.
- Add a **"Clear all"** button near the toast buttons: `Button("Clear all", variant: .ghost) { self.$toasts.send(.dismissAll) }` — dogfoods `.dismissAll`. (The existing repeated-variant buttons now demonstrate `×N` when clicked multiple times.)

- [ ] **Step 3: Host build both examples compile against the new API**

Run: `swift build 2>&1 | tail -10`
Expected: success (the shared macro/UI targets already built; the example host targets aren't part of `swift build` — the real check is the wasm build in Step 5, but a host `swift build` confirms Sources/tests are unaffected).

- [ ] **Step 4: Regenerate embedded templates**

Run: `swift scripts/embed-templates.swift`
Run: `grep -c "ToastStack(toasts:" Sources/SwiflowCLI/EmbeddedTemplates.swift`
Expected: `0` (both demos migrated). Then rebuild so the regenerated file compiles:
Run: `swift build 2>&1 | tail -5` → success.

- [ ] **Step 5: Build both demos to wasm**

Run: `swift build -c release --product swiflow 2>&1 | tail -5`
Run: `./.build/release/swiflow build --path examples/HelloWorld 2>&1 | tail -15`
Run: `./.build/release/swiflow build --path examples/SwiflowUIDemo 2>&1 | tail -15`
Expected: both wasm builds succeed.
Then revert the build-rewritten driver/SW copies:
Run: `git checkout -- 'examples/**/swiflow-driver.js' 'examples/**/swiflow-service-worker.js' 2>/dev/null; git status --short examples`
Confirm no `swiflow-driver.js`/`swiflow-service-worker.js` remain modified.

- [ ] **Step 6: Required in-browser verification (the live-count reactivity a unit test can't cover)**

Serve the demo and verify the three behaviors, then stop the server. (Run inline, never in a subagent; kill any leftover dev server on the port first.)
Run: `./.build/release/swiflow dev --path examples/SwiflowUIDemo` (note the port), open it, and confirm:
  1. Clicking the same toast button 5× → **one** toast whose badge reads `×2 … ×5`, updating **in place** (no slide-out/in flicker on each bump).
  2. Firing 5 *distinct* toasts → **3** visible; dismissing one → the 4th appears (FIFO).
  3. "Clear all" empties the stack.
Then stop the dev server (`pkill -f "swiflow dev"`).
Record the observations (a screenshot of the `×N` badge is ideal) in your report.

- [ ] **Step 7: Full suite green**

Run: `swift test 2>&1 | tail -15` → all pass.

- [ ] **Step 8: Commit**

```bash
git add examples Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "refactor(examples): migrate HelloWorld + SwiflowUIDemo toasts to ToastQueue

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the final reviewer

- **The novel/risky bit is the `recurrences` closure** (Task 2 Step 3): the count is fed live through a frozen keyed `embed` so the `×N` badge updates in place. Pure unit tests can't cover it — the Task 3 Step 6 in-browser check is its acceptance gate. Confirm that check was actually done (screenshot/observation), not skipped.
- **Coalesce ordering:** dedup runs *before* the cap check, so a duplicate never consumes a slot — verify the reducer tests assert both the visible-coalesce and pending-coalesce paths.
- **No `ToastView` timer/animation change** — pending toasts simply aren't rendered, so their timers never start; promotion mounts a fresh `ToastView` whose `onAppear` arms its own timer. Confirm nothing touched `reschedule`/`onAppear`/`exitAnimation`.
- **Deprecation is warning-only:** `ToastStack(toasts:)` still compiles and works; ensure no in-repo call site remains after Task 3 (grep), and that the build isn't configured warnings-as-errors.
- **Scope honesty:** `@ReducerState` is local — this did not add "fire from anywhere"; children still receive `$toasts.send`. That's expected, not a gap.
