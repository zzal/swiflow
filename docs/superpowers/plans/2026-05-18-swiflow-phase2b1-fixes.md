# Swiflow Phase 2b.1 — Critical Fixes from Exhaustive Review

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the seven highest-priority correctness, security, and test-coverage fixes that the Phase 1 + 2a + 2b exhaustive review surfaced, so the framework is honest about its security model and produces working DOM updates for every code path users can hit today.

**Architecture:** The fixes are mostly surgical. The biggest change introduces a new `Patch.setRawHTML` opcode so the raw-HTML write path is gated by a single, named-loud audit target instead of being smuggled through `Patch.setProperty(name: "innerHTML")`. The remaining six fixes are narrowly scoped bug fixes and missing-test additions.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, JavaScriptKit 0.53, vanilla JS driver, swift-argument-parser, GitHub Actions.

---

## File Structure (touched by this plan)

**Phase 1 — VDOM Brain (Sources/Swiflow/):**
- Modify: `Patch.swift` — add `setRawHTML` case
- Modify: `PatchSerializer.swift` — encode `setRawHTML`
- Modify: `Diff/Diff.swift` — route raw-HTML update through `setRawHTML`
- Modify: `Diff/IndexedChildrenDiff.swift` — emit `removeChild` before destroyed-then-replaced node
- Modify: `Diff/KeyedChildrenDiff.swift` — same fix for prefix/suffix cross-kind transitions

**Phase 2a — Bridge & Renderer (js-driver/, examples/HelloWorld/):**
- Modify: `js-driver/swiflow-driver.js` — add `setRawHTML` case, reject the `innerHTML` name in `setProperty`, call `removeEventListener` in `destroyNode`
- Regenerate: `examples/HelloWorld/swiflow-driver.js` (byte-identical copy)
- Regenerate: `examples/HelloWorld/index.html` (after template `{{NAME}}` fix in Task 4)

**Phase 2b — CLI (Sources/SwiflowCLI/, Tests/SwiflowCLITests/):**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift` — fix `rawIndexHTML` `<title>`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift` (after every JS driver edit, via `swift scripts/embed-driver.swift`)
- Add: `Tests/SwiflowCLITests/TemplatesTests.swift` — new `readmeMatchesExample` test
- Add: `Tests/SwiflowCLITests/DriverEmbedderTests.swift` — new formatting-drift assertion

**CI:**
- Modify: `.github/workflows/ci.yml` — install WASM SDK before tests

**Tests (Phase 1 — Tests/SwiflowTests/):**
- Modify: `DiffTests/TextDiffTests.swift` — assert `setRawHTML` (not `setProperty`) on raw-HTML update
- Modify: `DiffTests/IndexedChildrenTests.swift` — `crossKindMidList` + `crossKindAtTail` now expect `removeChild` before `destroyNode`
- Add: `DiffTests/KeyedChildrenTests.swift` — new test for keyed cross-kind transition (key reused across kind change)
- Modify: `PatchSerializerTests.swift` — assert `setRawHTML` encodes to op `"setRawHTML"` with `handle` + `html` fields

---

## Task 1: New `Patch.setRawHTML` opcode (threaded fix for raw-HTML update + audit-grep + four-bag invariant)

**Why:** Three issues collapse into one fix.
- **Phase 1 C2:** `Diff.swift:144-151` emits `setProperty(name: "innerHTML", ...)` on raw-HTML update; the driver assigns directly to the node's HTML property. When `createRawHTML`'s single-child fast path stored a `Text` node (any `rawHTML("plain text")`), the update is a silent no-op (`Text` has no such property).
- **Phase 2a #1:** The audit-grep `rg "innerHTML" js-driver/ Sources/SwiflowWeb/` misses `Diff.swift` entirely (it lives in `Sources/Swiflow/`), so a security review concludes "no path to the HTML property" when one exists. Worse: any user code placing the string `"innerHTML"` in `ElementData.properties` flows through the same unguarded `setProperty` path.
- **Phase 1 I4:** Routing raw-HTML updates through `setProperty` violates the four-bag separation invariant.

The new opcode makes `setRawHTML` the *only* path through which the HTML property is written, gives it a dedicated driver case that re-parses (so it works whether the handle points at an `Element` or a `Text` node), and lets us reject the `"innerHTML"` name defensively in the generic `setProperty` driver case.

**Files:**
- Modify: `Sources/Swiflow/Patch.swift`
- Modify: `Sources/Swiflow/PatchSerializer.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift:144-151`
- Modify: `js-driver/swiflow-driver.js` (add `setRawHTML` case, reject the `"innerHTML"` name in `setProperty`)
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift` (`swift scripts/embed-driver.swift`)
- Regenerate: `examples/HelloWorld/swiflow-driver.js` (copy from `js-driver/`)
- Modify: `Tests/SwiflowTests/PatchSerializerTests.swift`
- Modify: `Tests/SwiflowTests/DiffTests/TextDiffTests.swift`
- Add: `Tests/SwiflowTests/DiffTests/RawHTMLUpdateTests.swift` (new file, isolates the regression)

- [ ] **Step 1: Write the failing PatchSerializer test**

Open `Tests/SwiflowTests/PatchSerializerTests.swift` and add inside the existing `@Suite`:

```swift
@Test("setRawHTML encodes to op \"setRawHTML\" with handle and html fields")
func encodesSetRawHTML() {
    let payload = PatchSerializer.encode(
        .setRawHTML(handle: 7, html: "<b>hi</b>")
    )
    #expect(payload.op == "setRawHTML")
    #expect(payload.fields["handle"] == .int(7))
    #expect(payload.fields["html"] == .string("<b>hi</b>"))
}
```

- [ ] **Step 2: Run test, verify it fails to compile**

```bash
swift test --filter PatchSerializerTests 2>&1 | tail -20
```

Expected: `error: type 'Patch' has no member 'setRawHTML'`.

- [ ] **Step 3: Add the case to `Patch.swift`**

In `Sources/Swiflow/Patch.swift`, add immediately after the `setText` case (around line 50, inside the `// MARK: - Per-bag mutations` group). Keep the doc comment terse and audit-grep-friendly:

```swift
/// Replaces a node's HTML content. The **only** opcode that writes to the
/// `innerHTML` property at the driver layer. Emitted exclusively by the
/// raw-HTML diff path (`git grep "setRawHTML("` enumerates every site).
/// XSS responsibility lies with the caller of `VNode.rawHTML(_:)`.
case setRawHTML(handle: Int, html: String)
```

Update the leading doc comment at the top of the enum: change `"The 16 opcodes are grouped"` to `"The 17 opcodes are grouped"`.

- [ ] **Step 4: Add the encode arm in `PatchSerializer.swift`**

In `Sources/Swiflow/PatchSerializer.swift`, add immediately after the `setText` case (around line 89):

```swift
case .setRawHTML(let handle, let html):
    return PatchPayload(op: "setRawHTML", fields: [
        "handle": .int(handle),
        "html": .string(html),
    ])
```

- [ ] **Step 5: Run the serializer test — should pass now**

```bash
swift test --filter PatchSerializerTests 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 6: Write the failing Diff test**

Create `Tests/SwiflowTests/DiffTests/RawHTMLUpdateTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/RawHTMLUpdateTests.swift
import Testing
@testable import Swiflow

@Suite("rawHTML update emits setRawHTML (never setProperty(innerHTML))")
struct RawHTMLUpdateTests {
    @Test("rawHTML value change emits a single setRawHTML patch")
    func updatesViaSetRawHTML() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.rawHTML("<b>old</b>")
        let next = VNode.rawHTML("<b>new</b>")

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        #expect(u.patches == [.setRawHTML(handle: 0, html: "<b>new</b>")])
    }

    @Test("rawHTML diff never emits setProperty named \"innerHTML\"")
    func neverEmitsHtmlPropertyName() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let initial = VNode.rawHTML("a")
        let next = VNode.rawHTML("b")

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        for patch in u.patches {
            if case .setProperty(_, let name, _) = patch {
                Issue.record("rawHTML update produced setProperty(\"\(name)\")")
            }
        }
    }
}
```

- [ ] **Step 7: Run the new tests — verify they fail**

```bash
swift test --filter RawHTMLUpdateTests 2>&1 | tail -20
```

Expected: `updatesViaSetRawHTML` fails — actual patch is still the old `setProperty` form.

- [ ] **Step 8: Update `Diff.swift` to emit `setRawHTML`**

In `Sources/Swiflow/Diff/Diff.swift`, replace lines 144–151:

```swift
// RawHTML → rawHTML value change.
case (.rawHTML, .rawHTML(let newHTML)):
    patches.append(.setRawHTML(handle: mounted.handle, html: newHTML))
    mounted.vnode = next
    return mounted
```

- [ ] **Step 9: Run new diff tests — should pass now**

```bash
swift test --filter RawHTMLUpdateTests 2>&1 | tail -10
```

Expected: both tests pass.

- [ ] **Step 10: Update the existing `differentRawHTML` assertion in `TextDiffTests.swift`**

The Phase 1 reviewer noted that `Tests/SwiflowTests/DiffTests/TextDiffTests.swift:30` asserts the *old* `setProperty` patch. Change that assertion to expect `setRawHTML` instead. Run:

```bash
rg "innerHTML" Tests/SwiflowTests/
```

For each match where a test asserts `.setProperty(handle:, name: "innerHTML", value:)` on a raw-HTML transition, replace with `.setRawHTML(handle: <h>, html: "<...>")`. (If there are no remaining asserted `setProperty` patches with that name outside the new file, the system is fully migrated.)

- [ ] **Step 11: Add the `setRawHTML` case to the JS driver**

In `js-driver/swiflow-driver.js`, in the `applyPatches` switch (between `setText` and the `// Events` section, around line 138), add a `case "setRawHTML":` block that:

1. Creates a `<template>` element.
2. Assigns `p.html` into the template's HTML property (the SAME pattern already used by `createRawHTML` — this is intentionally the one mirrored path through the audit grep).
3. If `tpl.content.childNodes.length === 1`, takes `tpl.content.firstChild`; otherwise wraps the children in a `<span>`.
4. If the old node is attached (`old.parentNode`), calls `old.parentNode.replaceChild(next, old)`.
5. Updates `nodes.set(p.handle, next)`.

Mirror the comment from `createRawHTML` (point to `git grep "setRawHTML"` as the audit target, note that the opcode re-parses so it works for both `Element` and `Text` previous nodes). Keep the explicit `return` at the end of the case to match the switch style.

- [ ] **Step 12: Defensively reject the `"innerHTML"` name in the driver's `setProperty` case**

Same file, modify the existing `setProperty` case (around line 111) so that before the assignment, it checks `if (p.name === "innerHTML")` and `throw new Error("swiflow: setProperty refuses to write the innerHTML property; use VNode.rawHTML(_:) instead")`. Add a comment explaining that the runtime reaches the HTML property only via `setRawHTML`, which is the named-loud audit target, and that this defensive check prevents a user accidentally placing the name in `ElementData.properties` from silently injecting markup.

- [ ] **Step 13: Regenerate the embedded driver**

```bash
swift scripts/embed-driver.swift
```

Expected: `Sources/SwiflowCLI/EmbeddedDriver.swift` updates without errors.

- [ ] **Step 14: Copy the new driver into the example**

```bash
cp js-driver/swiflow-driver.js examples/HelloWorld/swiflow-driver.js
```

- [ ] **Step 15: Run the full test suite — every test passes**

```bash
swift test 2>&1 | tail -20
```

Expected: 0 failures. Pay attention to `DriverEmbedderTests.embeddedDriverIsFresh` (should pass because the embed step ran) and the byte-equality `InitCommandTests` (should pass because we copied to the example).

- [ ] **Step 16: Commit**

```bash
git add Sources/Swiflow/Patch.swift Sources/Swiflow/PatchSerializer.swift Sources/Swiflow/Diff/Diff.swift js-driver/swiflow-driver.js examples/HelloWorld/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift Tests/SwiflowTests/PatchSerializerTests.swift Tests/SwiflowTests/DiffTests/RawHTMLUpdateTests.swift Tests/SwiflowTests/DiffTests/TextDiffTests.swift
git commit -m "feat(diff): add setRawHTML opcode; gate raw-HTML writes behind a single audit target"
```

---

## Task 2: Emit `removeChild` before destroyed cross-kind replacement (indexed + keyed prefix/suffix)

**Why:** Phase 1 C1 + I1. In `IndexedChildrenDiff.swift:28-50`, when the per-index `update()` returns a fresh node (kind change or tag change), the code emits `destroyNode(oldChild)` (via `update`'s default arm) and then `insertBefore`/`appendChild` for the new child. There is *no* `removeChild` between them. The driver's `destroyNode` only deletes the handle from its Map; the actual DOM node stays attached to the parent. Result: stale text/element visible alongside the new node.

The same hole exists in the keyed prefix and suffix scans (`KeyedChildrenDiff.swift:31-43, 49-61`) when a key is reused across a kind change.

The fix: in both diff paths, after `update()` returns a node `!== oldChild`, emit `removeChild(parent: mounted.handle, child: oldChild.handle)` *before* the placement patch. The old `destroyNode` patch is still emitted by `update`'s `destroy()` call; that's correct (it cleans up the driver's Map and the handler registry). We just need to detach the live DOM node first.

**Files:**
- Modify: `Sources/Swiflow/Diff/IndexedChildrenDiff.swift:28-50`
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift:31-43, 49-61`
- Modify: `Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift` (correct existing wrong assertions in `crossKindMidList` and `crossKindAtTail`)
- Add: `Tests/SwiflowTests/DiffTests/KeyedCrossKindTests.swift` (new file)

- [ ] **Step 1: Correct the existing assertion in `crossKindMidList`**

Open `Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift`. The test at line 118 currently asserts the buggy patch sequence. Change the `#expect(u.patches == [...])` block to:

```swift
#expect(u.patches == [
    .removeChild(parent: 0, child: 1),
    .destroyNode(handle: 1),
    .createElement(handle: 3, tag: "span"),
    .insertBefore(parent: 0, child: 3, beforeChild: 2),
])
```

Update the test's leading comment to reflect that `removeChild` precedes `destroyNode`.

- [ ] **Step 2: Correct `crossKindAtTail` similarly**

Find `crossKindAtTail` in the same file and update its expected patch sequence:

```swift
#expect(u.patches == [
    .removeChild(parent: 0, child: 2),
    .destroyNode(handle: 2),
    .createElement(handle: 3, tag: "span"),
    .appendChild(parent: 0, child: 3),
])
```

- [ ] **Step 3: Run those tests — verify they fail**

```bash
swift test --filter IndexedChildrenTests 2>&1 | tail -20
```

Expected: `crossKindMidList` and `crossKindAtTail` fail because the actual patch list omits `removeChild`.

- [ ] **Step 4: Fix `IndexedChildrenDiff.swift`**

In `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`, the inside of the `if newChild !== oldChild` block needs to emit `removeChild` *before* the placement patch. The `destroyNode` for the old child has already been appended by the `update()` call's `destroy()` recursion (so it's already in `patches` at the position where we'd insert the `removeChild`). We need to insert `removeChild` *before* that destroy.

The cleanest fix is to capture the `patches.count` before calling `update()` and insert `removeChild` at that index. Replace lines 19–50 with:

```swift
for i in 0..<commonCount {
    let oldChild = mounted.children[i]
    let oldHandle = oldChild.handle
    let updatePatchStart = patches.count
    let newChild = update(
        mounted: oldChild,
        next: newChildren[i],
        into: &patches,
        handles: handles,
        handlers: handlers
    )
    if newChild !== oldChild {
        // update() emitted destroyNode for the old subtree but did NOT
        // detach the old node from the live DOM. Insert removeChild
        // BEFORE the destroyNode patches so the driver detaches first,
        // then drops the handle from its Map.
        patches.insert(
            .removeChild(parent: mounted.handle, child: oldHandle),
            at: updatePatchStart
        )
        mounted.replaceChild(at: i, with: newChild)
        if i + 1 < oldCount {
            let beforeSibling = mounted.children[i + 1]
            patches.append(.insertBefore(
                parent: mounted.handle,
                child: newChild.handle,
                beforeChild: beforeSibling.handle
            ))
        } else {
            patches.append(.appendChild(
                parent: mounted.handle,
                child: newChild.handle
            ))
        }
    }
}
```

- [ ] **Step 5: Run indexed tests — should pass now**

```bash
swift test --filter IndexedChildrenTests 2>&1 | tail -10
```

Expected: both cross-kind tests pass; no other indexed test regresses.

- [ ] **Step 6: Write the failing keyed cross-kind test**

Create `Tests/SwiflowTests/DiffTests/KeyedCrossKindTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/KeyedCrossKindTests.swift
import Testing
@testable import Swiflow

@Suite("Keyed cross-kind replacement detaches the old DOM node")
struct KeyedCrossKindTests {
    /// Two keyed siblings; the prefix scan hits a key match but the tag
    /// changes (span -> b). Without removeChild, the old <span>
    /// stays in the DOM.
    @Test("Keyed prefix cross-kind: emits removeChild before destroyNode")
    func keyedPrefixCrossKind() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "span", key: "a")),
            .element(ElementData(tag: "i", key: "b")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "b", key: "a")),  // tag change forces destroy+create
            .element(ElementData(tag: "i", key: "b")),
        ]))

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        // The exact handle numbers depend on allocation order; assert the
        // structural property: every destroyNode(h) in the patches is
        // preceded by a removeChild(_, child: h).
        var pendingDestroys: Set<Int> = []
        for patch in u.patches {
            switch patch {
            case .removeChild(_, let child):
                pendingDestroys.insert(child)
            case .destroyNode(let handle):
                #expect(pendingDestroys.contains(handle),
                        "destroyNode(\(handle)) was not preceded by removeChild")
                pendingDestroys.remove(handle)
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 7: Run the keyed test — verify it fails**

```bash
swift test --filter KeyedCrossKindTests 2>&1 | tail -20
```

Expected: fails because `KeyedChildrenDiff` prefix scan emits `destroyNode` with no preceding `removeChild`.

- [ ] **Step 8: Fix `KeyedChildrenDiff.swift` prefix and suffix scans**

In `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`, locate the prefix scan (~lines 31–43) and the suffix scan (~lines 49–61). Each contains a pattern of: `update()` call → if `newChild !== oldChild`, then `mounted.replaceChild(at:, with:)`. Apply the same `patches.insert` fix used in Task 2 Step 4:

```swift
let oldHandle = oldChild.handle
let updatePatchStart = patches.count
let newChild = update(...)
if newChild !== oldChild {
    patches.insert(
        .removeChild(parent: mounted.handle, child: oldHandle),
        at: updatePatchStart
    )
    // ... existing replaceChild + placement-patch logic
}
```

Read the surrounding code carefully — the prefix scan and the suffix scan may already emit an `insertBefore` for repositioning; if so, leave that alone. The fix is purely to insert the `removeChild` ahead of `update()`'s destroy patches.

- [ ] **Step 9: Run all diff tests — every test passes**

```bash
swift test --filter DiffTests 2>&1 | tail -20
```

Expected: 0 failures across indexed, keyed, attribute, property, style, handler, text, raw-HTML, and tag-replace diff tests.

- [ ] **Step 10: Commit**

```bash
git add Sources/Swiflow/Diff/IndexedChildrenDiff.swift Sources/Swiflow/Diff/KeyedChildrenDiff.swift Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift Tests/SwiflowTests/DiffTests/KeyedCrossKindTests.swift
git commit -m "fix(diff): detach old DOM node with removeChild before destroying it on cross-kind replace"
```

---

## Task 3: JS driver — call `removeEventListener` in `destroyNode`

**Why:** Phase 2a #2. The driver's `destroyNode` case (`js-driver/swiflow-driver.js:78-88`) only deletes entries from the `listeners` Map — it never invokes `removeEventListener` on the DOM node being destroyed. `removeHandler` correctly does both. The comment claims "Detach any listeners we tracked" but the actual DOM bindings remain until GC. Mostly harmless (detached nodes get GC'd), but it's architecturally inconsistent with `removeHandler` and falsifies the comment.

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift` (`swift scripts/embed-driver.swift`)
- Regenerate: `examples/HelloWorld/swiflow-driver.js`

- [ ] **Step 1: Update the `destroyNode` case**

In `js-driver/swiflow-driver.js`, replace lines 78–88 with a block that:

1. Looks up the DOM node: `const node = nodes.get(p.handle);`
2. Iterates `Array.from(listeners.keys())`.
3. For each key, finds the colon separator with `indexOf(":")`, skips keys without one.
4. Parses the prefix as a number; skips if it doesn't equal `p.handle` (avoids the latent prefix-overlap risk that `String.startsWith(p.handle + ":")` had).
5. Extracts the event name from `key.slice(sep + 1)`.
6. Looks up the bound function via `listeners.get(key)`.
7. If both `node` and `fn` are defined, calls `node.removeEventListener(event, fn)`.
8. Deletes the listener-map entry.
9. After the loop, `nodes.delete(p.handle)` and `return`.

Symmetric with the `removeHandler` case below: both `removeEventListener` AND delete from the map. Update the comment to reflect this is now true.

- [ ] **Step 2: Regenerate the embedded driver**

```bash
swift scripts/embed-driver.swift
```

- [ ] **Step 3: Copy the new driver into the example**

```bash
cp js-driver/swiflow-driver.js examples/HelloWorld/swiflow-driver.js
```

- [ ] **Step 4: Run the full test suite**

```bash
swift test 2>&1 | tail -20
```

Expected: `DriverEmbedderTests.embeddedDriverIsFresh` passes (we ran the embed step); the byte-equality tests pass (we copied to the example).

- [ ] **Step 5: Commit**

```bash
git add js-driver/swiflow-driver.js examples/HelloWorld/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "fix(driver): removeEventListener for tracked listeners on destroyNode"
```

---

## Task 4: Fix `indexHTML` template silently ignoring `{{NAME}}`

**Why:** Phase 2b #1. `Templates/Templates.swift:134-170` hardcodes `<title>Swiflow Hello World</title>` with no `{{NAME}}` placeholder. `indexHTML(name:)` calls `.replacingOccurrences(of: "{{NAME}}", with: name)` on a string that contains no `{{NAME}}` — a no-op. Every `swiflow init <anything>` produces the same browser tab title. The existing `indexHTMLMatchesExample` test passes only because the fixture name is `HelloWorld` — the test exercises the bug.

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift` (line 139)
- Modify: `examples/HelloWorld/index.html` (line 5, to match new template output for `name: "HelloWorld"`)
- Modify: `Tests/SwiflowCLITests/TemplatesTests.swift` (add a non-HelloWorld-name regression test)

- [ ] **Step 1: Write the failing test**

In `Tests/SwiflowCLITests/TemplatesTests.swift`, add to the suite:

```swift
@Test("index.html title substitutes {{NAME}}")
func indexHTMLTitleSubstitutesName() {
    let rendered = Templates.indexHTML(name: "MyCoolApp")
    #expect(rendered.contains("<title>MyCoolApp</title>"))
    #expect(!rendered.contains("Swiflow Hello World"))
    #expect(!rendered.contains("{{NAME}}"))
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
swift test --filter TemplatesTests 2>&1 | tail -20
```

Expected: `indexHTMLTitleSubstitutesName` fails (rendered string contains `Swiflow Hello World`, not `MyCoolApp`).

- [ ] **Step 3: Fix the template**

In `Sources/SwiflowCLI/Templates/Templates.swift`, change line 139 from:

```html
            <title>Swiflow Hello World</title>
```

to:

```html
            <title>{{NAME}}</title>
```

- [ ] **Step 4: Update the example to match new template output for `HelloWorld`**

Edit `examples/HelloWorld/index.html` line 5 from:

```html
    <title>Swiflow Hello World</title>
```

to:

```html
    <title>HelloWorld</title>
```

- [ ] **Step 5: Run TemplatesTests — every test passes**

```bash
swift test --filter TemplatesTests 2>&1 | tail -10
```

Expected: `indexHTMLTitleSubstitutesName` passes; `indexHTMLMatchesExample` continues to pass (the example now matches the new template's output for `name: "HelloWorld"`).

- [ ] **Step 6: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift examples/HelloWorld/index.html Tests/SwiflowCLITests/TemplatesTests.swift
git commit -m "fix(templates): substitute {{NAME}} in index.html <title>"
```

---

## Task 5: Add README byte-equality test

**Why:** Phase 2b #3. `TemplatesTests.readmeMentionsKeyCommands` only checks for the presence of substrings. The other five template files have byte-equality assertions against `examples/HelloWorld/`. This is the "load-bearing invariant" that prevents template/example drift — README is the only file uniquely lacking that guarantee.

**Files:**
- Modify: `Tests/SwiflowCLITests/TemplatesTests.swift`

- [ ] **Step 1: Add the failing test**

In `Tests/SwiflowCLITests/TemplatesTests.swift`, add immediately after the existing `gitignoreMatchesExample` test:

```swift
@Test("README.md renders identically to examples/HelloWorld/README.md")
func readmeMatchesExample() throws {
    let rendered = Templates.readme(name: "HelloWorld")
    let expected = try Self.exampleFile("README.md")
    #expect(rendered == expected)
}
```

- [ ] **Step 2: Run the test**

```bash
swift test --filter TemplatesTests 2>&1 | tail -20
```

Expected: One of two outcomes —
- (A) Test passes: the template already matches the example. Skip step 3.
- (B) Test fails: the template diverges from the example. Run a diff between `Templates.readme(name: "HelloWorld")` output and `examples/HelloWorld/README.md` to see the difference, then go to step 3.

- [ ] **Step 3: Reconcile any drift**

If the test failed: decide which is canonical (the template is the source of truth, since `swiflow init` users will get whatever the template produces). Update `examples/HelloWorld/README.md` to match `Templates.readme(name: "HelloWorld")` output exactly. Re-run step 2 to confirm parity.

- [ ] **Step 4: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowCLITests/TemplatesTests.swift examples/HelloWorld/README.md
git commit -m "test(templates): assert README byte-equality with examples/HelloWorld"
```

---

## Task 6: Add `DriverEmbedder` formatting-drift test

**Why:** Phase 2b #2. `scripts/embed-driver.swift:49-62` duplicates `DriverEmbedder.swiftSource:28-41` (acknowledged in the script's comment as necessary because the script runs standalone, outside SPM, and can't `import SwiflowCLI`). The existing `embeddedDriverIsFresh` test catches *JS source* drift between `js-driver/swiflow-driver.js` and `EmbeddedDriver.swift`, but it does *not* catch wrapping-format drift between the script and `DriverEmbedder`. If someone edits the header comment or indentation in one without updating the other, the next run of the script produces a different byte sequence than `DriverEmbedder` expects — and the freshness test will *still* pass because both pieces look at the same JS bytes.

The fix is a second test that compares `DriverEmbedder.swiftSource(forJSSource: onDiskJS)` against the committed `EmbeddedDriver.swift` *verbatim*. If the committed file was generated by the script and the script diverges from `DriverEmbedder`, the verbatim comparison fails.

**Files:**
- Modify: `Tests/SwiflowCLITests/DriverEmbedderTests.swift`

- [ ] **Step 1: Read the existing test to understand its setup**

```bash
cat Tests/SwiflowCLITests/DriverEmbedderTests.swift
```

Note how `embeddedDriverIsFresh` locates `js-driver/swiflow-driver.js` via `#filePath` and computes `EmbeddedDriver.javascriptSource` from it. We'll reuse the same `#filePath` plumbing for the new test.

- [ ] **Step 2: Add the failing-by-construction drift test**

In `Tests/SwiflowCLITests/DriverEmbedderTests.swift`, add inside the existing `@Suite`:

```swift
@Test("EmbeddedDriver.swift is bit-for-bit what DriverEmbedder would produce")
func embeddedDriverMatchesDriverEmbedderOutput() throws {
    // Catches drift between scripts/embed-driver.swift and
    // DriverEmbedder.swiftSource — if someone edits the wrapping logic
    // in one place without the other, the committed EmbeddedDriver.swift
    // (most recently generated by the script) will differ from what
    // DriverEmbedder would produce now.
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SwiflowCLITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let jsURL = repoRoot
        .appendingPathComponent("js-driver/swiflow-driver.js")
    let embeddedURL = repoRoot
        .appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

    let jsSource = try String(contentsOf: jsURL, encoding: .utf8)
    let expectedEmbedded = DriverEmbedder.swiftSource(forJSSource: jsSource)
    let actualEmbedded = try String(contentsOf: embeddedURL, encoding: .utf8)

    #expect(actualEmbedded == expectedEmbedded,
            "EmbeddedDriver.swift drifted from DriverEmbedder.swiftSource output. \
             Run `swift scripts/embed-driver.swift` and check the script/library \
             produce the same wrapping format.")
}
```

- [ ] **Step 3: Run the test**

```bash
swift test --filter DriverEmbedderTests 2>&1 | tail -20
```

Expected outcomes:
- (A) Passes: `EmbeddedDriver.swift` is already produced by output that matches `DriverEmbedder`. Skip step 4.
- (B) Fails: script and library currently disagree. Go to step 4.

- [ ] **Step 4: If failing, reconcile script and library**

Compare `scripts/embed-driver.swift` lines 49–62 with `Sources/SwiflowCLI/DriverEmbedder.swift` lines 28–41. Pick one to be canonical (the library is the source of truth — it's what `swiflow init` will use in the future to regenerate). Update the other to match exactly (whitespace included), then run `swift scripts/embed-driver.swift` to regenerate `EmbeddedDriver.swift`. Re-run the test until it passes.

- [ ] **Step 5: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add Tests/SwiflowCLITests/DriverEmbedderTests.swift scripts/embed-driver.swift Sources/SwiflowCLI/DriverEmbedder.swift Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "test(driver-embedder): catch wrapping-format drift between script and library"
```

---

## Task 7: CI — install WASM SDK so the integration test actually runs

**Why:** Phase 2b #4. `Tests/SwiflowCLITests/BuildCommandTests.swift`'s end-to-end test (`BuildCommandIntegrationTests.endToEnd()`) is gated on `.enabled(if: wasmSDKAvailable)`. The CI workflow at `.github/workflows/ci.yml` never installs a WASM SDK, so the gate evaluates false and the test silently skips on every PR. A bug that breaks the build pipeline (wrong argv, wrong working directory, etc.) is currently caught only by local devs who happen to have the SDK installed.

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Check the SDK release URL**

The Swift WASM SDK URL changes with each Swift release. As of Swift 6.0, the canonical artifactbundle is published at swift.org. Find the current URL — for Swift 6.0 it is roughly:

```
https://download.swift.org/swift-6.0.3-release/wasm32-unknown-wasi/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE_wasm32-unknown-wasi.artifactbundle.zip
```

(Confirm the exact URL by visiting https://www.swift.org/install/macos/#installation-via-static-sdk-for-wasi before pasting into the workflow.)

- [ ] **Step 2: Update `.github/workflows/ci.yml`**

Replace the existing `steps:` block with the version below. The new `Install WASM SDK` step runs on both runners, after Swift is set up and verified, before the test step:

```yaml
    steps:
      - uses: actions/checkout@v4

      - name: Set up Swift (Linux)
        if: runner.os == 'Linux'
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "6.0"

      - name: Verify Swift version
        run: swift --version

      - name: Install WASM SDK
        # Required for the end-to-end Test gated by wasmSDKAvailable in
        # BuildCommandIntegrationTests. Without this step the integration
        # test silently skips, leaving the swiflow build path untested in CI.
        run: |
          swift sdk install \
            https://download.swift.org/swift-6.0.3-release/wasm32-unknown-wasi/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE_wasm32-unknown-wasi.artifactbundle.zip
          swift sdk list

      - name: Build library + WebTarget
        run: swift build

      - name: Build CLI
        run: swift build --product swiflow

      - name: Test
        run: swift test --parallel
```

(If the URL is gated by a checksum or the Swift release pipeline expects `--checksum`, add that. The `swift sdk install` invocation will tell you in its output if a checksum is required.)

- [ ] **Step 3: Push to a branch and watch the workflow**

```bash
git checkout -b phase-2b1-ci-wasm-sdk
git add .github/workflows/ci.yml
git commit -m "ci: install WASM SDK so swiflow build integration test runs"
git push -u origin phase-2b1-ci-wasm-sdk
```

Open the GitHub Actions tab and watch both jobs. Expected:
- `Install WASM SDK` succeeds on macOS and Linux.
- `swift sdk list` output lists at least one `wasm`-suffixed SDK.
- `Test` step now executes `BuildCommandIntegrationTests.endToEnd` (instead of skipping). The job duration grows by ~30–60 seconds (one cold WASM compile).

- [ ] **Step 4: If WASM install fails on Linux, fall back to macOS-only**

If the WASM artifactbundle does not install on `ubuntu-22.04` (e.g., the SDK is macOS-only at this Swift version), narrow the install and test steps to macOS:

```yaml
      - name: Install WASM SDK
        if: runner.os == 'macOS'
        run: |
          swift sdk install <url>
```

The test will still run on macOS (covering the most common Swift WASM dev environment); Linux CI continues to cover the library and CLI builds without the WASM round-trip. Document the asymmetry in the workflow file with a `#` comment.

- [ ] **Step 5: Merge after CI is green**

Open a PR with title `ci: install WASM SDK so swiflow build integration test runs` and a body that:
- Summarizes that the `swift sdk install` step now enables `BuildCommandIntegrationTests.endToEnd()` (currently `.enabled(if: wasmSDKAvailable)`) to actually run in CI.
- Notes this closes the gap surfaced by the Phase 2b exhaustive review: the end-to-end `swiflow init` + `swiflow build` round-trip was never validated by CI.
- Includes a test plan with checks that the test runs (not skipped) on macOS and either runs or skips with a documented reason on Linux.

---

## Verification (after all 7 tasks)

```bash
swift test 2>&1 | tail -10
```

Expected: total test count grows from 163 → ~169 (rough: +1 PatchSerializer, +2 RawHTMLUpdate, +1 KeyedCrossKind, +1 indexHTMLTitle, +1 README byte-equality, +1 DriverEmbedder drift), all passing.

End-to-end smoke (locally, requires WASM SDK):

```bash
swift build -c release --product swiflow
mkdir -p /tmp/swiflow-smoke && cd /tmp/swiflow-smoke
/path/to/swiflow init my-app
cd my-app
/path/to/swiflow build
# Open index.html via any static server; the browser tab should read "my-app"
# (not "Swiflow Hello World"), proving Task 4 landed end-to-end.
```

---

## Out of Scope (deliberately deferred — separate plans)

These review findings are NOT addressed by this plan:

- **Phase 2a #3** — Stand up `Tests/SwiflowWebTests/` with dedicated tests for `JSAdapter`, `Renderer.renderOnce()`, `DispatcherBridge.installIfNeeded`. Deserves its own plan (~10 tests).
- **Phase 2a #4** — Verify `DispatcherBridge`'s `.object(closure)` callable from JS against JavaScriptKit 0.53 source. Functionally works; latent fragility.
- **Phase 2a #5** — Force-unwraps in `Renderer.renderOnce()` (`applyPatches!`, `mount!`). Deferred to Phase 2c when proper error surfacing makes sense.
- **Phase 2a #6** — Document the handler re-registration leak in the Hello World example. Phase 3's `@State` fixes the root cause.
- **Phase 1 I2** — Align duplicate-key detection `#if DEBUG` gating in `KeyedChildrenDiff.swift`. Cosmetic; one-line patch.
- **Phase 1 I3** — Add keyed map-middle LIS test (`[a,b,c,d] → [d,e,b]`). Worth adding when next touching the keyed diff.
- **Phase 1 I5** — `MountTreeConsistencyTests` keyed empty↔populated coverage.
- **Phase 1 observations** — `HandlerRegistry.assertEmpty()`, `HandleAllocator` `@MainActor`, redundant-`destroyNode` optimization. None are bugs.
- **Phase 2b observations** — `rawAppSwift` first-line comment path, `DriverEmbedder` `public` access level, README Quick Start path assumption, `WasmSDKProbe` stderr swallow. All cosmetic.
- **Phase 4** — `--swiflow-source` UX flip to git URL after publish.
