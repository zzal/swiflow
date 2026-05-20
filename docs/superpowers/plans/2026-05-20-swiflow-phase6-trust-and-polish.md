# Swiflow Phase 6 — Trust & Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the six credibility-multiplier items from the Phase 6 design — fix `.attr(_:_:Bool)`, hide `Binding`, document the `final class` requirement, loudify `embed { }`, add an honest README section, and garbage-collect superseded plan drafts.

**Architecture:** No new types and no new public surface. One internal enum case (`Attribute.skip`), one annotation (`@_documentation`), two source comments, one DEBUG-only runtime check, one new README section, and a chore commit. All work converges on a smaller credibility surface, not a larger feature surface.

**Tech Stack:** Swift 6.0, Swift Testing, swift-argument-parser. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-05-20-swiflow-phase6-trust-and-polish-design.md`](../specs/2026-05-20-swiflow-phase6-trust-and-polish-design.md)

---

## File Structure

**Edit (Swift sources):**
- `Sources/Swiflow/DSL/Modifiers.swift` — add `Attribute.skip` sentinel case; rewrite `attr(_:_:Bool)` overload to return `.skip` when `false`; update `applyAttributes(...)` to drop `.skip` cases.
- `Sources/Swiflow/DSL/VNodeModifiers.swift` — short-circuit the `attr(_:_:Bool)` postfix overload when `false`.
- `Sources/Swiflow/Reactivity/State.swift` — add `@_documentation(visibility: internal)` to `Binding<Value>` and `State.projectedValue`; rewrite the Binding doc-comment.
- `Sources/Swiflow/DSL/ComponentDSL.swift` — promote the factory-contract warning to a leading block; rewrite doc.
- `Sources/Swiflow/Reactivity/Component.swift` (potentially) or `Sources/SwiflowWeb/Renderer.swift` — DEBUG-only mounted-instance tracker for the diagnostic. Exact home depends on where mount/unmount actually run; investigate before coding (see Task D Step 1).
- `Sources/SwiflowCLI/Templates/Templates.swift` — add `final class` explainer comment to `rawAppSwift`.
- `examples/HelloWorld/Sources/App/App.swift` — same comment, kept byte-equal with template.
- `README.md` — new "Current State" section after intro; status line bump at end.

**Edit (tests):**
- `Tests/SwiflowTests/DSL/ModifiersTests.swift` — add tests for `attr` Bool true/false; check that `false` produces no attribute.
- `Tests/SwiflowTests/DSL/VNodeModifiersTests.swift` — same coverage for postfix path.
- `Tests/SwiflowTests/DSL/ComponentDSLTests.swift` (or where embed lives) — add a DEBUG-gated test that asserts the reused-instance diagnostic fires.

**Commit (new repo files):**
- `docs/superpowers/plans/2026-05-17-swiflow-phase2b-cli.md` — untracked, ship as archival.
- `docs/superpowers/plans/2026-05-18-swiflow-phase2b3-cosmetics-cleanup.md` — untracked, ship as archival.
- `docs/superpowers/plans/2026-05-18-swiflow-phase2c-dev-server.md` — untracked, ship as archival.
- `docs/superpowers/plans/2026-05-18-swiflow-phase3-reactivity.md` — untracked, ship as archival.

**No changes needed:**
- `Sources/Swiflow/VNode.swift` — `ElementData` already has `var` fields (Phase 5).
- `js-driver/swiflow-driver.js` + `Sources/SwiflowCLI/EmbeddedDriver.swift` — untouched in Phase 6.

---

## Task A: Fix `.attr(_:_:Bool)` no-op (both prefix and postfix paths)

**Files:**
- Modify: `Sources/Swiflow/DSL/Modifiers.swift:5-44, 78-135`
- Modify: `Sources/Swiflow/DSL/VNodeModifiers.swift:31-49`
- Add: tests in `Tests/SwiflowTests/DSL/`

- [ ] **A.1: Write the failing tests first**

  Add to (or create) `Tests/SwiflowTests/DSL/ModifiersAttrBoolTests.swift`:

  ```swift
  import Testing
  @testable import Swiflow

  @Suite("attr(_:_:Bool) — boolean attribute semantics")
  struct AttrBoolTests {

      @Test("prefix .attr writes presence-only string when true")
      func prefixTrueEmits() {
          let node = button("Save", .attr("disabled", true))
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.attributes["disabled"] == "")
      }

      @Test("prefix .attr omits attribute when false")
      func prefixFalseOmits() {
          let node = button("Save", .attr("disabled", false))
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.attributes["disabled"] == nil)
      }

      @Test("postfix .attr writes presence-only string when true")
      func postfixTrueEmits() {
          let node = button("Save").attr("disabled", true)
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.attributes["disabled"] == "")
      }

      @Test("postfix .attr omits attribute when false")
      func postfixFalseOmits() {
          let node = button("Save").attr("disabled", false)
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.attributes["disabled"] == nil)
      }
  }
  ```

- [ ] **A.2: Run the new tests, confirm they fail in the "false omits" cases**

  Run: `swift test --filter AttrBoolTests 2>&1 | tail -20`

  Expected: `prefixTrueEmits` and `postfixTrueEmits` pass; `prefixFalseOmits` and `postfixFalseOmits` fail (the current code writes `""` in both branches, so `data.attributes["disabled"]` is `""` not `nil`).

- [ ] **A.3: Add `Attribute.skip` and update the prefix overload**

  Edit `Sources/Swiflow/DSL/Modifiers.swift`. Inside `public enum Attribute`, add a new case (just below `case key(String)`):

  ```swift
      /// Internal sentinel produced by overloads that need to *omit* an
      /// attribute given a runtime condition (e.g. `attr(_:_:Bool)` with
      /// `false`). `applyAttributes` drops these during the fold; they
      /// never reach `ElementData`. Not for general use — the case stays
      /// `package` so external code cannot construct one.
      case skip
  ```

  Note: cases in a `public` enum default to public visibility. To keep `.skip` from leaking, we can either keep it public (it's harmless — calling `.skip` directly produces an attribute that drops itself, which is a no-op) or make the enum itself `@frozen`-equivalent and move `skip` to an internal extension. **Simplest correct choice: leave the case public; document it as internal-use; the fold step handles it.** Add this immediately after the new case:

  ```swift
      // (The .skip case is documented internal-use; see attr(_:_:Bool).)
  ```

  Then rewrite the Bool overload (replace lines 34-43):

  ```swift
      /// Sets an HTML boolean attribute. HTML boolean attributes are
      /// presence-or-absent — `disabled`, `checked`, `readonly`. This
      /// overload emits a presence-only attribute (empty string value) when
      /// `value` is `true`, and **omits the attribute entirely** when
      /// `value` is `false`. Matches HTML semantics; no call-site gating
      /// required.
      public static func attr(_ name: String, _ value: Bool) -> Attribute {
          value ? .attribute(name: name, value: "") : .skip
      }
  ```

  Then update `applyAttributes(...)` (in the same file) to drop `.skip`. Inside the `switch attribute` block (around line 92-123), add a new arm:

  ```swift
          case .skip:
              continue
  ```

- [ ] **A.4: Update the postfix overload**

  Edit `Sources/Swiflow/DSL/VNodeModifiers.swift`, lines 41-44. Replace:

  ```swift
      /// Adds (or overwrites) an HTML attribute (boolean: empty string written when true).
      func attr(_ name: String, _ value: Bool) -> VNode {
          mergeAttribute(self) { $0.attributes[name] = value ? "" : "" }
      }
  ```

  with:

  ```swift
      /// Adds (or overwrites) a presence-only HTML boolean attribute when
      /// `value` is `true`; omits the attribute entirely when `false`.
      func attr(_ name: String, _ value: Bool) -> VNode {
          guard value else { return self }
          return mergeAttribute(self) { $0.attributes[name] = "" }
      }
  ```

- [ ] **A.5: Run the new tests, confirm they pass**

  Run: `swift test --filter AttrBoolTests 2>&1 | tail -20`

  Expected: all four tests pass.

- [ ] **A.6: Run the full suite to verify no regression**

  Run: `swift test 2>&1 | tail -5`

  Expected: full suite passes; test count grows by 4 over Phase 5 baseline.

- [ ] **A.7: Commit Task A**

  ```bash
  git add Sources/Swiflow/DSL/Modifiers.swift Sources/Swiflow/DSL/VNodeModifiers.swift Tests/SwiflowTests/DSL/ModifiersAttrBoolTests.swift
  git commit -m "$(cat <<'EOF'
  fix(dsl): attr(_:_:Bool) omits attribute on false, matches HTML semantics

  Both the prefix and postfix Bool overloads previously expanded to
  `value ? "" : ""` — a no-op. `attr("disabled", false)` still emitted
  `disabled=""`, which the browser treats as truthy. This was correct in
  spirit (HTML boolean attributes are presence-or-absent, not value-based)
  but the API forced call-site gating that no other modifier requires.

  New shape: emit a presence-only empty string when true; omit the
  attribute entirely when false. The prefix path routes false through a
  new internal `Attribute.skip` case that `applyAttributes` drops during
  the fold; the postfix path short-circuits to `self`.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task B: Hide `Binding<Value>` from autocomplete until Phase 7

**Files:**
- Modify: `Sources/Swiflow/Reactivity/State.swift:68-73, 96-116`

- [ ] **B.1: Annotate `Binding` and `State.projectedValue` as documentation-internal**

  Edit `Sources/Swiflow/Reactivity/State.swift`.

  Replace lines 68-73:

  ```swift
      public var projectedValue: Binding<Value> {
          Binding(
              get: { self.storage.value },
              set: { self.wrappedValue = $0 }
          )
      }
  ```

  with:

  ```swift
      /// The two-way binding for this state cell, accessed via `$count`.
      /// **Reserved for Phase 7** — Phase 6 ships the symbol for ABI
      /// stability but no DSL modifiers consume `Binding<Value>` yet.
      /// Use `wrappedValue` (`count = 5`) for now; `input(.value($text))`
      /// starts working when Phase 7's `.value(_:)` modifier ships.
      @_documentation(visibility: internal)
      public var projectedValue: Binding<Value> {
          Binding(
              get: { self.storage.value },
              set: { self.wrappedValue = $0 }
          )
      }
  ```

  Replace lines 96-116:

  ```swift
  /// Two-way binding shaped like SwiftUI's. Used as the `projectedValue` of
  /// `@State`, accessed via the `$`-prefix sigil:
  ///
  /// ```swift
  /// @State var text = ""
  /// // ...
  /// input(.value($text))   // pass the binding
  /// ```
  ///
  /// Phase 3 v1 doesn't yet have any DSL bindings that consume `Binding`;
  /// it's surfaced now so the API is set in stone before Phase 4's form
  /// helpers land. Until then, callers can use it manually via `get`/`set`.
  public struct Binding<Value> {
      public let get: () -> Value
      public let set: (Value) -> Void

      public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
          self.get = get
          self.set = set
      }
  }
  ```

  with:

  ```swift
  /// Two-way binding shaped like SwiftUI's. **Reserved for Phase 7** —
  /// Phase 6 hides it from autocomplete and DocC via
  /// `@_documentation(visibility: internal)` because no DSL modifier in
  /// Phase 6 consumes a `Binding<Value>`. The type stays `public` for
  /// ABI stability; Phase 7 will surface it again when `.value($text)`,
  /// `.checked($flag)`, and `.selection($choice)` ship.
  ///
  /// See `docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md`
  /// (Phase 7 — Bindings, Refs & Form Foundations) for the consumer plan.
  @_documentation(visibility: internal)
  public struct Binding<Value> {
      public let get: () -> Value
      public let set: (Value) -> Void

      public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
          self.get = get
          self.set = set
      }
  }
  ```

- [ ] **B.2: Run the full suite to verify nothing breaks**

  Run: `swift test 2>&1 | tail -5`

  Expected: same pass count as after Task A.

  Note on `@_documentation`: this is a Swift compiler attribute available in Swift 5.8+. It does not affect ABI; it removes the symbol from DocC generation and from Xcode's symbol completion. The compiler may emit a warning if the attribute is unknown — verify on Swift 6.3.

- [ ] **B.3: Commit Task B**

  ```bash
  git add Sources/Swiflow/Reactivity/State.swift
  git commit -m "$(cat <<'EOF'
  docs(state): hide Binding<Value> from autocomplete until Phase 7

  Binding ships in Phase 3 without a DSL consumer — `input(.value($text))`
  doesn't compile because no `.value(_:Binding<...>)` overload exists yet.
  Phase 7 (Bindings, Refs & Form Foundations) will add the consumers; until
  then, surfacing the symbol via autocomplete creates a footgun on first
  read.

  Mark `Binding<Value>` and `State.projectedValue` with
  `@_documentation(visibility: internal)`. The symbols stay `public` for
  ABI stability — Phase 7 needs them — but disappear from Xcode completion
  and DocC. Doc-comments updated to point at the Phase 7 plan.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task C: `final class` explainer comment in template + example

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift:92-125`
- Modify: `examples/HelloWorld/Sources/App/App.swift:5-13`

- [ ] **C.1: Add the comment to the example first**

  Edit `examples/HelloWorld/Sources/App/App.swift`. Replace lines 5-13:

  ```swift
  /// Phase 3 Hello World — a Component with @State.
  ///
  /// Compared to Phase 2a:
  /// - State lives on the Component (was a global `var`).
  /// - No explicit Swiflow.rerender() call — mutating `@State count`
  ///   schedules a re-render automatically via the RAFScheduler.
  /// - No [weak self] or MainActor.assumeIsolated needed — the framework
  ///   handles all of that inside `.on(_:perform:)`.
  final class Counter: Component {
  ```

  with:

  ```swift
  /// Hello World — a Component with @State.
  ///
  /// `final class` (not `struct`) is required: @State reactivity wires the
  /// owner via Mirror after init, which needs reference semantics. See
  /// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
  /// `final` keyword is optional but matches the framework's expectation
  /// that Components aren't subclassed.
  final class Counter: Component {
  ```

- [ ] **C.2: Mirror the change in the template**

  Edit `Sources/SwiflowCLI/Templates/Templates.swift`. Inside the `rawAppSwift` raw-string literal (lines 92-125), replace the corresponding doc-comment block and `final class` line (lines 97-105) with the same text from C.1, keeping the indentation of the template literal (the literal uses 4-space indentation).

  ```swift
      private static let rawAppSwift: String = #"""
          // Sources/App/App.swift
          import Swiflow
          import SwiflowWeb

          /// Hello World — a Component with @State.
          ///
          /// `final class` (not `struct`) is required: @State reactivity wires the
          /// owner via Mirror after init, which needs reference semantics. See
          /// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
          /// `final` keyword is optional but matches the framework's expectation
          /// that Components aren't subclassed.
          final class Counter: Component {
              @State var count: Int = 0

              var body: VNode {
                  div(.class("container")) {
                      h1("Hello, Swiflow!")
                      p("Count: \(count)")
                      button("Increment", .on(.click) { self.count += 1 })
                  }
              }
          }

          @main
          struct App {
              @MainActor
              static func main() {
                  Swiflow.render(into: "#app") { Counter() }
              }
          }

          """#
  ```

- [ ] **C.3: Run the template byte-equality test**

  Run: `swift test --filter TemplatesTests 2>&1 | tail -10`

  Expected: `TemplatesTests/appSwiftMatchesExample` passes (template and example produce the same string).

  If it fails: indentation drift between template and example. Re-read both files, fix whichever drifted, rerun.

- [ ] **C.4: Run the full suite**

  Run: `swift test 2>&1 | tail -5`

  Expected: full suite still passes.

- [ ] **C.5: Commit Task C**

  ```bash
  git add Sources/SwiflowCLI/Templates/Templates.swift examples/HelloWorld/Sources/App/App.swift
  git commit -m "$(cat <<'EOF'
  docs(template): explain final class requirement on Counter

  Frontend devs coming from React/SwiftUI reach for `struct Counter:
  Component` first. The protocol-conformance error from that doesn't
  explain that @State reactivity needs reference semantics for the
  framework's Mirror-based owner wiring.

  One comment line above `final class Counter: Component`, in both the
  swiflow init template and the HelloWorld example, naming the rationale
  and pointing at Component.swift. Byte-equality test stays green.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task D: Loudify `embed { }` factory contract + DEBUG diagnostic

**Files:**
- Modify: `Sources/Swiflow/DSL/ComponentDSL.swift:1-40`
- Modify: a Diff/Renderer file that owns mount tracking (verify in D.1)
- Add: a test for the diagnostic

- [ ] **D.1: Locate the mount/unmount hooks**

  Before writing the diagnostic, locate where Component instances are first mounted (i.e., where the factory is invoked and the result becomes a live `MountNode`). Grep first:

  ```bash
  grep -rn "factory(" Sources/Swiflow/ Sources/SwiflowWeb/ | head -20
  grep -rn "func mount\|MountNode\b" Sources/Swiflow/ Sources/SwiflowWeb/ | head -20
  ```

  Identify the file + function where a freshly-constructed `Component` instance is first attached to the mount tree. Document the location in this checkbox before proceeding. (Likely `Sources/Swiflow/Diff/Diff.swift` or similar — the Phase 3 reactivity work landed mount logic there.)

- [ ] **D.2: Rewrite the `embed { }` doc-comment to lead with the warning**

  Edit `Sources/Swiflow/DSL/ComponentDSL.swift`. Replace lines 1-29:

  ```swift
  // Sources/Swiflow/DSL/ComponentDSL.swift

  /// Embeds a `Component` in a VNode tree.
  ///
  /// Usage in a parent component's body:
  /// ```swift
  /// div {
  ///     h1("Header")
  ///     embed { Counter() }              // unkeyed
  ///     embed("row-\(id)") { Row(id) }   // keyed; survives reorder
  /// }
  /// ```
  ///
  /// The `factory` closure is invoked at first mount only. Subsequent renders
  /// that produce an equal `ComponentDescription` at the same child position
  /// reuse the existing instance (so `@State` survives re-renders) — see
  /// `ComponentDescription` for the typeID+key identity rules.
  ///
  /// - Warning: The factory closure must allocate a **fresh** instance every
  ///   call — `{ Counter() }`, not `{ self.existingCounter }`. Passing an
  ///   existing instance defeats the per-position reuse logic and produces
  ///   undefined `@State` lifecycle behaviour: the Mirror-based owner wiring
  ///   runs against whatever component the framework instantiates here, not
  ///   whatever instance the closure happens to return on a subsequent call.
  public func embed<C: Component>(
      _ factory: @escaping () -> C
  ) -> VNode {
      .component(ComponentDescription(C.self, key: nil, factory: factory))
  }
  ```

  with:

  ```swift
  // Sources/Swiflow/DSL/ComponentDSL.swift

  /// Embeds a `Component` in a VNode tree.
  ///
  /// > ⚠️ **Factory contract:** the `factory` closure MUST allocate a fresh
  /// > instance on every call — write `{ Counter() }`, never
  /// > `{ self.existingCounter }`. Returning a previously-mounted instance
  /// > corrupts `@State` lifecycle: the Mirror-based owner wiring re-runs
  /// > against the framework's idea of "this slot's component", not the
  /// > instance the closure happens to return. DEBUG builds catch this with
  /// > a `swiflowDiagnostic`.
  ///
  /// Usage in a parent component's body:
  /// ```swift
  /// div {
  ///     h1("Header")
  ///     embed { Counter() }              // unkeyed
  ///     embed("row-\(id)") { Row(id) }   // keyed; survives reorder
  /// }
  /// ```
  ///
  /// The framework invokes `factory` only on first mount of a given
  /// `(typeID, key)` position. Subsequent renders at the same position
  /// reuse the existing instance — that's how `@State` survives re-renders.
  /// See `ComponentDescription` for the typeID+key identity rules.
  public func embed<C: Component>(
      _ factory: @escaping () -> C
  ) -> VNode {
      .component(ComponentDescription(C.self, key: nil, factory: factory))
  }
  ```

  Update the keyed overload's doc similarly (lines 31-39) — keep its inheritance reference to the unkeyed warning but mention the leading ⚠️ block.

- [ ] **D.3: Write the DEBUG-only diagnostic test first**

  Add to `Tests/SwiflowTests/DSL/ComponentDSLTests.swift` (or create if missing). The test:

  ```swift
  import Testing
  @testable import Swiflow
  @testable import SwiflowWeb  // or wherever the Renderer/mount layer lives

  @Suite("embed { } reused-instance diagnostic")
  struct EmbedReusedInstanceTests {

      // Guarded #if DEBUG because the diagnostic compiles out in release.
      #if DEBUG
      @Test("swiflowDiagnostic fires when a factory returns an already-mounted Component instance")
      @MainActor
      func diagnosticFiresOnReuse() async throws {
          // 1. Build a parent that holds a single Counter() and returns
          //    the SAME instance from both child-position factories.
          //    Wire it through the renderer's mount path.
          // 2. Assert that swiflowDiagnostic was invoked exactly once with
          //    a message that contains "embed".
          //
          // The exact harness depends on how swiflowDiagnostic is observable
          // in tests (it likely already has a test-side override hook from
          // Phase 4 — see Sources/Swiflow/Diagnostics/ for the entry point).
          // Plug into that hook; do not call swiflowDiagnostic directly.
          //
          // If the existing diagnostic system has no test hook, add one as
          // part of this task: a thread-local recorded-messages array set
          // before the test and asserted afterward.
          Issue.record("Implementer: fill this in once the mount/unmount hook from D.1 is identified.")
      }
      #endif
  }
  ```

  Run: `swift test --filter EmbedReusedInstanceTests 2>&1 | tail -10`

  Expected: the placeholder `Issue.record` fails — that's intentional, this is a TDD-style step that drives the implementer to wire the real test.

- [ ] **D.4: Implement the reused-instance check**

  In the mount-layer file identified in D.1, add:

  ```swift
  // DEBUG-only set of currently-mounted Component instance IDs, indexed
  // by ObjectIdentifier. Detects the embed { self.existingCounter }
  // footgun documented in Sources/Swiflow/DSL/ComponentDSL.swift.
  // Compiled out in release builds.
  #if DEBUG
  @MainActor
  private var swiflowMountedInstanceIDs: Set<ObjectIdentifier> = []
  #endif
  ```

  In the function that invokes `ComponentDescription.factory()` and adds the resulting instance to a `MountNode`, add (immediately after the factory call):

  ```swift
  #if DEBUG
  let oid = ObjectIdentifier(instance)
  if swiflowMountedInstanceIDs.contains(oid) {
      swiflowDiagnostic("embed { } factory returned an already-mounted Component instance. Factories must allocate a fresh instance per call — `{ Counter() }`, not `{ self.existingCounter }`. See Sources/Swiflow/DSL/ComponentDSL.swift for the factory contract.")
  } else {
      swiflowMountedInstanceIDs.insert(oid)
  }
  #endif
  ```

  In the unmount-equivalent path (where a `MountNode` for a Component is destroyed), add:

  ```swift
  #if DEBUG
  swiflowMountedInstanceIDs.remove(ObjectIdentifier(instance))
  #endif
  ```

  Names (`instance`, the function names) must match what's actually in the codebase per D.1. Adjust accordingly.

- [ ] **D.5: Wire the test's diagnostic recording hook**

  Replace the placeholder body in `EmbedReusedInstanceTests.diagnosticFiresOnReuse` with a real test that:

  1. Captures diagnostic messages via whatever hook the diagnostic system exposes (Phase 4 introduced `swiflowDiagnostic` — locate the hook by `grep -rn "swiflowDiagnostic" Sources/Swiflow/Diagnostics/`).
  2. Sets up a parent Component that returns the same Counter() instance from two embed sites.
  3. Renders, asserts the diagnostic was called with a message containing `"embed"`.
  4. Tears down cleanly (unmounts both, resets the diagnostic hook).

- [ ] **D.6: Run the full suite**

  Run: `swift test 2>&1 | tail -10`

  Expected: full suite passes, including the new diagnostic test.

- [ ] **D.7: Commit Task D**

  ```bash
  git add Sources/Swiflow/DSL/ComponentDSL.swift <mount-layer-file> Tests/SwiflowTests/DSL/ComponentDSLTests.swift
  git commit -m "$(cat <<'EOF'
  feat(dsl): loud embed { } factory contract + DEBUG reused-instance diagnostic

  The embed { } factory contract — "must allocate a fresh instance per
  call" — was documented as a mid-paragraph Warning. Frontend devs miss
  it because the doc-block looks routine. Promote the warning to a
  leading > ⚠️ block so it's the first thing anyone reads.

  Back the doc-warning with a DEBUG-only runtime check: track
  ObjectIdentifier of every currently-mounted Component instance; if a
  factory returns an instance that's already in the set, fire
  swiflowDiagnostic with a message that names the footgun and points at
  ComponentDSL.swift. Compiled to nothing in release.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task E: README "Current State" section + status bump

**Files:**
- Modify: `README.md`

- [ ] **E.1: Measure the WASM bundle size**

  From the repo root:

  ```bash
  cd examples/HelloWorld
  swift package clean
  swift package --swift-sdk swift-6.3-RELEASE_wasm js -c release 2>&1 | tail -5
  ls -lah .build/plugins/PackageToJS/outputs/Package/*.wasm
  cd ../..
  ```

  Record the `.wasm` size in KB. Also note total JS+WASM payload:

  ```bash
  du -sh examples/HelloWorld/.build/plugins/PackageToJS/outputs/Package/
  ```

- [ ] **E.2: Measure cold-build time**

  From `examples/HelloWorld/`:

  ```bash
  swift package clean
  time swift package --swift-sdk swift-6.3-RELEASE_wasm js -c release 2>&1 | tail -3
  ```

  Record real time.

- [ ] **E.3: Measure hot-build time**

  Without a clean:

  ```bash
  touch Sources/App/App.swift
  time swift package --swift-sdk swift-6.3-RELEASE_wasm js -c release 2>&1 | tail -3
  ```

  Record real time.

- [ ] **E.4: Insert the Current State section**

  Edit `README.md`. Immediately after line 8 (the "Swiflow batches all DOM mutations…" paragraph) and BEFORE the existing `**Status:** …` line, insert:

  ```markdown
  ## Current State

  Swiflow is **pre-1.0**. The DX uplift plan
  ([master plan](docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md))
  drives the roadmap to 1.0 across phases 6 through 13.

  **What works today (Phase 6):**
  - Reactive Components with `@State` and the typed `Event` DSL —
    `.on(.click) { self.count += 1 }`.
  - `URLSanitizer`-protected DSL fold (XSS-safe by default).
  - `swiflow init` scaffold + `swiflow build` (WASM SDK auto-probe) +
    `swiflow dev` (file-watch + full-page reload).
  - 281+ tests, Playwright e2e, DWARF debugging guide.

  **What's not in the box yet:**
  - **HMR** (instant save→pixels) — Phase 8. Today's dev loop is a full
    page reload on every save; state is lost.
  - **Two-way input binding** `input(.value($text))` — Phase 7.
  - **Refs** `Ref<Element>` — Phase 7.
  - **Component inspector / devtools** — Phase 9.
  - **`@Environment` / context DI** — Phase 10.
  - **Router** (`SwiflowRouter`) — Phase 11.
  - **Scoped CSS, animation primitives, form validation** — Phase 12.
  - **Multi-root rendering, lazy components, component testing harness,
    macro diagnostics** — Phase 13.

  **Costs you should know:**
  - **WASM bundle (Counter example, release):** ~`<MEASURED>` KB
    (`.wasm` only); ~`<MEASURED>` KB total payload with the JS runtime.
    Order-of-magnitude larger than a Vite-built JS app — that's the
    Swift-on-WASM tax.
  - **Cold build:** ~`<MEASURED>` seconds (`swift package clean` then
    `swift package --swift-sdk <wasm-sdk> js -c release`).
  - **Hot rebuild (single source touched):** ~`<MEASURED>` seconds.
    Phase 8's HMR will replace the full reload with a hot module swap
    that preserves `@State`.

  Measurements taken on `<MACHINE>` with Swift 6.3 / WASM SDK 6.3. Run
  the same commands locally to calibrate for your hardware.
  ```

  Replace `<MEASURED>` and `<MACHINE>` with the actual numbers from E.1-E.3.

- [ ] **E.5: Defer the status-line bump**

  Leave the `**Status:** Phase 5 (API Polish) complete...` line as-is for now. The final task (G) bumps it to Phase 6 after all other tasks have landed.

- [ ] **E.6: Commit Task E**

  ```bash
  git add README.md
  git commit -m "$(cat <<'EOF'
  docs(readme): add honest Current State section with measured costs

  Frontend engineers calibrated by Vite need to know the real cost of
  Swift-on-WASM up front. Hiding bundle size and build time makes them
  quit after the first save→reload cycle.

  Add a "Current State" section after the intro covering what ships in
  Phase 6, what doesn't yet (with phase numbers), and measured WASM
  bundle size + cold/hot build time on a typical machine. Link to the
  DX uplift master plan.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task F: Commit superseded plan drafts

**Files:**
- New: `docs/superpowers/plans/2026-05-17-swiflow-phase2b-cli.md`
- New: `docs/superpowers/plans/2026-05-18-swiflow-phase2b3-cosmetics-cleanup.md`
- New: `docs/superpowers/plans/2026-05-18-swiflow-phase2c-dev-server.md`
- New: `docs/superpowers/plans/2026-05-18-swiflow-phase3-reactivity.md`

These four files are untracked drafts; the work they describe has already shipped (see commits `f422241..ac0f88b`, `4b962b3`, `f3ce9ca`, Phase 3 reactivity commits, Phase 5 commits). Commit them as-is for the audit trail.

- [ ] **F.1: Verify the four files are exactly what was drafted**

  Run: `git status docs/superpowers/plans/ 2>&1 | head -20`

  Expected: four `??` untracked entries matching the filenames above. No staged changes.

- [ ] **F.2: Verify there's also `docs/compare/` untracked**

  Run: `git status docs/compare/ 2>&1 | head`

  If `docs/compare/` is untracked too, that's a separate set of files — verify they're intentional research artifacts before committing. If they look stale, ask before deleting.

- [ ] **F.3: Stage and commit the four plan drafts**

  ```bash
  git add docs/superpowers/plans/2026-05-17-swiflow-phase2b-cli.md \
          docs/superpowers/plans/2026-05-18-swiflow-phase2b3-cosmetics-cleanup.md \
          docs/superpowers/plans/2026-05-18-swiflow-phase2c-dev-server.md \
          docs/superpowers/plans/2026-05-18-swiflow-phase3-reactivity.md
  git commit -m "$(cat <<'EOF'
  chore(plans): commit superseded Phase 2b/2c/3 drafts for archival

  These four implementation plans were drafted while Phases 2b, 2c, and 3
  were in flight. The work they describe has since landed in main; the
  files have lingered as untracked drafts. Commit them as-is so the audit
  trail survives — no edits.

  Phase 6 (current) supersedes these; see
  docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md for
  the active roadmap.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task G: Final test pass + Phase 6 ship

**Files:**
- Modify: `README.md` (status line)
- Push to origin/main

- [ ] **G.1: Run the full test suite one more time**

  Run: `swift test 2>&1 | tail -10`

  Expected: full suite passes; test count is Phase-5-baseline (281) + Phase 6's added tests (target +5 to +8).

- [ ] **G.2: Run `swift build` cleanly**

  Run: `swift build 2>&1 | tail -5`

  Expected: build succeeds with no warnings introduced by Phase 6.

- [ ] **G.3: Verify `swiflow init` still produces a working scaffold**

  ```bash
  rm -rf /tmp/phase6-smoketest
  ./.build/debug/swiflow init phase6-smoketest --swiflow-source "$(pwd)" --output /tmp
  cd /tmp/phase6-smoketest
  swift build 2>&1 | tail -5
  cd -
  ```

  Expected: scaffold builds cleanly. (Full WASM build is too slow for the smoke test; `swift build` on the host target catches Swift-source-level breakage.)

- [ ] **G.4: Bump the README status line**

  Edit `README.md`. Replace:

  ```
  **Status:** Phase 5 (API Polish) complete. The framework is feature-complete
  through Phase 3 (Component + `@State` reactivity + RAFScheduler), hardened
  in Phase 4 (URL sanitizer, debug diagnostics, DWARF guide, JS-driver units,
  Playwright e2e), and polished in Phase 5 — `@MainActor` Component, typed
  `Event` enum, `.on(.click) { … }` handler API, `embed { … }`, factory-based
  `Swiflow.render(into:) { Counter() }`, postfix VNode modifiers.
  ```

  with:

  ```
  **Status:** Phase 6 (Trust & Polish) complete. Phase 5's API surface is
  intact; Phase 6 closed the credibility-erosion punch list — `attr(_:_:Bool)`
  now omits the attribute on `false`, `Binding<Value>` is hidden from
  autocomplete until Phase 7 ships its consumer, the `final class` template
  carries a one-line rationale, the `embed { }` factory contract is loud
  (with a DEBUG diagnostic), the README carries an honest Current State
  section, and superseded plan drafts are archived.
  ```

- [ ] **G.5: Commit the status bump**

  ```bash
  git add README.md
  git commit -m "$(cat <<'EOF'
  docs(readme): bump status to Phase 6 (Trust & Polish) complete

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **G.6: Push Phase 6 to origin/main**

  Per the project convention (one branch, push to origin/main directly):

  ```bash
  git push origin main
  ```

  Expected: clean push, no upstream divergence (rebase first if `git push` reports non-fast-forward).

- [ ] **G.7: Update memory with any new conventions learned**

  If Phase 6 surfaced a non-obvious project convention worth persisting, add a memory entry per the `using-superpowers` skill's memory guidance. Candidates:

  - `@_documentation(visibility: internal)` as the canonical way to hide a future-public symbol pre-1.0.
  - The `Attribute.skip` sentinel pattern for "drop me at fold time" — if it gets used elsewhere.

  Otherwise, skip this step.

---

## Verification

After all tasks land:

```bash
swift test 2>&1 | tail -5
# Expected: full suite passes; test count = 281 (Phase 5) + Phase 6 added tests.
```

Manual spot-check:

```bash
# 1. attr(_:_:Bool) on false now omits the attribute
swift -e 'import Swiflow; if case .element(let d) = button("X", .attr("disabled", false)) { print(d.attributes["disabled"] as Any) }'
# Expected: nil

# 2. Binding still compiles where Phase 7 needs it, but doesn't autocomplete
swift -e 'import Swiflow; let s = State<Int>(wrappedValue: 0); _ = s.projectedValue'
# Expected: compiles cleanly, no warning

# 3. README renders with the Current State section
grep -n "Current State" README.md
# Expected: matches "## Current State"
```

Browser smoke:

```bash
./.build/debug/swiflow dev
# Open http://localhost:3000 — the Counter increments. `@State` is still
# dropped on save (that's Phase 8), but the rest works.
```

---

## Out of Scope

Deferred to later phases per the master plan:

- HMR / module hot-swap → Phase 8.
- Binding DSL consumer (`.value($text)`, `.checked($flag)`, `.selection($choice)`) → Phase 7.
- `Ref<Element>` → Phase 7.
- Component inspector → Phase 9.
- `Swiflow.render(into:)` single-root precondition removal → Phase 13.
- Macro-driven `@ChildrenBuilder` diagnostics → Phase 13.

---

## Self-Review

- **Spec coverage:** Task A covers spec §1 (`.attr` no-op). Task B covers §2 (Binding hide). Task C covers §3 (`final class` comment). Task D covers §4 (loudify `embed { }` + DEBUG diagnostic). Task E covers §5 (README Current State). Task F covers §6 (garbage-collect superseded drafts). Task G ships.
- **Placeholder scan:** Task D Step 1 ("locate the mount/unmount hooks") explicitly defers the file path until the implementer greps — that's a deliberate placeholder; the surrounding steps name the work concretely.
- **Type consistency:** `Attribute.skip` (Task A) is referenced consistently in both the enum definition and the fold step. `@_documentation(visibility: internal)` (Task B) is applied to both `Binding<Value>` and `State.projectedValue`. The `final class` doc text (Task C) is identical between template and example.
