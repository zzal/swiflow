Since you are leaning toward a **React-style architecture** (Virtual DOM + Component-based) rather than a SwiftUI-style one, your framework needs to be built around the concept of **Reconciliation**.

Here is a Technical Specifications Sheet for a prototype version of your framework. Let's call the project **"SwiftFlow"** (placeholder name).

---

# 📜 Project Spec: SwiftFlow (Alpha)
**Goal:** A high-performance, declarative, component-based UI framework for SwiftWASM that uses a Virtual DOM to minimize JavaScript interop overhead.

---

## 1. Core Architecture Overview
SwiftFlow will follow a unidirectional data flow:
1.  **State Change:** User triggers an action $\rightarrow$ `@State` variable updates.
2.  **Re-render:** The component's `body` is re-evaluated, generating a new **Virtual Tree**.
3.  **Diffing:** The **Reconciler** compares the *New Virtual Tree* with the *Current Virtual Tree*.
4.  **Patching:** The Reconciler generates a **ChangeSet** (a list of minimal instructions).
5.  **Commit:** The **JS-Bridge Renderer** receives the ChangeSet and applies it to the real Browser DOM in a single batch.

---

## 2. Technical Component Specifications

### A. The Virtual DOM (VNode)
*   **Type:** `struct` (Value type for speed).
*   **Properties:**
    *   `tag`: `String` (e.g., "div", "button", "span").
    *   `attributes`: `[String: String]` (Class, ID, Style, etc.).
    *   `children`: `[VNode]` (Recursive structure).
    *   `key`: `String?` (For efficient list reconciliation).
    *   `onEvent`: `[String: (Event) -> Void]` (Event listeners like "click").

### B. The Reconciler (The "Brain")
*   **Algorithm:** A specialized tree-diffing algorithm (Heuristic O(n)).
*   **Responsibilities:**
    *   Maintain a reference to the "Current Tree."
    *   Compare nodes by `tag` and `key`.
    *   Identify `Insert`, `Remove`, `Replace`, and `UpdateAttribute` operations.
*   **Output:** A `Patch` object:
    ```swift
    enum Patch {
        case insert(node: VNode, index: Int)
        case remove(index: Int)
        case updateAttribute(index: Int, key: String, value: String)
        case replace(index: Int, newNode: VNode)
    }
    ```

### C. The Component Model
*   **Protocol:** `Component`
*   **Requirements:**
    *   `var body: VNode { get }`
    *   An internal mechanism to trigger a re-render when a property marked `@State` changes.
*   **State Management:** Use a custom Property Wrapper `@State` that registers the component with the `SwiftFlowEngine` upon mutation.

### D. The Renderer (The "Bridge")
*   **Implementation:** A thin layer using `JavaScriptKit`.
*   **Strategy:** **Batching.**
    *   Instead of calling `JS.appendChild` 100 times, the Renderer accepts `[Patch]`.
    *   It iterates through the array and executes the DOM manipulations in one execution loop to minimize the WASM-to-JS context switching cost.

---

## 3. Developer Experience (The "API")
The user should be able to write code that looks like this:

```swift
struct CounterComponent: Component {
    @State private var count = 0

    var body: VNode {
        Div(class: "container") {
            H1("Count: \(count)")
            Button(text: "Increment", onClick: { count += 1 })
        }
    }
}

// Entry point
@main
struct App {
    static func main() {
        SwiftFlow.render(CounterComponent(), into: "app-root")
    }
}
```

---

## 4. Implementation Roadmap (Milestones)

### Phase 1: The "Static" Engine (MVP)
*   [ ] Implement `VNode` struct.
*   [ ] Implement basic `render(vnode, into: elementID)` that converts a VNode into real DOM nodes.
*   [ ] **Goal:** Render a static page from Swift without any updates.

### Phase 2: The "Reactive" Engine (Alpha)
*   [ ] Implement `@State` property wrapper.
*   [ ] Implement the `diff(old, new)` algorithm.
*   [ ] Implement the `Patch` execution logic via `JavaScriptKit`.
*   [ ] **Goal:** Change a number on the screen via a button click.

### Phase 3: The "Optimization" Phase (Beta)
*   [ ] Implement `Keyed` reconciliation (for fast list updates).
*   [ ] Implement Batching (reducing JS bridge calls).
*   [ ] Create a set of standard HTML components (`Div`, `Span`, `Button`, `Input`).

---

## 5. Success Metrics (KPIs)
1.  **Memory Footprint:** VNode trees should not cause memory leaks in WASM.
2.  **Bridge Overhead:** A single batch update of 50 DOM changes should take $< 16ms$ (to maintain 60fps).
3.  **Code Conciseness:** A developer should be able to build a functional Todo List in $< 100$ lines of Swift.
