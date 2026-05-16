# Security Specification: Swift-Flow

## 1. The Primary Threat Model
We categorize our threats into three domains:
1.  **The Injection Domain (XSS):** Malicious data being interpreted as executable code in the browser.
2.  **The Memory Domain (WASM/Linear Memory):** Exploiting the boundary between Swift's memory management and the WASM linear memory space.
3.  **The Supply Chain Domain:** Malicious code entering the project through the CLI, NPM, or SPM.

---

## 2. Security Requirements (The "Defensive Layers")

### 2.1. Cross-Site Scripting (XSS) Prevention (The "Sanitization" Layer)
Since your framework handles the DOM, it is the primary gatekeeper for data being rendered.
*   **[SEC-1] Automatic Escaping:** The VDOM engine must treat all `String` values in `Attributes` or `Text` nodes as **unsafe by default**. The renderer must automatically escape HTML entities (e.g., `<` becomes `&lt;`) unless a developer explicitly uses a "trusted" wrapper (e.g., `RawHTML("...")`).
*   **[SEC-2] Attribute Validation:** The framework must restrict which attributes can be set via the DSL. For example, setting `onmouseover` via a standard attribute string should be blocked to prevent "Attribute Injection."

### 2.2. Memory & Boundary Safety (The "Sandbox" Layer)
WASM operates in a linear memory space. While Swift is "memory safe," the way it communicates with JavaScript can create holes.
*   **[SEC-3] Closure Ownership:** When passing Swift closures to JavaScript (for event listeners), the framework must ensure that the reference is strictly managed. We must prevent "Use-After-Free" scenarios where JS tries to call a Swift closure that has been deallocated from WASM memory.
*   **[SEC-4] Buffer Overflow Protection:** The `PatchBuffer` (the bridge between WASM and JS) must be strictly bounds-checked. The JS driver must never trust the "size" or "index" sent by the WASM side without validation.

### 2.3. Supply Chain Integrity (The "Trust" Layer)
Since your CLI automates the fetching of dependencies, the CLI itself is a high-value target.
*   **[SEC-5] Deterministic Builds:** The `swift-flow init` command should generate a lockfile (or use the existing `Package.resolved`) to ensure that every developer on a team is using the exact same version of the Library and the JS Driver.
*   **[SEC-6] Integrity Checking:** When the CLI fetches the JS Driver from NPM, it should ideally verify a checksum (hash) to ensure the file hasn't been intercepted or tamed (Man-in-the-Middle attack).

---

## 3. Security Implementation Strategy (The "Developer's Duty")

To make security part of the "Single Experience," we follow these principles:

1.  **Secure by Default:** The developer should not have to "turn on" security. If they write `Text(userInput)`, they are automatically protected from XSS.
2.  **Explicit Intent for Danger:** If a developer *needs* to render raw HTML, they must use a specific, searchable, and "loud" syntax like `UnsafeHTML(data)`. This makes security audits easy: a developer can simply search the codebase for `UnsafeHTML`.
3.  **Minimalism as Security:** By keeping the JS Driver as small and "dumb" as possible, we reduce the amount of code that could potentially contain a vulnerability.

---

## 4. Summary for the PRD

You should add a new section to your PRD:

> **Section 8: Security & Trust**
> *Swift-Flow adopts a **"Secure by Default"** philosophy. We mitigate **XSS** through automatic HTML escaping in the VDOM; mitigate **Memory Leaks/Corruption** through strict lifecycle management of WASM-to-JS closures; and mitigate **Supply Chain attacks** by enforcing deterministic dependency management via the CLI.*

**Does this level of security detail align with your vision for the framework?**
