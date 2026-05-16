Since you are aiming for a **React-style declarative component architecture** with a **custom specialized renderer**, you are essentially building a **Virtual DOM (VDOM) Engine** optimized for the WASM/JS bridge.

Here is a detailed **Technical Specifications Sheet** to guide your initial development.

---

# Project Spec: "Swift-React-Wasm" (Working Title)
**Objective:** A high-performance, component-based UI framework for Swift/WASM that uses a Virtual DOM to minimize JavaScript interop overhead.

---

## 1. Architectural Overview
The framework follows a **Unidirectional Data Flow** model.

1.  **The Developer Layer:** Writes `struct` components using a declarative DSL.
2.  **The Reconciler (WASM):** Manages the VDOM tree, performs diffing, and tracks state changes.
3.  **The Patch Set (The Bridge):** A serialized list of "mutations" (e.g., `AddNode`, `SetProp`).
4.  **The Renderer (JS/Bridge):** A minimal JavaScript "driver" that receives patches and applies them to the real DOM.

---

## 2. Core Component Specifications

### A. The Virtual Node (`VNode`)
This is the fundamental unit of the VDOM. It must be a lightweight Swift `struct`.

**Properties:**
*   `tag`: `String` (e.g., "div", "button", "h1").
*   `attributes`: `[String: AttributeValue]` (where `AttributeValue` is an enum of String, Int, Bool).
*   `children`: `[VNode]`.
*   `key`: `String?` (Crucial for React-style list reconciliation).
*   `onEvent`: `[String: (Event) -> Void]` (Mapping events like "click" to Swift closures).

### B. The Component Protocol (`Component`)
Every UI element must conform to this.

**Requirements:**
*   `var body: VNode { get }`: The declarative description of the UI.
*   `func lifecycleWillMount()`, `func lifecycleDidMount()`: Optional hooks.
*   `State` management: A mechanism to trigger a re-render when a property changes.

### C. The Reconciler (The "Diffing Engine")
This is the "Brain" of the framework.

**Logic Requirements:**
1.  **Tree Diffing Algorithm:** Implement a heuristic O(n) algorithm.
    *   If `oldTag != newTag` $\rightarrow$ Replace entire node.
    *   If `oldTag == newTag` $\rightarrow$ Diff attributes and diff children.
2.  **Keyed Reconciliation:** Use the `key` property to detect if elements in a list have moved, been added, or been deleted, rather than re-rendering the whole list.
3.  **Patch Generation:** Instead of applying changes immediately, the reconciler must output a `[Patch]` array.

---

## 3. The Bridge & Renderer Specs

### A. The Patch Protocol
To avoid "chatty" communication between WASM and JS, define a strictly typed Patch set.

**Patch Types:**
*   `.createElement(tag, attributes, index)`
*   `.removeElement(index)`
*   `.updateAttribute(index, key, value)`
*   `.replaceElement(index, newVNode)`
*   `.appendChild(parentIndex, childIndex)`

### B. The JS Driver (The "Thin Layer")
A small `.js` file included in the project template.
*   **Input:** A JSON or TypedArray representing the `[Patch]` list.
*   **Process:** A single loop that iterates through the patches and executes standard DOM commands (`document.createElement`, `element.setAttribute`, etc.).

---

## 4. Developer Experience (DX) Specs

### A. The DSL (Domain Specific Language)
The user should not manually instantiate `VNode`. They should use a "SwiftUI-like" syntax.

**Goal Syntax:**
```swift
func myView() -> View {
    Div(class: "container") {
        H1("Hello World")
        Button("Click Me") {
            print("Clicked!")
        }
    }
}
```

### B. The CLI Tool (`swift-web`)
A command-line tool to manage the lifecycle.
*   `swift-web init`: Scaffolds the project (creates `Package.swift`, `index.html`, and `App.swift`).
*   `swift-web run`: 
    1. Calls `swift build -target wasm32-unknown-emscripten`.
    2. Bundles the `.wasm` and `.js` files.
    3. Starts a local HTTP server (e.g., using a basic Swift-based server or Python/Node).

---

## 5. Implementation Roadmap (Phases)

### Phase 1: The Minimal Viable Diff (MVD)
*   [ ] Create `VNode` struct.
*   [ ] Implement basic `diff(old, new)` that returns a list of string commands.
*   [ ] Create a JS function that can parse these strings and update a simple `<div>`.

### Phase 2: State & Reactivity
*   [ ] Implement a `@State` property wrapper.
*   [ ] Create the "Scheduler": When `@State` changes, mark the component as "dirty" and schedule a re-render for the next animation frame.

### Phase 3: The Component Lifecycle
*   [ ] Implement the `Component` protocol.
*   [ ] Add support for nested components (a `VNode` can be a component that returns a `VNode`).

### Phase 4: Optimization (The "Pro" Phase)
*   [ ] **Keyed Diffing:** Optimize list rendering.
*   [ ] **Batching:** Ensure multiple state changes in one tick only trigger one bridge call.
*   [ ] **Memory Management:** Ensure Swift closures passed to JS (event listeners) are properly cleaned up to prevent memory leaks in the WASM linear memory.

---

## 6. Success Metrics
1.  **Code Size:** The framework overhead (the core engine) should be $< 100KB$ (compressed).
2.  **Frame Rate:** Complex UI updates should maintain $60FPS$ in the browser.
3.  **Ease of Use:** A developer should be able to go from `init` to "Hello World" in under 60 seconds.
