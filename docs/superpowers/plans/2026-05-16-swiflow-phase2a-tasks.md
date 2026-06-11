# Swiflow Phase 2a — Task-by-Task TDD Steps

> Companion to `2026-05-16-swiflow-phase2a-renderer-and-driver.md`. All 8 tasks live here so the parent plan file stays scannable. Read the parent first for goals, architecture, and the file map.

---

## Task 1: Package restructure — add `SwiflowWeb` target + `JavaScriptKit` dependency

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowWeb/SwiflowWeb.swift` (placeholder so target compiles)

This task lands the package skeleton. No new tests yet — Tasks 2+ add testable code under `Sources/Swiflow/` and the WASM-only `Sources/SwiflowWeb/` stays untested by `swift test`.

- [ ] **Step 1: Replace `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.21.0"),
    ],
    targets: [
        .target(
            name: "Swiflow",
            path: "Sources/Swiflow"
        ),
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb"
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests"
        ),
    ]
)
```

- [ ] **Step 2: Create `Sources/SwiflowWeb/SwiflowWeb.swift`**

```swift
// Sources/SwiflowWeb/SwiflowWeb.swift
//
// SwiflowWeb is the WASM-only renderer layer for Swiflow. All public API
// lives behind a `#if canImport(JavaScriptKit)` so the target compiles
// (empty) on platforms without WASM support — this lets `swift build` and
// `swift test` work on macOS/Linux developer machines while CI's WASM job
// builds the real symbols.

#if canImport(JavaScriptKit)
import JavaScriptKit
@_exported import Swiflow
#endif
```

- [ ] **Step 3: Resolve and build**

```bash
cd .
swift package resolve 2>&1 | tail -5
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```
Expected: resolve succeeds; build succeeds (SwiflowWeb compiles to empty module); 103 tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat: add SwiflowWeb target with JavaScriptKit dependency (skeleton)"
```

---

## Task 2: `PatchPayload` intermediate type

**Files:**
- Create: `Sources/Swiflow/PatchPayload.swift`
- Create: `Tests/SwiflowTests/PatchPayloadTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/PatchPayloadTests.swift
import Testing
@testable import Swiflow

@Suite("PatchPayload")
struct PatchPayloadTests {
    @Test("Equality compares op and fields")
    func equality() {
        let a = PatchPayload(op: "createElement", fields: [
            "handle": .int(0),
            "tag": .string("div"),
        ])
        let b = PatchPayload(op: "createElement", fields: [
            "handle": .int(0),
            "tag": .string("div"),
        ])
        #expect(a == b)
    }

    @Test("Different ops are unequal")
    func differentOps() {
        let a = PatchPayload(op: "createElement", fields: [:])
        let b = PatchPayload(op: "createText", fields: [:])
        #expect(a != b)
    }

    @Test("Different fields are unequal")
    func differentFields() {
        let a = PatchPayload(op: "createElement", fields: ["tag": .string("div")])
        let b = PatchPayload(op: "createElement", fields: ["tag": .string("span")])
        #expect(a != b)
    }

    @Test("Field cases discriminate by type")
    func fieldDiscrimination() {
        #expect(PatchPayload.Field.int(1) != PatchPayload.Field.string("1"))
        #expect(PatchPayload.Field.int(1) == PatchPayload.Field.int(1))
        #expect(PatchPayload.Field.property(.bool(true)) == PatchPayload.Field.property(.bool(true)))
        #expect(PatchPayload.Field.property(.bool(true)) != PatchPayload.Field.property(.bool(false)))
    }
}
```

- [ ] **Step 2: Run filter, expect red**

```bash
swift test --filter PatchPayloadTests
```

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/PatchPayload.swift

/// A serialized `Patch`, ready to be ferried across the WASM↔JS bridge.
///
/// `PatchPayload` is the testable intermediate between the typed `Patch`
/// enum and the untyped `JSObject` the JS driver receives. Holding the
/// payload as a plain Swift value lets every encoding decision live under
/// `swift test`; only the final dict→JSObject step depends on JavaScriptKit
/// and so escapes macOS-side testing.
public struct PatchPayload: Equatable, Sendable {
    public let op: String
    public let fields: [String: Field]

    public init(op: String, fields: [String: Field]) {
        self.op = op
        self.fields = fields
    }

    /// A single field value inside a `PatchPayload.fields` dictionary.
    public enum Field: Equatable, Sendable {
        case int(Int)
        case string(String)
        case property(PropertyValue)
    }
}
```

- [ ] **Step 4: Run, expect 4 tests pass**

```bash
swift test --filter PatchPayloadTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/PatchPayload.swift Tests/SwiflowTests/PatchPayloadTests.swift
git commit -m "feat: add PatchPayload intermediate type for patch serialization"
```

---

## Task 3: `PatchSerializer.encode(Patch) -> PatchPayload`

**Files:**
- Create: `Sources/Swiflow/PatchSerializer.swift`
- Create: `Tests/SwiflowTests/PatchSerializerTests.swift`

One pure function. Switches over all 16 `Patch` cases. The opcode discriminator (`op: String`) matches the case name exactly — this is the contract the JS driver's `switch (p.op)` depends on.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/PatchSerializerTests.swift
import Testing
@testable import Swiflow

@Suite("PatchSerializer")
struct PatchSerializerTests {

    // MARK: - Lifecycle

    @Test("createElement encodes op + handle + tag")
    func createElement() {
        let p = Patch.createElement(handle: 7, tag: "div")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createElement",
            fields: ["handle": .int(7), "tag": .string("div")]
        ))
    }

    @Test("createText encodes op + handle + text")
    func createText() {
        let p = Patch.createText(handle: 7, text: "hi")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createText",
            fields: ["handle": .int(7), "text": .string("hi")]
        ))
    }

    @Test("createRawHTML encodes op + handle + html")
    func createRawHTML() {
        let p = Patch.createRawHTML(handle: 7, html: "<b/>")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "createRawHTML",
            fields: ["handle": .int(7), "html": .string("<b/>")]
        ))
    }

    @Test("destroyNode encodes op + handle")
    func destroyNode() {
        let p = Patch.destroyNode(handle: 7)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "destroyNode",
            fields: ["handle": .int(7)]
        ))
    }

    // MARK: - Tree structure

    @Test("appendChild encodes op + parent + child")
    func appendChild() {
        let p = Patch.appendChild(parent: 1, child: 2)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "appendChild",
            fields: ["parent": .int(1), "child": .int(2)]
        ))
    }

    @Test("insertBefore encodes op + parent + child + beforeChild")
    func insertBefore() {
        let p = Patch.insertBefore(parent: 1, child: 2, beforeChild: 3)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "insertBefore",
            fields: [
                "parent": .int(1),
                "child": .int(2),
                "beforeChild": .int(3),
            ]
        ))
    }

    @Test("removeChild encodes op + parent + child")
    func removeChild() {
        let p = Patch.removeChild(parent: 1, child: 2)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeChild",
            fields: ["parent": .int(1), "child": .int(2)]
        ))
    }

    // MARK: - Mutations

    @Test("setAttribute encodes op + handle + name + value")
    func setAttribute() {
        let p = Patch.setAttribute(handle: 1, name: "class", value: "row")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setAttribute",
            fields: [
                "handle": .int(1),
                "name": .string("class"),
                "value": .string("row"),
            ]
        ))
    }

    @Test("removeAttribute encodes op + handle + name")
    func removeAttribute() {
        let p = Patch.removeAttribute(handle: 1, name: "class")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeAttribute",
            fields: ["handle": .int(1), "name": .string("class")]
        ))
    }

    @Test("setProperty encodes op + handle + name + property value")
    func setProperty() {
        let p = Patch.setProperty(handle: 1, name: "value", value: .string("x"))
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setProperty",
            fields: [
                "handle": .int(1),
                "name": .string("value"),
                "value": .property(.string("x")),
            ]
        ))
    }

    @Test("removeProperty encodes op + handle + name")
    func removeProperty() {
        let p = Patch.removeProperty(handle: 1, name: "value")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeProperty",
            fields: ["handle": .int(1), "name": .string("value")]
        ))
    }

    @Test("setStyle encodes op + handle + name + value")
    func setStyle() {
        let p = Patch.setStyle(handle: 1, name: "color", value: "red")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setStyle",
            fields: [
                "handle": .int(1),
                "name": .string("color"),
                "value": .string("red"),
            ]
        ))
    }

    @Test("removeStyle encodes op + handle + name")
    func removeStyle() {
        let p = Patch.removeStyle(handle: 1, name: "color")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeStyle",
            fields: ["handle": .int(1), "name": .string("color")]
        ))
    }

    @Test("setText encodes op + handle + text")
    func setText() {
        let p = Patch.setText(handle: 1, text: "hi")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "setText",
            fields: ["handle": .int(1), "text": .string("hi")]
        ))
    }

    // MARK: - Events

    @Test("addHandler encodes op + handle + event + handlerId")
    func addHandler() {
        let p = Patch.addHandler(handle: 1, event: "click", handlerId: 7)
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "addHandler",
            fields: [
                "handle": .int(1),
                "event": .string("click"),
                "handlerId": .int(7),
            ]
        ))
    }

    @Test("removeHandler encodes op + handle + event")
    func removeHandler() {
        let p = Patch.removeHandler(handle: 1, event: "click")
        #expect(PatchSerializer.encode(p) == PatchPayload(
            op: "removeHandler",
            fields: ["handle": .int(1), "event": .string("click")]
        ))
    }
}
```

- [ ] **Step 2: Run filter, expect red**

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/PatchSerializer.swift

/// Encodes a `Patch` into a `PatchPayload` for transport across the WASM↔JS
/// bridge.
///
/// The op-name strings are part of the wire format: the JS driver dispatches
/// on `payload.op`, so any rename here MUST be coordinated with
/// `js-driver/swiflow-driver.js`. Field names are case-sensitive and match
/// the JS driver's switch arms.
public enum PatchSerializer {
    public static func encode(_ patch: Patch) -> PatchPayload {
        switch patch {
        // MARK: Lifecycle
        case .createElement(let handle, let tag):
            return PatchPayload(op: "createElement", fields: [
                "handle": .int(handle),
                "tag": .string(tag),
            ])
        case .createText(let handle, let text):
            return PatchPayload(op: "createText", fields: [
                "handle": .int(handle),
                "text": .string(text),
            ])
        case .createRawHTML(let handle, let html):
            return PatchPayload(op: "createRawHTML", fields: [
                "handle": .int(handle),
                "html": .string(html),
            ])
        case .destroyNode(let handle):
            return PatchPayload(op: "destroyNode", fields: [
                "handle": .int(handle),
            ])

        // MARK: Tree structure
        case .appendChild(let parent, let child):
            return PatchPayload(op: "appendChild", fields: [
                "parent": .int(parent),
                "child": .int(child),
            ])
        case .insertBefore(let parent, let child, let beforeChild):
            return PatchPayload(op: "insertBefore", fields: [
                "parent": .int(parent),
                "child": .int(child),
                "beforeChild": .int(beforeChild),
            ])
        case .removeChild(let parent, let child):
            return PatchPayload(op: "removeChild", fields: [
                "parent": .int(parent),
                "child": .int(child),
            ])

        // MARK: Mutations
        case .setAttribute(let handle, let name, let value):
            return PatchPayload(op: "setAttribute", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .string(value),
            ])
        case .removeAttribute(let handle, let name):
            return PatchPayload(op: "removeAttribute", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setProperty(let handle, let name, let value):
            return PatchPayload(op: "setProperty", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .property(value),
            ])
        case .removeProperty(let handle, let name):
            return PatchPayload(op: "removeProperty", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setStyle(let handle, let name, let value):
            return PatchPayload(op: "setStyle", fields: [
                "handle": .int(handle),
                "name": .string(name),
                "value": .string(value),
            ])
        case .removeStyle(let handle, let name):
            return PatchPayload(op: "removeStyle", fields: [
                "handle": .int(handle),
                "name": .string(name),
            ])
        case .setText(let handle, let text):
            return PatchPayload(op: "setText", fields: [
                "handle": .int(handle),
                "text": .string(text),
            ])

        // MARK: Events
        case .addHandler(let handle, let event, let handlerId):
            return PatchPayload(op: "addHandler", fields: [
                "handle": .int(handle),
                "event": .string(event),
                "handlerId": .int(handlerId),
            ])
        case .removeHandler(let handle, let event):
            return PatchPayload(op: "removeHandler", fields: [
                "handle": .int(handle),
                "event": .string(event),
            ])
        }
    }
}
```

- [ ] **Step 4: Run all tests, expect 119 pass**

```bash
swift test
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/PatchSerializer.swift Tests/SwiflowTests/PatchSerializerTests.swift
git commit -m "feat: encode every Patch opcode to a tested PatchPayload"
```

---

## Task 4: `PatchPayload` → `JSObject` adapter (WASM-only)

**Files:**
- Create: `Sources/SwiflowWeb/JSAdapter.swift`

Untested in this task: macOS can't import `JavaScriptKit`. The mapping is straightforward. Correctness is verified end-to-end by the example app in Task 8.

- [ ] **Step 1: Write the adapter**

```swift
// Sources/SwiflowWeb/JSAdapter.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Converts a Swift `PatchPayload` into the `JSObject` shape the JS driver
/// expects: `{ op: String, ...named fields }`.
///
/// Field-level mapping rules:
/// - `.int(n)` → JS Number.
/// - `.string(s)` → JS String.
/// - `.property(.string(s))` → JS String.
/// - `.property(.int(n))` → JS Number.
/// - `.property(.double(d))` → JS Number.
/// - `.property(.bool(b))` → JS Boolean.
enum JSAdapter {
    static func toJSValue(_ payload: PatchPayload) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        obj.op = .string(payload.op)
        for (name, field) in payload.fields {
            obj[name] = field.toJSValue()
        }
        return .object(obj)
    }
}

extension PatchPayload.Field {
    func toJSValue() -> JSValue {
        switch self {
        case .int(let n):
            return .number(Double(n))
        case .string(let s):
            return .string(s)
        case .property(let pv):
            switch pv {
            case .string(let s): return .string(s)
            case .int(let n): return .number(Double(n))
            case .double(let d): return .number(d)
            case .bool(let b): return .boolean(b)
            }
        }
    }
}

#endif
```

- [ ] **Step 2: Verify the macOS build (empty module compiles)**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiflowWeb/JSAdapter.swift
git commit -m "feat: PatchPayload to JSObject adapter (WASM-only)"
```

---

## Task 5: `Renderer` class + `Swiflow.render` / `Swiflow.rerender`

**Files:**
- Create: `Sources/SwiflowWeb/Renderer.swift`
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`

- [ ] **Step 1: Write the Renderer**

```swift
// Sources/SwiflowWeb/Renderer.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Owns Swiflow's per-application render state in a WASM/browser environment.
///
/// A single Renderer is created by `Swiflow.render(_:into:)` and looked up by
/// `Swiflow.rerender()` through module-private ambient storage. Multiple
/// roots are out of scope for Phase 2a.
final class Renderer {
    let viewProducer: () -> VNode
    let selector: String
    let handles: HandleAllocator
    let handlers: HandlerRegistry
    var mountTree: MountNode?

    init(viewProducer: @escaping () -> VNode, selector: String) {
        self.viewProducer = viewProducer
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil
    }

    /// Runs the producer, diffs against the current mount tree, encodes
    /// patches into a JSArray, hands the array to `window.swiflow.applyPatches`,
    /// and (on first call) tells the driver to attach the root node at
    /// `selector`.
    func renderOnce() {
        let next = viewProducer()
        let result = diff(
            mounted: mountTree,
            next: next,
            handles: handles,
            handlers: handlers
        )

        // Encode patches to a JSArray.
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in result.patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }

        // Ship the batch across the bridge in one call.
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(result.newMountTree.handle)),
                JSValue.string(selector)
            )
        }
    }
}

#endif
```

- [ ] **Step 2: Replace `SwiflowWeb.swift` with the ambient renderer wiring**

```swift
// Sources/SwiflowWeb/SwiflowWeb.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
@_exported import Swiflow

// Module-private ambient renderer — single root per app in Phase 2a.
nonisolated(unsafe) private var ambientRenderer: Renderer?

public extension Swiflow {
    /// Mounts `viewProducer()` into the DOM node matched by `selector`.
    ///
    /// Subsequent calls to `Swiflow.rerender()` will re-evaluate the producer,
    /// diff against the committed tree, and ship the patches in one bridge
    /// call. Phase 2a supports a single root per app; calling `render` twice
    /// replaces the prior renderer (no cleanup — out of scope until Phase 3
    /// adds component lifecycle).
    static func render(_ viewProducer: @escaping () -> VNode, into selector: String) {
        let renderer = Renderer(viewProducer: viewProducer, selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }

    /// Re-evaluates the registered view producer and applies any resulting
    /// patches. A no-op if `render(_:into:)` has not been called.
    static func rerender() {
        ambientRenderer?.renderOnce()
    }

    /// The handler registry the active Renderer dispatches through.
    ///
    /// Use this inside `view()` to register `.on(...)` closures:
    ///
    /// ```swift
    /// button("Click", .on("click", Swiflow.handlers.register { _ in ... }))
    /// ```
    ///
    /// **Critical:** user closures MUST be registered via this property
    /// (not a private `HandlerRegistry` the user constructs themselves).
    /// `DispatcherBridge` routes every JS event to the Renderer's registry;
    /// handlers registered elsewhere will silently no-op when their event
    /// fires, AND will leak their closures because `diffHandlers`'s
    /// `handlers.remove(id:)` only affects the Renderer's registry.
    ///
    /// `Swiflow.render(_:into:)` must have been called before this property
    /// is accessed. Inside `view()` this is always safe — `render` constructs
    /// the Renderer and only THEN calls the producer.
    static var handlers: HandlerRegistry {
        guard let renderer = ambientRenderer else {
            fatalError("Swiflow.handlers accessed before Swiflow.render(_:into:) was called")
        }
        return renderer.handlers
    }
}

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
```

- [ ] **Step 3: Build verification**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowWeb/Renderer.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat: add Renderer class with Swiflow.render and Swiflow.rerender"
```

---

## Task 6: `DispatcherBridge` — register the single Swift dispatcher

**Files:**
- Create: `Sources/SwiflowWeb/DispatcherBridge.swift`

- [ ] **Step 1: Write the bridge**

```swift
// Sources/SwiflowWeb/DispatcherBridge.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Registers a single Swift function as `window.__swiflowDispatch` so the JS
/// driver can route DOM events back to Swift handlers.
///
/// The registered closure expects two arguments from JS:
/// 1. `handlerId: Number` — the integer ID stored in `HandlerRegistry`.
/// 2. `eventPayload: Object` — `{ type: String, targetValue: String? }`.
enum DispatcherBridge {
    /// Strong reference holding the `JSClosure` so it isn't deallocated.
    /// JSClosure-with-Swift-callback documentation: the closure must outlive
    /// every invocation, so we stash it module-private.
    nonisolated(unsafe) private static var installed: JSClosure?

    /// Idempotent: subsequent calls are no-ops. Phase 2a creates exactly one
    /// registry per app; this matches.
    static func installIfNeeded(registry: HandlerRegistry) {
        guard installed == nil else { return }

        let closure = JSClosure { args -> JSValue in
            // Defensive: silently no-op on malformed payloads. The driver
            // (Task 7) is the only caller and always provides both args.
            guard
                args.count >= 2,
                let handlerId = args[0].number.map({ Int($0) }),
                let payload = args[1].object
            else {
                return .undefined
            }

            let type = payload.type.string ?? ""
            let targetValue = payload.targetValue.string

            registry.dispatch(
                id: handlerId,
                event: Event(type: type, targetValue: targetValue)
            )

            // Returning a JSValue from the closure is required by JSClosure's
            // signature; the JS driver doesn't read it. Future phases may
            // surface preventDefault / stopPropagation here.
            return .undefined
        }

        // JavaScriptKit 0.53+ deprecated `.function(closure)`; use `.object`.
        // The JSClosure is implicitly convertible to a JSObject for this
        // purpose since it's no longer a JSFunction subclass.
        JSObject.global.__swiflowDispatch = .object(closure)
        installed = closure
    }
}

#endif
```

- [ ] **Step 2: Build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiflowWeb/DispatcherBridge.swift
git commit -m "feat: register __swiflowDispatch as the single JS-to-Swift entry"
```

---

## Task 7: The JS driver — `js-driver/swiflow-driver.js`

**Files:**
- Create: `js-driver/swiflow-driver.js`
- Create: `js-driver/README.md`

Vanilla JS, no bundler, no build step. Implements `window.swiflow.{registerDispatcher, applyPatches, mount}` and the per-listener wrapper that calls `window.__swiflowDispatch`.

- [ ] **Step 1: Write the driver to `js-driver/swiflow-driver.js`**

The full driver source — copy this verbatim. It includes the documented `rawHTML` escape-hatch path which assigns to `innerHTML` per the Phase 1 spec § 17 design. Search-grep `rawHTML(` to enumerate every audit site on the Swift side; the JS side has exactly one such assignment (in the `createRawHTML` arm).

```javascript
// js-driver/swiflow-driver.js
//
// Swiflow JS driver — vanilla JavaScript, no build step.
//
// The driver owns the canonical Map<int, Node> that the Swift side references
// by integer handle. It exposes three operations to Swift through the
// `window.swiflow` global:
//
//   - applyPatches(patches): a JSArray of patch objects; the driver iterates
//                            and executes each in arrival order.
//   - mount(rootHandle, selector): attach a previously-created node into
//                                  the DOM under querySelector(selector).
//   - registerDispatcher(fn): legacy hook reserved for future use.
//
// Per-listener wrappers call window.__swiflowDispatch(handlerId, event)
// when DOM events fire.

(function () {
  "use strict";

  /** Handle → DOM node. */
  const nodes = new Map();

  /** `${handle}:${event}` → bound listener function (for removal). */
  const listeners = new Map();

  /**
   * Serialize a DOM event into the minimal shape Swift expects.
   * Phase 1's Event has type + optional targetValue; everything else is
   * deferred to Phase 3.
   */
  function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    return { type: event.type, targetValue: targetValue };
  }

  /**
   * Apply a single patch. The opcode is `p.op`; field names match the
   * Swift-side `PatchSerializer.encode(...)` contract.
   */
  function applyOne(p) {
    switch (p.op) {
      // Lifecycle
      case "createElement":
        nodes.set(p.handle, document.createElement(p.tag));
        return;
      case "createText":
        nodes.set(p.handle, document.createTextNode(p.text));
        return;
      case "createRawHTML": {
        // Use a template element so the raw HTML is parsed as document
        // content. The first child of the template becomes the node;
        // wrap-around to a `<span>` if the markup produced multiple nodes
        // or none, so the handle always maps to exactly one node.
        //
        // This is the ONE intentional innerHTML assignment in the driver,
        // gated on the Swift side by VNode.rawHTML(...) (an audit-grep
        // target). XSS responsibility is documented to belong to the
        // caller of rawHTML().
        const tpl = document.createElement("template");
        tpl.innerHTML = p.html;
        let node;
        if (tpl.content.childNodes.length === 1) {
          node = tpl.content.firstChild;
        } else {
          node = document.createElement("span");
          while (tpl.content.firstChild) {
            node.appendChild(tpl.content.firstChild);
          }
        }
        nodes.set(p.handle, node);
        return;
      }
      case "destroyNode": {
        // Detach any listeners we tracked for this handle so JS GC can free
        // the wrapper functions.
        for (const key of Array.from(listeners.keys())) {
          if (key.startsWith(p.handle + ":")) {
            listeners.delete(key);
          }
        }
        nodes.delete(p.handle);
        return;
      }

      // Tree structure
      case "appendChild":
        nodes.get(p.parent).appendChild(nodes.get(p.child));
        return;
      case "insertBefore":
        nodes.get(p.parent).insertBefore(
          nodes.get(p.child),
          nodes.get(p.beforeChild)
        );
        return;
      case "removeChild":
        nodes.get(p.parent).removeChild(nodes.get(p.child));
        return;

      // Mutations
      case "setAttribute":
        nodes.get(p.handle).setAttribute(p.name, p.value);
        return;
      case "removeAttribute":
        nodes.get(p.handle).removeAttribute(p.name);
        return;
      case "setProperty":
        // value is already coerced to the right JS primitive by the Swift
        // adapter (string / number / boolean).
        nodes.get(p.handle)[p.name] = p.value;
        return;
      case "removeProperty":
        delete nodes.get(p.handle)[p.name];
        return;
      case "setStyle":
        nodes.get(p.handle).style[p.name] = p.value;
        return;
      case "removeStyle":
        nodes.get(p.handle).style[p.name] = "";
        return;
      case "setText": {
        // Both Text nodes and Element nodes expose textContent; Text nodes
        // also expose .data. Prefer .data when defined.
        const node = nodes.get(p.handle);
        if (node.data !== undefined) {
          node.data = p.text;
        } else {
          node.textContent = p.text;
        }
        return;
      }

      // Events
      case "addHandler": {
        const handlerId = p.handlerId;
        const fn = function (evt) {
          window.__swiflowDispatch(handlerId, serializeEvent(evt));
        };
        nodes.get(p.handle).addEventListener(p.event, fn);
        listeners.set(p.handle + ":" + p.event, fn);
        return;
      }
      case "removeHandler": {
        const key = p.handle + ":" + p.event;
        const fn = listeners.get(key);
        if (fn !== undefined) {
          nodes.get(p.handle).removeEventListener(p.event, fn);
          listeners.delete(key);
        }
        return;
      }

      default:
        console.error("swiflow-driver: unknown opcode", p.op, p);
        return;
    }
  }

  window.swiflow = {
    /** Called by Swift each frame with a JSArray of patch objects. */
    applyPatches: function (patches) {
      for (let i = 0; i < patches.length; i++) {
        applyOne(patches[i]);
      }
    },

    /** Called by Swift exactly once to attach the root node. */
    mount: function (rootHandle, selector) {
      const target = document.querySelector(selector);
      if (target === null) {
        throw new Error(
          "swiflow-driver: mount target '" + selector + "' not found"
        );
      }
      target.appendChild(nodes.get(rootHandle));
    },

    /**
     * Legacy hook reserved for future use. The Swift side currently registers
     * its dispatcher directly as `window.__swiflowDispatch` (see Task 6); a
     * future binary-buffer wire format may re-introduce a registration step.
     */
    registerDispatcher: function (_fn) {},
  };
})();
```

- [ ] **Step 2: Write `js-driver/README.md`**

```markdown
# js-driver

The Swiflow JavaScript driver. Vanilla JS, no build step.

## Contract

The driver exposes three operations under `window.swiflow`:

- `applyPatches(patches)` — accepts a `JSArray<JSObject>` produced by the
  Swift-side `PatchSerializer.encode(...) → JSAdapter.toJSValue(...)`
  pipeline. Iterates and executes each patch in arrival order against the
  driver-owned `Map<int, Node>`.
- `mount(rootHandle, selector)` — attaches the node identified by `rootHandle`
  into the DOM at `document.querySelector(selector)`. Called once per app
  during `Swiflow.render(_:into:)`.
- `registerDispatcher(fn)` — reserved, currently a no-op. The Swift dispatcher
  is published as `window.__swiflowDispatch` via JavaScriptKit's `JSClosure`.

## Wire format

Each patch is a plain JS object with an `op` string discriminator. Field names
are case-sensitive and must match the Swift-side `PatchSerializer.encode`
output exactly. See `Sources/Swiflow/PatchSerializer.swift` for the canonical
list of opcodes (16 total) and per-opcode fields.

## Event flow

When a DOM event fires on a node with a registered handler:

1. The driver's per-listener wrapper calls
   `window.__swiflowDispatch(handlerId, serializeEvent(event))`.
2. Swift's `DispatcherBridge` looks up `handlerId` in `HandlerRegistry` and
   invokes the closure.
3. If the closure mutates state and calls `Swiflow.rerender()`, a new diff
   pass produces a fresh `JSArray<JSObject>` and a single `applyPatches`
   call applies the batch.

## Security: the rawHTML escape hatch

The `createRawHTML` opcode is the only path in the driver that uses
`innerHTML`. The Swift side gates it via `VNode.rawHTML(_:)` — a loudly-named
function so `git grep "rawHTML("` enumerates every site where unescaped HTML
enters the DOM. XSS responsibility lies with the caller; the framework
guarantees no other path produces unescaped HTML.

## Authoring

Edit the file directly. Do not introduce a build step (TypeScript, esbuild,
etc.) in Phase 2; the file is small enough that the cost outweighs the
benefit. If the file grows past ~400 lines, consider splitting by concern
(applyOne could move into its own module) before considering a build.

## Distribution

In Phase 2a the driver is loaded by hand into `examples/HelloWorld/public/`.
Phase 2b's `swiflow init` will embed it as a Swift `String` resource in the
CLI binary and write it to each scaffolded project's `public/` directory.
```

- [ ] **Step 3: Commit**

```bash
git add js-driver/swiflow-driver.js js-driver/README.md
git commit -m "feat: vanilla JS driver implementing all 16 patch opcodes"
```

---

## Task 8: `examples/HelloWorld/` — hand-crafted demo + verification

**Files:**
- Create: `examples/HelloWorld/Package.swift`
- Create: `examples/HelloWorld/Sources/App/App.swift`
- Create: `examples/HelloWorld/public/index.html`
- Create: `examples/HelloWorld/public/swiflow-driver.js` (copied from `js-driver/`)
- Create: `examples/HelloWorld/README.md`
- Modify: `README.md` (top-level — update Phase 2a status)

- [ ] **Step 1: Write `examples/HelloWorld/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelloWorld",
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
```

- [ ] **Step 2: Write `examples/HelloWorld/Sources/App/App.swift`**

```swift
// examples/HelloWorld/Sources/App/App.swift
import SwiflowWeb

// Mutable counter shared with the click handler. Phase 3 will replace this
// with `@State`; for Phase 2a the spec's Hello World uses an explicit
// `Swiflow.rerender()` call so the bridge path is exercised end-to-end.
var count = 0

func view() -> VNode {
    div(.class("container")) {
        h1("Hello, Swiflow!")
        p("Count: \(count)")
        button(
            "Increment",
            .on("click", Swiflow.handlers.register { _ in
                count += 1
                Swiflow.rerender()
            })
        )
    }
}

@main
struct App {
    static func main() {
        Swiflow.render(view, into: "#app")
    }
}
```

- [ ] **Step 3: Write `examples/HelloWorld/public/index.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Swiflow Hello World</title>
    <style>
      body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; }
      .container { max-width: 480px; }
      button { padding: 0.4rem 0.9rem; font-size: 1rem; cursor: pointer; }
    </style>
  </head>
  <body>
    <div id="app"></div>

    <!-- Load the driver BEFORE the WASM bootstrap. -->
    <script src="swiflow-driver.js"></script>

    <!--
      JavaScriptKit's WASM bootstrap. The CDN URLs are pinned to specific
      versions; Phase 2b's `swiflow init` will write a self-hosted
      bootstrap.js so users aren't dependent on jsdelivr.
    -->
    <script type="module">
      import { WASI } from "https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.3.0/dist/index.js";
      import { SwiftRuntime } from "https://cdn.jsdelivr.net/npm/javascript-kit-swift@0.21.0/Runtime/index.mjs";

      const wasi = new WASI([], [], []);
      const swift = new SwiftRuntime();

      const module = await WebAssembly.compileStreaming(fetch("App.wasm"));
      const instance = await WebAssembly.instantiate(module, {
        wasi_snapshot_preview1: wasi.wasiImport,
        javascript_kit: swift.importObjects(),
      });
      swift.setInstance(instance);
      wasi.start(instance);
    </script>
  </body>
</html>
```

- [ ] **Step 4: Copy the driver into the example's `public/`**

```bash
cp ./js-driver/swiflow-driver.js \
   ./examples/HelloWorld/public/swiflow-driver.js
```

- [ ] **Step 5: Write `examples/HelloWorld/README.md`**

```markdown
# Swiflow Hello World

A hand-crafted demo proving the Phase 2a renderer + JS driver round-trip
works in a real browser. **No CLI required** — Phase 2b's `swiflow init`
will automate this.

## Prerequisites

- Swift 6.0+ with the WebAssembly SDK installed:
  ```bash
  swift sdk install <swift.org WASM SDK URL for your Swift version>
  ```
  See <https://swift.org/install> for the current SDK URL.
- Any static HTTP server: Python's `python3 -m http.server` works.

## Build

```bash
cd examples/HelloWorld
swift build --swift-sdk wasm32-unknown-wasi -c release
cp .build/wasm32-unknown-wasi/release/App.wasm public/App.wasm
```

## Serve

```bash
cd public
python3 -m http.server 3000
```

## Verify

Open <http://localhost:3000> in a browser. You should see:

- A heading: **Hello, Swiflow!**
- A paragraph: **Count: 0**
- A button: **Increment**

Click the button. The count should increment with each click.

If it doesn't:

- Open DevTools console. Errors from `swiflow-driver: unknown opcode` mean
  a Swift-side `PatchSerializer.encode` mismatch with the driver's `switch`.
- Errors from `swiflow-driver: mount target '#app' not found` mean the
  driver script loaded BEFORE the `<div id="app">` exists; check the script
  ordering in `index.html`.
- Errors mentioning `__swiflowDispatch is not a function` mean the WASM
  module hasn't initialized yet (or threw during startup). Look further up
  the console for the actual exception.

## What's next

Phase 2b will replace these manual steps with `swiflow init demo` +
`swiflow build`. Phase 2c will add `swiflow dev` with live reload.
```

- [ ] **Step 6: Update the top-level `README.md`**

In `./README.md`, replace the **Status** paragraph with:

```markdown
**Status:** Phase 2a in progress. Phase 1 (the VDOM "Brain") is complete and
the renderer + JS driver now exist; `examples/HelloWorld/` proves the
end-to-end round-trip in a browser. CLI scaffolding (`swiflow init`, `build`,
`dev`) is the Phase 2b/2c scope.
```

- [ ] **Step 7: Verify the macOS build is unchanged**

```bash
cd .
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```
Expected: 119 tests still pass. The example project is NOT built by the
parent package's `swift build`.

- [ ] **Step 8: (Optional, requires WASM SDK) Manual end-to-end verification**

If the WASM SDK is installed, follow the example README. Confirm:
- The count increments visually on each click.
- The DevTools console has no errors.
- DOM inspection shows the `<p>` text updating without recreating the
  surrounding `<div>` — verifies the diff is patching, not re-mounting.

If the WASM SDK is NOT installed, skip this step. The hand-off boundary is
that the next developer MUST run this verification before declaring Phase 2a
complete.

- [ ] **Step 9: Commit**

```bash
git add examples/HelloWorld README.md
git commit -m "feat: hand-crafted Hello World example proving renderer+driver round-trip"
```
