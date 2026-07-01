# `@Component` auto-injects `@MainActor` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a bare `@Component final class` main-actor isolated so users no longer write `@MainActor @Component`, then remove the now-redundant annotation across templates/examples/Sources.

**Architecture:** Add a third macro role (`@attached(memberAttribute)`) to `ComponentMacro` that stamps `@MainActor` onto user members (mirroring `@Query`/`@Mutation`'s `MainActorWitnessIsolation`, but isolating *all* members since a component is a main-actor reference type). Make the member-macro-synthesized decls (`bind`/`init`/storage) carry `@MainActor` when — and only when — the type isn't already explicitly isolated, preserving byte-identical expansion for existing `@MainActor @Component` code. Then sweep the redundant annotations.

**Tech Stack:** Swift 6.3, SwiftSyntax macros (`MemberAttributeMacro`), `assertMacroExpansion` golden tests, `swift build`/`swift test`, `swiflow build` (wasm).

## Global Constraints

- **Swift 6.3.2** toolchain; CI keys on `Package.swift`, skips example builds — so example/wasm builds must be run **locally**.
- **Byte-identical guarantee:** a class that already declares `@MainActor` must expand exactly as it does today (no new attributes anywhere in its expansion).
- **Golden test convention:** `assertMacroExpansion` is whitespace-exact. Write the test, run it, and paste the compiler's *actual* expanded output back as `expectedSource` (run-then-paste). Do NOT hand-guess attribute placement.
- **Authoritative gate:** golden tests diverge from the real compiler in both directions — a full host `swift build` + `swift test` is the real proof, plus a `swiflow build` wasm compile of a swept example.
- `@MainActor`-detection is **by attribute name** (`"MainActor"`); custom global actors (`@SomeActor`) are not auto-detected (documented limitation — such a user keeps writing their actor explicitly and adds `nonisolated`/`@MainActor` per member as needed).
- Commit messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: Auto-inject `@MainActor` in `ComponentMacro`

**Files:**
- Create: `Sources/SwiflowMacrosPlugin/ComponentIsolation.swift`
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` (add `MemberAttributeMacro` conformance; make synthesized `bind`/`init`/storage conditionally `@MainActor`)
- Modify: `Sources/Swiflow/Macros.swift:10-18` (add `@attached(memberAttribute)`)
- Test: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` (new cases + refresh existing goldens)
- Test (refresh only): `Tests/SwiflowMacrosTests/ComponentAutoInitTests.swift`, `ComponentMacroMutationTests.swift`, `ComponentMacroReducerTests.swift`

**Interfaces:**
- Consumes: existing `ComponentMacro: ExtensionMacro, MemberMacro`; the `access` keyword string from `SynthesizedAccess.keyword(for:)`.
- Produces:
  - `enum ComponentIsolation { static func attributes(for: some DeclSyntaxProtocol) -> [AttributeSyntax]; static func hasMainActorAttribute(_: AttributeListSyntax) -> Bool }`
  - `ComponentMacro` now also conforms to `MemberAttributeMacro`.

- [ ] **Step 1: Write the `ComponentIsolation` unit-ish golden test first (new behavior)**

Add to `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` a new test. Start from this *approximate* expected block; you will correct it in Step 4 via run-then-paste.

```swift
// Test: bare @Component auto-injects @MainActor onto user + synthesized members.
func testAutoInjectsMainActorOnBareComponent() {
    assertMacroExpansion(
        """
        @Component
        final class Counter {
            @State var count: Int = 0
            var body: VNode { .text("hi") }
            func bump() { count += 1 }
            nonisolated func pure() {}
            struct Nested {}
            typealias ID = Int
            static let tag = "c"
        }
        """,
        expandedSource: """
        final class Counter {
            @MainActor @State var count: Int = 0
            @MainActor var body: VNode { .text("hi") }
            @MainActor func bump() { count += 1 }
            nonisolated func pure() {}
            struct Nested {}
            typealias ID = Int
            @MainActor static let tag = "c"

            @MainActor private weak var runtimeOwner: AnyComponent?

            @MainActor private var runtimeScheduler: Scheduler?

            @MainActor static let stateCells: [any AnyStateCell] = [
            ]

            @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                self.runtimeOwner = owner
                self.runtimeScheduler = scheduler
            }
        }

        extension Counter: Component, _ComponentRuntime {
        }
        """,
        macros: testMacros
    )
}
```

- [ ] **Step 2: Run it to confirm it fails (role not added yet)**

Run: `swift test --filter ComponentMacroTests/testAutoInjectsMainActorOnBareComponent 2>&1 | tail -30`
Expected: FAIL — the expansion has no `@MainActor` on user members (role doesn't exist yet), and `stateCells` shows the real `StateCell<Counter>` body rather than the `[]` stub above.

- [ ] **Step 3: Create `ComponentIsolation.swift`**

```swift
// Sources/SwiflowMacrosPlugin/ComponentIsolation.swift
import SwiftSyntax
import SwiftSyntaxMacros

/// `@attached(memberAttribute)` logic for `@Component`.
///
/// `Component`/`_ComponentRuntime` are `@MainActor` protocols, but Swift does
/// NOT infer a protocol's global actor onto the primary type when conformance
/// is added by a generated extension (see `MainActorWitnessIsolation` for the
/// same problem in `@Query`/`@Mutation`). So `@Component` stamps `@MainActor`
/// onto the component's members itself — making a bare `@Component final class`
/// isolation-equivalent to `@MainActor @Component final class`.
///
/// Unlike `@Query`/`@Mutation` (value types crossing actors → witness-subset
/// isolation), a component is an inherently main-actor reference type, so ALL
/// members are isolated — faithfully mirroring `@MainActor class`.
enum ComponentIsolation {
    /// The attributes to add to one member. Skips what `@MainActor class` also
    /// leaves un-isolated (nested types, typealiases, deinit) and anything the
    /// author already isolated or opted out of with `nonisolated`.
    static func attributes(for member: some DeclSyntaxProtocol) -> [AttributeSyntax] {
        if member.is(StructDeclSyntax.self) || member.is(ClassDeclSyntax.self)
            || member.is(EnumDeclSyntax.self) || member.is(ActorDeclSyntax.self)
            || member.is(TypeAliasDeclSyntax.self) || member.is(DeinitializerDeclSyntax.self) {
            return []
        }
        if memberHasIsolation(member) { return [] }
        return ["@MainActor"]
    }

    /// True when the class carries an explicit `@MainActor` (detected by name).
    /// Used to skip auto-injection entirely so existing `@MainActor @Component`
    /// code expands byte-identically.
    static func hasMainActorAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attr) = element else { return false }
            return attr.attributeName.trimmedDescription == "MainActor"
        }
    }

    private static func memberHasIsolation(_ member: some DeclSyntaxProtocol) -> Bool {
        if let mods = member.asProtocol(WithModifiersSyntax.self)?.modifiers,
           mods.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) {
            return true
        }
        if let attrs = member.asProtocol(WithAttributesSyntax.self)?.attributes {
            return hasMainActorAttribute(attrs)
        }
        return false
    }
}
```

- [ ] **Step 4: Add the `MemberAttributeMacro` conformance to `ComponentMacro.swift`**

Append at the end of `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` (after the existing `extension`s / helpers):

```swift
extension ComponentMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self),
              classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            return []   // non-final / non-class: diagnosed by the other roles
        }
        // Whole-type skip: an explicitly-isolated component keeps today's exact
        // expansion (and avoids a redundant-attribute diagnostic).
        if ComponentIsolation.hasMainActorAttribute(classDecl.attributes) { return [] }
        return ComponentIsolation.attributes(for: member)
    }
}
```

- [ ] **Step 5: Make synthesized `bind`/`init`/storage conditionally `@MainActor`**

In `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`, inside the `MemberMacro` `expansion(...)`, right after `let access = SynthesizedAccess.keyword(for: classDecl.modifiers)`, add:

```swift
        // When the type is NOT already @MainActor, the memberAttribute role will
        // stamp user members — but it never sees these SYNTHESIZED members, so
        // they must isolate themselves. When the type already has @MainActor, emit
        // nothing extra (byte-identical to today; `stateCells` keeps its own
        // @MainActor as it does now).
        let synthActor = ComponentIsolation.hasMainActorAttribute(classDecl.attributes) ? "" : "@MainActor "
```

Then prefix `\(synthActor)` onto the synthesized `bind`, `init`, and the two runtime storage props:

- `bindDecl`: change to
  `DeclSyntax(stringLiteral: "\(synthActor)\(access)func bind(owner: AnyComponent, scheduler: Scheduler) {\n    \(bindBody)\n}")`
- `synthesizedInit`: change to
  `DeclSyntax(stringLiteral: "\(synthActor)\(access)init() {\n\(assignments)\n}")`
- storage lines in the `emitted` array: change to
  `"\(synthActor)private weak var runtimeOwner: AnyComponent?"` and
  `"\(synthActor)private var runtimeScheduler: Scheduler?"`

Leave `stateCellsDecl` unchanged (it already emits `@MainActor`, matching today for both branches).

- [ ] **Step 6: Add the macro role to the declaration**

In `Sources/Swiflow/Macros.swift`, add `@attached(memberAttribute)` to the `Component` macro (between the `@attached(member, ...)` block on line 11-17 and the `public macro Component()` on line 18):

```swift
@attached(memberAttribute)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")
```

- [ ] **Step 7: Run the new test and paste the real expansion**

Run: `swift test --filter ComponentMacroTests/testAutoInjectsMainActorOnBareComponent 2>&1 | tail -40`
It will fail on whitespace/exact `stateCells` body. Copy the actual expanded source from the failure diff into the test's `expandedSource` verbatim, then re-run.
Expected after paste: PASS. Verify in the pasted output that `@State var count`, `var body`, `func bump` carry `@MainActor`; `nonisolated func pure`, `struct Nested`, `typealias ID` do NOT; `static let tag`, `runtimeOwner`, `runtimeScheduler`, `bind` carry `@MainActor`.

- [ ] **Step 8: Add the byte-identical skip test (`@MainActor @Component`)**

Add a second test proving explicit `@MainActor` skips auto-injection. Use the CURRENT `testHappyPath` expected body but with `@MainActor` on the class line and NO added attributes on user/synthesized members:

```swift
// Test: an explicit @MainActor @Component skips auto-injection (byte-identical).
func testExplicitMainActorSkipsAutoInjection() {
    assertMacroExpansion(
        """
        @MainActor
        @Component
        final class Counter {
            @State var count: Int = 0
            var body: VNode { .text("hello") }
        }
        """,
        expandedSource: """
        <PASTE ACTUAL — expect: user members unchanged; runtimeOwner/runtimeScheduler/bind WITHOUT @MainActor; stateCells WITH @MainActor>
        """,
        macros: testMacros
    )
}
```

Run: `swift test --filter ComponentMacroTests/testExplicitMainActorSkipsAutoInjection 2>&1 | tail -40`, paste the real output, re-run to PASS. Confirm the member bodies match today's `testHappyPath` output shifted by the `@MainActor` class line (i.e. no `@MainActor` was added to `bind`/storage/user members).

- [ ] **Step 9: Refresh all existing goldens broken by the new behavior**

The existing golden tests feed **bare** `@Component`, so their expansions now gain `@MainActor` stamps. Run the whole macro suite:

Run: `swift test --filter SwiflowMacrosTests 2>&1 | tail -60`
For each failing `assertMacroExpansion`, paste the compiler's new expanded output into that test's `expandedSource`. Files to expect failures in: `ComponentMacroTests.swift` (incl. `testHappyPath`), `ComponentAutoInitTests.swift`, `ComponentMacroMutationTests.swift`, `ComponentMacroReducerTests.swift`.

**Critical:** `ComponentMacroReducerTests.swift` (~line 64) copies `ComponentMacroTests.testHappyPath`'s expansion *verbatim* ("verbatim from ComponentMacroTests.testHappyPath" comment). Update BOTH to the identical new output so they stay in sync.

- [ ] **Step 10: Full macro suite green**

Run: `swift test --filter SwiflowMacrosTests 2>&1 | tail -15`
Expected: all pass.

- [ ] **Step 11: Full host build + test (authoritative)**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -20`
Expected: build succeeds; full suite passes. (Sources/** still carry `@MainActor @Component` at this point, so they hit the skip path and are unaffected — this proves the change is non-breaking before the sweep.)

- [ ] **Step 12: Commit**

```bash
git add Sources/SwiflowMacrosPlugin/ComponentIsolation.swift \
        Sources/SwiflowMacrosPlugin/ComponentMacro.swift \
        Sources/Swiflow/Macros.swift \
        Tests/SwiflowMacrosTests/
git commit -m "feat(reactivity): @Component auto-injects @MainActor via memberAttribute role

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Sweep the redundant `@MainActor` annotations

**Files:**
- Modify: every `Sources/**` and `examples/**` file with `@MainActor @Component` (same-line) — enumerated by the grep below.
- Regenerate: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (via `swift scripts/embed-templates.swift`)

**Interfaces:**
- Consumes: Task 1's auto-injection (bare `@Component` now compiles isolated).
- Produces: no API surface — a source-hygiene sweep. Must keep `swift build` + wasm builds green.

- [ ] **Step 1: List the sweep targets**

Run: `grep -rln "@MainActor @Component" Sources examples`
Expected: the SwiflowUI overlay files (`Dropdown`/`Alert`/`Tooltip`/`DataTable`/`Prompt`/`Autocomplete`/`Toast`), `SwiflowRouter/Web/RouterRoot.swift`, and the `@Component` classes across `examples/**`.
**Exclude non-declarations:** `Sources/Swiflow/Macros.swift`, `Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift`, and `Sources/SwiflowCLI/EmbeddedTemplates.swift` mention `@MainActor @Component` only in **doc comments / generated code** — do NOT hand-edit them (EmbeddedTemplates is regenerated in Step 4).

- [ ] **Step 2: Rewrite `@MainActor @Component` → `@Component` in real declarations**

For each target file from Step 1 (excluding the three above), replace the same-line `@MainActor @Component` with `@Component`. Verify none used a two-line form:
Run: `grep -rn -B1 "^\s*@Component" Sources examples | grep "@MainActor"`
Expected: no output (all were same-line; confirmed during planning).

- [ ] **Step 3: Build host to prove the sweep is isolation-safe**

Run: `swift build 2>&1 | tail -20`
Expected: success. If a specific file fails (e.g. it has a `deinit` touching main-actor state — which auto-injection intentionally skips), restore `@MainActor` on THAT file only (it then hits the whole-type-skip path) and note it in the commit.

- [ ] **Step 4: Regenerate embedded templates**

The `swiflow new` scaffold is generated from `examples/**`, so the sweep must flow into the embedded copy.

Run: `swift scripts/embed-templates.swift`
Then confirm the generated file reflects the sweep:
Run: `grep -c "@MainActor @Component" Sources/SwiflowCLI/EmbeddedTemplates.swift`
Expected: `0`.

- [ ] **Step 5: Rebuild host after regen (embed-freshness)**

Run: `swift build 2>&1 | tail -10`
Expected: success (EmbeddedTemplates.swift compiles; the `embed-freshness` CI gate will also check byte-freshness).

- [ ] **Step 6: Verify a swept example still builds to wasm**

Run: `swift build -c release --product swiflow 2>&1 | tail -5 && ./.build/release/swiflow build --path examples/SwiflowUIDemo 2>&1 | tail -20`
Expected: wasm build succeeds — proves `wasm32` isolation holds for a swept example using SwiflowUI overlays + app components.
Then revert the build-rewritten driver/SW copies (they are not part of this change):
Run: `git checkout -- 'examples/**/swiflow-driver.js' 'examples/**/swiflow-service-worker.js' 2>/dev/null; git status --short examples | head`

- [ ] **Step 7: Full test suite green after sweep**

Run: `swift test 2>&1 | tail -15`
Expected: all pass (behavior unchanged; pure isolation-source hygiene).

- [ ] **Step 8: Final sweep verification**

Run: `grep -rn "@MainActor @Component" Sources examples | grep -v "Macros.swift\|SwiflowTaskRuntime.swift\|EmbeddedTemplates.swift"`
Expected: no output (every real declaration is now bare `@Component`; only doc-comment/generated mentions remain, and EmbeddedTemplates was regenerated to 0).

- [ ] **Step 9: Commit**

```bash
git add Sources examples
git commit -m "refactor(reactivity): drop redundant @MainActor from @Component decls

@Component now auto-injects @MainActor; sweep templates/examples/Sources to
the clean bare form and regenerate EmbeddedTemplates.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the final reviewer

- **Behavioral no-op:** this is an isolation/DX change with zero runtime effect. The real proof is `swift build` + `swift test` + one `swiflow build` wasm compile all green — golden tests alone are insufficient (they diverge from the compiler).
- **Backward-compat contract:** `@MainActor @Component` must still expand byte-identically (Task 1 Step 8) so no downstream user is forced to change.
- **Escape hatch:** `nonisolated` on a member is the documented opt-out; verify Task 1's `pure()` case proves it.
- **Docs:** update the `@State` doc comment in `Macros.swift:27` ("The host class must be `@MainActor @Component final class`") to reflect that `@MainActor` is now optional — fold this into Task 2 if trivial, else note as a follow-up.
