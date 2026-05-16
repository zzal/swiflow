# Swiflow Phase 1 — "The Brain" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pure-Swift, platform-independent VDOM library that builds and tests on macOS and Linux, with no WASM toolchain required. Delivers the `Swiflow` Swift package with `VNode`, `Patch`, `MountTree`, `HandleAllocator`, `HandlerRegistry`, a hybrid index+keyed diff engine, and the `@resultBuilder`-based DSL — all covered by Swift Testing assertions per the spec's Phase 1 test matrix.

**Architecture:** Tagged-enum `VNode` produced by lowercase free-function element builders (e.g. `div { … }`) and consumed by a `diff(mounted:next:handles:handlers:)` function that walks two parallel trees (an immutable just-built VNode tree against a persistent `MountNode` "fiber" tree carrying integer handles) and emits a flat `[Patch]` array. The library is renderer-agnostic — no JavaScriptKit, no DOM, no I/O — so Phase 2 can layer the JS bridge on top without changing any Phase 1 file.

**Tech Stack:** Swift 6.0+, Swift Package Manager, Swift Testing (`import Testing`), no third-party dependencies. Builds with `swift build`, tests with `swift test`. Targets macOS arm64/x86_64 and Linux x86_64/arm64.

**Reference spec:** `~/.claude/plans/i-want-you-to-dynamic-pancake.md` (the approved Swiflow refined spec). All decisions in this plan derive from sections 2, 3, 4, 8, 9 of that document. **Read the spec first**, then this plan.

**Repo state at start:** Greenfield. Only `docs/brainstorm/` and `docs/superpowers/plans/` exist. No `Package.swift`, no git history.

---

## File map (Phase 1 deliverables)

| Path | Responsibility |
|---|---|
| `Package.swift` | SPM manifest: library target `Swiflow`, test target `SwiflowTests`. |
| `Sources/Swiflow/VNode.swift` | `VNode` enum, `ElementData`, `PropertyValue`, `EventHandler`, `Event`. |
| `Sources/Swiflow/Patch.swift` | The 14-opcode `Patch` enum. |
| `Sources/Swiflow/HandleAllocator.swift` | Monotonic `Int` counter for node handles. |
| `Sources/Swiflow/HandlerRegistry.swift` | `[Int: EventHandler]` storage + `nextID()`. Phase-2 dispatcher wiring is a stub. |
| `Sources/Swiflow/MountTree.swift` | `MountNode` class — persistent across renders, holds handle + last-committed VNode. |
| `Sources/Swiflow/Diff/Diff.swift` | Public `diff(...)` entry point; element-vs-element dispatch; calls children diff helpers. |
| `Sources/Swiflow/Diff/IndexedChildrenDiff.swift` | Pair-by-index children diff. |
| `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` | Two-pointer keyed children diff with Map fallback. |
| `Sources/Swiflow/DSL/ResultBuilder.swift` | `@resultBuilder ChildrenBuilder`. |
| `Sources/Swiflow/DSL/Elements.swift` | `div`, `span`, `h1`, `h2`, `h3`, `p`, `button`, `a`, `input`, `ul`, `li`, `img`, `form`, `label`, `pre`, `code`, `section`, `header`, `footer`, `nav`, `main_`. |
| `Sources/Swiflow/DSL/Modifiers.swift` | `Attribute` value type + `.class`, `.id`, `.style`, `.attr`, `.prop`, `.on`. |
| `Sources/Swiflow/DSL/RawHTML.swift` | `rawHTML(_:)` free function returning `VNode.rawHTML(...)`. |
| `Tests/SwiflowTests/PropertyValueTests.swift` | Equality + decoding tests. |
| `Tests/SwiflowTests/VNodeTests.swift` | Construction + equality tests. |
| `Tests/SwiflowTests/PatchTests.swift` | Equality tests per variant. |
| `Tests/SwiflowTests/HandleAllocatorTests.swift` | Monotonicity, thread-safety not required. |
| `Tests/SwiflowTests/HandlerRegistryTests.swift` | Add / lookup / remove / id allocation. |
| `Tests/SwiflowTests/MountTreeTests.swift` | Construction + parent/child wiring. |
| `Tests/SwiflowTests/DiffTests/FirstMountTests.swift` | mounted=nil flows. |
| `Tests/SwiflowTests/DiffTests/AttributeDiffTests.swift` | attr add/remove/change. |
| `Tests/SwiflowTests/DiffTests/PropertyDiffTests.swift` | prop add/remove/change. |
| `Tests/SwiflowTests/DiffTests/StyleDiffTests.swift` | style add/remove/change. |
| `Tests/SwiflowTests/DiffTests/HandlerDiffTests.swift` | handler add/remove + registry side-effects. |
| `Tests/SwiflowTests/DiffTests/TextDiffTests.swift` | text↔text, text↔element, rawHTML cases. |
| `Tests/SwiflowTests/DiffTests/TagReplaceTests.swift` | div→span replace path. |
| `Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift` | insert/remove at start/mid/end. |
| `Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift` | swap/reverse/rotate/insert-mid+remove-end. |
| `Tests/SwiflowTests/DSLTests.swift` | DSL produces equivalent VNodes to explicit constructors. |
| `.gitignore` | `.build/`, `.swiftpm/`, `*.xcodeproj`, `.DS_Store`. |
| `LICENSE` | Apache 2.0. |
| `README.md` | Project intro + quick-start (will be expanded in Phase 2). |
| `CONTRIBUTING.md` | `swift test` invocation + branch model. |
| `.github/workflows/ci.yml` | macOS + Linux runners executing `swift build` + `swift test`. |

---

## Task 1: Repository bootstrap (git + license + .gitignore)

**Files:**
- Create: `/Users/alainduchesneau/Projets/swiflow/.gitignore`
- Create: `/Users/alainduchesneau/Projets/swiflow/LICENSE`
- Create: `/Users/alainduchesneau/Projets/swiflow/README.md`
- Create: `/Users/alainduchesneau/Projets/swiflow/CONTRIBUTING.md`

- [ ] **Step 1: Initialize git**

Run:
```bash
cd /Users/alainduchesneau/Projets/swiflow
git init
git config user.name "$(git config --global user.name || echo 'Swiflow Contributor')"
git config user.email "$(git config --global user.email || echo 'noreply@swiflow.dev')"
```
Expected: `Initialized empty Git repository in /Users/alainduchesneau/Projets/swiflow/.git/`

- [ ] **Step 2: Write `.gitignore`**

```
.DS_Store
.build/
.swiftpm/
*.xcodeproj/
Package.resolved
```

(Note: `Package.resolved` is ignored at the *meta-repo* level per the spec § 8; user-project scaffolds generated by `swiflow init` will commit theirs.)

- [ ] **Step 3: Write `LICENSE`**

Copy the standard Apache 2.0 license text verbatim from <https://www.apache.org/licenses/LICENSE-2.0.txt>. The copyright line at the bottom (`APPENDIX: How to apply...`) is not part of the licensed work and may be omitted.

Add a copyright header at the top:
```
Copyright 2026 The Swiflow Authors
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Followed by the full Apache 2.0 license text.

- [ ] **Step 4: Write `README.md`**

```markdown
# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 1 (the VDOM "Brain") is in active development. Phase 2 (the
`swiflow` CLI and JS driver) follows. See [docs/brainstorm/](docs/brainstorm/)
for the original design exploration.

## Quick start (Phase 1 — library only)

```bash
swift test
```

The `Swiflow` Swift package builds and tests on macOS and Linux with no WASM
toolchain required.

## License

Apache 2.0. See [LICENSE](LICENSE).
```

- [ ] **Step 5: Write `CONTRIBUTING.md`**

```markdown
# Contributing to Swiflow

Thank you for considering a contribution.

## Development

```bash
swift build         # build the library
swift test          # run all tests
```

Tests use the Swift Testing framework (`import Testing`), available in Swift
6.0 and later.

## Workflow

- Fork; create a topic branch.
- Keep commits small and focused; conventional commit prefixes are appreciated
  (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`).
- Open a pull request against `main`. CI must pass on macOS and Linux.

## License

By contributing, you agree your contribution will be licensed under the
Apache License, Version 2.0 (see [LICENSE](LICENSE)).
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore LICENSE README.md CONTRIBUTING.md
git commit -m "chore: initialize repository with Apache 2.0 license and docs"
```

Expected: a single commit on `main` with four files.

---

## Task 2: SPM manifest + first build

**Files:**
- Create: `/Users/alainduchesneau/Projets/swiflow/Package.swift`
- Create: `/Users/alainduchesneau/Projets/swiflow/Sources/Swiflow/Swiflow.swift` (placeholder, deleted in Task 4)
- Create: `/Users/alainduchesneau/Projets/swiflow/Tests/SwiflowTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
    ],
    targets: [
        .target(
            name: "Swiflow",
            path: "Sources/Swiflow"
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests"
        ),
    ]
)
```

- [ ] **Step 2: Write placeholder `Swiflow.swift`**

```swift
// Placeholder so the target has at least one source file.
// Deleted in Task 4 once VNode.swift exists.
public enum Swiflow {}
```

- [ ] **Step 3: Write smoke test**

```swift
// Tests/SwiflowTests/SmokeTests.swift
import Testing
@testable import Swiflow

@Suite("Smoke")
struct SmokeTests {
    @Test("Module imports cleanly")
    func moduleImports() {
        _ = Swiflow.self
    }
}
```

- [ ] **Step 4: Build and test**

Run:
```bash
swift build
swift test
```

Expected:
- `swift build`: succeeds, no warnings.
- `swift test`: `Test run with 1 test passed`.

If `swift test` complains about Swift Testing not being available, the
toolchain is older than Swift 6.0. Upgrade before continuing.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add SPM manifest with Swiflow library and SwiflowTests targets"
```

---

## Task 3: `PropertyValue` enum

**Files:**
- Create: `Sources/Swiflow/PropertyValue.swift`
- Create: `Tests/SwiflowTests/PropertyValueTests.swift`

`PropertyValue` is the typed value used in `ElementData.properties` (per spec
§ 4.1). Ships before `ElementData` because it's a dependency.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/PropertyValueTests.swift
import Testing
@testable import Swiflow

@Suite("PropertyValue")
struct PropertyValueTests {
    @Test("Equality discriminates by case and value")
    func equalityByCaseAndValue() {
        #expect(PropertyValue.string("x") == PropertyValue.string("x"))
        #expect(PropertyValue.string("x") != PropertyValue.string("y"))
        #expect(PropertyValue.string("1") != PropertyValue.int(1))
        #expect(PropertyValue.int(1) == PropertyValue.int(1))
        #expect(PropertyValue.double(1.5) == PropertyValue.double(1.5))
        #expect(PropertyValue.bool(true) == PropertyValue.bool(true))
        #expect(PropertyValue.bool(true) != PropertyValue.bool(false))
    }
}
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `swift test --filter PropertyValueTests`
Expected: failure, `PropertyValue` is undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/PropertyValue.swift

/// A typed value for a DOM property (the `node[name] = value` domain — distinct
/// from HTML attributes, inline styles, and event handlers).
public enum PropertyValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}
```

- [ ] **Step 4: Run test, expect PASS**

Run: `swift test --filter PropertyValueTests`
Expected: `Test run with 1 test passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/PropertyValue.swift Tests/SwiflowTests/PropertyValueTests.swift
git commit -m "feat: add PropertyValue typed enum for DOM properties"
```

---

## Task 4: `VNode`, `ElementData`, `EventHandler`, `Event`

**Files:**
- Create: `Sources/Swiflow/VNode.swift`
- Delete: `Sources/Swiflow/Swiflow.swift` (placeholder)
- Create: `Tests/SwiflowTests/VNodeTests.swift`
- Delete: `Tests/SwiflowTests/SmokeTests.swift` (smoke no longer needed)

The core data model per spec § 4.1. `EventHandler.id` is the registry key
(see Task 7); the closure is unequatable, so `EventHandler` equality compares
ID only.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/VNodeTests.swift
import Testing
@testable import Swiflow

@Suite("VNode")
struct VNodeTests {
    @Test("Text VNode equality compares string")
    func textEquality() {
        #expect(VNode.text("hi") == VNode.text("hi"))
        #expect(VNode.text("hi") != VNode.text("bye"))
    }

    @Test("RawHTML VNode equality compares string")
    func rawHTMLEquality() {
        #expect(VNode.rawHTML("<b>x</b>") == VNode.rawHTML("<b>x</b>"))
        #expect(VNode.rawHTML("<b>x</b>") != VNode.rawHTML("<i>x</i>"))
        #expect(VNode.text("hi") != VNode.rawHTML("hi"))
    }

    @Test("ElementData equality compares all bags")
    func elementDataEquality() {
        let a = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "x"],
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        let b = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "x"],
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        #expect(a == b)

        let c = ElementData(
            tag: "div",
            key: nil,
            attributes: ["class": "y"],  // different
            properties: [:],
            style: [:],
            handlers: [:],
            children: []
        )
        #expect(a != c)
    }

    @Test("ElementData with same handler IDs is equal even with different closures")
    func handlerEqualityByID() {
        let h1 = EventHandler(id: 7, invoke: { _ in })
        let h2 = EventHandler(id: 7, invoke: { _ in print("different closure") })
        let h3 = EventHandler(id: 8, invoke: { _ in })
        #expect(h1 == h2)
        #expect(h1 != h3)
    }

    @Test("VNode element equality recurses into children")
    func elementRecursesIntoChildren() {
        let leaf: VNode = .text("hello")
        let a = VNode.element(ElementData(
            tag: "div", key: nil, attributes: [:], properties: [:],
            style: [:], handlers: [:], children: [leaf]
        ))
        let b = VNode.element(ElementData(
            tag: "div", key: nil, attributes: [:], properties: [:],
            style: [:], handlers: [:], children: [leaf]
        ))
        #expect(a == b)
    }

    @Test("Event preserves type and optional target value")
    func eventConstruction() {
        let e = Event(type: "input", targetValue: "abc")
        #expect(e.type == "input")
        #expect(e.targetValue == "abc")

        let e2 = Event(type: "click", targetValue: nil)
        #expect(e2.targetValue == nil)
    }
}
```

- [ ] **Step 2: Delete the placeholder**

```bash
rm Sources/Swiflow/Swiflow.swift
rm Tests/SwiflowTests/SmokeTests.swift
```

- [ ] **Step 3: Run tests, expect FAIL**

Run: `swift test --filter VNodeTests`
Expected: build error — `VNode`, `ElementData`, `EventHandler`, `Event` are undeclared.

- [ ] **Step 4: Write the implementation**

```swift
// Sources/Swiflow/VNode.swift

/// The fundamental unit of the Swiflow virtual DOM.
///
/// `VNode` is a tagged enum: each render produces a fresh tree of `VNode`
/// values, and the diff engine compares it against the previously committed
/// tree to produce a list of `Patch`es.
///
/// - `element`: a tagged HTML-like node (see `ElementData`).
/// - `text`: a text node. Always rendered via `textContent` for XSS safety.
/// - `rawHTML`: an escape hatch that renders via `innerHTML`. The name is
///   loud on purpose — searching for `rawHTML(` enumerates every audit site.
public indirect enum VNode: Equatable {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
}

/// The payload of an `.element` VNode. Four separate bags model the four
/// distinct DOM categories, matching how Snabbdom / Vue / Inferno structure
/// their VNodes:
///
/// - `attributes`: set via `Element.setAttribute(name, value)`.
/// - `properties`: set via direct property assignment, e.g. `input.value = …`.
/// - `style`: inline style declarations, set via `element.style[name] = …`.
/// - `handlers`: event listeners. Keys are event names like `"click"`.
public struct ElementData: Equatable {
    public let tag: String
    public let key: String?
    public let attributes: [String: String]
    public let properties: [String: PropertyValue]
    public let style: [String: String]
    public let handlers: [String: EventHandler]
    public let children: [VNode]

    public init(
        tag: String,
        key: String? = nil,
        attributes: [String: String] = [:],
        properties: [String: PropertyValue] = [:],
        style: [String: String] = [:],
        handlers: [String: EventHandler] = [:],
        children: [VNode] = []
    ) {
        self.tag = tag
        self.key = key
        self.attributes = attributes
        self.properties = properties
        self.style = style
        self.handlers = handlers
        self.children = children
    }
}

/// An event handler keyed by its `id` in `HandlerRegistry`.
///
/// The closure itself is intentionally not part of equality (Swift closures
/// are unequatable); two handlers with the same `id` are considered equal
/// because the registry's monotonic ID is the identity.
public struct EventHandler: Equatable {
    public let id: Int
    public let invoke: (Event) -> Void

    public init(id: Int, invoke: @escaping (Event) -> Void) {
        self.id = id
        self.invoke = invoke
    }

    public static func == (lhs: EventHandler, rhs: EventHandler) -> Bool {
        lhs.id == rhs.id
    }
}

/// A DOM event surfaced into Swift.
///
/// Phase 1 keeps `Event` deliberately minimal. Phase 3 will extend it with
/// keyboard/pointer specifics as `Component` lifecycle wires up.
public struct Event: Equatable {
    public let type: String
    public let targetValue: String?

    public init(type: String, targetValue: String? = nil) {
        self.type = type
        self.targetValue = targetValue
    }
}
```

- [ ] **Step 5: Run tests, expect PASS**

Run: `swift test`
Expected: all 5 VNodeTests pass; PropertyValueTests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/VNode.swift Tests/SwiflowTests/VNodeTests.swift
git rm Sources/Swiflow/Swiflow.swift Tests/SwiflowTests/SmokeTests.swift
git commit -m "feat: add VNode, ElementData, EventHandler, Event core types"
```

---

## Task 5: `Patch` enum

**Files:**
- Create: `Sources/Swiflow/Patch.swift`
- Create: `Tests/SwiflowTests/PatchTests.swift`

The 14-opcode patch enum per spec § 4.2.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/PatchTests.swift
import Testing
@testable import Swiflow

@Suite("Patch")
struct PatchTests {
    @Test("Lifecycle opcodes equate by handle and payload")
    func lifecycleEquality() {
        #expect(Patch.createElement(handle: 1, tag: "div")
             == Patch.createElement(handle: 1, tag: "div"))
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createElement(handle: 2, tag: "div"))
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createElement(handle: 1, tag: "span"))

        #expect(Patch.createText(handle: 1, text: "x")
             == Patch.createText(handle: 1, text: "x"))
        #expect(Patch.createRawHTML(handle: 1, html: "<b/>")
             == Patch.createRawHTML(handle: 1, html: "<b/>"))
        #expect(Patch.destroyNode(handle: 1) == Patch.destroyNode(handle: 1))
    }

    @Test("Tree-structure opcodes equate by all positions")
    func structureEquality() {
        #expect(Patch.appendChild(parent: 1, child: 2)
             == Patch.appendChild(parent: 1, child: 2))
        #expect(Patch.insertBefore(parent: 1, child: 2, beforeChild: 3)
             == Patch.insertBefore(parent: 1, child: 2, beforeChild: 3))
        #expect(Patch.removeChild(parent: 1, child: 2)
             == Patch.removeChild(parent: 1, child: 2))
    }

    @Test("Mutation opcodes equate by all fields")
    func mutationEquality() {
        #expect(Patch.setAttribute(handle: 1, name: "class", value: "a")
             == Patch.setAttribute(handle: 1, name: "class", value: "a"))
        #expect(Patch.removeAttribute(handle: 1, name: "class")
             == Patch.removeAttribute(handle: 1, name: "class"))
        #expect(Patch.setProperty(handle: 1, name: "value", value: .string("x"))
             == Patch.setProperty(handle: 1, name: "value", value: .string("x")))
        #expect(Patch.removeProperty(handle: 1, name: "value")
             == Patch.removeProperty(handle: 1, name: "value"))
        #expect(Patch.setStyle(handle: 1, name: "color", value: "red")
             == Patch.setStyle(handle: 1, name: "color", value: "red"))
        #expect(Patch.removeStyle(handle: 1, name: "color")
             == Patch.removeStyle(handle: 1, name: "color"))
        #expect(Patch.setText(handle: 1, text: "hi")
             == Patch.setText(handle: 1, text: "hi"))
    }

    @Test("Event opcodes equate by all fields")
    func eventEquality() {
        #expect(Patch.addHandler(handle: 1, event: "click", handlerId: 7)
             == Patch.addHandler(handle: 1, event: "click", handlerId: 7))
        #expect(Patch.removeHandler(handle: 1, event: "click")
             == Patch.removeHandler(handle: 1, event: "click"))
    }

    @Test("Different opcodes never equate")
    func crossOpcodeInequality() {
        #expect(Patch.createElement(handle: 1, tag: "div")
             != Patch.createText(handle: 1, text: "div"))
        #expect(Patch.appendChild(parent: 1, child: 2)
             != Patch.removeChild(parent: 1, child: 2))
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter PatchTests`
Expected: build error — `Patch` is undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/Patch.swift

/// A single mutation instruction emitted by the diff engine and consumed by
/// the JS driver (in Phase 2). Patches reference DOM nodes by integer handles
/// pre-allocated on the Swift side; the driver maintains a `Map<int, Node>`.
///
/// The 14 opcodes are grouped:
/// - **Lifecycle**: create / destroy DOM nodes.
/// - **Tree structure**: parent/child wiring.
/// - **Per-bag mutations**: attribute / property / style / text.
/// - **Events**: add / remove DOM event listeners (handlerId points into
///   `HandlerRegistry`).
public enum Patch: Equatable {
    // MARK: - Lifecycle
    case createElement(handle: Int, tag: String)
    case createText(handle: Int, text: String)
    case createRawHTML(handle: Int, html: String)
    case destroyNode(handle: Int)

    // MARK: - Tree structure
    case appendChild(parent: Int, child: Int)
    case insertBefore(parent: Int, child: Int, beforeChild: Int)
    case removeChild(parent: Int, child: Int)

    // MARK: - Per-bag mutations
    case setAttribute(handle: Int, name: String, value: String)
    case removeAttribute(handle: Int, name: String)
    case setProperty(handle: Int, name: String, value: PropertyValue)
    case removeProperty(handle: Int, name: String)
    case setStyle(handle: Int, name: String, value: String)
    case removeStyle(handle: Int, name: String)
    case setText(handle: Int, text: String)

    // MARK: - Events
    case addHandler(handle: Int, event: String, handlerId: Int)
    case removeHandler(handle: Int, event: String)
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter PatchTests`
Expected: all 5 PatchTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Patch.swift Tests/SwiflowTests/PatchTests.swift
git commit -m "feat: add Patch enum with 14 mutation opcodes"
```

---

## Task 6: `HandleAllocator`

**Files:**
- Create: `Sources/Swiflow/HandleAllocator.swift`
- Create: `Tests/SwiflowTests/HandleAllocatorTests.swift`

Monotonic `Int` counter. Single-threaded (Swiflow renders on the main thread,
per the WASM single-threaded model). Per spec § 4.3, handles are **never
recycled** — this is intentional for debuggability.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/HandleAllocatorTests.swift
import Testing
@testable import Swiflow

@Suite("HandleAllocator")
struct HandleAllocatorTests {
    @Test("First handle is 0 by default")
    func firstHandleIsZero() {
        let a = HandleAllocator()
        #expect(a.next() == 0)
    }

    @Test("Handles are monotonically increasing")
    func monotonic() {
        let a = HandleAllocator()
        let h0 = a.next()
        let h1 = a.next()
        let h2 = a.next()
        #expect(h0 < h1)
        #expect(h1 < h2)
        #expect(h0 + 1 == h1)
        #expect(h1 + 1 == h2)
    }

    @Test("Custom starting handle respected")
    func customStart() {
        let a = HandleAllocator(start: 100)
        #expect(a.next() == 100)
        #expect(a.next() == 101)
    }

    @Test("Independent allocators do not share state")
    func independent() {
        let a = HandleAllocator()
        let b = HandleAllocator()
        _ = a.next()
        _ = a.next()
        #expect(b.next() == 0)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter HandleAllocatorTests`
Expected: build error — `HandleAllocator` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/HandleAllocator.swift

/// Monotonically allocates integer node handles. Handles are never recycled
/// (see Swiflow refined spec § 4.3 — "Handle lifetime contract"). Swift `Int`
/// is 64-bit on every Swiflow target platform, so practical exhaustion is
/// ~292,000 years at one million allocations per second.
public final class HandleAllocator {
    private var counter: Int

    public init(start: Int = 0) {
        self.counter = start
    }

    /// Returns the next handle, then increments.
    public func next() -> Int {
        defer { counter += 1 }
        return counter
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter HandleAllocatorTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/HandleAllocator.swift Tests/SwiflowTests/HandleAllocatorTests.swift
git commit -m "feat: add HandleAllocator for monotonic node handle allocation"
```

---

## Task 7: `HandlerRegistry`

**Files:**
- Create: `Sources/Swiflow/HandlerRegistry.swift`
- Create: `Tests/SwiflowTests/HandlerRegistryTests.swift`

Phase 1 implements the storage half of the registry. Phase 2 will add the JS
dispatcher wiring. The registry assigns integer IDs to `(Event) -> Void`
closures, looks them up, and removes them.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/HandlerRegistryTests.swift
import Testing
@testable import Swiflow

@Suite("HandlerRegistry")
struct HandlerRegistryTests {
    @Test("Registering a closure returns a fresh ID")
    func registerReturnsID() {
        let r = HandlerRegistry()
        let h1 = r.register { _ in }
        let h2 = r.register { _ in }
        #expect(h1.id != h2.id)
        #expect(h2.id == h1.id + 1)
    }

    @Test("Lookup returns the registered handler")
    func lookupReturnsHandler() {
        let r = HandlerRegistry()
        let stored = r.register { _ in }
        let found = r.handler(forID: stored.id)
        #expect(found != nil)
        #expect(found?.id == stored.id)
    }

    @Test("Lookup of unknown ID returns nil")
    func lookupUnknownReturnsNil() {
        let r = HandlerRegistry()
        #expect(r.handler(forID: 999) == nil)
    }

    @Test("Remove drops the entry; lookup returns nil afterward")
    func removeDropsEntry() {
        let r = HandlerRegistry()
        let h = r.register { _ in }
        r.remove(id: h.id)
        #expect(r.handler(forID: h.id) == nil)
    }

    @Test("Remove of unknown ID is a no-op")
    func removeUnknownIsNoOp() {
        let r = HandlerRegistry()
        r.remove(id: 12345)  // must not crash
    }

    @Test("Dispatch invokes the registered closure")
    func dispatchInvokesClosure() {
        let r = HandlerRegistry()
        var observed: String?
        let h = r.register { event in observed = event.type }
        r.dispatch(id: h.id, event: Event(type: "click"))
        #expect(observed == "click")
    }

    @Test("Dispatch to unknown ID is a no-op")
    func dispatchUnknownIsNoOp() {
        let r = HandlerRegistry()
        r.dispatch(id: 999, event: Event(type: "click"))  // must not crash
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter HandlerRegistryTests`
Expected: `HandlerRegistry` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// The DSL calls `register(_:)` whenever a `.on("click") { … }` modifier is
/// applied. The diff engine then surfaces the handler ID inside a
/// `Patch.addHandler(…, handlerId:)` so the JS driver can route DOM events
/// back through a single Swift entry point (`dispatch(id:event:)`) per the
/// Swiflow refined spec § 4.1 and Branch 9.
///
/// Phase 1 ships storage + dispatch. Phase 2 wires the JS-side global
/// dispatcher to call into `dispatch(id:event:)` via JavaScriptKit.
public final class HandlerRegistry {
    private var nextID: Int = 0
    private var handlers: [Int: EventHandler] = [:]

    public init() {}

    /// Registers a closure and returns the `EventHandler` value to embed in
    /// an `ElementData.handlers` dictionary.
    @discardableResult
    public func register(_ invoke: @escaping (Event) -> Void) -> EventHandler {
        let id = nextID
        nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        return h
    }

    /// Returns the registered handler for an ID, or `nil` if absent (already
    /// removed or never registered).
    public func handler(forID id: Int) -> EventHandler? {
        handlers[id]
    }

    /// Drops the handler entry. A no-op for unknown IDs.
    public func remove(id: Int) {
        handlers.removeValue(forKey: id)
    }

    /// Invokes the closure registered under `id` with the given event.
    /// A no-op for unknown IDs (e.g., a stale event fired after unmount).
    public func dispatch(id: Int, event: Event) {
        handlers[id]?.invoke(event)
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter HandlerRegistryTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/HandlerRegistry.swift Tests/SwiflowTests/HandlerRegistryTests.swift
git commit -m "feat: add HandlerRegistry for closure ID allocation and dispatch"
```

---

## Task 8: `MountTree`

**Files:**
- Create: `Sources/Swiflow/MountTree.swift`
- Create: `Tests/SwiflowTests/MountTreeTests.swift`

The mount tree is the persistent "fiber" alongside the most recently committed
VNode tree (spec § 4.3). Each `MountNode` owns a JS handle and remembers the
last-committed VNode at that position.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/MountTreeTests.swift
import Testing
@testable import Swiflow

@Suite("MountTree")
struct MountTreeTests {
    @Test("MountNode stores handle and last-committed VNode")
    func storesHandleAndVNode() {
        let node = MountNode(handle: 42, vnode: .text("hi"))
        #expect(node.handle == 42)
        #expect(node.vnode == .text("hi"))
        #expect(node.children.isEmpty)
        #expect(node.handlerIds.isEmpty)
        #expect(node.parent == nil)
    }

    @Test("addChild wires parent pointer")
    func addChildWiresParent() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let child = MountNode(handle: 2, vnode: .text("c"))
        parent.addChild(child)
        #expect(parent.children.count == 1)
        #expect(parent.children[0] === child)
        #expect(child.parent === parent)
    }

    @Test("removeChild detaches and clears parent pointer")
    func removeChildDetaches() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let child = MountNode(handle: 2, vnode: .text("c"))
        parent.addChild(child)
        parent.removeChild(at: 0)
        #expect(parent.children.isEmpty)
        #expect(child.parent == nil)
    }

    @Test("insertChild at index wires parent pointer")
    func insertChildAtIndex() {
        let parent = MountNode(handle: 1, vnode: .text("p"))
        let a = MountNode(handle: 2, vnode: .text("a"))
        let b = MountNode(handle: 3, vnode: .text("b"))
        let c = MountNode(handle: 4, vnode: .text("c"))
        parent.addChild(a)
        parent.addChild(c)
        parent.insertChild(b, at: 1)
        #expect(parent.children.map(\.handle) == [2, 3, 4])
        #expect(b.parent === parent)
    }

    @Test("handlerIds tracks event→handler mappings")
    func handlerIdsTracking() {
        let node = MountNode(handle: 1, vnode: .text("x"))
        node.handlerIds["click"] = 7
        node.handlerIds["input"] = 8
        #expect(node.handlerIds["click"] == 7)
        #expect(node.handlerIds["input"] == 8)
        #expect(node.handlerIds.count == 2)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter MountTreeTests`
Expected: `MountNode` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/MountTree.swift

/// A persistent counterpart to a committed `VNode` tree. The diff engine
/// reads the `MountNode` (left-hand side) against a freshly produced `VNode`
/// (right-hand side) and emits `Patch`es; the mount tree is updated in place
/// after each diff so subsequent renders compare against the new state.
///
/// `MountNode` is a class (reference type) because the parent/child graph is
/// mutated in place. The parent pointer is `weak` to avoid retain cycles.
public final class MountNode {
    public let handle: Int
    public var vnode: VNode
    public private(set) var children: [MountNode]

    /// Maps event name (e.g. `"click"`) to the handler ID currently registered
    /// in `HandlerRegistry`. Mirrored on the JS driver side via
    /// `Patch.addHandler` / `.removeHandler`.
    public var handlerIds: [String: Int]

    public private(set) weak var parent: MountNode?

    public init(
        handle: Int,
        vnode: VNode,
        children: [MountNode] = [],
        handlerIds: [String: Int] = [:]
    ) {
        self.handle = handle
        self.vnode = vnode
        self.children = children
        self.handlerIds = handlerIds
        for child in children {
            child.parent = self
        }
    }

    /// Appends a child and updates its parent pointer.
    public func addChild(_ child: MountNode) {
        children.append(child)
        child.parent = self
    }

    /// Inserts a child at `index` and updates its parent pointer.
    public func insertChild(_ child: MountNode, at index: Int) {
        children.insert(child, at: index)
        child.parent = self
    }

    /// Removes the child at `index` and clears its parent pointer.
    /// Caller is responsible for emitting any `destroyNode` / `removeChild`
    /// patches.
    public func removeChild(at index: Int) {
        let child = children.remove(at: index)
        child.parent = nil
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter MountTreeTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/MountTree.swift Tests/SwiflowTests/MountTreeTests.swift
git commit -m "feat: add MountNode persistent fiber tree with handle tracking"
```

---

## Task 9: `Diff` entry point — first-mount path

**Files:**
- Create: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/FirstMountTests.swift`

Phase 1's biggest task split into small slices. This task ships only the
`mounted == nil` path: a fresh first render that creates every node and wires
the tree.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/FirstMountTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — first mount")
struct FirstMountTests {
    @Test("First mount of a text node emits createText only")
    func textFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .text("hello"),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createText(handle: 0, text: "hello")])
        #expect(result.newMountTree.handle == 0)
        #expect(result.newMountTree.vnode == .text("hello"))
        #expect(result.newMountTree.children.isEmpty)
    }

    @Test("First mount of a rawHTML node emits createRawHTML only")
    func rawHTMLFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .rawHTML("<b>x</b>"),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createRawHTML(handle: 0, html: "<b>x</b>")])
    }

    @Test("First mount of an empty div emits createElement only")
    func emptyDivFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div")),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [.createElement(handle: 0, tag: "div")])
    }

    @Test("First mount of a div with attributes emits set patches in order")
    func divWithAttributesFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "div",
                attributes: ["class": "row", "id": "main"]
            )),
            handles: handles,
            handlers: handlers
        )
        // The first patch must be createElement; the order of attribute
        // patches is non-deterministic across dictionary iteration, so verify
        // by membership rather than position.
        #expect(result.patches.first == .createElement(handle: 0, tag: "div"))
        #expect(result.patches.contains(.setAttribute(handle: 0, name: "class", value: "row")))
        #expect(result.patches.contains(.setAttribute(handle: 0, name: "id", value: "main")))
        #expect(result.patches.count == 3)
    }

    @Test("First mount of a parent with two children wires appendChild")
    func parentWithTwoChildrenFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "ul",
                children: [.text("a"), .text("b")]
            )),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [
            .createElement(handle: 0, tag: "ul"),
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
        #expect(result.newMountTree.children.count == 2)
        #expect(result.newMountTree.children[0].handle == 1)
        #expect(result.newMountTree.children[1].handle == 2)
    }

    @Test("First mount of an element with a handler registers and emits addHandler")
    func elementWithHandlerFirstMount() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let handler = handlers.register { _ in }
        let result = diff(
            mounted: nil,
            next: .element(ElementData(
                tag: "button",
                handlers: ["click": handler]
            )),
            handles: handles,
            handlers: handlers
        )
        #expect(result.patches == [
            .createElement(handle: 0, tag: "button"),
            .addHandler(handle: 0, event: "click", handlerId: handler.id),
        ])
        #expect(result.newMountTree.handlerIds["click"] == handler.id)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter FirstMountTests`
Expected: `diff(...)` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/Diff/Diff.swift

/// The output of a single diff pass: the patches to apply, plus the new
/// mount tree to commit as the next render's left-hand side.
public struct DiffResult {
    public let patches: [Patch]
    public let newMountTree: MountNode

    public init(patches: [Patch], newMountTree: MountNode) {
        self.patches = patches
        self.newMountTree = newMountTree
    }
}

/// Diffs `next` against `mounted`, producing the patches the renderer must
/// apply and the new mount tree to commit. When `mounted` is `nil`, the
/// function treats every node as fresh and emits `create…` patches for the
/// entire tree.
public func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> DiffResult {
    var patches: [Patch] = []
    let root = mount(next, into: &patches, handles: handles, handlers: handlers)
    return DiffResult(patches: patches, newMountTree: root)
}

// MARK: - Mount helpers (first render only — Task 9 scope)

/// Creates the DOM-side node and (recursively) all children, appending patches
/// in document order. Returns the new `MountNode` describing the freshly
/// mounted subtree.
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> MountNode {
    switch vnode {
    case .text(let value):
        let h = handles.next()
        patches.append(.createText(handle: h, text: value))
        return MountNode(handle: h, vnode: vnode)

    case .rawHTML(let html):
        let h = handles.next()
        patches.append(.createRawHTML(handle: h, html: html))
        return MountNode(handle: h, vnode: vnode)

    case .element(let data):
        let h = handles.next()
        patches.append(.createElement(handle: h, tag: data.tag))

        for (name, value) in data.attributes {
            patches.append(.setAttribute(handle: h, name: name, value: value))
        }
        for (name, value) in data.properties {
            patches.append(.setProperty(handle: h, name: name, value: value))
        }
        for (name, value) in data.style {
            patches.append(.setStyle(handle: h, name: name, value: value))
        }
        var handlerIds: [String: Int] = [:]
        for (eventName, handler) in data.handlers {
            patches.append(.addHandler(
                handle: h,
                event: eventName,
                handlerId: handler.id
            ))
            handlerIds[eventName] = handler.id
        }

        let mountNode = MountNode(
            handle: h,
            vnode: vnode,
            handlerIds: handlerIds
        )

        for childVNode in data.children {
            let childMount = mount(
                childVNode,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            patches.append(.appendChild(parent: h, child: childMount.handle))
            mountNode.addChild(childMount)
        }

        return mountNode
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter FirstMountTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/FirstMountTests.swift
git commit -m "feat: add Diff entry point and first-mount path"
```

---

## Task 10: Diff — attribute diff (mounted ≠ nil, same tag)

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/AttributeDiffTests.swift`

Adds the same-tag element update path, scoped to attributes only. Subsequent
tasks (11–14) add property, style, handler, text bags.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/AttributeDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — attributes")
struct AttributeDiffTests {

    /// Convenience: mount `initial`, then diff `next` against the result.
    /// Returns only the *second* diff's patches (not the first-mount patches).
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let update = diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers)
        return update.patches
    }

    @Test("Adding an attribute emits setAttribute")
    func addAttribute() {
        let a = VNode.element(ElementData(tag: "div"))
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        #expect(patches(from: a, to: b) == [
            .setAttribute(handle: 0, name: "class", value: "x"),
        ])
    }

    @Test("Removing an attribute emits removeAttribute")
    func removeAttribute() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        let b = VNode.element(ElementData(tag: "div"))
        #expect(patches(from: a, to: b) == [
            .removeAttribute(handle: 0, name: "class"),
        ])
    }

    @Test("Changing an attribute emits setAttribute with the new value")
    func changeAttribute() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"]))
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "y"]))
        #expect(patches(from: a, to: b) == [
            .setAttribute(handle: 0, name: "class", value: "y"),
        ])
    }

    @Test("Unchanged attributes emit no patches")
    func unchangedNoPatches() {
        let attrs = ["class": "x", "id": "main"]
        let a = VNode.element(ElementData(tag: "div", attributes: attrs))
        let b = VNode.element(ElementData(tag: "div", attributes: attrs))
        #expect(patches(from: a, to: b).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter AttributeDiffTests`
Expected: tests fail because Task 9's `diff` does not yet handle `mounted != nil`.

- [ ] **Step 3: Extend `Diff.swift` with the update path and a `diffAttributes` helper**

Replace the `diff(...)` function body and add a private `update` helper. The
new contents of `Sources/Swiflow/Diff/Diff.swift`:

```swift
// Sources/Swiflow/Diff/Diff.swift

public struct DiffResult {
    public let patches: [Patch]
    public let newMountTree: MountNode

    public init(patches: [Patch], newMountTree: MountNode) {
        self.patches = patches
        self.newMountTree = newMountTree
    }
}

public func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> DiffResult {
    var patches: [Patch] = []
    let root: MountNode
    if let mounted = mounted {
        root = update(
            mounted: mounted,
            next: next,
            into: &patches,
            handles: handles,
            handlers: handlers
        )
    } else {
        root = mount(next, into: &patches, handles: handles, handlers: handlers)
    }
    return DiffResult(patches: patches, newMountTree: root)
}

// MARK: - Mount (first render) — unchanged from Task 9

func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> MountNode {
    switch vnode {
    case .text(let value):
        let h = handles.next()
        patches.append(.createText(handle: h, text: value))
        return MountNode(handle: h, vnode: vnode)

    case .rawHTML(let html):
        let h = handles.next()
        patches.append(.createRawHTML(handle: h, html: html))
        return MountNode(handle: h, vnode: vnode)

    case .element(let data):
        let h = handles.next()
        patches.append(.createElement(handle: h, tag: data.tag))

        for (name, value) in data.attributes {
            patches.append(.setAttribute(handle: h, name: name, value: value))
        }
        for (name, value) in data.properties {
            patches.append(.setProperty(handle: h, name: name, value: value))
        }
        for (name, value) in data.style {
            patches.append(.setStyle(handle: h, name: name, value: value))
        }
        var handlerIds: [String: Int] = [:]
        for (eventName, handler) in data.handlers {
            patches.append(.addHandler(
                handle: h,
                event: eventName,
                handlerId: handler.id
            ))
            handlerIds[eventName] = handler.id
        }

        let mountNode = MountNode(
            handle: h,
            vnode: vnode,
            handlerIds: handlerIds
        )

        for childVNode in data.children {
            let childMount = mount(
                childVNode,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            patches.append(.appendChild(parent: h, child: childMount.handle))
            mountNode.addChild(childMount)
        }

        return mountNode
    }
}

// MARK: - Update (subsequent renders)

/// Reconciles `next` against `mounted`. The returned `MountNode` is the
/// committed mount-tree node for that position (it may be the same object as
/// `mounted` if the diff is in-place, or a fresh replacement if the tag
/// changed — subsequent tasks add the replace path).
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> MountNode {
    // Task 10 scope: same-tag element with only `attributes` changes.
    // Other bags + text + rawHTML + tag replace are added in Tasks 11–17.
    guard
        case .element(let oldData) = mounted.vnode,
        case .element(let newData) = next,
        oldData.tag == newData.tag
    else {
        // Placeholder: tag-replace and text/rawHTML paths land in Tasks 14–15.
        // For now, fall back to remount (will be replaced).
        fatalError("update path for non-attribute changes not yet implemented")
    }

    diffAttributes(
        handle: mounted.handle,
        old: oldData.attributes,
        new: newData.attributes,
        into: &patches
    )

    mounted.vnode = next
    return mounted
}

/// Emits `setAttribute` / `removeAttribute` patches for the symmetric
/// difference between two attribute dictionaries.
func diffAttributes(
    handle: Int,
    old: [String: String],
    new: [String: String],
    into patches: inout [Patch]
) {
    // Sets and changes.
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setAttribute(handle: handle, name: name, value: newValue))
        }
    }
    // Removals.
    for name in old.keys where new[name] == nil {
        patches.append(.removeAttribute(handle: handle, name: name))
    }
}
```

> The `fatalError` is a deliberate scaffold — Tasks 11–17 progressively replace
> it. The first-mount tests still pass (mount path untouched); the
> attribute-diff tests now pass.

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter AttributeDiffTests` then `swift test`.
Expected: attribute tests pass; previously-passing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/AttributeDiffTests.swift
git commit -m "feat: diff updates attribute bag on same-tag elements"
```

---

## Task 11: Diff — property bag

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/PropertyDiffTests.swift`

Same pattern as attributes; the only difference is `PropertyValue` equality.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/PropertyDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — properties")
struct PropertyDiffTests {
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        return diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers).patches
    }

    @Test("Adding a property emits setProperty")
    func addProperty() {
        let a = VNode.element(ElementData(tag: "input"))
        let b = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "value", value: .string("x")),
        ])
    }

    @Test("Removing a property emits removeProperty")
    func removeProperty() {
        let a = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        let b = VNode.element(ElementData(tag: "input"))
        #expect(patches(from: a, to: b) == [
            .removeProperty(handle: 0, name: "value"),
        ])
    }

    @Test("Changing a property emits setProperty with new value")
    func changeProperty() {
        let a = VNode.element(ElementData(tag: "input", properties: ["value": .string("x")]))
        let b = VNode.element(ElementData(tag: "input", properties: ["value": .string("y")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "value", value: .string("y")),
        ])
    }

    @Test("Property type change emits setProperty")
    func changePropertyType() {
        let a = VNode.element(ElementData(tag: "input", properties: ["checked": .bool(true)]))
        let b = VNode.element(ElementData(tag: "input", properties: ["checked": .string("yes")]))
        #expect(patches(from: a, to: b) == [
            .setProperty(handle: 0, name: "checked", value: .string("yes")),
        ])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter PropertyDiffTests`
Expected: failures — the property bag is not yet diffed.

- [ ] **Step 3: Add `diffProperties` and wire it into `update`**

In `Sources/Swiflow/Diff/Diff.swift`, append a helper after `diffAttributes`:

```swift
/// Emits `setProperty` / `removeProperty` patches for the symmetric
/// difference between two property dictionaries.
func diffProperties(
    handle: Int,
    old: [String: PropertyValue],
    new: [String: PropertyValue],
    into patches: inout [Patch]
) {
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setProperty(handle: handle, name: name, value: newValue))
        }
    }
    for name in old.keys where new[name] == nil {
        patches.append(.removeProperty(handle: handle, name: name))
    }
}
```

Modify the body of `update(...)` so the post-`guard` block becomes:

```swift
    diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
    diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)

    mounted.vnode = next
    return mounted
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/PropertyDiffTests.swift
git commit -m "feat: diff updates property bag on same-tag elements"
```

---

## Task 12: Diff — style bag

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/StyleDiffTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/StyleDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — styles")
struct StyleDiffTests {
    private func patches(from initial: VNode, to next: VNode) -> [Patch] {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mount = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        return diff(mounted: mount.newMountTree, next: next, handles: handles, handlers: handlers).patches
    }

    @Test("Adding a style declaration emits setStyle")
    func addStyle() {
        let a = VNode.element(ElementData(tag: "div"))
        let b = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        #expect(patches(from: a, to: b) == [
            .setStyle(handle: 0, name: "color", value: "red"),
        ])
    }

    @Test("Removing a style declaration emits removeStyle")
    func removeStyle() {
        let a = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        let b = VNode.element(ElementData(tag: "div"))
        #expect(patches(from: a, to: b) == [
            .removeStyle(handle: 0, name: "color"),
        ])
    }

    @Test("Changing a style declaration emits setStyle with new value")
    func changeStyle() {
        let a = VNode.element(ElementData(tag: "div", style: ["color": "red"]))
        let b = VNode.element(ElementData(tag: "div", style: ["color": "blue"]))
        #expect(patches(from: a, to: b) == [
            .setStyle(handle: 0, name: "color", value: "blue"),
        ])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter StyleDiffTests`

- [ ] **Step 3: Add `diffStyle` and wire it into `update`**

Append after `diffProperties`:

```swift
/// Emits `setStyle` / `removeStyle` patches for the symmetric difference
/// between two style dictionaries.
func diffStyle(
    handle: Int,
    old: [String: String],
    new: [String: String],
    into patches: inout [Patch]
) {
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setStyle(handle: handle, name: name, value: newValue))
        }
    }
    for name in old.keys where new[name] == nil {
        patches.append(.removeStyle(handle: handle, name: name))
    }
}
```

Update the `update` body to include:

```swift
    diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
    diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)
    diffStyle(handle: mounted.handle, old: oldData.style, new: newData.style, into: &patches)

    mounted.vnode = next
    return mounted
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/StyleDiffTests.swift
git commit -m "feat: diff updates style bag on same-tag elements"
```

---

## Task 13: Diff — handler bag

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/HandlerDiffTests.swift`

Handlers are special: removing a handler must `remove` from the registry too.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/HandlerDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — handlers")
struct HandlerDiffTests {

    @Test("Adding a handler emits addHandler and updates handlerIds")
    func addHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button")),
            handles: handles,
            handlers: handlers
        )

        let h = handlers.register { _ in }
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [
            .addHandler(handle: 0, event: "click", handlerId: h.id),
        ])
        #expect(update.newMountTree.handlerIds["click"] == h.id)
    }

    @Test("Removing a handler emits removeHandler and drops from registry")
    func removeHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )

        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button")),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [.removeHandler(handle: 0, event: "click")])
        #expect(update.newMountTree.handlerIds["click"] == nil)
        #expect(handlers.handler(forID: h.id) == nil, "removed handlers must be dropped from the registry")
    }

    @Test("Swapping a handler emits removeHandler then addHandler")
    func swapHandler() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h1 = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h1])),
            handles: handles,
            handlers: handlers
        )

        let h2 = handlers.register { _ in }
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h2])),
            handles: handles,
            handlers: handlers
        )

        #expect(update.patches == [
            .removeHandler(handle: 0, event: "click"),
            .addHandler(handle: 0, event: "click", handlerId: h2.id),
        ])
        #expect(update.newMountTree.handlerIds["click"] == h2.id)
        #expect(handlers.handler(forID: h1.id) == nil)
        #expect(handlers.handler(forID: h2.id) != nil)
    }

    @Test("Unchanged handler ID emits no patches")
    func unchangedNoPatches() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let mountResult = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        let update = diff(
            mounted: mountResult.newMountTree,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        #expect(update.patches.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter HandlerDiffTests`

- [ ] **Step 3: Add `diffHandlers` and wire into `update`**

Append after `diffStyle`:

```swift
/// Emits `addHandler` / `removeHandler` patches for the symmetric difference
/// between two handler dictionaries. Removed handlers are dropped from the
/// `HandlerRegistry` so their closures can be released. Returns the new
/// `handlerIds` map to commit on the mount node.
func diffHandlers(
    handle: Int,
    old: [String: Int],
    new: [String: EventHandler],
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) -> [String: Int] {
    var nextIDs: [String: Int] = [:]

    // Additions and swaps.
    for (event, newHandler) in new {
        if let oldID = old[event], oldID == newHandler.id {
            // Unchanged.
            nextIDs[event] = oldID
        } else {
            if let oldID = old[event] {
                patches.append(.removeHandler(handle: handle, event: event))
                handlers.remove(id: oldID)
            }
            patches.append(.addHandler(handle: handle, event: event, handlerId: newHandler.id))
            nextIDs[event] = newHandler.id
        }
    }

    // Pure removals (event no longer present in new).
    for (event, oldID) in old where new[event] == nil {
        patches.append(.removeHandler(handle: handle, event: event))
        handlers.remove(id: oldID)
    }

    return nextIDs
}
```

Update the `update` body:

```swift
    diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
    diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)
    diffStyle(handle: mounted.handle, old: oldData.style, new: newData.style, into: &patches)
    mounted.handlerIds = diffHandlers(
        handle: mounted.handle,
        old: mounted.handlerIds,
        new: newData.handlers,
        handlers: handlers,
        into: &patches
    )

    mounted.vnode = next
    return mounted
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/HandlerDiffTests.swift
git commit -m "feat: diff updates handler bag with registry cleanup"
```

---

## Task 14: Diff — text, rawHTML, text↔element transitions

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/TextDiffTests.swift`

This task replaces the `fatalError` for non-element cases. Adds:
- `text → text` with same value → no patches.
- `text → text` with different value → `setText`.
- `rawHTML → rawHTML` with new value → `setProperty(innerHTML, ...)` (or destroy+create — choose `setProperty` for fewer patches).
- `text → element` (or any cross-case) → destroy old, mount new, **caller** must emit replacement in parent (handled at parent level — for the root, just destroy + remount).
- `element → text` similarly.

For Task 14, focus on the root: when the root case-kind changes, the new mount tree is a fresh node and the patches are `destroyNode(old) + mount(new)`. Note that for the root, no parent exists to receive `removeChild`/`appendChild` — the renderer (Phase 2) is responsible for re-mounting the root selector. We document this as a contract: a root tag/case change produces patches that destroy and recreate the root; the renderer must re-attach.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/TextDiffTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — text and rawHTML")
struct TextDiffTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("Identical text emits no patches")
    func identicalText() {
        let (_, u) = diffPair(.text("hi"), .text("hi"))
        #expect(u.patches.isEmpty)
    }

    @Test("Different text emits setText, mount tree retains handle")
    func differentText() {
        let (m, u) = diffPair(.text("hi"), .text("bye"))
        let rootHandle = m.newMountTree.handle
        #expect(u.patches == [.setText(handle: rootHandle, text: "bye")])
        #expect(u.newMountTree.handle == rootHandle)
        #expect(u.newMountTree.vnode == .text("bye"))
    }

    @Test("Different rawHTML emits setProperty(innerHTML), mount tree retains handle")
    func differentRawHTML() {
        let (m, u) = diffPair(.rawHTML("<b/>"), .rawHTML("<i/>"))
        #expect(u.patches == [
            .setProperty(handle: m.newMountTree.handle, name: "innerHTML", value: .string("<i/>")),
        ])
    }

    @Test("Text→element at root emits destroy+create, new mount tree has fresh handle")
    func textToElementAtRoot() {
        let (m, u) = diffPair(.text("hi"), .element(ElementData(tag: "span")))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createElement(handle: m.newMountTree.handle + 1, tag: "span"),
        ])
        #expect(u.newMountTree.handle == m.newMountTree.handle + 1)
    }

    @Test("Element→text at root emits destroy+create")
    func elementToTextAtRoot() {
        let (m, u) = diffPair(.element(ElementData(tag: "span")), .text("hi"))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createText(handle: m.newMountTree.handle + 1, text: "hi"),
        ])
    }

    @Test("Text→rawHTML at root emits destroy+create")
    func textToRawHTMLAtRoot() {
        let (m, u) = diffPair(.text("hi"), .rawHTML("<b/>"))
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createRawHTML(handle: m.newMountTree.handle + 1, html: "<b/>"),
        ])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter TextDiffTests`

- [ ] **Step 3: Rewrite `update(...)` to dispatch on case combinations**

Replace the entire `update(...)` function with:

```swift
/// Reconciles `next` against `mounted`. The returned `MountNode` is the
/// committed mount-tree node for that position. If the diff replaces the
/// node (different case kind, or different element tag — see Task 15), the
/// returned `MountNode` is a fresh object with a new handle and the caller
/// is responsible for any parent-level `insertBefore` / `appendChild`
/// rewiring (for the root, the renderer reattaches to the selector).
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> MountNode {
    switch (mounted.vnode, next) {
    // Same-kind, same-content: nothing to do.
    case (.text(let oldText), .text(let newText)) where oldText == newText:
        return mounted
    case (.rawHTML(let oldHTML), .rawHTML(let newHTML)) where oldHTML == newHTML:
        return mounted

    // Text → text value change.
    case (.text, .text(let newText)):
        patches.append(.setText(handle: mounted.handle, text: newText))
        mounted.vnode = next
        return mounted

    // RawHTML → rawHTML value change.
    case (.rawHTML, .rawHTML(let newHTML)):
        patches.append(.setProperty(
            handle: mounted.handle,
            name: "innerHTML",
            value: .string(newHTML)
        ))
        mounted.vnode = next
        return mounted

    // Element → element, same tag: per-bag diff (Tasks 10–13, 16–17).
    case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:
        diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
        diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)
        diffStyle(handle: mounted.handle, old: oldData.style, new: newData.style, into: &patches)
        mounted.handlerIds = diffHandlers(
            handle: mounted.handle,
            old: mounted.handlerIds,
            new: newData.handlers,
            handlers: handlers,
            into: &patches
        )
        // Children diff lands in Tasks 16–17.
        diffChildren(
            mounted: mounted,
            newChildren: newData.children,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
        mounted.vnode = next
        return mounted

    // Any other transition: destroy the old subtree and mount fresh.
    default:
        destroy(mounted, into: &patches, handlers: handlers)
        return mount(next, into: &patches, handles: handles, handlers: handlers)
    }
}

/// Emits `destroyNode` for `node` and recursively for every descendant.
/// Also drops every handler ID from the registry.
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry
) {
    for child in node.children {
        destroy(child, into: &patches, handlers: handlers)
    }
    for (_, handlerID) in node.handlerIds {
        handlers.remove(id: handlerID)
    }
    patches.append(.destroyNode(handle: node.handle))
}

/// Stub — replaced in Tasks 16 and 17.
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    // No-op for Task 14; children diffing arrives in Tasks 16–17.
}
```

> **Removed:** the old `fatalError(...)` branch.
> **Added:** `destroy(_:into:handlers:)` recursive teardown and a `diffChildren` stub that Tasks 16–17 will flesh out.

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test`
Expected: every existing suite still passes; `TextDiffTests` passes (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/TextDiffTests.swift
git commit -m "feat: diff handles text, rawHTML, and cross-kind transitions"
```

---

## Task 15: Diff — tag-replace within elements

**Files:**
- Modify: nothing (covered by Task 14's `default` branch); only adds tests.
- Create: `Tests/SwiflowTests/DiffTests/TagReplaceTests.swift`

The `default:` arm of Task 14 already handles `div → span` by destroying and
mounting fresh. This task locks the behaviour with explicit tests so future
refactors can't silently break it.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/TagReplaceTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — tag replace")
struct TagReplaceTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("Different tag at root destroys and recreates with new handle")
    func differentTagReplaces() {
        let (m, u) = diffPair(
            .element(ElementData(tag: "div")),
            .element(ElementData(tag: "span"))
        )
        #expect(u.patches == [
            .destroyNode(handle: m.newMountTree.handle),
            .createElement(handle: m.newMountTree.handle + 1, tag: "span"),
        ])
        #expect(u.newMountTree.handle != m.newMountTree.handle)
    }

    @Test("Tag replace destroys all descendants too")
    func tagReplaceDestroysDescendants() {
        let (m, u) = diffPair(
            .element(ElementData(tag: "ul", children: [.text("a"), .text("b")])),
            .element(ElementData(tag: "ol"))
        )
        // Children destroyed first (post-order), then the parent, then the
        // fresh element is created.
        let oldRoot = m.newMountTree.handle
        let childA = m.newMountTree.children[0].handle
        let childB = m.newMountTree.children[1].handle
        #expect(u.patches == [
            .destroyNode(handle: childA),
            .destroyNode(handle: childB),
            .destroyNode(handle: oldRoot),
            .createElement(handle: oldRoot + 1, tag: "ol"),
        ])
    }

    @Test("Tag replace removes handlers from the registry")
    func tagReplaceCleansRegistry() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let h = handlers.register { _ in }
        let m = diff(
            mounted: nil,
            next: .element(ElementData(tag: "button", handlers: ["click": h])),
            handles: handles,
            handlers: handlers
        )
        _ = diff(
            mounted: m.newMountTree,
            next: .element(ElementData(tag: "div")),
            handles: handles,
            handlers: handlers
        )
        #expect(handlers.handler(forID: h.id) == nil)
    }
}
```

- [ ] **Step 2: Run tests, expect PASS (existing implementation suffices)**

Run: `swift test --filter TagReplaceTests`
Expected: 3 tests pass on the first try, because Task 14's `default` arm
already covers tag replace. If they fail, check that `destroy(_:into:handlers:)`
recurses post-order before emitting the parent's `destroyNode`.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/DiffTests/TagReplaceTests.swift
git commit -m "test: lock tag-replace diff behaviour against future regressions"
```

---

## Task 16: Children diff — indexed (no keys)

**Files:**
- Create: `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift` (route from `diffChildren` stub)
- Create: `Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift`

Index-pairing algorithm: pair `oldChildren[i]` with `newChildren[i]` and
recurse. For length deltas, emit appends for surplus new children and
`removeChild` + `destroyNode` for surplus old children.

The algorithm only fires when **neither** the old nor the new children have
keys; Task 17 adds the keyed path.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — children (indexed)")
struct IndexedChildrenTests {
    private func ul(_ texts: [String]) -> VNode {
        .element(ElementData(tag: "ul", children: texts.map { .text($0) }))
    }

    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }

    @Test("Same-length children with identical texts emit no patches")
    func sameLengthIdentical() {
        let u = diffPair(ul(["a", "b"]), ul(["a", "b"]))
        #expect(u.patches.isEmpty)
    }

    @Test("Same-length children with one changed text emits one setText")
    func sameLengthOneChanged() {
        let u = diffPair(ul(["a", "b"]), ul(["a", "B"]))
        // Old text "b" lives at handle 2 (ul=0, "a"=1, "b"=2).
        #expect(u.patches == [.setText(handle: 2, text: "B")])
    }

    @Test("Appending one child emits createText + appendChild")
    func appendOne() {
        let u = diffPair(ul(["a"]), ul(["a", "b"]))
        // ul=0, "a"=1; new "b" gets handle 2.
        #expect(u.patches == [
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Removing the last child emits removeChild + destroyNode")
    func removeLast() {
        let u = diffPair(ul(["a", "b"]), ul(["a"]))
        // "b" lives at handle 2; ul at 0.
        #expect(u.patches == [
            .removeChild(parent: 0, child: 2),
            .destroyNode(handle: 2),
        ])
    }

    @Test("Append at end with type change of existing child")
    func appendAndChange() {
        let u = diffPair(ul(["a"]), ul(["A", "b"]))
        // ul=0, "a"=1, new "b"=2.
        #expect(u.patches == [
            .setText(handle: 1, text: "A"),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Removing all children emits per-child removeChild+destroyNode")
    func removeAllChildren() {
        let u = diffPair(ul(["a", "b"]), ul([]))
        #expect(u.patches == [
            .removeChild(parent: 0, child: 1),
            .destroyNode(handle: 1),
            .removeChild(parent: 0, child: 2),
            .destroyNode(handle: 2),
        ])
    }

    @Test("Index-pair handles position-shifted text (no keys)")
    func positionShiftedText() {
        // ["a","b","c"] → ["b","c","a"] without keys: index-pair compares
        // a↔b (different → setText), b↔c (different → setText), c↔a
        // (different → setText). This is *correct under no-keys semantics*
        // (every index changed text); the keyed path (Task 17) does better.
        let u = diffPair(ul(["a", "b", "c"]), ul(["b", "c", "a"]))
        #expect(u.patches == [
            .setText(handle: 1, text: "b"),
            .setText(handle: 2, text: "c"),
            .setText(handle: 3, text: "a"),
        ])
    }

    @Test("Empty list → populated emits per-child create+appendChild")
    func emptyToPopulated() {
        let u = diffPair(ul([]), ul(["a", "b"]))
        // ul=0; "a" gets handle 1; "b" gets handle 2.
        #expect(u.patches == [
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
            .createText(handle: 2, text: "b"),
            .appendChild(parent: 0, child: 2),
        ])
    }

    @Test("Empty list → empty list emits no patches")
    func emptyToEmpty() {
        let u = diffPair(ul([]), ul([]))
        #expect(u.patches.isEmpty)
    }

    @Test("Insert in the middle of an existing list (no keys)")
    func insertMiddle() {
        // ["a","c"] → ["a","b","c"]. Index-pair compares a==a (no-op),
        // c→b (setText), then appends one new node (which will be the new
        // tail "c" with a fresh handle).
        let u = diffPair(ul(["a", "c"]), ul(["a", "b", "c"]))
        #expect(u.patches == [
            .setText(handle: 2, text: "b"),
            .createText(handle: 3, text: "c"),
            .appendChild(parent: 0, child: 3),
        ])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter IndexedChildrenTests`
Expected: failures (stub `diffChildren` is a no-op).

- [ ] **Step 3: Write `IndexedChildrenDiff.swift`**

```swift
// Sources/Swiflow/Diff/IndexedChildrenDiff.swift

/// Pairs `oldChildren[i]` with `newChildren[i]` and recurses via `update`.
/// For length deltas, emits appends for surplus new children and
/// `removeChild` + `destroyNode` for surplus old children. Mutates
/// `mounted.children` in place.
func diffChildrenIndexed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    let oldCount = mounted.children.count
    let newCount = newChildren.count
    let commonCount = min(oldCount, newCount)

    // 1. Reconcile common prefix.
    for i in 0..<commonCount {
        let oldChild = mounted.children[i]
        let newChild = update(
            mounted: oldChild,
            next: newChildren[i],
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        if newChild !== oldChild {
            // The update returned a fresh node (cross-kind / tag replace).
            // Replace in the parent's children array; for indexed (no keys),
            // we treat this as "remove old, insert new at same index" — the
            // patches emitted by update() already destroyed the old node.
            mounted.children[i] = newChild
            // Wire parent pointer; insertBefore is required for the new node.
            // Since the old node was destroyed in-place, we insertBefore the
            // next sibling (if any) or appendChild.
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

    // 2. Append surplus new children.
    if newCount > oldCount {
        for i in oldCount..<newCount {
            let childMount = mount(
                newChildren[i],
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            patches.append(.appendChild(parent: mounted.handle, child: childMount.handle))
            mounted.addChild(childMount)
        }
    }

    // 3. Remove surplus old children. Iterate from the end so indices remain
    //    valid as we splice the array.
    if oldCount > newCount {
        for i in stride(from: oldCount - 1, through: newCount, by: -1) {
            let removed = mounted.children[i]
            patches.append(.removeChild(parent: mounted.handle, child: removed.handle))
            destroy(removed, into: &patches, handlers: handlers)
            mounted.removeChild(at: i)
        }
    }
}
```

- [ ] **Step 4: Wire into the `diffChildren` stub**

In `Sources/Swiflow/Diff/Diff.swift`, replace the existing `diffChildren`
stub with:

```swift
/// Dispatches between the indexed and keyed children-diff strategies. If
/// **any** child in the old or new lists carries a key, the keyed path is
/// used (Task 17); otherwise pair-by-index (Task 16).
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    if hasAnyKey(mounted.children) || hasAnyKey(newChildren) {
        // Keyed path lands in Task 17.
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
    } else {
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
    }
}

/// Returns true if any element in `vnodes` is an `.element` with a non-nil
/// key.
func hasAnyKey(_ vnodes: [VNode]) -> Bool {
    for v in vnodes {
        if case .element(let data) = v, data.key != nil {
            return true
        }
    }
    return false
}

/// Same predicate, for `MountNode` (whose `.vnode` carries the key).
func hasAnyKey(_ nodes: [MountNode]) -> Bool {
    for n in nodes {
        if case .element(let data) = n.vnode, data.key != nil {
            return true
        }
    }
    return false
}
```

> The keyed branch is wired identically to indexed for now; Task 17 swaps it in.

- [ ] **Step 5: Run tests, expect PASS**

Run: `swift test`
Expected: all `IndexedChildrenTests` cases pass plus every previously-passing
suite.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/IndexedChildrenDiff.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/IndexedChildrenTests.swift
git commit -m "feat: index-pair children diff for unkeyed child lists"
```

---

## Task 17: Children diff — keyed (two-pointer + Map)

**Files:**
- Create: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift` (route keyed branch to the new file)
- Create: `Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift`

Two-pointer algorithm with Map fallback (per spec § 4.4): scan from both ends
for stable prefix/suffix, then bucket the middle by key and emit minimal
`insertBefore` / `removeChild` patches.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — children (keyed)")
struct KeyedChildrenTests {
    /// Builds `<ul><li key=K>K</li>...</ul>` for the given keys.
    private func ul(_ keys: [String]) -> VNode {
        .element(ElementData(
            tag: "ul",
            children: keys.map {
                .element(ElementData(tag: "li", key: $0, children: [.text($0)]))
            }
        ))
    }

    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }

    /// Returns only the structural opcodes (insertBefore, removeChild,
    /// destroyNode, appendChild, createElement, createText). Ignores
    /// attribute/property/style/handler/text patches, which can drift.
    private func structuralPatches(_ patches: [Patch]) -> [Patch] {
        patches.filter { patch in
            switch patch {
            case .insertBefore, .removeChild, .destroyNode,
                 .appendChild, .createElement, .createText:
                return true
            default:
                return false
            }
        }
    }

    @Test("Reordering keyed items emits only insertBefore patches (no destroys)")
    func reorderEmitsInsertBefore() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["c", "a", "b"]))
        // Existing handles: ul=0, li-a=1, "a"-text=2, li-b=3, "b"=4, li-c=5, "c"=6.
        // c was last, now first → insertBefore c before a.
        let s = structuralPatches(u.patches)
        #expect(s == [.insertBefore(parent: 0, child: 5, beforeChild: 1)])
    }

    @Test("Removing a keyed item emits removeChild + destroyNode for that key only")
    func removeKeyedItem() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["a", "c"]))
        // Drop "b" (li handle 3, text handle 4).
        let s = structuralPatches(u.patches)
        #expect(s == [
            .removeChild(parent: 0, child: 3),
            .destroyNode(handle: 4),
            .destroyNode(handle: 3),
        ])
    }

    @Test("Inserting a keyed item in the middle emits insertBefore for the new node")
    func insertKeyedItemMiddle() {
        let u = diffPair(ul(["a", "c"]), ul(["a", "b", "c"]))
        // New li for "b". After mount, existing handles: ul=0, li-a=1, "a"=2,
        // li-c=3, "c"=4. New li-b uses handles 5,6 (or two fresh handles).
        let s = structuralPatches(u.patches)
        // Find the createElement (for the new li) and the createText (for "b").
        guard let firstCreate = s.first, case .createElement(let liHandle, "li") = firstCreate else {
            Issue.record("expected first structural patch to be createElement(li)")
            return
        }
        // Then a createText for "b".
        let textHandle = liHandle + 1
        #expect(s == [
            .createElement(handle: liHandle, tag: "li"),
            .createText(handle: textHandle, text: "b"),
            .appendChild(parent: liHandle, child: textHandle),
            .insertBefore(parent: 0, child: liHandle, beforeChild: 3),
        ])
    }

    @Test("Full reverse [a,b,c] → [c,b,a] emits two insertBefore patches")
    func fullReverse() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["c", "b", "a"]))
        let s = structuralPatches(u.patches)
        // li-a=1, li-b=3, li-c=5.
        // After moving c to front: [c,a,b]. Then move b before a → [c,b,a].
        // That's two insertBefores; concrete ordering depends on algorithm
        // direction. Both of these are acceptable; assert on count + content.
        #expect(s.count == 2)
        #expect(s.allSatisfy {
            if case .insertBefore = $0 { return true } else { return false }
        })
    }

    @Test("Swap of adjacent keyed items emits one insertBefore")
    func swapAdjacent() {
        let u = diffPair(ul(["a", "b"]), ul(["b", "a"]))
        let s = structuralPatches(u.patches)
        // li-a=1, li-b=3. Move b before a → insertBefore(0, 3, 1).
        #expect(s == [.insertBefore(parent: 0, child: 3, beforeChild: 1)])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter KeyedChildrenTests`
Expected: most tests fail because the keyed branch currently calls the
indexed implementation, which would destroy and recreate.

- [ ] **Step 3: Write `KeyedChildrenDiff.swift`**

The algorithm: scan stable prefix (both ends pointers `oldStart`, `newStart`
advance while keys match), then stable suffix (`oldEnd`, `newEnd` retreat
while keys match), then bucket the remaining old children by key into a Map,
and process the remaining new children, reusing or creating as needed and
emitting `insertBefore` for moves.

```swift
// Sources/Swiflow/Diff/KeyedChildrenDiff.swift

/// Reconciles a list of keyed children. Algorithm:
///
/// 1. Pin the longest stable **prefix**: while `old[start].key == new[start].key`,
///    recurse and advance both pointers.
/// 2. Pin the longest stable **suffix**: same from the right.
/// 3. Anything left in the middle: bucket old by key into a Map, walk the new
///    middle, and either reuse (`insertBefore`) or mount + insert.
/// 4. Whatever stays in the bucket at the end is destroyed.
///
/// For elements without keys mixed into a keyed list, fall through to indexed
/// pairing in that slot. (Phase 1 emits a diagnostic in Phase 4; for now,
/// treat unkeyed children as having key `"__index_<i>"`.)
func diffChildrenKeyed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    var oldStart = 0
    var newStart = 0
    var oldEnd = mounted.children.count - 1
    var newEnd = newChildren.count - 1

    // 1. Stable prefix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldStart]) == keyOf(newChildren[newStart])
    {
        let updated = update(
            mounted: mounted.children[oldStart],
            next: newChildren[newStart],
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        if updated !== mounted.children[oldStart] {
            mounted.children[oldStart] = updated
        }
        oldStart += 1
        newStart += 1
    }

    // 2. Stable suffix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldEnd]) == keyOf(newChildren[newEnd])
    {
        let updated = update(
            mounted: mounted.children[oldEnd],
            next: newChildren[newEnd],
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        if updated !== mounted.children[oldEnd] {
            mounted.children[oldEnd] = updated
        }
        oldEnd -= 1
        newEnd -= 1
    }

    // 3. Both ranges exhausted: stable prefix + suffix covered everything.
    if oldStart > oldEnd && newStart > newEnd {
        return
    }

    // 4. Pure inserts (old range exhausted, new range has work).
    if oldStart > oldEnd {
        // Anchor is the first node in the stable suffix (which sits at
        // mounted.children[oldStart], because the suffix scan didn't touch
        // the front and oldEnd has now slipped below oldStart).
        let beforeHandle: Int? = (oldStart < mounted.children.count)
            ? mounted.children[oldStart].handle
            : nil
        var insertIndex = oldStart
        for i in newStart...newEnd {
            let child = mount(
                newChildren[i],
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            if let before = beforeHandle {
                patches.append(.insertBefore(parent: mounted.handle, child: child.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: child.handle))
            }
            mounted.insertChild(child, at: insertIndex)
            insertIndex += 1
        }
        return
    }

    // 5. Pure removes (new range exhausted, old range has work).
    if newStart > newEnd {
        for i in stride(from: oldEnd, through: oldStart, by: -1) {
            let removed = mounted.children[i]
            patches.append(.removeChild(parent: mounted.handle, child: removed.handle))
            destroy(removed, into: &patches, handlers: handlers)
            mounted.removeChild(at: i)
        }
        return
    }

    // 6. Map-based middle: bucket old by key.
    var oldByKey: [String: MountNode] = [:]
    var oldIndexByKey: [String: Int] = [:]
    for i in oldStart...oldEnd {
        let key = keyOf(mounted.children[i])
        oldByKey[key] = mounted.children[i]
        oldIndexByKey[key] = i
    }

    // Walk the new middle; for each new child, either reuse from oldByKey
    // (emit insertBefore) or mount fresh.
    var newSlice: [MountNode] = []
    for i in newStart...newEnd {
        let newChild = newChildren[i]
        let key = keyOf(newChild)
        if let reused = oldByKey.removeValue(forKey: key) {
            let updated = update(
                mounted: reused,
                next: newChild,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            newSlice.append(updated)
            // Always emit insertBefore for moved/middle items relative to the
            // next stable suffix anchor.
            let anchor: Int? = (newEnd + 1 < newChildren.count)
                ? mounted.children[oldEnd + 1].handle
                : nil
            if let before = anchor {
                patches.append(.insertBefore(parent: mounted.handle, child: updated.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: updated.handle))
            }
        } else {
            let fresh = mount(
                newChild,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            newSlice.append(fresh)
            let anchor: Int? = (newEnd + 1 < newChildren.count)
                ? mounted.children[oldEnd + 1].handle
                : nil
            if let before = anchor {
                patches.append(.insertBefore(parent: mounted.handle, child: fresh.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: fresh.handle))
            }
        }
    }

    // 7. Destroy anything still in oldByKey (not reused).
    for (_, leftover) in oldByKey {
        patches.append(.removeChild(parent: mounted.handle, child: leftover.handle))
        destroy(leftover, into: &patches, handlers: handlers)
    }

    // 8. Splice mounted.children: [prefix] + newSlice + [suffix].
    let prefix = Array(mounted.children[0..<oldStart])
    let suffix = Array(mounted.children[(oldEnd + 1)..<mounted.children.count])
    let merged = prefix + newSlice + suffix
    // Detach all then re-attach to refresh parent pointers cleanly.
    while !mounted.children.isEmpty {
        mounted.removeChild(at: mounted.children.count - 1)
    }
    for child in merged {
        mounted.addChild(child)
    }
}

/// Returns the key of a `MountNode` (its committed element key) or a synthetic
/// index key if the node has no key. Phase 4 will emit a diagnostic when
/// keyed and unkeyed children are mixed.
func keyOf(_ node: MountNode) -> String {
    if case .element(let data) = node.vnode, let key = data.key {
        return key
    }
    return "__noKey_\(node.handle)"
}

/// Returns the key of an incoming VNode, or a synthetic per-position key.
func keyOf(_ vnode: VNode) -> String {
    if case .element(let data) = vnode, let key = data.key {
        return key
    }
    return "__noKey_unkeyed"
}
```

- [ ] **Step 4: Switch the `diffChildren` keyed branch to call `diffChildrenKeyed`**

In `Sources/Swiflow/Diff/Diff.swift`, change `diffChildren` to:

```swift
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    if hasAnyKey(mounted.children) || hasAnyKey(newChildren) {
        diffChildrenKeyed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
    } else {
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
    }
}
```

- [ ] **Step 5: Run tests, expect PASS**

Run: `swift test`
Expected: all suites pass. The keyed children tests verify structural-only
patches via the `structuralPatches` helper because the attribute/property
sub-patches around `<li>` aren't load-bearing for the algorithm's correctness.

> **If a keyed test fails**, the most likely cause is the anchor calculation
> in steps 4 and 6 (pure inserts; middle reuse). The reference is the *first
> node of the stable suffix* on the mount tree, which is
> `mounted.children[oldEnd + 1]` (equivalently `mounted.children[oldStart]`
> when `oldStart > oldEnd`). Walk through the test inputs by hand to confirm.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/KeyedChildrenDiff.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift
git commit -m "feat: keyed children diff with two-pointer scan and Map fallback"
```

---

## Task 18: DSL — `ChildrenBuilder` result builder

**Files:**
- Create: `Sources/Swiflow/DSL/ResultBuilder.swift`
- Create: `Tests/SwiflowTests/DSLTests.swift`

The result builder converts `{ vnodeA; vnodeB }` into `[VNode]`. Supports
zero, one, many, optional, conditional, and array expressions.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/DSLTests.swift
import Testing
@testable import Swiflow

@Suite("DSL — ChildrenBuilder")
struct ChildrenBuilderTests {

    @ChildrenBuilder
    private func empty() -> [VNode] {}

    @ChildrenBuilder
    private func singleText() -> [VNode] {
        VNode.text("hi")
    }

    @ChildrenBuilder
    private func multiple() -> [VNode] {
        VNode.text("a")
        VNode.text("b")
        VNode.text("c")
    }

    @ChildrenBuilder
    private func conditional(_ flag: Bool) -> [VNode] {
        VNode.text("always")
        if flag {
            VNode.text("conditionally")
        }
    }

    @ChildrenBuilder
    private func eitherOr(_ flag: Bool) -> [VNode] {
        if flag {
            VNode.text("yes")
        } else {
            VNode.text("no")
        }
    }

    @ChildrenBuilder
    private func arrayLiteral() -> [VNode] {
        for s in ["x", "y", "z"] {
            VNode.text(s)
        }
    }

    @Test("Empty block produces no children")
    func emptyProducesNone() {
        #expect(empty().isEmpty)
    }

    @Test("Single expression produces one child")
    func singleProducesOne() {
        #expect(singleText() == [.text("hi")])
    }

    @Test("Multiple expressions produce ordered children")
    func multipleProducesAll() {
        #expect(multiple() == [.text("a"), .text("b"), .text("c")])
    }

    @Test("Optional branch is included or skipped based on condition")
    func optionalIncludesWhenTrue() {
        #expect(conditional(true) == [.text("always"), .text("conditionally")])
        #expect(conditional(false) == [.text("always")])
    }

    @Test("Either branch picks one side")
    func eitherPicksBranch() {
        #expect(eitherOr(true) == [.text("yes")])
        #expect(eitherOr(false) == [.text("no")])
    }

    @Test("For-loop produces all iterations")
    func forLoopProducesAll() {
        #expect(arrayLiteral() == [.text("x"), .text("y"), .text("z")])
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter ChildrenBuilderTests`
Expected: `ChildrenBuilder` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/DSL/ResultBuilder.swift

/// Builds a `[VNode]` from a SwiftUI-style trailing-closure block. Supports
/// single expressions, multiple statements, optional branches, either-or
/// (`if/else`), and `for` loops.
@resultBuilder
public enum ChildrenBuilder {
    public static func buildBlock() -> [VNode] { [] }

    public static func buildBlock(_ components: [VNode]...) -> [VNode] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: VNode) -> [VNode] {
        [expression]
    }

    public static func buildExpression(_ expression: [VNode]) -> [VNode] {
        expression
    }

    public static func buildOptional(_ component: [VNode]?) -> [VNode] {
        component ?? []
    }

    public static func buildEither(first component: [VNode]) -> [VNode] {
        component
    }

    public static func buildEither(second component: [VNode]) -> [VNode] {
        component
    }

    public static func buildArray(_ components: [[VNode]]) -> [VNode] {
        components.flatMap { $0 }
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter ChildrenBuilderTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/ResultBuilder.swift Tests/SwiflowTests/DSLTests.swift
git commit -m "feat: add @resultBuilder ChildrenBuilder for VNode list construction"
```

---

## Task 19: DSL — `Attribute` value type and modifiers

**Files:**
- Create: `Sources/Swiflow/DSL/Modifiers.swift`
- Modify: `Tests/SwiflowTests/DSLTests.swift` (append a new `@Suite`)

`Attribute` is the variadic argument type the element factories take. Each
modifier produces an `Attribute` value that gets merged into the eventual
`ElementData`.

- [ ] **Step 1: Append the new test suite**

Append to `Tests/SwiflowTests/DSLTests.swift`:

```swift
@Suite("DSL — Attribute modifiers")
struct AttributeModifierTests {

    @Test(".class produces an attribute named 'class'")
    func classModifier() {
        let attr = Attribute.class("row")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["class": "row"])
    }

    @Test(".id produces an attribute named 'id'")
    func idModifier() {
        let attr = Attribute.id("main")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["id": "main"])
    }

    @Test(".attr produces an arbitrary attribute")
    func attrModifier() {
        let attr = Attribute.attr("data-foo", "bar")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.attributes == ["data-foo": "bar"])
    }

    @Test(".prop produces a property")
    func propModifier() {
        let attr = Attribute.prop("value", .string("x"))
        let data = applyAttributes(tag: "input", [attr])
        #expect(data.properties == ["value": .string("x")])
    }

    @Test(".style produces an inline style declaration")
    func styleModifier() {
        let attr = Attribute.style("color", "red")
        let data = applyAttributes(tag: "div", [attr])
        #expect(data.style == ["color": "red"])
    }

    @Test(".key sets the element key")
    func keyModifier() {
        let attr = Attribute.key("k1")
        let data = applyAttributes(tag: "li", [attr])
        #expect(data.key == "k1")
    }

    @Test(".on produces a handler entry (uses ambient registry)")
    func onModifier() {
        var fired = false
        let attr = Attribute.on("click", HandlerRegistry.testInstance.register { _ in fired = true })
        let data = applyAttributes(tag: "button", [attr])
        #expect(data.handlers["click"] != nil)
        // Dispatch directly to assert wiring.
        data.handlers["click"]?.invoke(Event(type: "click"))
        #expect(fired)
    }

    @Test("Multiple modifiers of the same category merge in declaration order")
    func multipleMergeInOrder() {
        let data = applyAttributes(tag: "div", [
            .class("a"),
            .style("color", "red"),
            .style("font-size", "12px"),
        ])
        #expect(data.attributes == ["class": "a"])
        #expect(data.style == ["color": "red", "font-size": "12px"])
    }

    @Test("Later modifier of same key overrides earlier")
    func laterOverrides() {
        let data = applyAttributes(tag: "div", [
            .class("a"),
            .class("b"),
        ])
        #expect(data.attributes == ["class": "b"])
    }
}

// HandlerRegistry.testInstance — a process-wide convenience for tests.
// Production code uses an injected registry; this just keeps the DSL tests
// readable.
extension HandlerRegistry {
    static let testInstance = HandlerRegistry()
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter AttributeModifierTests`
Expected: `Attribute` and `applyAttributes` undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/DSL/Modifiers.swift

/// A single modifier passed to an element factory (e.g. `div(.class("row"))`).
/// Each case maps directly to one of `ElementData`'s bags.
public enum Attribute {
    case attribute(name: String, value: String)
    case property(name: String, value: PropertyValue)
    case style(name: String, value: String)
    case handler(event: String, value: EventHandler)
    case key(String)

    // Convenience factories.

    public static func attr(_ name: String, _ value: String) -> Attribute {
        .attribute(name: name, value: value)
    }

    public static func `class`(_ value: String) -> Attribute {
        .attribute(name: "class", value: value)
    }

    public static func id(_ value: String) -> Attribute {
        .attribute(name: "id", value: value)
    }

    public static func prop(_ name: String, _ value: PropertyValue) -> Attribute {
        .property(name: name, value: value)
    }

    public static func style(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }

    public static func on(_ event: String, _ handler: EventHandler) -> Attribute {
        .handler(event: event, value: handler)
    }

    public static func key(_ value: String) -> Attribute {
        .key(value)
    }
}

/// Folds a list of `Attribute`s into the four bags + key of an `ElementData`.
/// Later attributes of the same key override earlier ones — this matches the
/// "last write wins" intuition of standard DOM property assignment.
public func applyAttributes(
    tag: String,
    _ attributes: [Attribute],
    children: [VNode] = []
) -> ElementData {
    var attrs: [String: String] = [:]
    var props: [String: PropertyValue] = [:]
    var styles: [String: String] = [:]
    var handlers: [String: EventHandler] = [:]
    var key: String? = nil

    for attribute in attributes {
        switch attribute {
        case .attribute(let name, let value):
            attrs[name] = value
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

    return ElementData(
        tag: tag,
        key: key,
        attributes: attrs,
        properties: props,
        style: styles,
        handlers: handlers,
        children: children
    )
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter AttributeModifierTests`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/Modifiers.swift Tests/SwiflowTests/DSLTests.swift
git commit -m "feat: add Attribute modifier enum and applyAttributes folder"
```

---

## Task 20: DSL — element factories

**Files:**
- Create: `Sources/Swiflow/DSL/Elements.swift`
- Modify: `Tests/SwiflowTests/DSLTests.swift` (append element factory suite)

Lowercase free functions: `div`, `span`, `h1`, `h2`, `h3`, `p`, `button`, `a`,
`input`, `ul`, `li`, `img`, `form`, `label`, `pre`, `code`, `section`,
`header`, `footer`, `nav`, `main_` (`main` is a Swift keyword adjacent).

Each factory accepts a variadic `Attribute...` and an optional
`@ChildrenBuilder` trailing closure. There's also a convenience overload that
takes a single `String` body for text-only elements (e.g.
`h1("Hello")`).

- [ ] **Step 1: Append the new test suite**

Append to `Tests/SwiflowTests/DSLTests.swift`:

```swift
@Suite("DSL — element factories")
struct ElementFactoryTests {

    @Test("div with no attrs and no children")
    func bareDiv() {
        let node = div()
        #expect(node == .element(ElementData(tag: "div")))
    }

    @Test("div with class and child text")
    func divWithClassAndChild() {
        let node = div(.class("row")) {
            VNode.text("hi")
        }
        let expected = VNode.element(ElementData(
            tag: "div",
            attributes: ["class": "row"],
            children: [.text("hi")]
        ))
        #expect(node == expected)
    }

    @Test("h1 with text-only convenience overload")
    func h1Text() {
        let node = h1("Hello")
        let expected = VNode.element(ElementData(
            tag: "h1",
            children: [.text("Hello")]
        ))
        #expect(node == expected)
    }

    @Test("button with handler and text body")
    func buttonWithHandler() {
        let registry = HandlerRegistry()
        let h = registry.register { _ in }
        let node = button("Click", .on("click", h))
        let expected = VNode.element(ElementData(
            tag: "button",
            handlers: ["click": h],
            children: [.text("Click")]
        ))
        #expect(node == expected)
    }

    @Test("ul with mapped children")
    func ulMappedChildren() {
        let items = ["a", "b", "c"]
        let node = ul {
            for item in items {
                li { VNode.text(item) }
            }
        }
        let expected = VNode.element(ElementData(
            tag: "ul",
            children: items.map { i in
                .element(ElementData(tag: "li", children: [.text(i)]))
            }
        ))
        #expect(node == expected)
    }

    @Test("input self-closing with property")
    func inputWithProperty() {
        let node = input(.prop("value", .string("x")), .attr("type", "text"))
        let expected = VNode.element(ElementData(
            tag: "input",
            attributes: ["type": "text"],
            properties: ["value": .string("x")]
        ))
        #expect(node == expected)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter ElementFactoryTests`
Expected: every factory undeclared.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/DSL/Elements.swift

// MARK: - Generic factory helpers

/// Generic factory used by every element below. Variadic `Attribute`s and an
/// optional trailing children block.
public func element(
    _ tag: String,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: tag, attributes, children: children()))
}

/// Text-only convenience: `h1("Hello")`.
public func element(
    _ tag: String,
    _ text: String,
    _ attributes: Attribute...
) -> VNode {
    .element(applyAttributes(tag: tag, attributes, children: [.text(text)]))
}

// MARK: - Concrete elements

public func div(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "div", attributes, children: children()))
}

public func span(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "span", attributes, children: children()))
}

public func p(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: children()))
}

public func p(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: [.text(text)]))
}

public func h1(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: children()))
}

public func h1(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: [.text(text)]))
}

public func h2(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: children()))
}

public func h2(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: [.text(text)]))
}

public func h3(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: children()))
}

public func h3(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: [.text(text)]))
}

public func button(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: children()))
}

public func button(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: [.text(text)]))
}

public func a(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: children()))
}

public func a(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: [.text(text)]))
}

public func input(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "input", attributes))
}

public func img(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "img", attributes))
}

public func ul(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "ul", attributes, children: children()))
}

public func li(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: children()))
}

public func li(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: [.text(text)]))
}

public func form(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "form", attributes, children: children()))
}

public func label(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: children()))
}

public func label(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: [.text(text)]))
}

public func pre(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "pre", attributes, children: children()))
}

public func code(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: children()))
}

public func code(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: [.text(text)]))
}

public func section(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "section", attributes, children: children()))
}

public func header(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "header", attributes, children: children()))
}

public func footer(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "footer", attributes, children: children()))
}

public func nav(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "nav", attributes, children: children()))
}

/// `main` is a Swift keyword in some attribute contexts; spell the factory
/// `main_` to avoid surprising users.
public func main_(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "main", attributes, children: children()))
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter ElementFactoryTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/Elements.swift Tests/SwiflowTests/DSLTests.swift
git commit -m "feat: add lowercase free-function HTML element factories"
```

---

## Task 21: DSL — `rawHTML` escape hatch

**Files:**
- Create: `Sources/Swiflow/DSL/RawHTML.swift`
- Modify: `Tests/SwiflowTests/DSLTests.swift` (append rawHTML suite)

A loud, searchable convenience for the `VNode.rawHTML(_:)` case.

- [ ] **Step 1: Append the test suite**

Append to `Tests/SwiflowTests/DSLTests.swift`:

```swift
@Suite("DSL — rawHTML escape hatch")
struct RawHTMLDSLTests {
    @Test("rawHTML produces a VNode.rawHTML case")
    func producesRawHTMLCase() {
        let node = rawHTML("<svg/>")
        #expect(node == .rawHTML("<svg/>"))
    }

    @Test("rawHTML can be embedded as a child")
    func embedAsChild() {
        let node = div { rawHTML("<b>x</b>") }
        let expected = VNode.element(ElementData(
            tag: "div",
            children: [.rawHTML("<b>x</b>")]
        ))
        #expect(node == expected)
    }
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `swift test --filter RawHTMLDSLTests`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/DSL/RawHTML.swift

/// Renders unescaped HTML via the DOM's `innerHTML` setter. Use this only
/// when the markup is trusted (constants, server-sanitized input, …).
///
/// The name is intentional: `git grep "rawHTML("` enumerates every audit
/// site in a project. There is no shorter alias.
public func rawHTML(_ html: String) -> VNode {
    .rawHTML(html)
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/RawHTML.swift Tests/SwiflowTests/DSLTests.swift
git commit -m "feat: add rawHTML escape hatch as a loudly-named DSL helper"
```

---

## Task 22: Mount-tree consistency check

**Files:**
- Modify: `Tests/SwiflowTests/MountTreeTests.swift` (append a new suite)

Spec § 4.5: "after every diff, the committed `newMountTree` must structurally
equal the input VNode (modulo handles)." This adds a property-style test that
sweeps the major diff scenarios.

- [ ] **Step 1: Append the test suite**

Append to `Tests/SwiflowTests/MountTreeTests.swift`:

```swift
@Suite("Mount-tree consistency after diff")
struct MountTreeConsistencyTests {

    /// Walk a `MountNode` and produce the VNode it represents (i.e., the
    /// committed `vnode` recursively replaced by its children's committed
    /// `vnode`s). For elements, the returned VNode preserves the latest
    /// children structure but uses each child's stored `vnode`.
    private func committedVNode(_ node: MountNode) -> VNode {
        switch node.vnode {
        case .text, .rawHTML:
            return node.vnode
        case .element(let data):
            let kids = node.children.map(committedVNode)
            return .element(ElementData(
                tag: data.tag,
                key: data.key,
                attributes: data.attributes,
                properties: data.properties,
                style: data.style,
                handlers: data.handlers,
                children: kids
            ))
        }
    }

    private func roundTrip(_ a: VNode, _ b: VNode) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        #expect(committedVNode(m.newMountTree) == a, "first mount must reconstruct input")
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        #expect(committedVNode(u.newMountTree) == b, "post-diff mount tree must reconstruct b")
    }

    @Test("Consistency: text → text")
    func textToText() {
        roundTrip(.text("a"), .text("b"))
    }

    @Test("Consistency: element with attribute change")
    func attrChange() {
        roundTrip(
            .element(ElementData(tag: "div", attributes: ["class": "x"])),
            .element(ElementData(tag: "div", attributes: ["class": "y"]))
        )
    }

    @Test("Consistency: list of children (indexed)")
    func childrenIndexed() {
        roundTrip(
            .element(ElementData(tag: "ul", children: [.text("a"), .text("b")])),
            .element(ElementData(tag: "ul", children: [.text("a"), .text("B"), .text("c")]))
        )
    }

    @Test("Consistency: list of children (keyed reorder)")
    func childrenKeyedReorder() {
        let withKeys: ([String]) -> VNode = { keys in
            .element(ElementData(
                tag: "ul",
                children: keys.map {
                    .element(ElementData(tag: "li", key: $0, children: [.text($0)]))
                }
            ))
        }
        roundTrip(withKeys(["a", "b", "c"]), withKeys(["c", "a", "b"]))
    }

    @Test("Consistency: tag replace")
    func tagReplace() {
        roundTrip(
            .element(ElementData(tag: "div")),
            .element(ElementData(tag: "span"))
        )
    }
}
```

- [ ] **Step 2: Run tests, expect PASS**

Run: `swift test --filter MountTreeConsistencyTests`
Expected: 5 tests pass. If any fail, the diff or one of the children paths is
leaving the mount tree out of sync with the input. Debug from the failing
test.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/MountTreeTests.swift
git commit -m "test: lock mount-tree consistency invariant across all diff paths"
```

---

## Task 23: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

GitHub Actions runs `swift build` and `swift test` on macOS and Linux on every
push and PR. (The WASM SDK setup for `swiflow init` template validation lands
in Phase 2; Phase 1 has no WASM dependency.)

- [ ] **Step 1: Write the workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    name: Test (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14, ubuntu-22.04]
    steps:
      - uses: actions/checkout@v4

      - name: Set up Swift (Linux)
        if: runner.os == 'Linux'
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "6.0"

      - name: Verify Swift version
        run: swift --version

      - name: Build
        run: swift build

      - name: Test
        run: swift test --parallel
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run swift build and swift test on macOS and Linux"
```

- [ ] **Step 3: Local verification**

Run: `swift test --parallel`
Expected: all suites pass under parallel execution.

If running parallel reveals flakiness (it shouldn't — every test allocates
its own `HandleAllocator` and `HandlerRegistry`), investigate. The only
shared state is `HandlerRegistry.testInstance` in `DSLTests.swift` — if a
test fails intermittently, replace that single use with a local instance.

---

## Task 24: Doc comments pass + Phase 1 README update

**Files:**
- Modify: `Sources/Swiflow/*.swift` (add `///` headers wherever missing)
- Modify: `README.md`

This task is the "Public API surface documented with `///` doc comments"
clause of Phase 1's success criteria. Most files already carry doc comments
from Tasks 3–21; this pass closes any gaps.

- [ ] **Step 1: Audit doc-comment coverage**

Run:
```bash
grep -rL '^///' Sources/Swiflow/ | grep -v '/.build/'
```
Expected: every public symbol should have a `///` doc comment. Add ones where
missing.

For any file that still lacks header documentation, add a one-paragraph file
comment at the top describing its role.

- [ ] **Step 2: Update README with Phase 1 capabilities**

Replace `README.md` body with:

```markdown
# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 1 (the VDOM "Brain") is complete. The `Swiflow` Swift
package compiles and tests on macOS and Linux with no WASM toolchain required.
Phase 2 (the `swiflow` CLI, dev server, and JS driver) is in progress.

## What's in Phase 1?

- `VNode` — a tagged-enum virtual DOM with element / text / rawHTML cases.
- `Patch` — 14 mutation opcodes the (future) JS driver will execute.
- A hybrid diff engine — index-pair for unkeyed children, two-pointer + Map
  for keyed children.
- A `@resultBuilder`-based DSL with lowercase free-function elements:
  ```swift
  let view = div(.class("container")) {
      h1("Hello, Swiflow!")
      ul {
          for item in items {
              li(.key(item.id)) { p(item.text) }
          }
      }
  }
  ```
- An XSS-safe `rawHTML(_:)` escape hatch (search `rg "rawHTML\("` to audit
  every use).

## Quick start

```bash
swift test
```

All Phase 1 functionality is exercised by the `SwiflowTests` target.

## Architecture

See [the refined spec](https://github.com/<TODO>/<repo>/blob/main/docs/superpowers/specs/) (Phase 1+2 deep, Phase 3+4 sketched) and
[the original brainstorm](docs/brainstorm/) for design rationale.

## License

Apache 2.0. See [LICENSE](LICENSE).
```

> Replace `<TODO>/<repo>` with the actual GitHub coordinates once the repo
> is published. Leave the placeholder for now.

- [ ] **Step 3: Final verification**

Run:
```bash
swift build
swift test
```
Expected:
- Build: succeeds with no warnings.
- Test: every test suite (PropertyValue, VNode, Patch, HandleAllocator,
  HandlerRegistry, MountTree, all DiffTests, ChildrenBuilder,
  AttributeModifier, ElementFactory, RawHTMLDSL, MountTreeConsistency)
  passes.

If a warning appears, fix the underlying issue before committing.

- [ ] **Step 4: Commit**

```bash
git add Sources README.md
git commit -m "docs: complete public-API doc comments and update Phase 1 README"
```

---

## Phase 1 Completion Checklist

After Task 24, verify:

- [ ] `swift build` succeeds with no warnings on macOS and Linux.
- [ ] `swift test --parallel` reports zero failures.
- [ ] Every `Patch` variant is emitted by at least one test (search for
      `\.\w+\(` patterns in `Tests/SwiflowTests/`).
- [ ] No imports outside `Foundation`-free `Swiflow` (run
      `grep -r '^import' Sources/Swiflow/` — should be empty).
- [ ] CI workflow runs green on the first push.

When all boxes are checked, the Phase 1 spec criteria are met. Phase 2 begins
with its own plan; it will add the `SwiflowCLI` executable, the JS driver, and
the JavaScriptKit-based renderer that consumes the `Patch` enum produced here.

---

## Out of Scope for This Plan

Reaffirming what the spec deferred:

- The `Swiflow.render(_:into:)` and `Swiflow.rerender()` public APIs (Phase 2 —
  these need JavaScriptKit and so cannot exist in the platform-independent
  library target).
- `PatchSerializer.swift` and `HandlerRegistry`'s JS-side dispatcher wiring
  (Phase 2 — JavaScriptKit-dependent).
- The CLI executable (`SwiflowCLI` target), dev server, file watcher, JS
  driver, `swiflow init` templates (Phase 2).
- `@State`, `Component`, scheduler, lifecycle hooks (Phase 3).
- LIS-optimized keyed diff, binary patch buffer, source maps, URL sanitizer,
  Homebrew tap, NPM driver publish (Phase 4).
- Diagnostic error messages for mixed keyed/unkeyed children, duplicate keys
  (Phase 4 — Phase 1 silently treats unkeyed siblings of keyed siblings as
  having synthetic keys via `keyOf(_:)`).
