# Swiflow Regions — Swift Core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Swift, JavaScriptKit-free, Foundation-free core of Swiflow Regions — the typed `region(...)` DSL that lowers to an `<sf-region>` element VNode, plus the props-encode and typed-event-decode seams — so the host↔guest contract is locked and fully unit-tested under `swift test` before any browser runtime exists.

**Architecture:** Additions live in core `Sources/Swiflow/`. Props (`Encodable`) are encoded to a JSON string at VNode-build time via the existing foundation-free `JSONValueEncoder` (promoted into core) and carried as the `sfProps` DOM property. Typed events flow back through the existing `EventHandler`/`HandlerRegistry` path: a new `EventInfo.detail: String?` carries the raw JSON payload, and a typed `.onEvent` modifier decodes it into the guest's `RegionEvent` via an **injectable `RegionEventDecoding` seam** (the concrete decoder is installed by the browser runtime in a later plan; tests install a stub). The typed surface is a `RegionView<Guest>` wrapper, made usable in `@Component` bodies via an additive `ChildrenBuilder.buildExpression` overload.

**Tech Stack:** Swift 6, swift-testing (`import Testing`), the `@resultBuilder ChildrenBuilder`, the `JSONValueEncoder` from SwiflowStore (moved to core in Task 1). No JavaScriptKit, no Foundation in any file this plan touches.

---

## File Structure

**Created:**
- `Sources/Swiflow/Regions/RegionGuest.swift` — `RegionGuest`, `RegionEvent`, `RegionError`.
- `Sources/Swiflow/Regions/RegionDecoder.swift` — the `RegionEventDecoding` seam + ambient `RegionDecoder.current`.
- `Sources/Swiflow/Regions/RegionView.swift` — `RegionModifiable`, `RegionView<G>`, the typed `region(_:key:props:)` factory, sizing + `.onEvent`/`.onError`.
- `Sources/Swiflow/Regions/RegionInline.swift` — `AnyRegionView`, the inline `region(source:key:props:)` factory.
- `Sources/Swiflow/Regions/RegionBuilder.swift` — the `ChildrenBuilder.buildExpression` overloads.
- `Tests/SwiflowTests/Regions/*` — one test file per task.

**Modified:**
- `Sources/Swiflow/VNode.swift` — add `EventInfo.detail: String?`.
- `Sources/Swiflow/JSON/` (new dir) — the moved `JSONValue` + `JSONValueEncoder`.
- `Sources/SwiflowStore/*` — drop the moved files; reference the types via `import Swiflow`.

---

## Task 1: Promote the foundation-free JSON encoder into core

**Files:**
- Move: `Sources/SwiflowStore/JSONValueEncoder.swift` (and any `JSONValue` definition file) → `Sources/Swiflow/JSON/`
- Move: the encoder's tests → `Tests/SwiflowTests/JSON/`
- Modify: `Sources/SwiflowStore/PersistentStore.swift` (imports resolve via `import Swiflow`)

- [ ] **Step 1: Locate the files defining `JSONValue` and `JSONValueEncoder`**

Run: `grep -rln "struct JSONValueEncoder\|enum JSONValue\|struct JSONValue" Sources/SwiflowStore`
Expected: lists `Sources/SwiflowStore/JSONValueEncoder.swift` and possibly a separate `JSONValue` file.

- [ ] **Step 2: Confirm they are Foundation-free (must be, to live in core)**

Run: `grep -rn "import Foundation\|import JavaScriptKit" $(grep -rln "JSONValueEncoder\|enum JSONValue" Sources/SwiflowStore)`
Expected: no output. If any import appears, STOP — the move is unsafe; report back.

- [ ] **Step 3: Move the source file(s) into core**

```bash
mkdir -p Sources/Swiflow/JSON
git mv Sources/SwiflowStore/JSONValueEncoder.swift Sources/Swiflow/JSON/JSONValueEncoder.swift
# If a separate JSONValue file was found in Step 1, move it too:
# git mv Sources/SwiflowStore/JSONValue.swift Sources/Swiflow/JSON/JSONValue.swift
```

- [ ] **Step 4: Move the encoder tests into the core test target and fix the import**

```bash
mkdir -p Tests/SwiflowTests/JSON
# Use the path(s) from: grep -rln "JSONValueEncoder" Tests/SwiflowStoreTests
git mv Tests/SwiflowStoreTests/JSONValueEncoderTests.swift Tests/SwiflowTests/JSON/JSONValueEncoderTests.swift
```

In the moved test file, change `@testable import SwiflowStore` to `@testable import Swiflow`.

- [ ] **Step 5: Build the whole package**

Run: `swift build`
Expected: success. `SwiflowStore`'s references to `JSONValueEncoder`/`JSONValue` resolve through its existing `import Swiflow`. If a reference fails to resolve, the type was not `public` — add `public` to the type and its members and rebuild.

- [ ] **Step 6: Run the moved encoder tests and the Store tests**

Run: `swift test --filter 'SwiflowTests.JSONValueEncoder' && swift test --filter 'SwiflowStoreTests'`
Expected: PASS (encoder behaves identically; Store still encodes via the now-core type).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(core): promote foundation-free JSONValueEncoder into Swiflow core"
```

---

## Task 2: Add `EventInfo.detail`

**Files:**
- Modify: `Sources/Swiflow/VNode.swift` (the `EventInfo` struct, ~158-223)
- Test: `Tests/SwiflowTests/Regions/EventInfoDetailTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/EventInfoDetailTests.swift
import Testing
@testable import Swiflow

@Suite("EventInfo.detail")
struct EventInfoDetailTests {
    @Test("detail defaults to nil and is omitted from existing call sites")
    func detailDefaultsNil() {
        let e = EventInfo(type: "click")
        #expect(e.detail == nil)
    }

    @Test("detail round-trips through the initializer and participates in equality")
    func detailRoundTrips() {
        let a = EventInfo(type: "sf:event", detail: #"{"kind":"select","id":7}"#)
        let b = EventInfo(type: "sf:event", detail: #"{"kind":"select","id":7}"#)
        let c = EventInfo(type: "sf:event", detail: nil)
        #expect(a.detail == #"{"kind":"select","id":7}"#)
        #expect(a == b)
        #expect(a != c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.EventInfoDetailTests'`
Expected: FAIL — "extra argument 'detail' in call" / `value of type 'EventInfo' has no member 'detail'`.

- [ ] **Step 3: Add the property and initializer parameter**

In `Sources/Swiflow/VNode.swift`, inside `struct EventInfo`, add after the `metaKey: Bool` declaration:

```swift
    /// Raw JSON payload for custom events (e.g. a region's `sf:event`/`sf:error`).
    /// `nil` for ordinary DOM events. Carried as a `String` (not a `JSObject`) so
    /// `EventInfo` stays `Sendable` and core `Swiflow` stays free of JavaScriptKit;
    /// typed decoding happens in the Region DSL via `RegionEventDecoding`.
    public let detail: String?
```

Add `detail: String? = nil,` to the initializer parameter list (after `metaKey: Bool = false`), and `self.detail = detail` in the initializer body.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.EventInfoDetailTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/VNode.swift Tests/SwiflowTests/Regions/EventInfoDetailTests.swift
git commit -m "feat(core): add EventInfo.detail for custom-event payloads"
```

---

## Task 3: Region contract types — `RegionEvent`, `RegionGuest`, `RegionError`

**Files:**
- Create: `Sources/Swiflow/Regions/RegionGuest.swift`
- Test: `Tests/SwiflowTests/Regions/RegionContractTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionContractTests.swift
import Testing
@testable import Swiflow

private struct DemoProps: Encodable { var count: Int }
private struct DemoEvent: RegionEvent { let kind: String; let id: Int }
private enum DemoGuest: RegionGuest {
    typealias Props = DemoProps
    typealias Event = DemoEvent
    static let source = "regions/demo.wasm"
}

@Suite("Region contract")
struct RegionContractTests {
    @Test("A guest binds its source, props, and event types")
    func guestBindsTypes() {
        #expect(DemoGuest.source == "regions/demo.wasm")
        // Associated types are usable:
        let _: DemoGuest.Props = DemoProps(count: 1)
        let _: DemoGuest.Event.Type = DemoEvent.self
    }

    @Test("RegionError decodes from its wire shape")
    func regionErrorIsDecodable() {
        let _: RegionError.Type = RegionError.self
        let err = RegionError(code: "load-failed", message: "404")
        #expect(err.code == "load-failed")
        #expect(err.message == "404")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionContractTests'`
Expected: FAIL — `cannot find type 'RegionEvent'/'RegionGuest'/'RegionError' in scope`.

- [ ] **Step 3: Create the contract types**

```swift
// Sources/Swiflow/Regions/RegionGuest.swift

/// A decodable event a region guest emits back to the host. Conformers are
/// plain `Decodable` value types; the framework decodes the `sf:event`
/// payload into this type via `RegionEventDecoding`.
public protocol RegionEvent: Decodable {}

/// The contract for one external wasm guest: its served `source`, the `Props`
/// the host sends in, and the `Event` it emits out. Declaring a guest type
/// once lets every `.onEvent` handler *infer* its event type — no annotation.
public protocol RegionGuest {
    associatedtype Props: Encodable
    associatedtype Event: RegionEvent
    /// URL/path of the guest wasm asset (e.g. `"regions/scene.wasm"`).
    static var source: String { get }
}

/// The payload of a region's `sf:error` event.
public struct RegionError: Decodable, Error, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionContractTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionGuest.swift Tests/SwiflowTests/Regions/RegionContractTests.swift
git commit -m "feat(core): add RegionGuest/RegionEvent/RegionError contract types"
```

---

## Task 4: The decode seam — `RegionEventDecoding` + `RegionDecoder.current`

**Files:**
- Create: `Sources/Swiflow/Regions/RegionDecoder.swift`
- Test: `Tests/SwiflowTests/Regions/RegionDecoderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionDecoderTests.swift
import Testing
@testable import Swiflow

private struct Ping: Decodable, Equatable { let n: Int }

/// A stub decoder that records what it was asked to decode and returns a fixed value.
private struct StubDecoding: RegionEventDecoding {
    let result: Any
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let typed = result as? E else { throw RegionError(code: "stub", message: json) }
        return typed
    }
}

@MainActor
@Suite("RegionDecoder seam")
struct RegionDecoderTests {
    @Test("current is nil by default and installs/uninstalls")
    func installs() {
        #expect(RegionDecoder.current == nil)
        RegionDecoder.current = StubDecoding(result: Ping(n: 1))
        defer { RegionDecoder.current = nil }
        let decoded = try? RegionDecoder.current?.decode(Ping.self, from: "{}")
        #expect(decoded == Ping(n: 1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionDecoderTests'`
Expected: FAIL — `cannot find 'RegionDecoder'/'RegionEventDecoding' in scope`.

- [ ] **Step 3: Create the seam**

```swift
// Sources/Swiflow/Regions/RegionDecoder.swift

/// Decodes a region event/error from its raw JSON `String` into a `Decodable`
/// value type. Core defines only this seam; the browser runtime installs a
/// concrete implementation (e.g. one backed by JavaScriptKit's `JSValueDecoder`),
/// and tests install a stub. This keeps core `Swiflow` free of JavaScriptKit
/// and Foundation while still expressing the typed-event contract.
public protocol RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E
}

/// Ambient install point for the active `RegionEventDecoding`. Set once by the
/// runtime at startup. `MainActor`-isolated because region handlers run on the
/// main actor.
@MainActor
public enum RegionDecoder {
    public static var current: (any RegionEventDecoding)?
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionDecoderTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionDecoder.swift Tests/SwiflowTests/Regions/RegionDecoderTests.swift
git commit -m "feat(core): add injectable RegionEventDecoding seam"
```

---

## Task 5: `RegionView<G>` + the typed `region(_:key:props:)` factory (lowering)

**Files:**
- Create: `Sources/Swiflow/Regions/RegionView.swift`
- Test: `Tests/SwiflowTests/Regions/RegionLoweringTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionLoweringTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int; var hue: Double }
private struct SceneEvent: RegionEvent { let kind: String; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps
    typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

@MainActor
@Suite("Region lowering")
struct RegionLoweringTests {
    @Test("region(_:key:props:) lowers to an <sf-region> element with source attr + encoded props")
    func lowersToElement() {
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 3, hue: 0.5))
        guard case .element(let data) = view.asVNode() else {
            Issue.record("expected .element"); return
        }
        #expect(data.tag == "sf-region")
        #expect(data.key == "hero")
        #expect(data.attributes["data-source"] == "regions/scene.wasm")
        // Props are encoded to a JSON string property the diff can compare:
        guard case .string(let json)? = data.properties["sfProps"] else {
            Issue.record("expected sfProps string property"); return
        }
        #expect(json.contains("\"count\":3"))
        #expect(json.contains("\"hue\":0.5"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionLoweringTests'`
Expected: FAIL — `cannot find 'region'/'RegionView' in scope`.

- [ ] **Step 3: Create `RegionView` and the factory**

```swift
// Sources/Swiflow/Regions/RegionView.swift

/// Shared building state + sizing modifiers for the typed and inline region
/// faces. Conformers expose a mutable `ElementData` and rebuild from it.
public protocol RegionModifiable {
    var data: ElementData { get set }
    init(data: ElementData)
}

public extension RegionModifiable {
    /// Fill the parent slot (the default sizing when none is given).
    func fill() -> Self {
        var d = data; d.style["width"] = "100%"; d.style["height"] = "100%"
        return Self(data: d)
    }
    /// Fixed CSS pixel size.
    func frame(width: Int, height: Int) -> Self {
        var d = data; d.style["width"] = "\(width)px"; d.style["height"] = "\(height)px"
        return Self(data: d)
    }
    /// Self-sufficient aspect ratio: fills available width, height derives.
    /// Two ints, not `16/9` — a bare ratio would be Swift integer division.
    func aspectRatio(_ w: Int, _ h: Int) -> Self {
        var d = data; d.style["aspect-ratio"] = "\(w) / \(h)"; d.style["width"] = "100%"
        return Self(data: d)
    }
    func asVNode() -> VNode { .element(data) }
}

/// The typed face of a region, parameterized by its guest. Carries `G.Event`
/// so `.onEvent`'s closure parameter is inferred with no annotation.
public struct RegionView<G: RegionGuest>: RegionModifiable {
    public var data: ElementData
    public init(data: ElementData) { self.data = data }
}

/// Build a region for guest `G`. Props are encoded to a JSON string at build
/// time (so the diff compares them as one opaque value) and carried as the
/// `sfProps` property; the guest source rides as the `data-source` attribute.
@MainActor
public func region<G: RegionGuest>(
    _ guest: G.Type,
    key: String,
    props: G.Props
) -> RegionView<G> {
    let json = (try? JSONValueEncoder().encode(props).jsonString) ?? "null"
    let data = ElementData(
        tag: "sf-region",
        key: key,
        attributes: ["data-source": G.source],
        properties: ["sfProps": .string(json)]
    )
    return RegionView<G>(data: data)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionLoweringTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionView.swift Tests/SwiflowTests/Regions/RegionLoweringTests.swift
git commit -m "feat(core): add RegionView<G> and typed region(_:key:props:) factory"
```

---

## Task 6: Make `RegionView` usable in a `@Component` body

**Files:**
- Create: `Sources/Swiflow/Regions/RegionBuilder.swift`
- Test: `Tests/SwiflowTests/Regions/RegionBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionBuilderTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

@MainActor
@Suite("Region builder integration")
struct RegionBuilderTests {
    @Test("a RegionView can sit inside a div { } body and lowers to a child element")
    func regionInBody() {
        let tree = div {
            region(G.self, key: "k", props: P(x: 1))
        }
        guard case .element(let outer) = tree,
              case .element(let child)? = outer.children.first else {
            Issue.record("expected div with one element child"); return
        }
        #expect(child.tag == "sf-region")
        #expect(child.key == "k")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionBuilderTests'`
Expected: FAIL — the `region(...)` expression in the builder doesn't type-check (`cannot convert RegionView<G> to [VNode]`).

- [ ] **Step 3: Add the builder overload**

```swift
// Sources/Swiflow/Regions/RegionBuilder.swift

public extension ChildrenBuilder {
    /// Lift a typed region into the children list.
    static func buildExpression<G: RegionGuest>(_ expression: RegionView<G>) -> [VNode] {
        [expression.asVNode()]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionBuilderTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionBuilder.swift Tests/SwiflowTests/Regions/RegionBuilderTests.swift
git commit -m "feat(core): accept RegionView in ChildrenBuilder bodies"
```

---

## Task 7: Sizing modifiers on `RegionView`

**Files:**
- Test: `Tests/SwiflowTests/Regions/RegionSizingTests.swift`
- (No source change — sizing comes from `RegionModifiable` added in Task 5; this task proves it on `RegionView`.)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionSizingTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

@MainActor
@Suite("Region sizing")
struct RegionSizingTests {
    private func style(_ v: RegionView<G>) -> [String: String] {
        guard case .element(let d) = v.asVNode() else { return [:] }
        return d.style
    }

    @Test(".fill sets width/height 100%")
    func fill() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).fill())
        #expect(s["width"] == "100%")
        #expect(s["height"] == "100%")
    }

    @Test(".frame sets fixed px")
    func frame() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).frame(width: 640, height: 480))
        #expect(s["width"] == "640px")
        #expect(s["height"] == "480px")
    }

    @Test(".aspectRatio is self-sufficient: aspect-ratio + width 100%")
    func aspect() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).aspectRatio(16, 9))
        #expect(s["aspect-ratio"] == "16 / 9")
        #expect(s["width"] == "100%")
    }
}
```

- [ ] **Step 2: Run test to verify it passes (sizing already implemented in Task 5)**

Run: `swift test --filter 'SwiflowTests.RegionSizingTests'`
Expected: PASS. (If FAIL, the `RegionModifiable` extension from Task 5 is missing a case — fix it there.)

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/Regions/RegionSizingTests.swift
git commit -m "test(core): cover RegionView sizing modifiers"
```

---

## Task 8: Typed `.onEvent` (decode + dispatch)

**Files:**
- Modify: `Sources/Swiflow/Regions/RegionView.swift` (add `.onEvent`)
- Test: `Tests/SwiflowTests/Regions/RegionOnEventTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionOnEventTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int }
private struct SceneEvent: RegionEvent, Equatable { let kind: String; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps; typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

/// Returns a preset typed value, and records the JSON it was handed.
private final class RecordingDecoder: RegionEventDecoding {
    let event: SceneEvent
    init(_ e: SceneEvent) { self.event = e }
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let typed = event as? E else { throw RegionError(code: "x", message: json) }
        return typed
    }
}

@MainActor
@Suite("Region .onEvent")
struct RegionOnEventTests {
    @Test(".onEvent registers an sf:event handler that decodes detail into the typed closure")
    func onEventDecodes() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = RecordingDecoder(SceneEvent(kind: "select", id: 9))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var received: SceneEvent?
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 1))
            .onEvent { e in received = e }

        guard case .element(let data) = view.asVNode(),
              let handler = data.handlers["sf:event"] else {
            Issue.record("expected an sf:event handler"); return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:event", detail: #"{"kind":"select","id":9}"#))
        #expect(received == SceneEvent(kind: "select", id: 9))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionOnEventTests'`
Expected: FAIL — `value of type 'RegionView<Scene>' has no member 'onEvent'`.

- [ ] **Step 3: Add `.onEvent` to `RegionView`**

Append to `Sources/Swiflow/Regions/RegionView.swift`:

```swift
public extension RegionView {
    /// Handle a guest event. The closure parameter type is inferred as
    /// `G.Event` — no annotation. The raw `sf:event` JSON payload is decoded
    /// through the installed `RegionDecoder`; if none is installed or decoding
    /// fails, the event is dropped.
    @MainActor
    func onEvent(_ action: @escaping @MainActor (G.Event) -> Void) -> RegionView<G> {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(G.Event.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:event"] = handler
        return RegionView<G>(data: d)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionOnEventTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionView.swift Tests/SwiflowTests/Regions/RegionOnEventTests.swift
git commit -m "feat(core): typed RegionView.onEvent with decode seam"
```

---

## Task 9: `.onError`

**Files:**
- Modify: `Sources/Swiflow/Regions/RegionView.swift` (add `.onError`)
- Test: `Tests/SwiflowTests/Regions/RegionOnErrorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionOnErrorTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

private final class ErrDecoder: RegionEventDecoding {
    let err: RegionError
    init(_ e: RegionError) { self.err = e }
    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let typed = err as? T else { throw RegionError(code: "x", message: json) }
        return typed
    }
}

@MainActor
@Suite("Region .onError")
struct RegionOnErrorTests {
    @Test(".onError registers an sf:error handler that decodes RegionError")
    func onErrorDecodes() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = ErrDecoder(RegionError(code: "load-failed", message: "404"))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var received: RegionError?
        let view = region(G.self, key: "k", props: P(x: 1)).onError { received = $0 }

        guard case .element(let data) = view.asVNode(),
              let handler = data.handlers["sf:error"] else {
            Issue.record("expected an sf:error handler"); return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:error", detail: #"{"code":"load-failed","message":"404"}"#))
        #expect(received == RegionError(code: "load-failed", message: "404"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionOnErrorTests'`
Expected: FAIL — `RegionView<G>` has no member `onError`.

- [ ] **Step 3: Add `.onError` to `RegionView`**

Append to the `public extension RegionView` block in `Sources/Swiflow/Regions/RegionView.swift`:

```swift
    /// Handle a region failure (load/instantiate/trap/protocol-mismatch). The
    /// app typically flips state here to render a sibling fallback.
    @MainActor
    func onError(_ action: @escaping @MainActor (RegionError) -> Void) -> RegionView<G> {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(RegionError.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:error"] = handler
        return RegionView<G>(data: d)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionOnErrorTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Regions/RegionView.swift Tests/SwiflowTests/Regions/RegionOnErrorTests.swift
git commit -m "feat(core): RegionView.onError with decoded RegionError"
```

---

## Task 10: The inline secondary form — `region(source:key:props:)`

**Files:**
- Create: `Sources/Swiflow/Regions/RegionInline.swift`
- Modify: `Sources/Swiflow/Regions/RegionBuilder.swift` (add `AnyRegionView` overload)
- Test: `Tests/SwiflowTests/Regions/RegionInlineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/Regions/RegionInlineTests.swift
import Testing
@testable import Swiflow

private struct ChartProps: Encodable { var bars: Int }
private struct ChartEvent: RegionEvent, Equatable { let bar: Int }

private final class ChartDecoder: RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let v = ChartEvent(bar: 4) as? E else { throw RegionError(code: "x", message: json) }
        return v
    }
}

@MainActor
@Suite("Region inline form")
struct RegionInlineTests {
    @Test("region(source:key:props:) lowers like the typed form")
    func inlineLowers() {
        let v = region(source: "regions/chart.wasm", key: "c", props: ChartProps(bars: 12))
        guard case .element(let d) = v.asVNode() else { Issue.record("expected element"); return }
        #expect(d.tag == "sf-region")
        #expect(d.attributes["data-source"] == "regions/chart.wasm")
        guard case .string(let json)? = d.properties["sfProps"] else { Issue.record("expected sfProps"); return }
        #expect(json.contains("\"bars\":12"))
    }

    @Test("inline .onEvent requires an annotation but decodes the same way")
    func inlineOnEvent() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = ChartDecoder()
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var got: ChartEvent?
        let v = region(source: "regions/chart.wasm", key: "c", props: ChartProps(bars: 1))
            .onEvent { (e: ChartEvent) in got = e }
        guard case .element(let d) = v.asVNode(), let h = d.handlers["sf:event"] else {
            Issue.record("expected sf:event handler"); return
        }
        registry.dispatch(id: h.id, event: EventInfo(type: "sf:event", detail: "{}"))
        #expect(got == ChartEvent(bar: 4))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'SwiflowTests.RegionInlineTests'`
Expected: FAIL — no `region(source:key:props:)` overload / no `AnyRegionView`.

- [ ] **Step 3: Create `AnyRegionView` and the inline factory**

```swift
// Sources/Swiflow/Regions/RegionInline.swift

/// The untyped face of a region, for quick/dynamic guests that skip a
/// `RegionGuest` declaration. Sizing comes from `RegionModifiable`; `.onEvent`
/// is generic over the event type, so call sites must annotate the closure.
public struct AnyRegionView: RegionModifiable {
    public var data: ElementData
    public init(data: ElementData) { self.data = data }
}

/// Inline region: no guest type, so the event type is supplied by the
/// `.onEvent` closure annotation rather than inferred.
@MainActor
public func region(
    source: String,
    key: String,
    props: some Encodable
) -> AnyRegionView {
    let json = (try? JSONValueEncoder().encode(props).jsonString) ?? "null"
    let data = ElementData(
        tag: "sf-region",
        key: key,
        attributes: ["data-source": source],
        properties: ["sfProps": .string(json)]
    )
    return AnyRegionView(data: data)
}

public extension AnyRegionView {
    @MainActor
    func onEvent<E: RegionEvent>(_ action: @escaping @MainActor (E) -> Void) -> AnyRegionView {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(E.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:event"] = handler
        return AnyRegionView(data: d)
    }

    @MainActor
    func onError(_ action: @escaping @MainActor (RegionError) -> Void) -> AnyRegionView {
        var d = data
        let handler = _registerAmbientHandler { info in
            guard let detail = info.detail, let decoder = RegionDecoder.current else { return }
            guard let decoded = try? decoder.decode(RegionError.self, from: detail) else { return }
            action(decoded)
        }
        d.handlers["sf:error"] = handler
        return AnyRegionView(data: d)
    }
}
```

- [ ] **Step 4: Add the builder overload for `AnyRegionView`**

Append to `Sources/Swiflow/Regions/RegionBuilder.swift`:

```swift
public extension ChildrenBuilder {
    /// Lift an inline region into the children list.
    static func buildExpression(_ expression: AnyRegionView) -> [VNode] {
        [expression.asVNode()]
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionInlineTests'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Regions/RegionInline.swift Sources/Swiflow/Regions/RegionBuilder.swift Tests/SwiflowTests/Regions/RegionInlineTests.swift
git commit -m "feat(core): inline region(source:key:props:) secondary form"
```

---

## Task 11: Full-surface smoke test

**Files:**
- Test: `Tests/SwiflowTests/Regions/RegionSmokeTests.swift`

- [ ] **Step 1: Write the test (proves the README-style call site compiles and lowers)**

```swift
// Tests/SwiflowTests/Regions/RegionSmokeTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int; var hue: Double }
private struct SceneEvent: RegionEvent { enum Kind: String, Decodable { case select, hover }; let kind: Kind; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps; typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

@MainActor
@Suite("Region smoke")
struct RegionSmokeTests {
    @Test("the canonical typed call site composes and lowers to one sf-region child")
    func canonical() {
        var selected = 0
        var fellBack = false
        let tree = div {
            region(Scene.self, key: "hero", props: SceneProps(count: 3, hue: 0.5))
                .onEvent { e in selected = e.id }     // e: SceneEvent inferred
                .onError { _ in fellBack = true }
                .fill()
        }
        guard case .element(let outer) = tree,
              case .element(let child)? = outer.children.first else {
            Issue.record("expected one sf-region child"); return
        }
        #expect(child.tag == "sf-region")
        #expect(child.handlers["sf:event"] != nil)
        #expect(child.handlers["sf:error"] != nil)
        #expect(child.style["width"] == "100%")
        _ = (selected, fellBack) // silence unused warnings; behavior covered in Tasks 8–9
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter 'SwiflowTests.RegionSmokeTests'`
Expected: PASS.

- [ ] **Step 3: Run the entire core test target to confirm no regressions**

Run: `swift test --filter 'SwiflowTests'`
Expected: PASS (all pre-existing tests + the new Region suites).

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowTests/Regions/RegionSmokeTests.swift
git commit -m "test(core): full-surface smoke for the typed region call site"
```

---

## Exit criteria (Plan 1)

- `region(Guest.self, key:, props:)` and the inline `region(source:key:props:)` both lower to an `<sf-region>` element carrying `data-source` + an `sfProps` JSON string, usable inside a `div { }` body.
- `.onEvent` infers the guest's event type (no annotation) and decodes `EventInfo.detail` through the installed `RegionDecoder`; `.onError` decodes `RegionError`.
- Sizing (`.fill()`/`.frame`/`.aspectRatio`) writes the right CSS.
- All of the above is covered by `swift test --filter 'SwiflowTests'` on macOS with **no** browser, **no** JavaScriptKit, **no** Foundation in any touched file.
- The foundation-free `JSONValueEncoder` now lives in core and SwiflowStore still passes.

## Handoff to Plan 2 (Browser runtime)

Plan 2 consumes this contract: it installs a concrete `RegionEventDecoding` (JavaScriptKit `JSValueDecoder`) via `RegionDecoder.current`, ships `swiflow-regions.js` (the `<sf-region>` custom element reading `data-source` + `sfProps`, spawning the worker, transferring the OffscreenCanvas), wires `serializeEvent` to forward `event.detail`, and teaches `DispatcherBridge` to read `payload.detail`. No core DSL change should be needed — if one is, that's a signal the contract was under-specified here.
