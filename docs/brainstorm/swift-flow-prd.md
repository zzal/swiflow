# PRD: Project "Swift-Flow" (Working Title)
**Status:** Draft / Discovery Phase  
**Vision:** To provide the first "Zero-Config" professional web development ecosystem for Swift, optimized specifically for the WASM/JS bridge bottleneck.

---

## 1. Executive Summary & Product Vision
Current Swift-WASM tools (Tokamak, ElementaryUI) focus on **syntax**—making Swift look like SwiftUI. However, they ignore the **Developer Experience (DX)** and the **Runtime Performance** issues inherent in the WASM-to-JS bridge.

**Swift-Flow** is not just a UI library; it is a **Web Development Orchestrator**. It combines a high-performance, batched VDOM engine with a seamless CLI toolchain, effectively becoming the "Vite of the Swift Ecosystem."

---

## 2. Target Audience (User Personas)
1.  **The iOS/macOS Developer:** Wants to bring their Swift skills to the web without learning the complexities of Webpack, NPM, or complex Emscripten toolchains.
2.  **The Performance-First Web Dev:** Wants to use Swift's type safety and speed but is frustrated by the "bridge tax" and slow build times of current WASM implementations.

---

## 3. Competitive Differentiation (The "Winning Formula")

| The Problem | Current Solutions (Tokamak/Elementary) | **Swift-Flow Solution** |
| :--- | :--- | :--- |
| **The "Bridge Tax"** | Frequent, small JS calls (Slow). | **Batched Mutation Patches** (Fast). |
| **Toolchain Friction** | Manual SPM/Makefile/Docker setup. | **Unified CLI** (`swift-flow init/run`). |
| **The "Blank Page"** | You get code, but no environment. | **Scaffolded Ecosystem** (Dev server, Bundler). |
| **Memory Safety** | Standard ARC (leads to JS leaks). | **Lifecycle-Managed Closures** (Zero Leaks). |

---

## 4. Functional Requirements (The "What")

### 4.1. The Orchestrator (CLI Tooling)
*   **[FR-1] Project Scaffolding:** `swift-flow init` must generate a standardized project structure (Sources, Public, Package.swift).
*   **[FR-2] Instant Dev Loop:** `swift-flow dev` must compile the project and launch a local hot-reloading server.
*   **[FR-3] Optimized Build:** `swift-flow build` must produce a production-ready bundle (minimized WASM + optimized JS driver).

### 4.2. The Runtime (Engine)
*   **[FR-4] Batched Reconciler:** The engine must collect all VDOM changes within a single `requestAnimationFrame` and ship them as a single `[Patch]` array to JavaScript.
*   **[FR-5] Reactive State:** Implementation of a `@State` property wrapper that triggers the Reconciler without manual intervention.
*   **[FR-6] Keyed Diffing:** Must support `key` properties in lists to ensure O(n) performance during DOM reordering.

### 4.3. The Memory Manager
*   **[FR-7] Lifecycle Cleanup:** Every component must implement a `willUnmount` protocol that automatically unbinds all JavaScript event listeners to prevent WASM memory leaks.

---

## 5. Technical Specifications (The "How")

### 5.1. The Data Flow (The "Batching" Architecture)
1.  **State Change:** User interacts $\rightarrow$ `@State` updates.
2.  **Diffing:** Swift Reconciler calculates the difference between `OldTree` and `NewTree`.
3.  **Serialization:** Differences are converted into a `PatchBuffer` (an array of integers/enums).
4.  **The Single Leap:** One call: `js_apply_patches(patchBuffer)`.
5.  **Execution:** The JS Driver iterates the buffer and applies changes to the DOM.

### 5.2. Component Syntax (The "DSL")
The framework will provide a declarative, SwiftUI-inspired DSL:
```swift
struct CounterView: Component {
    @State private var count = 0

    var body: View {
        VStack {
            Text("Count is: \(count)")
            Button("Increment") { count += 1 }
        }
    }
}
```

---

## 6. Success Metrics (KPIs)
*   **Time to First Render:** A user should go from `swift-flow init` to "Hello World" in $< 60$ seconds.
*   **Bridge Overhead:** Total time spent in JS-to-WASM transition should be $< 5\%$ of total frame time during standard UI interactions.
*   **Bundle Size:** The core framework (Engine + CLI output) should remain under $150KB$ uncompressed for the initial load.

---

## 7. Roadmap (Phases)
*   **Phase 1 (Foundation):** CLI Scaffolding + Basic VDOM + Simple JS Bridge.
*   **Phase 2 (Reactivity):** `@State` implementation + Batched Patching logic.
*   **Phase 3 (Lifecycle):** Component mounting/unmounting + Memory Leak prevention.
*   **Phase 4 (Production):** Keyed diffing + Build optimization + Documentation.
