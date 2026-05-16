# PRD: Project "Swift-Flow"
**Status:** Finalized Vision / Discovery Phase  
**Core Concept:** A unified development orchestrator for the Swift-WASM ecosystem.

---

## 1. Vision Statement
To eliminate the toolchain friction in Swift-WASM development by providing **Vite-inspired developer ergonomics**. Swift-Flow aims to transform the Swift-to-Web experience from a complex compilation task into an instant, seamless, and high-performance development loop.

---

## 2. The Problem Space (The "Why")
The current Swift-WASM landscape is fragmented:
1.  **High Friction:** Developers must manually manage `Package.swift`, Emscripten toolchains, and complex JavaScript glue code.
2.  **The "Bridge Tax":** Current UI libraries communicate with the DOM via frequent, small JavaScript calls, creating a massive performance bottleneck in the WASM-to-JS bridge.
3.  **Lack of Orchestration:** Existing tools are either "UI Libraries" (which lack a dev environment) or "Compiler Wrappers" (which lack a modern developer experience).

---

## 3. Product Pillars (The "Winning Formula")

### I. Unified Orchestration (The "Ergonomics" Pillar)
We do not just provide a library; we provide a workflow. Through a single CLI, we abstract the complexity of the toolchain, providing instant scaffolding and a hot-reloading development server.

### II. Batched Reactivity (The "Performance" Pillar)
We solve the "Bridge Tax" by implementing a specialized Reconciler. Instead of individual DOM updates, we collect all changes in a Swift-based VDOM and ship them to the browser as a single, optimized "Mutation Batch."

### III. Lifecycle-Aware Memory Management (The "Safety" Pillar)
We bridge the gap between Swift's ARC and the JavaScript Garbage Collector. Our framework ensures that every component's lifecycle is strictly managed, automatically cleaning up event listeners and closures to prevent WASM memory leaks.

---

## 4. Functional Requirements

### 4.1. The CLI Orchestrator (`swift-flow`)
*   **[FR-1] Zero-Config Scaffolding:** `swift-flow init` creates a complete, ready-to-run project structure.
*   **[FR-2] Instant Dev Loop:** `swift-flow dev` automates the build-and-serve cycle with a local development server.
*   **[FR-3] Production Bundling:** `swift-flow build` generates an optimized, minimized production bundle (WASM + JS Driver).

### 4.2. The Runtime Engine
*   **[FR-4] Batched VDOM Reconciler:** A Swift-native diffing engine that produces a `[Patch]` array to minimize WASM $\leftrightarrow$ JS transitions.
*   **[FR-5] Reactive State Management:** A `@State` property wrapper that triggers the reconciliation cycle automatically.
*   **[FR-6] Keyed Reconciliation:** Support for unique keys in collections to enable high-performance list updates.

### 4.3. The Safety Layer
*   **[FR-7] Automated Cleanup:** A protocol-based lifecycle system that ensures all JS-side references are released when a component is unmounted.

---

## 5. Technical Architecture (High-Level)

1.  **The Developer Layer:** Writes declarative Swift code using a SwiftUI-inspired DSL.
2.  **The Logic Layer (WASM/Swift):** 
    *   Manages the Virtual DOM.
    *   Handles state changes and diffing.
    *   Serializes changes into a `PatchBuffer`.
3.  **The Bridge (The "Single Leap"):** A single call transfers the `PatchBuffer` from WASM memory to the JS environment.
4.  **The Driver Layer (JavaScript):** A minimal, high-speed loop that iterates through the `PatchBuffer` and applies mutations to the real DOM.

---

## 6. Success Metrics (KPIs)
*   **Onboarding Speed:** Time from `init` to "Hello World" in the browser must be $< 60$ seconds.
*   **Runtime Efficiency:** The overhead of the WASM $\leftrightarrow$ JS bridge must remain below $5\%$ of the frame budget during standard interactions.
*   **Memory Stability:** Zero increase in WASM linear memory usage after repeated mounting/unmounting of complex components.

---

## 7. Security & Trust

Swift-Flow adopts a "Secure by Default" philosophy. We mitigate XSS through automatic HTML escaping in the VDOM; mitigate Memory Leaks/Corruption through strict lifecycle management of WASM-to-JS closures; and mitigate Supply Chain attacks by enforcing deterministic dependency management via the CLI.

---

## 8. Roadmap

*   **Phase 1: Foundation (The Engine):** CLI scaffolding, basic VDOM, and the Batched Patching bridge.
*   **Phase 2: Reactivity (The Life):** `@State` implementation and the Scheduler.
*   **Phase 3: Lifecycle (The Safety):** Component mounting/unmounting and memory leak prevention.
*   **Phase 4: Optimization (The Polish):** Keyed diffing and production-grade bundling.
