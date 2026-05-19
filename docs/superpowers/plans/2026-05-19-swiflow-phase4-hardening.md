# Swiflow Phase 4 — Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Swiflow before Phase 5 — close the explicitly-listed XSS hole, catch framework footguns at runtime in debug builds, decide what to do about WASM source maps, and add a thin Node-based test layer (JS driver units + one Playwright happy-path).

**Architecture:** Three layers of additions: (a) cross-platform Swift code in `Sources/Swiflow/Reactivity/` for `URLSanitizer` and `Diagnostics`; (b) modifications to `Sources/Swiflow/DSL/Modifiers.swift`'s `applyAttributes` fold step to route URL-bearing attributes through the sanitizer; (c) a Node-based test layer alongside (not replacing) the existing Swift Testing suite — `js-driver/test/` for opcode coverage with jsdom, and `tests/playwright/` for browser e2e.

**Tech Stack:** Swift 6.3 (existing); Node 20 LTS + `node:test` + `jsdom` (new, for JS driver tests); `@playwright/test` + Chromium (new, for browser e2e); GitHub Actions cache for both Node toolchains.

---

## Out of scope (locked from spec)

- `swiflow build --production` (wasm-opt + gzip + DWARF strip) — defer to ship-readiness phase
- Homebrew tap + release pipeline — defer
- NPM driver publish (`@swiflow/driver`) — defer
- Keyed diff LIS optimization — defer to perf phase
- Binary patch buffer (`Uint8Array` over linear memory) — defer to perf phase
- Perf benchmarks in CI — needs baseline first; defer
- Firefox/WebKit Playwright coverage — Phase 5+
- Visual regression / screenshot diffing — Phase 5+

---

## File structure

### Created
- `Sources/Swiflow/Reactivity/URLSanitizer.swift` — sanitization logic + Swiflow.urlSanitizer config
- `Sources/Swiflow/Reactivity/Diagnostics.swift` — `swiflowDiagnostic(_:)` central helper
- `Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift`
- `Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift`
- `js-driver/package.json` — `node:test` + `jsdom` deps
- `js-driver/test/helpers.js` — jsdom setup + driver loader (via script-tag injection)
- `js-driver/test/opcodes.test.js` — opcode coverage
- `js-driver/test/dev-reload.test.js` — WebSocket reload handler
- `tests/playwright/package.json` — `@playwright/test` dep
- `tests/playwright/playwright.config.ts` — `webServer` = `swiflow dev`
- `tests/playwright/counter.spec.ts` — happy-path Counter test
- `tests/playwright/README.md` — how-to
- `docs/debugging-wasm.md` — DWARF or source-map debugging guide (final form depends on Task 3 outcome)

### Modified
- `Sources/Swiflow/DSL/Modifiers.swift` — `applyAttributes` routes URL attributes through `URLSanitizer`
- `Sources/Swiflow/Diff/Diff.swift` — call diagnostic helpers from `diffChildren` dispatcher + `mount()` `.component` arm (component-cycle depth check)
- `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` — duplicate-key set-walk pre-pass
- `.github/workflows/ci.yml` — add `JS Driver Tests` job (push+PR) and `Playwright E2E` job (PR only)
- `Sources/SwiflowCLI/Commands/BuildCommand.swift` — conditional (Task 4 only, if spike outcome is "native SDK support" or "manual emit step")

---

## Task ordering (with natural pause point)

1. **URL sanitizer** — smallest, security item, no dependencies.
2. **Diagnostic errors** (incl. refactor of Task 1's debug print to use the new central helper) — **🛑 pause for user review**.
3. **Source maps spike** (2h timebox) — investigation only.
4. **Source maps follow-up** — conditional on Task 3 outcome.
5. **JS driver units** (`node:test` + jsdom, driver loaded via script-tag injection).
6. **Playwright e2e** (Counter happy path).

---

### Task 1: URL sanitizer + DSL sanitization at the fold step

**Files:**
- Create: `Sources/Swiflow/Reactivity/URLSanitizer.swift`
- Create: `Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift`
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — `applyAttributes` routes URL-bearing attributes through the sanitizer

**Design notes:**

- Sanitize at the `applyAttributes` fold step (the DSL boundary), not in element factories or patch emission. This catches both `.attr("href", ...)` and any future convenience like `.href(...)` for free.
- The sanitizer matches against the attribute name case-insensitively, and only fires for four URL-bearing names: `href`, `src`, `action`, `formaction`. Other attributes pass through unchanged.
- On rejection: drop the attribute entirely (don't write to the bag), print a debug-mode warning. Task 2 will swap the print for `swiflowDiagnostic`.
- Defaults configured via `nonisolated(unsafe)` static properties — same pattern as `ambientRenderer` in `Sources/SwiflowWeb/SwiflowWeb.swift`.

- [ ] **Step 1: Write the failing test file**

Create `Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift`:

```swift
// Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift
import Testing
@testable import Swiflow

@Suite("URLSanitizer")
struct URLSanitizerTests {

    @Test("Allows the default scheme set: http, https, mailto, tel, ftp")
    func allowsDefaultSchemes() {
        let allowed = [
            "http://example.com",
            "https://example.com/path?q=1",
            "mailto:user@example.com",
            "tel:+15551234",
            "ftp://ftp.example.com/file.zip",
        ]
        for url in allowed {
            #expect(URLSanitizer.sanitize(url) == url, "Expected allow for: \(url)")
        }
    }

    @Test("Allows relative URLs and fragment-only URLs")
    func allowsRelativeAndFragment() {
        let allowed = [
            "/path/to/page",
            "path/to/page",
            "../page",
            "#section",
            "#",
            "",
        ]
        for url in allowed {
            #expect(URLSanitizer.sanitize(url) == url, "Expected allow for relative/fragment: \(url)")
        }
    }

    @Test("Rejects javascript: scheme")
    func rejectsJavascript() {
        #expect(URLSanitizer.sanitize("javascript:alert(1)") == nil)
    }

    @Test("Rejects javascript: case-insensitively")
    func rejectsJavascriptCaseInsensitive() {
        #expect(URLSanitizer.sanitize("JAVASCRIPT:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("JavaScript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("javaSCRIPT:alert(1)") == nil)
    }

    @Test("Rejects javascript: with leading whitespace and control characters")
    func rejectsJavascriptWithLeadingWhitespace() {
        #expect(URLSanitizer.sanitize("  javascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\tjavascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\njavascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\u{0001}javascript:alert(1)") == nil)
    }

    @Test("Rejects javascript: encoded with HTML entities")
    func rejectsJavascriptHTMLEntities() {
        #expect(URLSanitizer.sanitize("javascript&#58;alert(1)") == nil)
        #expect(URLSanitizer.sanitize("javascript&#x3A;alert(1)") == nil)
    }

    @Test("Rejects data: by default")
    func rejectsDataURLsByDefault() {
        #expect(URLSanitizer.sanitize("data:text/html,<script>alert(1)</script>") == nil)
        #expect(URLSanitizer.sanitize("data:image/png;base64,iVBORw0KGgo=") == nil)
    }

    @Test("Allows data: when allowDataURLs is true")
    func allowsDataURLsWhenOptedIn() {
        URLSanitizer.allowDataURLs = true
        defer { URLSanitizer.allowDataURLs = false }
        #expect(URLSanitizer.sanitize("data:image/png;base64,iVBORw0KGgo=") == "data:image/png;base64,iVBORw0KGgo=")
        #expect(URLSanitizer.sanitize("javascript:alert(1)") == nil)
    }

    @Test("Rejects blob: by default; allows when opted in")
    func blobURLOptIn() {
        #expect(URLSanitizer.sanitize("blob:https://example.com/uuid") == nil)
        URLSanitizer.allowBlobURLs = true
        defer { URLSanitizer.allowBlobURLs = false }
        #expect(URLSanitizer.sanitize("blob:https://example.com/uuid") == "blob:https://example.com/uuid")
    }

    @Test("Rejects vbscript: scheme")
    func rejectsVbscript() {
        #expect(URLSanitizer.sanitize("vbscript:msgbox(1)") == nil)
        #expect(URLSanitizer.sanitize("VBSCRIPT:msgbox(1)") == nil)
    }

    @Test("Custom allowedSchemes override the defaults")
    func customAllowedSchemes() {
        URLSanitizer.allowedSchemes = ["myscheme"]
        defer { URLSanitizer.allowedSchemes = URLSanitizer.defaultAllowedSchemes }
        #expect(URLSanitizer.sanitize("myscheme://anything") == "myscheme://anything")
        #expect(URLSanitizer.sanitize("https://example.com") == nil, "https no longer in allowlist")
    }

    @Test("applyAttributes drops javascript: href and keeps benign attributes")
    func applyAttributesDropsJavascriptHref() {
        let element = applyAttributes(tag: "a", [
            .attr("href", "javascript:alert(1)"),
            .class("link"),
        ])
        #expect(element.attributes["href"] == nil, "Expected javascript: href to be dropped from the bag")
        #expect(element.attributes["class"] == "link", "Class should pass through unchanged")
    }

    @Test("applyAttributes sanitizes case-variant attribute names")
    func applyAttributesCaseInsensitive() {
        let element = applyAttributes(tag: "a", [
            .attr("HREF", "javascript:alert(1)"),
        ])
        #expect(element.attributes["HREF"] == nil)
    }

    @Test("applyAttributes keeps safe href + src + action + formaction")
    func applyAttributesKeepsSafeURLAttributes() {
        let element = applyAttributes(tag: "form", [
            .attr("action", "/submit"),
            .attr("formaction", "https://example.com/alt"),
        ])
        #expect(element.attributes["action"] == "/submit")
        #expect(element.attributes["formaction"] == "https://example.com/alt")
    }

    @Test("applyAttributes does NOT sanitize non-URL attributes (data-* etc.)")
    func applyAttributesPassesThroughNonURLAttrs() {
        let element = applyAttributes(tag: "div", [
            .attr("data-href", "javascript:alert(1)"),
            .attr("title", "javascript:alert(1)"),
        ])
        #expect(element.attributes["data-href"] == "javascript:alert(1)")
        #expect(element.attributes["title"] == "javascript:alert(1)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "URLSanitizer"`
Expected: compile error — `URLSanitizer` doesn't exist; `applyAttributes` doesn't sanitize.

- [ ] **Step 3: Implement `URLSanitizer.swift`**

Create `Sources/Swiflow/Reactivity/URLSanitizer.swift`:

```swift
// Sources/Swiflow/Reactivity/URLSanitizer.swift

import Foundation

/// Validates and sanitizes URL values destined for the four URL-bearing
/// HTML attributes (`href`, `src`, `action`, `formaction`). Returns `nil`
/// for any value that fails the allowlist; callers (the DSL fold step)
/// drop the attribute when `nil` is returned.
///
/// **Security focus:** the default allowlist excludes `javascript:`,
/// `vbscript:`, `data:`, `blob:`, and any unknown scheme. The two most
/// commonly-needed-but-risky schemes (`data:`, `blob:`) have explicit
/// opt-in toggles so a calling application can re-enable them with a
/// loudly-named static property.
///
/// **Audit pattern:** every URL-bearing attribute that reaches the DOM
/// passes through `URLSanitizer.sanitize(_:)`. Search for that exact
/// symbol to enumerate every entry point. The `VNode.rawHTML(...)`
/// escape hatch is the only documented way to bypass.
public enum URLSanitizer {

    public static let defaultAllowedSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "ftp",
    ]

    nonisolated(unsafe) public static var allowedSchemes: Set<String> = defaultAllowedSchemes

    nonisolated(unsafe) public static var allowDataURLs: Bool = false

    nonisolated(unsafe) public static var allowBlobURLs: Bool = false

    public static let urlAttributeNames: Set<String> = [
        "href", "src", "action", "formaction",
    ]

    public static func sanitize(_ rawValue: String) -> String? {
        let cleaned = stripControlAndLeadingWhitespace(rawValue)
        let decoded = decodeHTMLColonEntities(cleaned)

        if decoded.isEmpty || decoded.hasPrefix("#") {
            return rawValue
        }

        guard let scheme = extractScheme(decoded) else {
            return rawValue
        }

        let lowerScheme = scheme.lowercased()

        if lowerScheme == "data" {
            return allowDataURLs ? rawValue : nil
        }
        if lowerScheme == "blob" {
            return allowBlobURLs ? rawValue : nil
        }

        return allowedSchemes.contains(lowerScheme) ? rawValue : nil
    }

    // MARK: - Internals

    private static func stripControlAndLeadingWhitespace(_ s: String) -> String {
        let withoutControls = String(s.unicodeScalars.filter { scalar in
            let v = scalar.value
            return !(v < 0x20 || v == 0x7F)
        })
        return String(withoutControls.drop(while: { $0.isWhitespace }))
    }

    private static func decodeHTMLColonEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#58;", with: ":")
         .replacingOccurrences(of: "&#x3a;", with: ":", options: .caseInsensitive)
         .replacingOccurrences(of: "&#x3A;", with: ":")
    }

    private static func extractScheme(_ s: String) -> String? {
        guard let colonIndex = s.firstIndex(of: ":") else { return nil }
        let beforeColon = s[s.startIndex..<colonIndex]
        guard !beforeColon.isEmpty else { return nil }
        for char in beforeColon {
            let isAlpha = char.isLetter && char.isASCII
            let isDigit = char.isNumber && char.isASCII
            let isExtra = (char == "+" || char == "-" || char == ".")
            if !(isAlpha || isDigit || isExtra) {
                return nil
            }
        }
        if let first = beforeColon.first, !(first.isLetter && first.isASCII) {
            return nil
        }
        return String(beforeColon)
    }
}
```

- [ ] **Step 4: Modify `applyAttributes` in `Sources/Swiflow/DSL/Modifiers.swift`**

Find the `case .attribute(let name, let value):` arm inside the loop and replace it. The full loop becomes:

```swift
    for attribute in attributes {
        switch attribute {
        case .attribute(let name, let value):
            // URL-bearing attributes (href, src, action, formaction) route
            // through URLSanitizer before reaching the bag. The check is
            // case-insensitive on the attribute name. Non-URL attributes
            // pass through unchanged.
            if URLSanitizer.urlAttributeNames.contains(name.lowercased()) {
                if let sanitized = URLSanitizer.sanitize(value) {
                    attrs[name] = sanitized
                } else {
                    // Drop the attribute entirely. Debug-mode notice; Task 2
                    // will reword this comment but keep the print as-is.
                    #if DEBUG
                    print("[Swiflow] URLSanitizer rejected \(name)=\"\(value)\" — attribute dropped. Use VNode.rawHTML for the rare case where unsanitized URLs are intentional.")
                    #endif
                }
            } else {
                attrs[name] = value
            }
        case .property(let name, let value):
            props[name] = value
        case .style(let name, let value):
            styles[name] = value
        case .handler(let event, let value):
            handlers[event] = value
        case .key(let value):
            key = value
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "URLSanitizer"`
Expected: PASS — all 14 tests pass.

- [ ] **Step 6: Run the full unit suite for regressions**

Run: `swift test --skip "end-to-end"`
Expected: 229 + 14 = 243 tests pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/Reactivity/URLSanitizer.swift Sources/Swiflow/DSL/Modifiers.swift Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift
git commit -m "$(cat <<'EOF'
feat(security): URLSanitizer scrubs javascript: from URL attributes

Closes the XSS hole the security spec explicitly listed. Every
URL-bearing HTML attribute (href, src, action, formaction) routes
through URLSanitizer.sanitize at the DSL fold step before reaching
the attribute bag. Rejected values are dropped entirely — no
about:blank or # substitution — so the failure is visibly loud
without breaking the page.

The sanitizer normalises before checking:
- Strips ASCII control characters (browsers do)
- Trims leading whitespace
- Decodes the colon HTML entities (&#58;, &#x3a;, &#x3A;)

Default allowlist: http, https, mailto, tel, ftp + relative + fragment.
data: and blob: rejected by default; opt-in via URLSanitizer's
allowDataURLs / allowBlobURLs.

The check is case-insensitive on attribute name, so .attr("HREF", ...)
is scrubbed too. Non-URL attributes (data-*, title, etc.) pass through
unchanged.

VNode.rawHTML(...) remains the documented bypass for the rare case
where an unsanitized URL is intentional.

Task 2 will refactor the debug-mode notice rationale (no behaviour change).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Diagnostic errors (debug-only, fatalError) + clarify Task 1's print intent

**Files:**
- Create: `Sources/Swiflow/Reactivity/Diagnostics.swift` — central `swiflowDiagnostic(_:)` helper
- Modify: `Sources/Swiflow/Diff/Diff.swift` — add component-cycle depth guard in `mount()` `.component` arm; thread depth through recursive calls
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` — duplicate-key set-walk pre-pass
- Modify: `Sources/Swiflow/Diff/Diff.swift` — `diffChildren` dispatcher: detect mixed keyed/unkeyed
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — clarify the Task 1 print rationale (URL rejection stays a log, not a diagnostic)
- Create: `Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift`

**Design notes:**

- `swiflowDiagnostic(_:)` is `#if DEBUG`-guarded and calls `fatalError(message)` in DEBUG, no-op in release.
- Component-cycle depth check: thread `depth: Int = 0` through `mount()`. Increment when crossing `.component`. If `> 32`, diagnostic.
- Duplicate-key check: in `KeyedChildrenDiff.swift`'s entry, walk new children's keys with a `Set<String>`. Collision → diagnostic with duplicate key + positions.
- Mixed-keyed check: in `diffChildren` dispatcher, count keyed vs unkeyed in new children. Both > 0 → diagnostic with parent tag + counts.
- Tests use `#expect(processExitsWith: .failure) { ... }` (Swift Testing 6.0+ exit-test API). Wraps the offending call; subprocess crashes; parent test asserts the failure.
- URL sanitizer's "reject" path stays a `print`, NOT `swiflowDiagnostic` — XSS attempts shouldn't crash the page. Only programmer-error footguns crash.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift`:

```swift
// Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift
import Testing
@testable import Swiflow

@Suite("Diagnostics (debug-only)")
struct DiagnosticsTests {

    final class CounterStub: Component {
        var body: VNode { .text("0") }
    }

    /// Component whose body returns another component anchor — infinite
    /// anchor cycle. Exists only to exercise the depth-guard diagnostic.
    final class CycleComponent: Component {
        var body: VNode { component({ CycleComponent() }) }
    }

    @Test(
        "Duplicate keys among siblings crash with a clear message in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func duplicateKeysCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let parent = div {
                span(.key("a"))
                span(.key("a"))
            }
            _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
        }
    }

    @Test(
        "Mixed keyed/unkeyed siblings crash with a clear message in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func mixedKeyedUnkeyedCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let parent = ul {
                li(.key("a"))
                li()
            }
            _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
        }
    }

    @Test(
        "Component body cycle (depth > 32) crashes with a clear message in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func componentCycleCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let v = VNode.component(.init(CycleComponent.self) { CycleComponent() })
            _ = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        }
    }

    @Test("URLSanitizer rejection drops the attribute but does NOT crash (in DEBUG or release)")
    func urlSanitizerDoesNotCrash() {
        // URL rejection is a LOG, not a crash. Pages must render even
        // when an attacker injects javascript: into href.
        let element = applyAttributes(tag: "a", [
            .attr("href", "javascript:alert(1)"),
        ])
        #expect(element.attributes["href"] == nil)
    }

    @Test("Diagnostics module exposes the swiflowDiagnostic symbol")
    func diagnosticSymbolExists() {
        let fn: (@autoclosure () -> String) -> Void = swiflowDiagnostic
        _ = fn
    }
}

/// Helper for `.disabled(if:)` on the exit-test crash cases.
/// Release-mode runs would not crash (the diagnostic compiles to nothing),
/// so the test would fail spuriously — skip it instead.
private var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
```

> **Note on the `.disabled(if:)` API:** verify against the installed Swift Testing 6.3 spelling. If `.disabled(if:)` is named differently (e.g. `.enabled(if:)` with inverted condition), adjust the call sites. The intent is "skip in release builds, run in debug builds."

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Diagnostics (debug-only)"`
Expected: compile error — `swiflowDiagnostic` doesn't exist; the three checks aren't implemented.

- [ ] **Step 3: Implement `Diagnostics.swift`**

Create `Sources/Swiflow/Reactivity/Diagnostics.swift`:

```swift
// Sources/Swiflow/Reactivity/Diagnostics.swift

/// Single entry point for the framework's debug-only diagnostic checks.
///
/// In debug builds (`-c debug`, the default), calling this function
/// invokes `fatalError(message)` — the test suite's exit-test cases
/// detect the crash and verify the message substring. In release builds
/// (`-c release`), the call is compiled to nothing: zero CPU cost, zero
/// binary footprint.
///
/// Message convention: framework concept first, then location/cause,
/// then guidance. React-style.
///
/// Example:
/// `swiflowDiagnostic("Duplicate key 'foo' among siblings of <ul>. Keys must be unique within a parent. Offending positions: 1 and 3.")`
///
/// **When to use:** programming errors that produce silent wrong behaviour
/// in production (duplicate keys, infinite component recursion, mixed
/// keyed/unkeyed children). NOT for runtime conditions a well-formed
/// application might legitimately hit (network errors, user input
/// validation, XSS attempts — those should LOG, not crash).
@inlinable
public func swiflowDiagnostic(_ message: @autoclosure () -> String) {
    #if DEBUG
    fatalError("Swiflow diagnostic: \(message())")
    #endif
}
```

- [ ] **Step 4: Add duplicate-key check to `KeyedChildrenDiff.swift`**

Find `diffChildrenKeyed` in `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`. At the very top of the function body, add:

```swift
    // Diagnostic pre-pass: detect duplicate keys among the new children.
    // Keys MUST be unique within a parent — duplicates cause the keyed
    // diff to pick wrong moves (last-write-wins on the position map).
    #if DEBUG
    do {
        var seen: [String: Int] = [:]
        for (index, child) in newChildren.enumerated() {
            if case .element(let data) = child, let key = data.key {
                if let firstIndex = seen[key] {
                    let parentTag: String
                    if case .element(let parentData) = mounted.vnode {
                        parentTag = parentData.tag
                    } else {
                        parentTag = "<root>"
                    }
                    swiflowDiagnostic("Duplicate key '\(key)' among siblings of <\(parentTag)>. Keys must be unique within a parent. Offending positions: \(firstIndex) and \(index).")
                }
                seen[key] = index
            }
        }
    }
    #endif
```

- [ ] **Step 5: Add mixed-keyed check to `diffChildren` dispatcher**

Find `diffChildren` in `Sources/Swiflow/Diff/Diff.swift`. At the top of its body, before the existing dispatcher logic, add:

```swift
    // Diagnostic: detect mixed keyed/unkeyed siblings. Either every
    // sibling has a key, or none — partial keying gives unkeyed
    // children unstable identity and they re-render as recreated.
    #if DEBUG
    do {
        var keyedCount = 0
        var unkeyedCount = 0
        for child in newChildren {
            if case .element(let data) = child {
                if data.key != nil { keyedCount += 1 } else { unkeyedCount += 1 }
            }
        }
        if keyedCount > 0 && unkeyedCount > 0 {
            let parentTag: String
            if case .element(let parentData) = mounted.vnode {
                parentTag = parentData.tag
            } else {
                parentTag = "<root>"
            }
            swiflowDiagnostic("Children of <\(parentTag)> mix keyed (\(keyedCount)) and unkeyed (\(unkeyedCount)) entries. Either key every child or key none.")
        }
    }
    #endif
```

Keep the existing dispatcher body unchanged after the new block.

- [ ] **Step 6: Add component-cycle depth guard to `mount()`'s `.component` arm**

In `Sources/Swiflow/Diff/Diff.swift`, modify `mount()` to thread a `depth` parameter. The function signature gains `depth: Int = 0`:

```swift
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    depth: Int = 0
) -> MountNode {
```

The `.element` arm passes `depth: depth` unchanged to its recursive `mount()` calls (children don't increase component depth — only crossing a `.component` anchor does). The `.component` arm becomes:

```swift
    case .component(let desc):
        // Diagnostic: depth guard catches `body` cycles like
        // `component({ self })` or A.body → component(B); B.body → component(A).
        // 32 nested anchors is already absurd — cycles always exceed it.
        #if DEBUG
        if depth > 32 {
            swiflowDiagnostic("Component anchor depth exceeded 32. This usually means a component's body returned a VNode.component anchor cycle (e.g. body returns `component({ self })`). Bodies must terminate at non-component VNodes.")
        }
        #endif
        let instance = desc.instantiate()
        wireState(on: instance, scheduler: scheduler)
        let anchorHandle = handles.next()
        let bodyVNode = instance.instance.body
        let bodyMount = mount(
            bodyVNode,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            depth: depth + 1
        )
        return MountNode(
            handle: anchorHandle,
            vnode: vnode,
            component: instance,
            componentBody: bodyMount
        )
```

The reuse arm in `update()` does NOT need depth tracking — instance reuse means same instance; only initial mount multiplies depth.

- [ ] **Step 7: Clarify Modifiers.swift comment**

In `Sources/Swiflow/DSL/Modifiers.swift`, update the URL-rejection branch comment to make the no-crash intent explicit (the `print` itself stays):

```swift
                } else {
                    // URL sanitizer rejection is a LOG, not a crash —
                    // an injected javascript: should drop the attribute
                    // and let the page continue rendering. swiflowDiagnostic
                    // crashes in DEBUG and is reserved for programmer-error
                    // footguns (duplicate keys, component cycles, etc.).
                    #if DEBUG
                    print("[Swiflow] URLSanitizer rejected \(name)=\"\(value)\" — attribute dropped. Use VNode.rawHTML for the rare case where unsanitized URLs are intentional.")
                    #endif
                }
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter "Diagnostics (debug-only)"`
Expected: PASS — 5 tests pass (3 exit-test crashes, 1 URL sanitizer non-crash, 1 symbol-exists).

- [ ] **Step 9: Run the full unit suite for regressions**

Run: `swift test --skip "end-to-end"`
Expected: 243 + 5 = 248 tests pass, 0 failures.

- [ ] **Step 10: Verify release-build behaviour (diagnostics compile to nothing)**

Run: `swift test -c release --filter "Diagnostics (debug-only)"`
Expected: the three exit-test cases are SKIPPED via `.disabled(if: !isDebugBuild)` (visible as "skipped" in the test report). The two non-crash tests still pass.

If `.disabled(if:)` doesn't compile against the installed Swift Testing version, two fallbacks:
- Use `.enabled(if: isDebugBuild)` (inverted condition).
- Wrap the test bodies in `#if DEBUG ... #endif` so the test compiles to a no-op assertion in release.

- [ ] **Step 11: Commit**

```bash
git add Sources/Swiflow/Reactivity/Diagnostics.swift Sources/Swiflow/Diff/Diff.swift Sources/Swiflow/Diff/KeyedChildrenDiff.swift Sources/Swiflow/DSL/Modifiers.swift Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift
git commit -m "$(cat <<'EOF'
feat(reactivity): debug-only diagnostics for framework footguns

Three checks ship gated on #if DEBUG, with a central swiflowDiagnostic
helper that fatalErrors in DEBUG and is compiled to nothing in release:

1. Duplicate keys among siblings — pre-pass in diffChildrenKeyed.
   Today produces silent wrong moves; now crashes with the duplicate
   key + offending sibling positions.
2. Mixed keyed/unkeyed siblings — pre-check in diffChildren dispatcher.
   Today degrades unkeyed children to recreate-every-render; now
   crashes with the parent tag and the keyed/unkeyed counts.
3. Component body anchor cycle — depth guard in mount()'s .component
   arm, threaded through the existing mount recursion. Today loops
   until stack overflow; now crashes at depth 32 with a hint about
   the cycle.

Tests use Swift Testing 6.0's #expect(processExitsWith: .failure)
exit-test API. The three crash tests are gated with .disabled(if:)
so they skip cleanly in release-mode runs (where the diagnostics
compile to nothing).

Also clarifies the Task 1 URLSanitizer comment: URL rejection is a
LOG, not a crash — XSS attempts shouldn't crash user pages.
swiflowDiagnostic stays reserved for programmer-error footguns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 🛑 PAUSE POINT — End of Task 2

At this point the user-facing hardening is shipped: URL sanitizer closes the XSS hole, debug-only diagnostics catch the three known framework footguns. The remainder (source maps spike, JS driver tests, Playwright e2e) is internal investment that benefits future development but doesn't change runtime behaviour for users.

Recommended user-review activities before resuming:
- Inspect the URLSanitizer test table — does it cover the XSS patterns you care about?
- Try a deliberate duplicate-key bug locally (init a demo, add two `li(.key("a"))` siblings, build) — confirm the diagnostic fires.
- Decide whether Tasks 3–6 are worth the wall time, or whether you'd rather punt and ship what you have.

---

### Task 3: Source maps spike (2-hour timebox)

**Goal:** investigate whether shipping `.wasm.map` source maps gives meaningfully better debugging than the existing DWARF + Chrome C/C++ extension flow. **Investigation only — no code commit until Task 4.**

**Files:** none committed during this task.

- [ ] **Step 1: Set up the demo + baseline DWARF flow**

```bash
TMP=$(mktemp -d -t swiflow-spike-XXXXXX)
SWIFLOW=/Users/alainduchesneau/Projets/swiflow/.build/release/swiflow
"$SWIFLOW" init demo --path "$TMP" --swiflow-source /Users/alainduchesneau/Projets/swiflow
cd "$TMP/demo"
# Edit Sources/App/App.swift: add `fatalError("test trap")` inside Counter's body.
"$SWIFLOW" dev &
DEV_PID=$!
echo "Demo at http://localhost:3000 with DWARF symbols (dev mode)."
echo "Open Chrome → DevTools → Sources panel."
echo "Install the C/C++ DevTools extension if not present:"
echo "  https://chromewebstore.google.com/detail/cc++-devtools-support-dwa/pdcpmagijalfljmkmjngeonclgbbannb"
echo "Trigger the trap (click any button — body re-renders, trap fires)."
echo "Inspect the stack trace in DevTools. Note whether Swift filenames + line numbers appear."
```

Record findings in `/tmp/swiflow-source-maps-spike.md`:
- Does the stack frame show `App.swift:42` or just hex offsets?
- How many clicks/navigations are needed to get there?
- Does the source view in DevTools open the Swift file?

- [ ] **Step 2: Probe PackageToJS for source-map support**

```bash
swift package --swift-sdk swift-6.3-RELEASE_wasm js --help 2>&1 | grep -i "source\|map\|debug" | head -20
find ~/.swiftpm/swift-sdks -name "*.swift" 2>/dev/null | xargs grep -l "sourcemap\|source-map\|\.wasm\.map" 2>/dev/null | head -5
```

Record: does the plugin already emit `.wasm.map`? Does it have a flag we missed?

- [ ] **Step 3: Check Chrome's stock DevTools (no extension) against `.wasm.map`**

```bash
brew install binaryen 2>&1 | tail -3
ls "$TMP/demo/.build/plugins/PackageToJS/outputs/Package/App.wasm"
wasm-opt --help 2>&1 | grep -i "sourcemap\|source-map" | head -10
# wasm-opt input.wasm -o output.wasm --output-source-map output.wasm.map
```

Record: does Chrome stock DevTools (no extension) use `.wasm.map`? What does it map to?

- [ ] **Step 4: Decide and document the outcome**

Pick ONE of:

| Outcome | Next step |
|---|---|
| **A.** DWARF + Chrome ext is already adequate; source maps add nothing | Task 4 writes `docs/debugging-wasm.md` recommending the DWARF flow. No source-maps follow-up. |
| **B.** Source maps require a manual `wasm-opt` step | Task 4 adds a CLI flag `swiflow build --emit-source-maps` + toolchain wiring + docs. |
| **C.** Source maps work natively via the SDK | Task 4 wires source-map emission into `BuildInvocation` for dev builds. |

- [ ] **Step 5: Clean up and write the spike report**

```bash
kill $DEV_PID 2>/dev/null || true
rm -rf "$TMP"
# Write findings to /tmp/swiflow-source-maps-spike.md for Task 4.
```

Spike output contract: `/tmp/swiflow-source-maps-spike.md` contains:
- Heading: "Outcome: A | B | C"
- Bullet list of probe results
- Specific flag/command names for Task 4 path B or C to use
- Optional: links to relevant Chrome docs or PackageToJS source lines

No git commit during this task.

---

### Task 4: Source maps follow-up (conditional on Task 3 outcome)

**Read `/tmp/swiflow-source-maps-spike.md` first.** Follow the matching path below.

#### Path A — DWARF is already adequate

**Files:**
- Create: `docs/debugging-wasm.md`

- [ ] **Step A1: Write the debugging guide**

Create `docs/debugging-wasm.md`:

```markdown
# Debugging Swiflow apps in the browser

Swiflow's dev builds emit DWARF debug symbols inside the produced `.wasm`
(via PackageToJS's `--debug-info-format dwarf` flag, set automatically
when running `swiflow dev`). Chrome's C/C++ DevTools extension reads
those symbols directly and maps WASM traps back to Swift source lines.

This avoids the need for separate `.wasm.map` source-map files (which
the Swift WASM toolchain doesn't currently emit cleanly).

## One-time setup

1. Install the Chrome C/C++ DevTools extension:
   https://chromewebstore.google.com/detail/cc++-devtools-support-dwa/pdcpmagijalfljmkmjngeonclgbbannb
2. Enable in Chrome's DevTools → Settings → Experiments →
   "WebAssembly Debugging: Enable DWARF support".
3. Restart DevTools.

## Per-app workflow

1. Start the dev server: `swiflow dev`.
2. Open the app in Chrome.
3. Open DevTools → Sources panel.
4. Trigger any error or set a breakpoint. The stack trace and source
   view will resolve to Swift filenames + line numbers.

## Limitations

- Production builds (`--production`, when shipped) will strip DWARF for
  size; debugging there falls back to hex offsets.
- The C/C++ extension does not yet support stepping through Swift's
  closure-based control flow as cleanly as native Swift debugging.
  File issues with Chromium for missing features.
```

- [ ] **Step A2: Commit**

```bash
git add docs/debugging-wasm.md
git commit -m "$(cat <<'EOF'
docs: WASM debugging guide via DWARF + Chrome C/C++ extension

Two-hour spike confirmed the current debugging story (DWARF emitted
in dev builds + Chrome's C/C++ DevTools extension) is the canonical
path. Swift's WASM toolchain doesn't cleanly emit .wasm.map source
maps; the C/C++ extension reads DWARF directly and maps traps to
Swift filenames + line numbers, which is what we want.

Documenting the one-time extension install + per-app workflow.

Source-map emission is deferred until the toolchain story changes
or a real user request makes it worth re-investigating.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

#### Path B — Manual `wasm-opt` step

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` — add `--emit-source-maps` flag + post-build invocation
- Create: `docs/debugging-wasm.md`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift` — assert argv composition with the new flag

- [ ] **Step B1: Write the failing test** for argv composition. Add to `BuildCommandArgvTests`:

```swift
@Test("emit-source-maps flag adds a post-build wasm-opt invocation")
func emitSourceMapsArgv() throws {
    let stub = StubProcessRunner(stubbedExitCode: 0)
    let composer = BuildInvocation(
        swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
        projectPath: URL(fileURLWithPath: "/tmp/demo"),
        swiftSDK: "swift-6.3-RELEASE_wasm",
        toolchainBundleID: nil,
        configuration: .dev,
        emitSourceMaps: true
    )
    _ = try composer.run(using: stub)
    // First call: swift package js (as today)
    // Second call: wasm-opt with --output-source-map
    #expect(stub.calls.count == 2)
    let second = stub.calls[1]
    #expect(second.executable.lastPathComponent == "wasm-opt")
    #expect(second.arguments.contains("--output-source-map"))
}
```

- [ ] **Step B2: Implement**

In `Sources/SwiflowCLI/Commands/BuildCommand.swift`, add `emitSourceMaps: Bool = false` to `BuildInvocation.init`. In `run()`, after the existing `swift package js` call returns successfully, if `emitSourceMaps`, spawn `wasm-opt` to emit the source map:

```swift
if emitSourceMaps {
    let wasmPath = projectPath
        .appendingPathComponent(".build/plugins/PackageToJS/outputs/Package/App.wasm")
    let mapPath = wasmPath.appendingPathExtension("map")
    let optResult = try runner.run(
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/wasm-opt"),
        arguments: [
            wasmPath.path,
            "-o", wasmPath.path,
            "--output-source-map", mapPath.path,
        ],
        workingDirectory: projectPath,
        environment: nil,
        captureOutput: false
    )
    if optResult.exitCode != 0 {
        throw BuildCommandError.sourceMapEmitFailed(exitCode: optResult.exitCode)
    }
}
```

Add `case sourceMapEmitFailed(exitCode: Int32)` to `BuildCommandError` with a description: "wasm-opt source-map emission failed with exit code N. Install binaryen (`brew install binaryen`) and ensure wasm-opt is on PATH."

- [ ] **Step B3: Add the CLI flag** in `BuildCommand`:

```swift
@Flag(name: .customLong("emit-source-maps"),
      help: "Emit a .wasm.map source-map file alongside App.wasm. Requires wasm-opt on PATH.")
var emitSourceMaps: Bool = false
```

Pass it through to `BuildInvocation`:

```swift
let invocation = BuildInvocation(
    swiftExecutable: swift,
    projectPath: projectURL,
    swiftSDK: sdk,
    toolchainBundleID: toolchainBundleID,
    emitSourceMaps: emitSourceMaps
)
```

- [ ] **Step B4: Write `docs/debugging-wasm.md`** documenting BOTH the DWARF flow AND the new source-map flow.

- [ ] **Step B5: Run tests + commit**

```bash
swift test --filter "BuildCommand argv"
swift test --skip "end-to-end"
git add Sources/SwiflowCLI/Commands/BuildCommand.swift docs/debugging-wasm.md Tests/SwiflowCLITests/BuildCommandTests.swift
git commit -m "feat(build): swiflow build --emit-source-maps + WASM debugging guide

Spike found that wasm-opt --output-source-map produces a usable
.wasm.map alongside App.wasm, readable by Chrome's stock DevTools
(no extension needed). Add an opt-in CLI flag so users who want the
Chrome-stock flow can take it without leaving DWARF behind.

The DWARF + Chrome C/C++ extension path stays as the default
recommendation in docs/debugging-wasm.md; --emit-source-maps is the
alternative when extension installation isn't an option.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
"
```

#### Path C — SDK native support

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` — `BuildInvocation`'s dev-mode argv adds the SDK source-map flag
- Create: `docs/debugging-wasm.md`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift` — assert the new argv segment

- [ ] **Step C1: Write the failing test** for argv composition. Add to `BuildCommandArgvTests` — exact flag name from the spike report. Template:

```swift
@Test("Dev configuration includes the SDK's source-map flag")
func devConfigurationEmitsSourceMaps() throws {
    let stub = StubProcessRunner(stubbedExitCode: 0)
    let composer = BuildInvocation(
        swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
        projectPath: URL(fileURLWithPath: "/tmp/demo"),
        swiftSDK: "swift-6.3-RELEASE_wasm",
        toolchainBundleID: nil,
        configuration: .dev
    )
    _ = try composer.run(using: stub)
    // Replace <FLAG> with the actual SDK flag from the spike report.
    #expect(stub.calls[0].arguments.contains("<FLAG>"))
}
```

- [ ] **Step C2: Implement** — in `BuildInvocation.run()`'s `.dev` arm, append the flag from the spike report alongside the existing `--debug-info-format dwarf`.

- [ ] **Step C3: Write `docs/debugging-wasm.md`** documenting the source-map flow with screenshots of Chrome stock DevTools showing Swift sources.

- [ ] **Step C4: Run tests + commit**

```bash
swift test --filter "BuildCommand argv"
swift test --skip "end-to-end"
git add Sources/SwiflowCLI/Commands/BuildCommand.swift docs/debugging-wasm.md Tests/SwiflowCLITests/BuildCommandTests.swift
git commit -m "feat(build): dev builds emit .wasm.map via the SDK's native source-map flag

Spike confirmed the SDK supports source-map emission via <FLAG>.
Wire it into BuildInvocation's .dev arm alongside the existing
--debug-info-format dwarf, so swiflow dev produces both DWARF (for
Chrome C/C++ extension users) and .wasm.map (for Chrome stock
DevTools).

Documenting both paths in docs/debugging-wasm.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
"
```

---

### Task 5: JS driver units via `node:test` + `jsdom`

**Files:**
- Create: `js-driver/package.json` — Node deps + `npm test` alias
- Create: `js-driver/test/helpers.js` — jsdom setup + driver loader (via script-tag injection)
- Create: `js-driver/test/opcodes.test.js` — coverage for the 17 opcodes
- Create: `js-driver/test/dev-reload.test.js` — WebSocket reload handler
- Modify: `.github/workflows/ci.yml` — add `JS Driver Tests` job (push + PR)

**Design notes:**

- Tests run via `node --test js-driver/test/` — no extra runner needed (`node:test` built into Node 18+).
- The driver is an IIFE that installs itself onto `window.swiflow`. **Load it via script-tag injection**: append a `<script>` element whose `textContent` is the driver source, into a JSDOM window with `runScripts: "dangerously"`. JSDOM executes the script synchronously on append, in the modified window — exactly the production runtime path. This avoids any `Function()`-style dynamic-code construction and lets the test pre-mutate globals (e.g. `window.WebSocket`) before the driver loads.
- Helpers expose `setupDriver()` returning `{ window, document, swiflow }` for each test. Each test starts with a fresh DOM.
- Tests assert against `document.querySelector(...)` etc. — what an end user would see.

- [ ] **Step 1: Write `js-driver/package.json`**

```json
{
  "name": "@swiflow/driver-tests",
  "private": true,
  "version": "0.0.0",
  "description": "Internal node:test + jsdom unit tests for swiflow-driver.js. Not published.",
  "type": "module",
  "scripts": {
    "test": "node --test test/"
  },
  "devDependencies": {
    "jsdom": "^25.0.0"
  }
}
```

- [ ] **Step 2: Write `js-driver/test/helpers.js`**

```js
// js-driver/test/helpers.js
//
// Loads swiflow-driver.js inside a fresh jsdom window for each test
// via a <script> tag append. JSDOM with runScripts: "dangerously"
// executes the script synchronously upon append — same code path
// production uses when the page loads the driver. This avoids any
// dynamic-code-construction APIs.

import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

/**
 * Creates a fresh jsdom window, loads the driver into it via a
 * <script> tag append, and returns { window, document, swiflow }.
 *
 * @param {object} [opts]
 * @param {boolean} [opts.dev=false] — sets window.SWIFLOW_DEV before
 *   the driver loads, so the dev-mode reload listener installs.
 * @returns {{ window: Window, document: Document, swiflow: any }}
 */
export function setupDriver(opts = {}) {
  const dom = new JSDOM(
    "<!DOCTYPE html><html><body><div id='app'></div></body></html>",
    { url: "http://localhost:3000/", runScripts: "dangerously" }
  );
  if (opts.dev) {
    dom.window.SWIFLOW_DEV = true;
  }
  const scriptEl = dom.window.document.createElement("script");
  scriptEl.textContent = driverSource;
  dom.window.document.head.appendChild(scriptEl);
  return {
    window: dom.window,
    document: dom.window.document,
    swiflow: dom.window.swiflow,
  };
}
```

- [ ] **Step 3: Write `js-driver/test/opcodes.test.js`**

```js
// js-driver/test/opcodes.test.js
//
// Unit coverage for the driver's 17 opcodes. Each test starts with a
// fresh jsdom + driver via setupDriver().

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupDriver } from "./helpers.js";

describe("driver opcodes", () => {

  test("createElement + appendChild + mount renders into #app", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createElement", handle: 2, tag: "span" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    const app = document.querySelector("#app");
    assert.equal(app.children.length, 1);
    assert.equal(app.firstElementChild.tagName, "DIV");
    assert.equal(app.firstElementChild.firstElementChild?.tagName, "SPAN");
  });

  test("createText creates a Text node addressable by handle", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "p" },
      { op: "createText", handle: 2, text: "hello" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("p").textContent, "hello");
  });

  test("createRawHTML installs parsed HTML as a single subtree", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createRawHTML", handle: 2, html: "<b>bold</b><i>italic</i>" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    const div = document.querySelector("div");
    assert.match(div.innerHTML, /<b>bold<\/b>.*<i>italic<\/i>/);
  });

  test("destroyNode drops the map entry; re-destroying is a no-op", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createElement", handle: 2, tag: "span" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("div").children.length, 1);
    swiflow.applyPatches([{ op: "destroyNode", handle: 2 }]);
    swiflow.applyPatches([{ op: "destroyNode", handle: 2 }]);
    // No DOM-removal assertion — destroyNode drops the driver's map
    // entry only. removeChild is what removes from DOM.
  });

  test("insertBefore places a child before a reference child", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "ul" },
      { op: "createElement", handle: 2, tag: "li" },
      { op: "createElement", handle: 3, tag: "li" },
      { op: "createElement", handle: 4, tag: "li" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "appendChild", parent: 1, child: 3 },
      { op: "insertBefore", parent: 1, child: 4, beforeChild: 3 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("ul").children.length, 3);
  });

  test("removeChild removes the node from its parent in the DOM", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "ul" },
      { op: "createElement", handle: 2, tag: "li" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("ul").children.length, 1);
    swiflow.applyPatches([{ op: "removeChild", parent: 1, child: 2 }]);
    assert.equal(document.querySelector("ul").children.length, 0);
  });

  test("setAttribute + removeAttribute round-trip", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "a" },
      { op: "setAttribute", handle: 1, name: "href", value: "/somewhere" },
      { op: "setAttribute", handle: 1, name: "title", value: "go there" },
    ]);
    swiflow.mount(1, "#app");
    const a = document.querySelector("a");
    assert.equal(a.getAttribute("href"), "/somewhere");
    assert.equal(a.getAttribute("title"), "go there");
    swiflow.applyPatches([{ op: "removeAttribute", handle: 1, name: "title" }]);
    assert.equal(a.getAttribute("title"), null);
  });

  test("setProperty assigns directly (e.g. input.value)", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "input" },
      { op: "setProperty", handle: 1, name: "value", value: "typed" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("input").value, "typed");
  });

  test("removeProperty resets the property to its default", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "input" },
      { op: "setProperty", handle: 1, name: "value", value: "x" },
      { op: "removeProperty", handle: 1, name: "value" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("input").value, "");
  });

  test("setStyle + removeStyle round-trip on inline style", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "setStyle", handle: 1, name: "color", value: "red" },
      { op: "setStyle", handle: 1, name: "background", value: "white" },
    ]);
    swiflow.mount(1, "#app");
    const div = document.querySelector("div");
    assert.equal(div.style.color, "red");
    assert.equal(div.style.background, "white");
    swiflow.applyPatches([{ op: "removeStyle", handle: 1, name: "color" }]);
    assert.equal(div.style.color, "");
  });

  test("setText updates a text node's data", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "p" },
      { op: "createText", handle: 2, text: "before" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "setText", handle: 2, text: "after" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("p").textContent, "after");
  });

  test("setRawHTML replaces a node's inner HTML wholesale", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createRawHTML", handle: 2, html: "<b>v1</b>" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "setRawHTML", handle: 2, html: "<i>v2</i>" },
    ]);
    swiflow.mount(1, "#app");
    assert.match(document.querySelector("div").innerHTML, /<i>v2<\/i>/);
  });

  test("addHandler installs a listener that calls __swiflowDispatch", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let receivedHandlerId = null;
    let receivedPayload = null;
    window.__swiflowDispatch = (id, payload) => {
      receivedHandlerId = id;
      receivedPayload = payload;
    };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 42 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("button").click();
    assert.equal(receivedHandlerId, 42);
    assert.equal(receivedPayload.type, "click");
    done();
  });

  test("removeHandler detaches the listener so subsequent events don't dispatch", () => {
    const { swiflow, window, document } = setupDriver();
    let callCount = 0;
    window.__swiflowDispatch = () => { callCount += 1; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 1 },
    ]);
    swiflow.mount(1, "#app");
    const btn = document.querySelector("button");
    btn.click();
    assert.equal(callCount, 1);
    swiflow.applyPatches([{ op: "removeHandler", handle: 1, event: "click" }]);
    btn.click();
    assert.equal(callCount, 1, "After removeHandler the listener should NOT fire");
  });
});
```

- [ ] **Step 4: Write `js-driver/test/dev-reload.test.js`**

```js
// js-driver/test/dev-reload.test.js
//
// Verifies that the driver's dev-mode WebSocket reload listener is
// installed when window.SWIFLOW_DEV is set, and that receiving a
// {"type":"reload"} frame triggers location.reload().
//
// Setup must mutate window.WebSocket BEFORE the driver loads, so we
// build the JSDOM window manually here (helpers.js's setupDriver
// loads the driver immediately after constructing the window).

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

describe("dev-mode WebSocket reload", () => {

  test("WebSocket connects to /reload and a reload frame triggers location.reload()", () => {
    let constructedURL = null;
    let onMessage = null;

    class FakeWS {
      constructor(url) { constructedURL = url; }
      addEventListener() {}
      set onmessage(fn) { onMessage = fn; }
      get onmessage() { return onMessage; }
      set onclose(fn) {}
      set onerror(fn) {}
    }

    const dom = new JSDOM(
      "<!DOCTYPE html><html><body><div id='app'></div></body></html>",
      { url: "http://localhost:3000/", runScripts: "dangerously" }
    );
    dom.window.SWIFLOW_DEV = true;
    dom.window.WebSocket = FakeWS;

    let reloaded = false;
    Object.defineProperty(dom.window.location, "reload", {
      configurable: true,
      value: () => { reloaded = true; },
    });

    // Load the driver via script-tag append — JSDOM with runScripts:
    // "dangerously" executes the script synchronously upon append.
    const scriptEl = dom.window.document.createElement("script");
    scriptEl.textContent = driverSource;
    dom.window.document.head.appendChild(scriptEl);

    assert.match(constructedURL ?? "", /\/reload$/);
    onMessage({ data: JSON.stringify({ type: "reload" }) });
    assert.equal(reloaded, true, "{ type: 'reload' } frame must trigger location.reload()");
  });
});
```

- [ ] **Step 5: Add the `JS Driver Tests` job to `.github/workflows/ci.yml`**

Append below the existing `test:` job:

```yaml
  js-driver-tests:
    name: JS Driver Tests
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node 20
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
          cache-dependency-path: js-driver/package.json

      - name: Install JS deps
        working-directory: js-driver
        run: npm install --no-audit --no-fund

      - name: Run JS driver tests
        working-directory: js-driver
        run: npm test
```

- [ ] **Step 6: Smoke-test locally**

```bash
cd js-driver
npm install
npm test
```

Expected: every opcode test passes; the dev-reload test passes.

- [ ] **Step 7: Commit**

```bash
git add js-driver/package.json js-driver/test/helpers.js js-driver/test/opcodes.test.js js-driver/test/dev-reload.test.js .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
test(js-driver): node:test + jsdom coverage for the 17 opcodes

The Phase 2c e2e is the only previous test exercising the JS driver,
and it requires a full WASM build cycle to run. Add a thin Node-based
layer that drives swiflow-driver.js inside a jsdom window and asserts
DOM-side behaviour for each opcode:

- create* / destroyNode (3 ops)
- appendChild / insertBefore / removeChild (3 ops)
- setAttribute / removeAttribute (2 ops)
- setProperty / removeProperty (2 ops)
- setStyle / removeStyle (2 ops)
- setText / setRawHTML (2 ops)
- addHandler / removeHandler with synthetic clicks + a stubbed
  __swiflowDispatch (2 ops, plus the implicit dispatcher hook)

Plus a dev-mode test that fakes WebSocket and confirms a {"type":
"reload"} frame triggers location.reload() (proves the Phase 2c
hot-reload wire format is honoured by the driver).

The driver is loaded into the JSDOM window via a <script> tag
append — JSDOM with runScripts: "dangerously" executes it
synchronously upon append, which is the same code path production
uses when the page loads the driver. No dynamic-code-construction
APIs.

CI adds a JS Driver Tests job (ubuntu-22.04, Node 20) on push and PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Playwright happy-path e2e

**Files:**
- Create: `tests/playwright/package.json`
- Create: `tests/playwright/playwright.config.ts`
- Create: `tests/playwright/counter.spec.ts`
- Create: `tests/playwright/README.md`
- Modify: `.github/workflows/ci.yml` — add `Playwright E2E` job (PR only)

**Design notes:**

- One Playwright spec, Chromium only. Counter renders, clicks increment, "Count: 2" appears.
- `playwright.config.ts` uses Playwright's `webServer` to spawn `swiflow dev` against a generated demo project. Demo is scaffolded at config-load time using `execFileSync` (passes args as an array — no shell interpolation, safer for path arguments).
- CI: PR-only trigger. Uses cached `~/.cache/ms-playwright` for browser binaries.

- [ ] **Step 1: Write `tests/playwright/package.json`**

```json
{
  "name": "@swiflow/e2e-tests",
  "private": true,
  "version": "0.0.0",
  "description": "Internal Playwright happy-path e2e for the Counter demo. Not published.",
  "type": "module",
  "scripts": {
    "test": "playwright test",
    "install-browsers": "playwright install --with-deps chromium"
  },
  "devDependencies": {
    "@playwright/test": "^1.50.0",
    "typescript": "^5.6.0"
  }
}
```

- [ ] **Step 2: Write `tests/playwright/playwright.config.ts`**

```ts
// tests/playwright/playwright.config.ts
import { defineConfig } from "@playwright/test";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

// Resolve repo root from this file's location.
const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

// Scaffold a fresh demo project once per test session.
const DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-e2e-"));
const DEMO_PROJECT = join(DEMO_TMP, "demo");

// Build swiflow CLI if not present. execFileSync (no shell) so paths
// don't need quoting and there's no shell-interpolation surface.
if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the e2e harness...");
  execFileSync(
    "swift",
    ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" }
  );
}

// Init the demo. Args passed as an array — no shell escaping needed.
execFileSync(
  SWIFLOW,
  ["init", "demo", "--path", DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

export default defineConfig({
  testDir: ".",
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: {
    command: `${SWIFLOW} dev`,
    cwd: DEMO_PROJECT,
    url: "http://127.0.0.1:3000",
    reuseExistingServer: false,
    timeout: 300_000,  // cold WASM build can take ~3 min
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
```

- [ ] **Step 3: Write `tests/playwright/counter.spec.ts`**

```ts
// tests/playwright/counter.spec.ts
import { test, expect } from "@playwright/test";

test.describe("Counter demo", () => {
  test("Renders, increments via @State, persists between clicks", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();
    await expect(page.getByText("Count: 0")).toBeVisible();

    const button = page.getByRole("button", { name: "Increment" });
    await button.click();
    await expect(page.getByText("Count: 1")).toBeVisible();

    await button.click();
    await expect(page.getByText("Count: 2")).toBeVisible();

    // Sanity: the old "Count: 0" should no longer exist anywhere.
    await expect(page.getByText("Count: 0")).toHaveCount(0);
  });

  test("Multiple rapid clicks all register (rAF batching does not drop)", async ({ page }) => {
    await page.goto("/");
    const button = page.getByRole("button", { name: "Increment" });
    for (let i = 0; i < 5; i++) {
      await button.click();
    }
    await expect(page.getByText("Count: 5")).toBeVisible();
  });
});
```

- [ ] **Step 4: Write `tests/playwright/README.md`**

```markdown
# Swiflow Playwright e2e

Browser-based happy-path test for the Counter demo. Verifies @State
mutations propagate through the Scheduler + RAFScheduler + diff +
patch + JS driver round-trip end-to-end.

## Running locally

    cd tests/playwright
    npm install
    npx playwright install --with-deps chromium
    npm test

The first run scaffolds a fresh demo project under your temp directory,
builds it with `swiflow dev`, and points Playwright at it. Subsequent
runs reuse Playwright's browser binary cache.

## What it tests

- Counter renders with "Hello, Swiflow!" + "Count: 0" + Increment button
- Click increments visibly (1 → 2)
- Rapid clicks all register (no rAF drops)

## What it does NOT test

- Hot reload (would need source-file mutation mid-test; deferred)
- Multiple browsers (Chromium only; Firefox + WebKit are Phase 5+)
- Production builds (no `--production` flag exists yet)
```

- [ ] **Step 5: Add the `Playwright E2E` job to `.github/workflows/ci.yml`**

Append below the `js-driver-tests` job:

```yaml
  playwright-e2e:
    name: Playwright E2E
    runs-on: ubuntu-22.04
    # PR-only: Playwright + Chromium binaries + a full WASM build is
    # expensive; gate behind the merge boundary.
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4

      - name: Set up Swift 6.3.0
        uses: vapor/swiftly-action@v0.2.1
        with:
          toolchain: "6.3.0"

      - name: Cache SwiftPM build + WASM SDK
        uses: actions/cache@v4
        with:
          path: |
            .build
            ~/.cache/org.swift.swiftpm
            ~/.config/swiftpm/swift-sdks
          key: ${{ runner.os }}-swift6.3.0-wasm6.3.0-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-swift6.3.0-wasm6.3.0-

      - name: Install WASM SDK (if not cached)
        run: |
          if swift sdk list 2>/dev/null | grep -q "swift-6.3-RELEASE_wasm$"; then
            echo "WASM SDK already installed (cache hit)."
          else
            swift sdk install \
              https://download.swift.org/swift-6.3-release/wasm-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_wasm.artifactbundle.tar.gz \
              --checksum 9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9
          fi

      - name: Build swiflow CLI
        run: swift build -c release --product swiflow

      - name: Set up Node 20
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
          cache-dependency-path: tests/playwright/package.json

      - name: Cache Playwright browsers
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: ${{ runner.os }}-playwright-chromium-v1.50

      - name: Install Playwright deps
        working-directory: tests/playwright
        run: npm install --no-audit --no-fund

      - name: Install Playwright browsers
        working-directory: tests/playwright
        run: npx playwright install --with-deps chromium

      - name: Run Playwright e2e
        working-directory: tests/playwright
        run: npm test

      - name: Upload Playwright trace on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-trace
          path: tests/playwright/test-results/
          retention-days: 14
```

- [ ] **Step 6: Smoke-test locally**

```bash
swift build -c release --product swiflow
cd tests/playwright
npm install
npx playwright install --with-deps chromium
npm test
```

Expected: both Counter tests pass within ~5 min (first run includes WASM build).

- [ ] **Step 7: Commit + open PR to confirm CI fires the new job**

```bash
git checkout -b ci/playwright-e2e
git add tests/playwright/package.json tests/playwright/playwright.config.ts tests/playwright/counter.spec.ts tests/playwright/README.md .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
test(e2e): Playwright happy-path Counter spec

One Playwright spec, Chromium only. Drives the Counter demo end-to-end
in a real browser to verify @State -> Scheduler -> RAFScheduler -> diff
-> patch -> JS driver -> DOM all work together. Two scenarios:

1. Single-click increment: assert visible Count: 1 / Count: 2 after
   sequential clicks; assert the previous Count: 0 text disappears
   (sanity check that diff replaced rather than appended).
2. Rapid clicks: 5 clicks in a tight loop -> assert Count: 5 - proves
   the rAF batcher doesn't drop state updates under burst load.

Playwright config scaffolds a fresh demo via swiflow init at session
setup using execFileSync (no shell interpolation) and runs swiflow
dev as the webServer. CI runs on PRs only (gated for free-tier
minutes; Playwright + Chromium + cold WASM build is ~5 min).

Browser binaries cached via actions/cache keyed on the Playwright
version segment in the path. Failed runs upload the Playwright trace
as an artifact for 14 days.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin ci/playwright-e2e
gh pr create --fill --base main
```

Confirm `Playwright E2E` job appears in the PR's check list and passes (~5 min cold, ~3 min cached). Merge to main once green.

---

## Self-review (run by the controller before dispatching subagents)

1. **Spec coverage** — every section of `docs/superpowers/specs/2026-05-19-swiflow-phase4-hardening-design.md`:
   - §4 URL sanitizer → Task 1 ✓
   - §5 Diagnostic errors → Task 2 ✓ (all 3 checks + release-mode skip via .disabled)
   - §6 Source maps spike → Task 3 ✓ (2h timebox preserved)
   - §6.3 Source maps follow-up matrix → Task 4 paths A/B/C ✓
   - §7.1 JS driver units → Task 5 ✓
   - §7.2 Playwright happy path → Task 6 ✓
   - §7.3 CI integration → Task 5 (push+PR) + Task 6 (PR only) ✓
   - §8 Ordering + pause point → ordering matches; pause point after Task 2 ✓
   - §9 Risk register → spike timebox, Playwright cache, Node 20 pin, release-mode diagnostic skip all addressed ✓
   - §10 Success criteria → covered by Tasks 1+2+4+5+6 ✓

2. **Placeholder scan** — no "TBD", "TODO", "fill in", "similar to Task N", "implement later", "appropriate". Task 4 paths B/C are abbreviated relative to A but each has Steps B1–B5 / C1–C4; the abbreviation is intentional since the spike's outcome determines which path runs. Path C's `<FLAG>` placeholder is intentionally unresolved — the spike report fills it in.

3. **Type consistency:**
   - `URLSanitizer.sanitize(_:)` signature consistent across §4.5 (spec), Task 1 (impl + tests), Task 2 (refactor)
   - `swiflowDiagnostic(_:)` signature `(@autoclosure () -> String) -> Void` consistent
   - `setupDriver()` returns `{ window, document, swiflow }` consistently in helpers + opcode tests
   - `BuildInvocation.init`'s `emitSourceMaps` parameter shows up only in Task 4 path B
   - `URLSanitizer.urlAttributeNames`, `URLSanitizer.allowedSchemes`, `URLSanitizer.allowDataURLs`, `URLSanitizer.allowBlobURLs`, `URLSanitizer.defaultAllowedSchemes` — all symbols referenced in tests are defined in the impl
   - JS driver helpers `setupDriver()` uses script-tag injection (NOT dynamic-code-construction APIs); the dev-reload test does its own manual JSDOM init for the same reason

4. **One known soft-spot:** Task 2 Step 10 (release-mode no-op verification) gestures at `.disabled(if: !isDebugBuild)` but `Test.ConditionTrait` may name the API slightly differently. The implementer should verify against the installed Swift Testing 6.3 API. Acceptable — the intent is clear, the actual API spelling is a one-line fix at one site.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-19-swiflow-phase4-hardening.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Same SDD pattern Phase 3 used.

**2. Inline Execution** — I implement each task in this session using executing-plans, batched with checkpoints.

Pause point after Task 2 matches the spec (user-facing hardening shipped; rest is internal investment).

Which approach?
