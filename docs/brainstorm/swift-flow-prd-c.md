# PRD: Project "Swift-Flow" (Finalized Strategy)
**Status:** Architectural Blueprint  
**Vision:** To provide a **Vite-inspired developer experience** for Swift-WASM through a "Single Experience" orchestration model.

---

## 1. Executive Summary
Swift-Flow is a professional-grade ecosystem designed to solve the fragmentation in Swift-WASM development. Instead of providing only a UI library, Swift-Flow provides a **Unified Orchestration Layer**. It uses a highly optimized, batched VDOM engine to solve the WASM-to-JS bridge bottleneck and a minimalist CLI to provide a seamless, zero-config "Single Experience" for developers.

---

## 2. Product Pillars (The "Winning Formula")

### I. The Batched Engine (Performance)
To overcome the "Bridge Tax," the runtime will not communicate with the DOM via individual calls. It will utilize a **Batched Mutation Model**, where all changes in a single render cycle are serialized into a single array of patches and sent to a minimal JS driver in one "leap."

### II. The Single Experience (Ergonomics)
While the architecture is modular (Library, CLI, JS Driver), the user experience is monolithic. Through a unified CLI, the user's interaction is reduced to a single tool that handles scaffolding, dependency management, and the development loop.

### III. Lifecycle-Managed Safety (Reliability)
The framework will manage the "Handshake" between Swift's memory and the Browser's DOM, ensuring that component unmounting automatically triggers the destruction of JavaScript event listeners to prevent memory leaks.

---

## 3. Technical Roadmap (The "Core-Out" Strategy)

The project will be executed in three distinct stages to ensure engineering stability.

### Phase 1: The "Brain" (The Core Logic)
**Goal:** Prove the mathematical validity of the VDOM and the Diffing engine.
*   **Deliverable:** A pure Swift Library (Package).
*   **Core Requirements:**
    *   `VNode` structure (tag, attributes, children).
    *   `Diffing Engine`: An O(n) algorithm that compares two `VNode` trees.
    *   `Patch Generation`: The ability to output a list of instructions (e.g., `.replace`, `.updateAttribute`).
*   **Success Metric:** A passing suite of unit tests proving that changing a property in a `VNode` produces the correct `Patch`.

### Phase 2: The "Glue" (The Minimalist CLI)
**Goal:** Establish the "Single Experience" and automate the toolchain.
*   **Deliverable:** A minimalist Swift-based CLI tool.
*   **Core Requirements:**
    *   `swift-flow init`: Scaffolds a project, writes the `Package.swift`, and creates the folder structure.
    *   `swift-flow run`: Wraps `swift run` to launch the project.
    *   **The Orchestration Proof:** Demonstrating that the CLI can successfully link the Swift Library to a basic HTML/JS environment.
*   **Success Metric:** A developer can go from an empty folder to a running "Hello World" web page using only two commands.

### Phase 3: The "Meat" (The Full Framework)
**Goal:** Build the high-level features that make the framework usable for real apps.
*   **Deliverable:** A complete, production-ready ecosystem.
*   **Core Requirements:**
    *   **Reactivity:** Implementation of the `@State` property wrapper and a `Scheduler` to batch updates.
    *   **The JS Driver:** A robust, NPM-distributed driver to execute the patches.
    *   **Lifecycle Hooks:** `didMount`, `willUnmount`, etc., for component management.
    *   **Component DSL:** A SwiftUI-like syntax for building complex UI trees.
*   **Success Metric:** A complex, stateful application (e.g., a Todo list) running at 60FPS with zero manual JS configuration.

---

## 4. Functional Requirements (The "What")

### 4.1. The Reconciler (WASM/Swift)
*   **[FR-1] Patch Batching:** All mutations must be collected into a single buffer per frame.
*   **[FR-2] Keyed Reconciliation:** Must support `key` properties for efficient list reordering.
*   **[FR-3] Attribute Diffing:** Must efficiently detect changes in HTML attributes/properties.

### 4.2. The Orchestrator (CLI)
*   **[FR-4] Dependency Injection:** The CLI must automatically configure the `Package.swift` to include the `Swift-Flow-Lib`.
*   **[FR-5] Asset Management:** The CLI must manage the lifecycle of the JS Driver (fetching from NPM and placing it in the build directory).

### 4.3. The Driver (JS)
*   **[FR-6] Atomic Execution:** The driver must apply the `PatchBuffer` synchronously to prevent UI tearing.

---

## 5. Success Metrics (KPIs)

1.  **Developer Velocity:** Time from `init` to "Running App" $< 60$ seconds.
2.  **Runtime Performance:** Total time spent in JS-to-WASM bridge calls $< 5\%$ of the total frame budget.
3.  **Memory Stability:** Zero growth in WASM linear memory during repetitive component mounting/unmounting cycles.

---

## 6. Risk Mitigation
*   **Risk:** Complexity of the WASM-to-JS bridge. 
    *   *Mitigation:* Use `JavaScriptKit` for the initial bridge and move to a custom `PatchBuffer` (TypedArray) for performance.
*   **Risk:** Difficulty in distributing the CLI. 
    *   *Mitigation:* Use SPM for the CLI distribution to keep it within the native Swift ecosystem.

---

## 7. Security & Trust

Swift-Flow adopts a "Secure by Default" philosophy. We mitigate XSS through automatic HTML escaping in the VDOM; mitigate Memory Leaks/Corruption through strict lifecycle management of WASM-to-JS closures; and mitigate Supply Chain attacks by enforcing deterministic dependency management via the CLI.

