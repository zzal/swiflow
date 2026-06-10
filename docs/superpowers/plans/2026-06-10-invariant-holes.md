# Invariant Holes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the 6 remaining non-SwiflowDOM HIGH findings from `docs/reviews/2026-06-10-quality-audit.md` — documented invariants that the code doesn't enforce.

**Architecture:** Six independent, small fixes: route the postfix `.attr` modifier through `URLSanitizer` (closing the XSS-allowlist bypass); give SwiflowQuery a zero-observer GC rider on the existing `tick()` (entries die `gcTime` after their last subscriber); make history-mode routing carry query strings and make `Link` hrefs mode-aware via a core `RouterMode`; make `StyleInjectionRegistry` buffer-and-flush so install-before-render works; detect `Optional<T>` syntactically in the macro; extend the CI Foundation grep to all six WASM modules.

**Tech Stack:** Swift 6 / Swift Testing; swift-syntax for the macro task; one YAML edit. All host-testable except two one-line JSKit-gated router edits (noted).

**Audit findings cleared:** Unit 1 HIGH (URLSanitizer bypass), Unit 7 HIGH (no cache eviction), Unit 8 HIGH ×2 (history query loss; mode-unaware Link), Unit 10 HIGH (installBaseStyles ordering), Unit 6 HIGH (Optional<T> wrong code). Plus Unit 2 MEDIUM (CI guard covers 3 of 6 WASM modules).

---

## Environment notes (read first)

- Swift tests: ALWAYS `env -u SWIFLOW_SOURCE swift test`. Suite is **781 tests / 177 suites green** on `main` @ `857c777`.
- Branch: `git checkout -b feat/invariant-holes` from `main`.
- No js-driver edits in this plan → no embed/codegen steps.
- Tasks are independent — execute in the given order but nothing blocks on anything except Task 7 (bookkeeping) being last.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/Swiflow/DSL/VNodeModifiers.swift` | modify | postfix `.attr(String,String)` routes URL attrs through the sanitizer |
| `Sources/Swiflow/Reactivity/URLSanitizer.swift` | modify | audit-pattern doc updated (two entry points now) |
| `Sources/SwiflowQuery/{Query,QueryEntry,QueryClient}.swift` | modify | `gcTime` + zero-observer eviction in `tick()` |
| `Sources/SwiflowRouter/Core/Router.swift` | modify | `RouterMode` enum, `Router.mode`, `Router.href(forPath:)` |
| `Sources/SwiflowRouter/Core/RouterKey.swift` | modify | default router carries `.hash` |
| `Sources/SwiflowRouter/Web/RouterRoot.swift` | modify | history `readPath` includes `location.search`; `Mode` → typealias |
| `Sources/SwiflowRouter/Web/Link.swift` | modify | href via `router.href(forPath:)` |
| `Sources/Swiflow/CSS/StyleInjectionRegistry.swift` | modify | pending-buffer + flush on sink install |
| `Sources/SwiflowUI/Theme.swift` | modify | doc updated (up-front install now actually safe) |
| `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` | modify | syntactic optionality detection |
| `.github/workflows/ci.yml` | modify | Foundation grep covers all 6 WASM modules |
| Tests | create/modify | one test file per task, named below |
| `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md` | modify | bookkeeping |

---

### Task 1: Route postfix `.attr` through URLSanitizer

`URLSanitizer.swift:14-17` documents: "every URL-bearing attribute that reaches the DOM passes through `URLSanitizer.sanitize(_:)`… `VNode.rawHTML(...)` is the only documented way to bypass." The prefix path enforces it (`DSL/Modifiers.swift:129-139`); the postfix `VNode.attr(_:_:)` (`DSL/VNodeModifiers.swift:32-34`) writes straight into the bag. (`.data` is exempt: it writes `data-\(name)` which can never collide with `href/src/action/formaction`; the Int/Double/Bool `.attr` overloads can't carry a scheme.)

**Files:**
- Modify: `Sources/Swiflow/DSL/VNodeModifiers.swift`, `Sources/Swiflow/Reactivity/URLSanitizer.swift:14-17`
- Test: `Tests/SwiflowTests/DSL/PostfixURLSanitizerTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/DSL/PostfixURLSanitizerTests.swift
import Testing
@testable import Swiflow

@Suite
@MainActor
struct PostfixURLSanitizerTests {

    private func attributes(of node: VNode) -> [String: String] {
        guard case .element(let data) = node else { return [:] }
        return data.attributes
    }

    @Test func postfixAttrDropsJavascriptHref() {
        let node = a { VNode.text("x") }.attr("href", "javascript:alert(1)")
        #expect(attributes(of: node)["href"] == nil,
                "postfix .attr must enforce the same allowlist as the prefix path")
    }

    @Test func postfixAttrKeepsSafeHref() {
        let node = a { VNode.text("x") }.attr("href", "https://example.com")
        #expect(attributes(of: node)["href"] == "https://example.com")
    }

    @Test func postfixAttrIsCaseInsensitiveOnTheName() {
        let node = a { VNode.text("x") }.attr("HREF", "javascript:alert(1)")
        #expect(attributes(of: node)["HREF"] == nil)
    }

    @Test func postfixAttrLeavesNonURLAttributesAlone() {
        let node = div { VNode.text("x") }.attr("title", "javascript:not-a-url-slot")
        #expect(attributes(of: node)["title"] == "javascript:not-a-url-slot")
    }
}
```

(If the DSL has no `a` factory, use any element factory that exists — check `Sources/Swiflow/DSL/Elements.swift`; `div` definitely exists.)

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter PostfixURLSanitizerTests`
Expected: `postfixAttrDropsJavascriptHref` and the case-insensitive test FAIL (attribute present with the raw javascript: value).

- [ ] **Step 3: Implement**

In `Sources/Swiflow/DSL/VNodeModifiers.swift`, replace the string `.attr` overload:

```swift
    /// Adds (or overwrites) an HTML attribute (string value).
    ///
    /// URL-bearing attribute names (`href`, `src`, `action`, `formaction` —
    /// case-insensitive) route through `URLSanitizer.sanitize(_:)`, exactly
    /// like the prefix `Attribute` path: a rejected value drops the attribute.
    func attr(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { data in
            if URLSanitizer.urlAttributeNames.contains(name.lowercased()) {
                if let sanitized = URLSanitizer.sanitize(value) {
                    data.attributes[name] = sanitized
                } else {
                    #if DEBUG
                    print("[Swiflow] URLSanitizer rejected \(name)=\"\(value)\" — attribute dropped. Use VNode.rawHTML for the rare case where unsanitized URLs are intentional.")
                    #endif
                }
            } else {
                data.attributes[name] = value
            }
        }
    }
```

In `Sources/Swiflow/Reactivity/URLSanitizer.swift`, update the audit-pattern paragraph (lines 14-17) to name both entry points:

```swift
/// **Audit pattern:** every URL-bearing attribute that reaches the DOM
/// passes through `URLSanitizer.sanitize(_:)` — via the prefix `Attribute`
/// fold (DSL/Modifiers.swift) and the postfix `VNode.attr(_:_:)` modifier
/// (DSL/VNodeModifiers.swift). Search for that exact symbol to enumerate
/// every entry point. The `VNode.rawHTML(...)` escape hatch is the only
/// documented way to bypass.
```

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter PostfixURLSanitizerTests` → 4 passing.
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green (785 expected).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(core): postfix .attr enforces the URLSanitizer allowlist

Closes the documented-invariant bypass: VNode.attr(\"href\", ...) wrote
straight into the attribute bag while the prefix path sanitized. Clears
audit HIGH: 'URLSanitizer bypass via postfix modifiers'."
```

---

### Task 2: SwiflowQuery zero-observer cache eviction

`QueryClient.entries` is insert-only: every entry permanently retains its value AND its `boxedFetch` closure (captured deps). Parameterized keys grow the cache unboundedly. Fix: entries with no live subscribers are kept for `gcTime` (back-nav remounts reuse the cached data), then evicted. The sweep rides the existing `tick(now:)` that production's `BackgroundRevalidation` already drives.

**Files:**
- Modify: `Sources/SwiflowQuery/Query.swift` (protocol + default), `Sources/SwiflowQuery/QueryEntry.swift`, `Sources/SwiflowQuery/QueryClient.swift` (observation, reconcile, tick)
- Test: `Tests/SwiflowQueryTests/CacheEvictionTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Read an existing test (e.g. `Tests/SwiflowQueryTests/QueryClientTests.swift`) first for how suites construct a `QueryClient` with a `ManualClock` and drive `reconcile`/`observe`/`tick` — mirror those helpers. The contracts:

```swift
// Tests/SwiflowQueryTests/CacheEvictionTests.swift
import Testing
@testable import SwiflowQuery
@testable import Swiflow

@Suite
@MainActor
struct CacheEvictionTests {

    // Construct client + a subscribed entry the way QueryClientTests does
    // (AnyComponent owner + scheduler + reconcile with one observation whose
    // gcTime is .seconds(300)), then:

    @Test func entryIsEvictedGCTimeAfterLastSubscriberDrops() {
        // 1. observe + reconcile → entry exists.
        // 2. dropComponent(owner) → no live subscribers.
        // 3. clock.advance(by: .seconds(299)); client.tick(now: clock.now())
        //    → entry STILL present (within gcTime).
        // 4. clock.advance(by: .seconds(2)); client.tick(now: clock.now())
        //    → wait: the FIRST tick after the drop only STAMPS
        //    unobservedSince; eviction happens once now - unobservedSince
        //    >= gcTime. So: tick once right after the drop (stamps), advance
        //    301s, tick again → entry gone.
        // Assert via client.entries[key] == nil.
    }

    @Test func entryWithLiveSubscriberIsNeverEvicted() {
        // observe + reconcile, do NOT drop; advance 10_000s; tick.
        // Assert client.entries[key] != nil.
    }

    @Test func reObservationWithinGCTimeKeepsTheCachedValue() {
        // observe, commit a value (drive the fetch via the existing test
        // pattern), dropComponent, tick (stamps), advance 100s (< gcTime),
        // re-observe + reconcile with the same key, tick.
        // Assert entry still present AND its cached value survived.
    }

    @Test func evictionCancelsAnInFlightFetch() {
        // observe with a never-completing fetch (existing tests have a
        // pattern for a hanging continuation), drop, tick (stamps),
        // advance past gcTime, tick → entry gone and the in-flight task
        // was cancelled (await it / assert isCancelled per existing patterns).
    }
}
```

Write these as REAL tests using the suite's established helpers — the comments above are the required behavior, not the literal code. All four must compile against the internals (`@testable`) and initially FAIL (no eviction exists).

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter CacheEvictionTests`
Expected: compile failure (`gcTime` doesn't exist on the observation) or assertion failures (entries never evicted).

- [ ] **Step 3: Implement**

`Sources/SwiflowQuery/Query.swift` — add to the protocol (after `retry`):

```swift
    /// How long a cache entry outlives its last subscriber before being
    /// garbage-collected. Defaults to 5 minutes: long enough that back-nav
    /// remounts hit warm cache, short enough that parameterized keys
    /// (`["users", id]`) don't grow the cache unboundedly.
    var gcTime: Duration { get }
```

and to the defaults extension:

```swift
    var gcTime: Duration { .seconds(300) }
```

`Sources/SwiflowQuery/QueryEntry.swift` — add after `nextRetryDue`:

```swift
    /// Promoted from the latest observation, like `staleTime`.
    var gcTime: Duration = .seconds(300)
    /// Clock time this entry lost its last live subscriber; `nil` while
    /// observed. Stamped/cleared by `tick`'s GC sweep.
    var unobservedSince: Duration?
```

`Sources/SwiflowQuery/QueryClient.swift`:
1. `QueryObservation` gains `let gcTime: Duration` (after `retry`).
2. `observe` passes `gcTime: q.gcTime`.
3. `reconcile`'s entry-update block gains `entry.gcTime = ob.gcTime`.
4. Replace `tick(now:)` with:

```swift
    /// Driven by the production interval (and tests). Fires due retries and
    /// due polls for live entries, and garbage-collects entries that have had
    /// no live subscriber for `gcTime` — evicting both the cached value and
    /// the `boxedFetch` closure (which retains the query's captured deps).
    package func tick(now: Duration) {
        var evict: [QueryKey] = []
        for (key, entry) in entries {
            guard hasLiveSubscribers(key) else {
                // GC sweep: stamp the moment the entry became unobserved,
                // evict once it has been unobserved for gcTime. Back-nav
                // remounts within the window reuse the warm entry.
                if let since = entry.unobservedSince {
                    if now - since >= entry.gcTime { evict.append(key) }
                } else {
                    entry.unobservedSince = now
                }
                continue
            }
            entry.unobservedSince = nil
            guard entry.inFlight == nil else { continue }
            if let due = entry.nextRetryDue, now >= due {
                entry.nextRetryDue = nil
                startFetch(for: key, entry: entry)          // retry
                continue
            }
            if let interval = entry.refetchInterval,
               let last = entry.lastFetched, now - last >= interval {
                startFetch(for: key, entry: entry)          // poll
            }
        }
        for key in evict {
            entries[key]?.inFlight?.cancel()
            entries.removeValue(forKey: key)
            subscribers.removeValue(forKey: key)
        }
    }
```

(This also deletes the stale "Filled in by later tasks." / "(scheduled by Task 7)" comments on `tick` — audit LOW, free fix. Note the original guarded `entry.inFlight == nil` at the TOP of the loop; the new shape moves that guard after the GC block so unobserved-but-fetching entries still age toward eviction. Eviction cancels the in-flight task.)

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter CacheEvictionTests` → 4 passing.
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green (existing tick/revalidation tests must still pass — if one fails because it constructed entries without subscribers and ticked across 5 simulated minutes, that test is now exercising eviction; adjust it consciously and report).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(query): zero-observer cache eviction (gcTime)

Entries now die gcTime (default 5 min) after their last subscriber
drops, releasing the cached value and the captured-deps fetch closure.
The sweep rides the existing background-revalidation tick. Clears audit
HIGH: 'no cache eviction / GC: entries live forever'."
```

---

### Task 3: Router — history-mode query strings + mode-aware Link hrefs

Two verified HIGHs: (a) history-mode `readPath` returns only `location.pathname`, so Back/refresh silently drops `?query` (hash mode keeps it — the query rides inside the hash); (b) `Link` always emits `href="/about"` while the default hash mode's canonical URL is `#/about` — cmd/click and "copy link address" go to a real server path. `Router` carries no mode, so Link can't adapt.

**Files:**
- Modify: `Sources/SwiflowRouter/Core/Router.swift`, `Sources/SwiflowRouter/Core/RouterKey.swift`, `Sources/SwiflowRouter/Web/RouterRoot.swift`, `Sources/SwiflowRouter/Web/Link.swift`
- Test: `Tests/SwiflowRouterTests/RouterModeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowRouterTests/RouterModeTests.swift
import Testing
@testable import SwiflowRouter

@Suite
struct RouterModeTests {

    private func router(mode: RouterMode) -> Router {
        Router(path: "/", mode: mode, navigate: { _ in }, replace: { _ in }, back: {})
    }

    @Test func hashModeHrefsCarryTheHashPrefix() {
        #expect(router(mode: .hash).href(forPath: "/about") == "#/about")
        #expect(router(mode: .hash).href(forPath: "/search?q=x") == "#/search?q=x")
    }

    @Test func historyModeHrefsAreThePathItself() {
        #expect(router(mode: .history).href(forPath: "/about") == "/about")
    }

    @Test func defaultRouterModeIsHash() {
        // Backward compat: the 4-argument init (no mode) must keep compiling
        // and default to .hash, matching RouterRoot's default.
        let r = Router(path: "/", navigate: { _ in }, replace: { _ in }, back: {})
        #expect(r.mode == .hash)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter RouterModeTests`
Expected: compile failure (`RouterMode` / `mode:` / `href(forPath:)` don't exist).

- [ ] **Step 3: Implement Core**

`Sources/SwiflowRouter/Core/Router.swift` — add the enum above `Router` and extend the struct:

```swift
/// How the router encodes routes in the browser URL. Lives in Core (not
/// Web) so `Link` can render mode-correct hrefs from the environment value
/// without importing the browser layer.
public enum RouterMode: Sendable, Equatable {
    case hash, history
}
```

In `Router`: add `public let mode: RouterMode`; give `init` a `mode: RouterMode = .hash` parameter (placed after `path` so the label keeps call sites readable; the default preserves source compatibility for the 4-arg form); add:

```swift
    /// The `href` a link to `path` should carry under this router's mode:
    /// hash mode's canonical URL is `#/about` (so cmd/middle-click and
    /// "copy link address" resolve to the route, not a server path);
    /// history mode uses the path itself.
    public func href(forPath path: String) -> String {
        switch mode {
        case .hash: return "#" + path
        case .history: return path
        }
    }
```

`Sources/SwiflowRouter/Core/RouterKey.swift` — the no-op default already gets `.hash` via the default parameter; no change needed unless the compiler asks (then pass `mode: .hash` explicitly).

- [ ] **Step 4: Implement Web (JSKit-gated; verified by inspection + wasm build)**

`Sources/SwiflowRouter/Web/RouterRoot.swift`:
1. Replace `public enum Mode { case hash, history }` with `public typealias Mode = RouterMode` (keeps `RouterRoot(mode: .hash)` call sites compiling).
2. In `body`, construct the router with the mode: `Router(path: currentPath, mode: mode, navigate: …, replace: …, back: …)`.
3. In `readPath`, fix history mode:

```swift
        case .history:
            // pathname alone loses the query on popstate/refresh — the
            // audit's 'history mode drops query strings' finding. The
            // matcher strips the query for matching; RouterContext.query
            // parses it.
            let pathname = loc["pathname"].string ?? "/"
            let search = loc["search"].string ?? ""
            return pathname + search
```

`Sources/SwiflowRouter/Web/Link.swift` — in `body`, derive the href from the ambient router (which now carries the mode):

```swift
    public var body: VNode {
        // Capture navigate during body — ambientRouter.wrappedValue reads
        // AmbientEnvironment.current which is set by the diff only during body.
        capturedNavigate = ambientRouter.navigate
        let href = ambientRouter.href(forPath: path)
        let refAttr = Attribute.refBinding(AnyRefBinding(linkRef))
        switch content {
        case .label(let text):
            return link(.attr("href", href), refAttr) { VNode.text(text) }
        case .children(let nodes):
            return link(.attr("href", href), refAttr) { nodes }
        }
    }
```

(`@Environment(\.router) private var ambientRouter` — if the property wrapper's value access needs `.wrappedValue` or different spelling, match how `navigate` is already read two lines up.)

- [ ] **Step 5: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter "RouterModeTests|SwiflowRouter"` → green (existing router tests must keep passing — the Core API change is additive-with-default).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green (788 expected).
Note in the report: the two Web-file edits are `#if canImport(JavaScriptKit)`-gated and not exercised by host tests — final verification is the wasm build in this plan's end-to-end section.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(router): history mode keeps query strings; Link hrefs are mode-aware

RouterMode moves to Core on the Router environment value, so Link can
render '#/path' under the default hash mode (cmd/click and copy-link now
resolve to the route); history-mode readPath appends location.search so
Back/refresh stop dropping queries. Clears audit HIGHs: 'history mode
drops query strings' and 'Link is mode-unaware'."
```

---

### Task 4: StyleInjectionRegistry — buffer before the sink exists

`StyleInjectionRegistry.injectOnce` records the id and emits through a nil sink when called before `Swiflow.render` wires `CSSInjector.setup()` — and `Theme.swift` actively advises calling `installBaseStyles()` "up front", which therefore silently injects nothing. Even the render path itself constructs the root (`factory()`) one line before `setup()`. Fix: buffer `(id, css)` pairs recorded while the sink is nil and flush them when the sink is installed.

**Files:**
- Modify: `Sources/Swiflow/CSS/StyleInjectionRegistry.swift`, `Sources/SwiflowUI/Theme.swift:27-29` (doc)
- Test: `Tests/SwiflowTests/CSS/StyleInjectionBufferTests.swift` (create; if registry tests already live elsewhere — check `grep -rln StyleInjectionRegistry Tests/` — extend that file instead)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/CSS/StyleInjectionBufferTests.swift
import Testing
@testable import Swiflow

@Suite(.serialized)
@MainActor
struct StyleInjectionBufferTests {

    @Test func injectionsBeforeTheSinkFlushWhenItArrives() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        var emitted: [(String, String)] = []

        StyleInjectionRegistry.injectOnce(id: "swiflow-early") { ".x{color:red}" }
        #expect(emitted.isEmpty)

        StyleInjectionRegistry.emit = { id, css in emitted.append((id, css)) }

        #expect(emitted.count == 1)
        #expect(emitted[0].0 == "swiflow-early")
        #expect(emitted[0].1 == ".x{color:red}")
    }

    @Test func onceSemanticsSurviveTheBuffer() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        var emitted: [String] = []

        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }
        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }
        StyleInjectionRegistry.emit = { id, _ in emitted.append(id) }
        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }

        #expect(emitted == ["swiflow-dup"])
    }

    @Test func resetClearsThePendingBuffer() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        StyleInjectionRegistry.injectOnce(id: "swiflow-stale") { ".s{}" }
        StyleInjectionRegistry.reset()

        var emitted: [String] = []
        StyleInjectionRegistry.emit = { id, _ in emitted.append(id) }
        #expect(emitted.isEmpty, "reset must drop buffered emits, not replay them")
    }
}
```

Cleanup discipline: leave `emit = nil` + `reset()` at the end of each test if the sibling suites expect a clean registry (check how ThemeTests handles it and match).

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter StyleInjectionBufferTests`
Expected: first test FAILS (`emitted` stays empty — recorded-before-sink ids are never re-emitted).

- [ ] **Step 3: Implement**

Replace the body of `Sources/Swiflow/CSS/StyleInjectionRegistry.swift`'s enum:

```swift
@MainActor
public enum StyleInjectionRegistry {
    /// Ids already injected this session.
    private static var injectedIDs: Set<String> = []

    /// Emits recorded while no sink was installed. Flushed (in record order)
    /// the moment `emit` is set, so installing styles before
    /// `Swiflow.render(into:_:)` wires the DOM sink is safe — the CSS is
    /// buffered, not lost.
    private static var pending: [(id: String, css: String)] = []

    /// The emit sink. SwiflowDOM sets this to append a `<style>` to `<head>`.
    /// `nil` on a host with no DOM (tests/headless): `injectOnce` records the
    /// id AND buffers the css; setting the sink flushes the buffer.
    public static var emit: ((_ id: String, _ css: String) -> Void)? {
        didSet {
            guard let emit, !pending.isEmpty else { return }
            let flush = pending
            pending = []
            for entry in flush { emit(entry.id, entry.css) }
        }
    }

    /// Injects `css` under `id` exactly once. The `css` builder runs only on
    /// the first call for an id (so repeat renders don't rebuild the string).
    /// Returns `true` iff this call performed the (first) injection.
    @discardableResult
    public static func injectOnce(id: String, css: () -> String) -> Bool {
        guard !injectedIDs.contains(id) else { return false }
        injectedIDs.insert(id)
        if let emit {
            emit(id, css())
        } else {
            pending.append((id: id, css: css()))
        }
        return true
    }

    /// Forgets all injected ids AND drops any buffered emits, so the next
    /// `injectOnce` re-emits fresh. Tests/HMR.
    public static func reset() {
        injectedIDs = []
        pending = []
    }
}
```

(Preserve the file's header comment; update its "emit must be assigned before the first injectOnce call" sentence — that constraint is the bug being fixed; replace with "emits recorded before the sink is set are buffered and flushed when it arrives.")

In `Sources/SwiflowUI/Theme.swift:27-29`, the doc comment "also public so apps/tests can install deterministically up front" is now actually true — extend it: "(safe even before `Swiflow.render` — the registry buffers until the DOM sink is installed)".

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter "StyleInjectionBufferTests|Theme|CSS"` → green (ThemeTests' swappable-sink tests must keep passing; if one set `emit` to a recorder AFTER an injectOnce and asserted nothing was emitted, it encoded the old lossy behavior — update it consciously and report).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(core): style-injection registry buffers emits until the sink exists

installBaseStyles() before Swiflow.render — which Theme.swift's own docs
recommend — used to record the id against a nil sink and silently inject
nothing forever. Buffered emits now flush when SwiflowDOM installs the
sink. Clears audit HIGH: 'installBaseStyles up-front advice silently
breaks injection'."
```

---

### Task 5: ComponentMacro — syntactic optionality detection

`ComponentMacro.swift:98` decides optionality with `valueType.hasSuffix("?")`, so the legal `@State var x: Optional<Int>` spelling is classified non-optional and silently skips the `HMRNilSentinel` normalization — reintroducing the exact bug the adjacent comment says the code prevents.

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift:98`
- Test: `Tests/SwiflowMacrosTests/` — extend the existing file that tests optional-state expansion (find it: `grep -rln "HMRNilSentinel\|restoreNil" Tests/SwiflowMacrosTests/`)

- [ ] **Step 1: Write the failing test**

Mirror the existing optional-expansion test (the suite has one for `Int?` — e.g. `testOptionalRestoreNilAndSnapshotSentinel`). Add a sibling using the long spelling. Shape (adapt to the file's actual assertion helper — likely `assertMacroExpansion` or string-contains on the expansion):

```swift
@Test func optionalLongSpellingGetsTheSentinelBranch() {
    // @State var x: Optional<Int> must expand identically to
    // @State var x: Int? — i.e. its StateCell carries the
    // HMRNilSentinel-normalizing snapshot and a working restoreNil.
    // Copy the existing Int? expansion test, change the declared type to
    // Optional<Int>, and assert the SAME expansion features:
    //   - snapshot contains "HMRNilSentinel"
    //   - restoreNil sets the property to nil and returns true
}
```

Write it as a REAL test against the suite's existing helpers; also add a `Swift.Optional<Int>` case if the helper makes it a one-liner.

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter SwiflowMacros`
Expected: the new test FAILS — the expansion takes the non-optional branch (`restoreNil: { _ in false }`, no sentinel).

- [ ] **Step 3: Implement**

In `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`, replace line 98:

```swift
            let isOptional = Self.isOptionalType(typeAnno.type)
```

and add the helper to the macro type:

```swift
    /// Optionality by SYNTAX, not by string suffix: `Int?` is
    /// `OptionalTypeSyntax`; the long spellings `Optional<Int>` and
    /// `Swift.Optional<Int>` are identifier/member types named "Optional".
    /// (The audit found `hasSuffix("?")` silently mis-classified the long
    /// spelling, skipping HMRNilSentinel normalization.)
    static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) { return true }
        if let ident = type.as(IdentifierTypeSyntax.self),
           ident.name.text == "Optional",
           ident.genericArgumentClause != nil {
            return true
        }
        if let member = type.as(MemberTypeSyntax.self),
           member.name.text == "Optional",
           member.genericArgumentClause != nil {
            return true
        }
        return false
    }
```

(If `MemberTypeSyntax` is spelled differently in swift-syntax 600 — check with `grep -rn "MemberTypeSyntax" $(swift build --show-bin-path 2>/dev/null)/../checkouts/swift-syntax/Sources/SwiftSyntax/generated/ 2>/dev/null | head -1` or just try compiling; the 600.x name is `MemberTypeSyntax`.)

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter SwiflowMacros` → green including the new case(s).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(macros): detect Optional<T> spelling syntactically

hasSuffix(\"?\") mis-classified the long Optional spelling, silently
skipping HMRNilSentinel normalization — the exact type-erased-nil bug
the surrounding code exists to prevent. Clears audit HIGH: 'optionality
detected by string suffix'."
```

---

### Task 6: Extend the CI Foundation-free guard to all six WASM modules

`.github/workflows/ci.yml` greps only `Swiflow SwiflowRouter SwiflowDOM`; `SwiflowQuery`, `SwiflowFetcher`, `SwiflowUI` also ship in the WASM binary and are unguarded (audit Unit 2 MEDIUM). All six are currently clean.

**Files:**
- Modify: `.github/workflows/ci.yml` (the "Verify Foundation-free runtime" step, ~lines 116-132)

- [ ] **Step 1: Edit the step**

Update the comment and the grep list:

```yaml
      - name: Verify Foundation-free runtime
        # ALL six WASM-bound modules (Swiflow, SwiflowRouter, SwiflowDOM,
        # SwiflowQuery, SwiflowFetcher, SwiflowUI) ship in the binary.
        # Importing Foundation there risks pulling back the reflection /
        # demangler / SIMD cost that Phase 15 cut by 90%. Host-side modules
        # (SwiflowCLI, SwiflowMacrosPlugin) run on macOS/Linux only and are
        # not gated.
        run: |
          set -euo pipefail
          # Update this list when adding a new runtime module.
          if grep -rn "^import Foundation$" \
               Sources/Swiflow \
               Sources/SwiflowRouter \
               Sources/SwiflowDOM \
               Sources/SwiflowQuery \
               Sources/SwiflowFetcher \
               Sources/SwiflowUI; then
            echo "::error::Runtime modules must not import Foundation."
            echo "::error::See docs/superpowers/specs/2026-05-27-phase16-foundation-free-runtime-design.md"
            exit 1
          fi
```

- [ ] **Step 2: Verify locally**

Run:
```bash
grep -rn "^import Foundation$" Sources/Swiflow Sources/SwiflowRouter Sources/SwiflowDOM Sources/SwiflowQuery Sources/SwiflowFetcher Sources/SwiflowUI; echo "exit: $?"
```
Expected: no matches, `exit: 1` (grep's no-match exit) — which is the PASS condition in the CI step.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: extend the Foundation-free guard to all six WASM modules

SwiflowQuery/SwiflowFetcher/SwiflowUI ship in the binary too; the guard
covered only half. Clears audit MEDIUM: 'Foundation-free CI guard covers
3 of 6 WASM-bound modules'."
```

---

### Task 7: CHANGELOG + audit bookkeeping

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]` → `### Fixed`), `docs/reviews/2026-06-10-quality-audit.md`

- [ ] **Step 1: CHANGELOG**

Append to the existing `### Fixed` list under `## [Unreleased]`:

```markdown
- **XSS allowlist:** the postfix `.attr("href", …)` modifier now routes
  through `URLSanitizer` like the prefix path (the documented invariant had
  a public bypass).
- **Query cache growth:** entries are garbage-collected `gcTime` (default
  5 minutes, configurable per query) after their last subscriber unmounts.
- **Router:** history mode no longer drops `?query` strings on back/refresh;
  `Link` hrefs are mode-aware (`#/path` under the default hash mode, so
  cmd/click and copy-link resolve to the route).
- **SwiflowUI:** `installBaseStyles()` before `Swiflow.render` now works —
  the style registry buffers until the DOM sink is installed.
- **`@State var x: Optional<Int>`** (long spelling) now gets the same
  HMR nil-handling as `Int?`.
```

- [ ] **Step 2: Audit annotations**

Append ` **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**` to:
- Unit 1 `### HIGH — URLSanitizer bypass via postfix modifiers *(verified)*`
- Unit 7 `### HIGH — No cache eviction / GC: entries live forever *(verified)*`
- Unit 8 `### HIGH — History mode drops query strings on initial load and popstate *(verified)*`
- Unit 8 `### HIGH — Link is mode-unaware; hrefs are wrong under the default hash mode *(verified)*`
- Unit 10 `### HIGH — \`installBaseStyles()\` "up front" advice silently breaks injection *(verified)*`
- Unit 6 `### HIGH — Optionality detected by string suffix; \`Optional<T>\` spelling produces wrong code *(verified)*`
- Unit 2 `### MEDIUM — Foundation-free CI guard covers 3 of 6 WASM-bound modules` (same annotation)

Tally table updates: Swiflow (core) High 1→0; SwiflowMacrosPlugin High 1→0; SwiflowQuery High 1→0; SwiflowRouter High 2→0; SwiflowUI High 1→0; Cross-module Medium 3→2; Total High 9→3, Medium 38→37. (Remaining 3 Highs are all SwiflowDOM — the round-4 candidates.)

- [ ] **Step 3: Final verification + commit**

```bash
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2   # full suite green
git add CHANGELOG.md docs/reviews/2026-06-10-quality-audit.md
git commit -m "docs: changelog + audit bookkeeping for invariant-holes round"
```

---

## Verification (end-to-end)

1. `env -u SWIFLOW_SOURCE swift test` — full host suite green (≈792, exact count per new tests).
2. The Task 6 grep run locally exits 1 (no matches).
3. Manual (requires wasm toolchain): `cd examples/MiniRouter && swiflow build` — proves the JSKit-gated RouterRoot/Link edits compile for wasm.
4. Manual smoke (optional): MiniRouter under `swiflow dev` — Link hrefs show `#/...` on hover; navigating with `?q=x` in history mode would need a history-mode demo (none exists; covered by inspection + the Core href tests).

## Out of scope (deliberately)

- SwiflowDOM's 3 remaining Highs (multi-root HMR state, dead viewProducer/rerender mode, dev surfaces in release wasm) — round 4; the release gating needs a `-D` flag design through BuildCommand.
- Router Mediums (path-param percent-decoding, matchFull/matchPrefix twins, valueless query keys).
- Query Mediums (rollback clobber, valuesEqual dead plumbing, supersede duplication).
- SwiflowUI Medium (`.padding`/`.gap` not triggering installation).
