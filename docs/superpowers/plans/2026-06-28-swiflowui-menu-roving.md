# SwiflowUI roving `role=menu` for Dropdown — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `Dropdown` into a WAI-ARIA roving `role=menu` — `role="menu"`/`menuitem`, real-focus roving tabindex (↑/↓ wrap, Home/End), native focus-on-open via `autofocus`, Tab-to-close — with disabled items rendered `inert`, all without any public API or core/framework change.

**Architecture:** All logic stays in `Sources/SwiflowUI/Dropdown.swift`. `DropdownItem` keeps its API but renders disabled buttons with `inert` instead of `disabled`. `DropdownMenu.body` post-processes the built item nodes (the menu is the only unit that knows item order/count): it injects `role="menuitem"`, `tabindex="-1"`, a stable id, `autofocus` on the first enabled item, and a keydown roving handler on each enabled item. Focus movement is imperative DOM (`getElementById(...).focus()`), `#if canImport(JavaScriptKit)`-guarded exactly like `Autocomplete`. Open/dismiss/focus-return stay native (Popover API). No `@State` — DOM focus is the source of truth.

**Tech Stack:** Swift 6.3, SwiflowUI (VNode DSL), native Popover API + CSS Anchor Positioning, JavaScriptKit (browser only), Swift Testing, Playwright.

**Spec:** `docs/superpowers/specs/2026-06-28-swiflowui-menu-roving-design.md`

---

## File Structure

- **Modify** `Sources/SwiflowUI/Dropdown.swift` — JS import; `DropdownItem` disabled→`inert`; `DropdownMenu.body` roving assembly + `aria-haspopup="menu"` + menu `role="menu"`; file-local predicates; `rove` keydown; CSS `[inert]`; doc rewrites.
- **Modify** `Tests/SwiflowUITests/DropdownTests.swift` — update the `aria-haspopup` assertion; add roving/role/inert/autofocus/keydown tests.
- **Modify** `examples/SwiflowUIDemo/Sources/App/App.swift` — add a disabled item to the demo dropdown to showcase `inert` + roving-skip.
- **Regenerate** `Sources/SwiflowCLI/EmbeddedTemplates.swift` — `swift scripts/embed-templates.swift` (the freshness gate fails CI otherwise; `examples/*/` is embedded).
- **Create** `Tests/playwright/playwright.swiflowui.config.ts` — in-place build of `examples/SwiflowUIDemo` on :3004 (mirrors `playwright.edgecases.config.ts`; avoids the `.e2e-cache/sw` SourceKit-LSP race).
- **Create** `Tests/playwright/dropdown.spec.ts` — roving focus behavior (browser-only).

---

## Reference facts (verified against current code)

- `Attribute.attr(_ name, _ value: Bool)` and the VNode `.attr(name, Bool)` modifier emit a **presence-only** attribute: `attributes[name] = ""` when `true`, omitted when `false`. So "is inert" ≡ `data.attributes["inert"] != nil` (NOT `== "true"`).
- `.class("x")` and the `.class(_)` VNode modifier write `attributes["class"]`. Item class is `"sw-dropdown__item sw-dropdown__item--<variant> …"`; divider class is `"sw-dropdown__divider"` (does not contain `"sw-dropdown__item"`).
- VNode postfix modifiers exist: `.attr(_:_:)`, `.id(_:)`, and `.on(_:perform:)` (the `(EventInfo) -> Void` overload). `.on` registers into `HandlerAmbient.current` and **traps if no registry is active** — host tests must wrap render in `building { … }` (already the pattern in `DropdownTests.swift`).
- `EventInfo.key` carries `event.key` (`"ArrowDown"`, `"Enter"`, `"Tab"`, …). Marshaled end-to-end already.
- Autocomplete's imperative focus pattern: `JSObject.global.document.object` → `doc.getElementById?(id).object` → `el.focus?()` / `el.scrollIntoView?(…)`, all inside `#if canImport(JavaScriptKit)`.
- Handlers can't `preventDefault` (memory `no-event-preventdefault`) — Enter/Space/Escape are handled **natively** (button activation + `popovertargetaction="hide"` + popover light-dismiss), not in our keydown handler.

---

## Task 1: Disabled `DropdownItem` renders `inert`, styled via `[inert]`

**Files:**
- Modify: `Sources/SwiflowUI/Dropdown.swift` (the `disabled` branch in `DropdownItem`, ~line 147; CSS rules ~lines 239 & 245)
- Test: `Tests/SwiflowUITests/DropdownTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `struct DropdownTests` in `Tests/SwiflowUITests/DropdownTests.swift`:

```swift
    @Test("disabled item renders inert (not the disabled attribute), with no action/close") func disabledIsInert() {
        let node = building {
            dd { [DropdownItem("Edit") {}, DropdownItem("Archive", disabled: true) {}] }
        }
        let root = el(node)!
        let menu = firstWithClass(root, "sw-dropdown__menu")!
        // The disabled item is the one whose label is "Archive".
        let archive = menu.children.compactMap(el).first { allText(.element($0)).contains("Archive") }!
        #expect(archive.attributes["inert"] == "")          // presence-only boolean attribute
        #expect(archive.attributes["disabled"] == nil)      // no longer uses the disabled attribute
        #expect(archive.handlers["click"] == nil)           // no action
        #expect(archive.attributes["popovertarget"] == nil) // no close-on-select
    }
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter DropdownTests/disabledIsInert`
Expected: FAIL — `archive.attributes["inert"]` is `nil` (current code emits `disabled`).

- [ ] **Step 3: Switch the disabled branch to `inert`**

In `Sources/SwiflowUI/Dropdown.swift`, change the `disabled` branch of `DropdownItem`:

```swift
    var attrs: [Attribute] = [.class(cls), .attr("type", "button")]
    if disabled {
        attrs.append(.attr("inert", true))   // not focusable, removed from the a11y tree; no action/close
    } else {
        attrs.append(.on(.click, perform: action))
        // Close the menu on select (declarative), when rendered inside a Dropdown.
        if let menuID = DropdownAmbient.currentMenuID {
            attrs.append(.attr("popovertarget", menuID))
            attrs.append(.attr("popovertargetaction", "hide"))
        }
    }
    attrs += callerRest
    return element("button", attributes: attrs, children: [text(label)])
```

- [ ] **Step 4: Update the CSS to target `[inert]` instead of `:disabled`**

In `dropdownStyleSheet`, replace the two `:disabled` rules:

```css
    .sw-dropdown__item:hover:not([inert]) { background-color: var(--sw-surface-2); }
```

```css
    .sw-dropdown__item[inert] { opacity: var(--sw-disabled-opacity); cursor: not-allowed; }
```

(These replace `.sw-dropdown__item:hover:not(:disabled)` and `.sw-dropdown__item:disabled` respectively.)

- [ ] **Step 5: Run the test and confirm it passes**

Run: `swift test --filter DropdownTests/disabledIsInert`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/Dropdown.swift Tests/SwiflowUITests/DropdownTests.swift
git commit -m "feat(dropdown): disabled items render inert, styled via [inert]

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Roving `role=menu` assembly in `DropdownMenu`

**Files:**
- Modify: `Sources/SwiflowUI/Dropdown.swift` (top import; `DropdownMenu.body`; add private helpers + `rove`; add file-local predicates)
- Test: `Tests/SwiflowUITests/DropdownTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `struct DropdownTests`:

```swift
    @Test("menu container is role=menu; trigger advertises aria-haspopup=menu") func menuRoles() {
        let node = building { dd { [DropdownItem("Edit") {}] } }
        let root = el(node)!
        let trigger = firstWithClass(root, "sw-dropdown__trigger")!
        let menu = firstWithClass(root, "sw-dropdown__menu")!
        #expect(trigger.attributes["aria-haspopup"] == "menu")
        #expect(menu.attributes["role"] == "menu")
    }

    @Test("every item gets role=menuitem, tabindex=-1, and a stable per-index id") func menuItemRoving() {
        let node = building {
            dd { [DropdownItem("Edit") {}, DropdownDivider(), DropdownItem("Delete", variant: .danger) {}] }
        }
        let root = el(node)!
        let menu = firstWithClass(root, "sw-dropdown__menu")!
        let menuID = menu.attributes["id"]!
        let items = menu.children.compactMap(el).filter { ($0.attributes["class"] ?? "").contains("sw-dropdown__item") }
        #expect(items.count == 2)
        for item in items {
            #expect(item.attributes["role"] == "menuitem")
            #expect(item.attributes["tabindex"] == "-1")
        }
        #expect(items[0].attributes["id"] == "\(menuID)-item-0")
        #expect(items[1].attributes["id"] == "\(menuID)-item-1")
        // The divider is untouched (still a separator, no menuitem role).
        let divider = firstWithClass(root, "sw-dropdown__divider")!
        #expect(divider.attributes["role"] == "separator")
    }

    @Test("first ENABLED item gets autofocus + a keydown handler; disabled items get neither") func autofocusAndKeydown() {
        let node = building {
            dd { [DropdownItem("First", disabled: true) {},
                  DropdownItem("Second") {},
                  DropdownItem("Third") {}] }
        }
        let root = el(node)!
        let menu = firstWithClass(root, "sw-dropdown__menu")!
        let items = menu.children.compactMap(el).filter { ($0.attributes["class"] ?? "").contains("sw-dropdown__item") }
        // items[0] = First (disabled/inert), items[1] = Second, items[2] = Third
        #expect(items[0].attributes["inert"] == "")
        #expect(items[0].attributes["autofocus"] == nil)   // disabled is never the autofocus target
        #expect(items[0].handlers["keydown"] == nil)       // disabled gets no roving handler
        #expect(items[1].attributes["autofocus"] == "")    // first ENABLED item
        #expect(items[1].handlers["keydown"] != nil)
        #expect(items[2].attributes["autofocus"] == nil)   // only the first enabled item autofocuses
        #expect(items[2].handlers["keydown"] != nil)
    }
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter DropdownTests/menuRoles`
Expected: FAIL — `aria-haspopup` is `"true"`, menu has no `role`, items have no `role`/`id`/`autofocus`/`keydown`.

- [ ] **Step 3: Add the JavaScriptKit import**

At the top of `Sources/SwiflowUI/Dropdown.swift`, after `import Swiflow`:

```swift
// Sources/SwiflowUI/Dropdown.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif
```

- [ ] **Step 4: Wire the roving transform + roles into `DropdownMenu.body`**

In `DropdownMenu.body`, change the item build to run the transform, switch `aria-haspopup` to `"menu"`, and add `role="menu"` to the menu div:

```swift
        // Items read the menu id from the ambient to wire close-on-select.
        let prev = DropdownAmbient.currentMenuID
        DropdownAmbient.currentMenuID = menuID
        let rawItems = items()
        DropdownAmbient.currentMenuID = prev
        let itemNodes = rovingMenuItems(rawItems)
```

In the `trigger` element's attributes, change:

```swift
            .attr("aria-haspopup", "menu"),
```

In the `menu` element's attributes, add `role="menu"`:

```swift
        let menu = element("div", attributes: [
            .class("sw-dropdown__menu"),
            .attr("role", "menu"),
            .attr("popover", "auto"),
            .attr("id", menuID),
            .style("position-anchor", anchor),
            .style("position-area", placement.positionArea),
        ], children: itemNodes)
```

- [ ] **Step 5: Add the roving methods to `DropdownMenu`**

Inside `final class DropdownMenu`, after `body`, add:

```swift
    /// Post-process the built item nodes into a roving WAI-ARIA menu. Every menu item gets
    /// `role="menuitem"`, `tabindex="-1"`, and a stable id (`<menuID>-item-<n>`); the first
    /// ENABLED item gets `autofocus` (the Popover API focuses it when the menu opens); every
    /// enabled item gets a keydown handler that roves focus. Disabled items are `inert` —
    /// skipped (no autofocus, no handler, excluded from the roving order). Dividers and any
    /// non-item nodes pass through untouched. Only the menu knows item order/count, so the
    /// assembly lives here rather than in `DropdownItem`.
    private func rovingMenuItems(_ nodes: [VNode]) -> [VNode] {
        // Pass 1: assign each menu item a stable id; collect the enabled ids in order.
        var idForNode: [String?] = []
        var enabledIDs: [String] = []
        var itemIndex = 0
        for node in nodes {
            if isDropdownMenuItem(node) {
                let id = "\(menuID)-item-\(itemIndex)"
                itemIndex += 1
                idForNode.append(id)
                if isEnabledDropdownItem(node) { enabledIDs.append(id) }
            } else {
                idForNode.append(nil)
            }
        }
        // Pass 2: inject menu semantics; first enabled item autofocuses; enabled items rove.
        var firstEnabledAssigned = false
        return nodes.enumerated().map { index, node in
            guard let id = idForNode[index] else { return node }   // non-item → untouched
            var item = node
                .attr("role", "menuitem")
                .attr("tabindex", -1)
                .id(id)
            if isEnabledDropdownItem(node) {
                if !firstEnabledAssigned {
                    item = item.attr("autofocus", true)
                    firstEnabledAssigned = true
                }
                let currentID = id
                let order = enabledIDs
                let owningMenuID = menuID
                item = item.on(.keydown) { (e: EventInfo) in
                    DropdownMenu.rove(e, current: currentID, order: order, menuID: owningMenuID)
                }
            }
            return item
        }
    }

    /// Imperatively rove focus among the enabled menu items in response to a keydown.
    /// `#if canImport(JavaScriptKit)`-guarded DOM access (a no-op on host), mirroring
    /// Autocomplete's focus-by-id. ↑/↓ wrap; Home/End jump to the ends; Tab closes the menu.
    /// Enter/Space/Escape are intentionally NOT handled here — they are native (`<button>`
    /// activation + `popovertargetaction="hide"`, and popover light-dismiss with focus return).
    private static func rove(_ e: EventInfo, current: String, order: [String], menuID: String) {
        guard let key = e.key, !order.isEmpty,
              let idx = order.firstIndex(of: current) else { return }
        let count = order.count
        let target: String?
        let close: Bool
        switch key {
        case "ArrowDown": target = order[(idx + 1) % count];         close = false
        case "ArrowUp":   target = order[(idx + count - 1) % count]; close = false
        case "Home":      target = order[0];                         close = false
        case "End":       target = order[count - 1];                 close = false
        case "Tab":       target = nil;                              close = true
        default:          return
        }
        #if canImport(JavaScriptKit)
        guard let doc = JSObject.global.document.object else { return }
        if close {
            _ = doc.getElementById?(menuID).object?.hidePopover?()
        } else if let target, let el = doc.getElementById?(target).object {
            _ = el.focus?()
        }
        #endif
    }
```

- [ ] **Step 6: Add the file-local predicates**

At file scope in `Dropdown.swift` (e.g. just below `DropdownDivider`), add:

```swift
/// True when `node` is a Dropdown menu item button (enabled or disabled). Dividers
/// (`sw-dropdown__divider`) and non-element nodes are excluded.
@MainActor
func isDropdownMenuItem(_ node: VNode) -> Bool {
    guard case .element(let data) = node else { return false }
    return (data.attributes["class"] ?? "").contains("sw-dropdown__item")
}

/// True when `node` is a Dropdown menu item that is NOT inert (focusable/actionable).
/// Inert items are stored with a presence-only `inert` attribute (empty-string value).
@MainActor
func isEnabledDropdownItem(_ node: VNode) -> Bool {
    guard case .element(let data) = node else { return false }
    return (data.attributes["class"] ?? "").contains("sw-dropdown__item")
        && data.attributes["inert"] == nil
}
```

- [ ] **Step 7: Update the existing `aria-haspopup` assertion**

In the existing `renders()` test, change:

```swift
        #expect(trigger.attributes["aria-haspopup"] == "menu")
```

(was `== "true"`).

- [ ] **Step 8: Run the full Dropdown suite and confirm green**

Run: `swift test --filter DropdownTests`
Expected: PASS (all, including the updated `renders()` and the three new tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowUI/Dropdown.swift Tests/SwiflowUITests/DropdownTests.swift
git commit -m "feat(dropdown): roving role=menu (menuitem, tabindex, autofocus, arrow keys)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Rewrite the doc comments

**Files:**
- Modify: `Sources/SwiflowUI/Dropdown.swift` (the `Dropdown` doc block ~lines 32-41; the `DropdownItem` doc ~lines 132-133)

- [ ] **Step 1: Rewrite the `Dropdown` doc comment**

Replace the stale doc block above `public func Dropdown(` (the paragraph that ends "…not a strict ARIA menu.)") with:

```swift
/// A **menu** of actions (WAI-ARIA `role="menu"`): a trigger button that reveals an anchored
/// popover of `role="menuitem"` items.
///
/// Native-first and lifecycle-free — no runtime state. (It's a `@Component` only to pin a stable
/// popover id across re-renders; see `DropdownMenu` below.) Built on the Popover API
/// (`popover="auto"`) + CSS Anchor Positioning, so it gets top-layer rendering, ESC + click-outside
/// dismissal, and trigger-anchored placement for free; each item closes the menu on select via
/// `popovertargetaction="hide"`.
///
/// **Keyboard (roving tabindex — the APG menu pattern):** Enter/Space on the trigger opens the
/// menu and focus lands on the first item (native `autofocus`); ↑/↓ move between items and wrap;
/// Home/End jump to the first/last; Enter/Space activate the focused item and close; Esc closes and
/// returns focus to the trigger; Tab closes the menu. Disabled items are `inert` and skipped.
///
///     Dropdown("Actions") {
///         DropdownItem("Edit") { edit() }
///         DropdownItem("Duplicate") { duplicate() }
///         DropdownDivider()
///         DropdownItem("Delete", variant: .danger) { delete() }
///     }
///
/// Caller `Attribute...`/`.class` land on the trigger button.
///
/// > Note: `label`/`placement` and the `items` builder are captured when the dropdown is
/// > first mounted (the component is `embed`-reused, to keep a stable popover id across
/// > re-renders). For a dropdown whose label or items change while mounted, pass a `key:`
/// > that changes with them so the menu is rebuilt with fresh props.
///
/// > Anchor positioning is Baseline-newer (Chromium/Safari; not yet Firefox). Where it's
/// > unsupported the menu still opens (a centered popover), just not anchored to the trigger.
```

- [ ] **Step 2: Rewrite the `DropdownItem` doc comment**

Replace the two-line doc above `public func DropdownItem(` with:

```swift
/// One actionable row in a `Dropdown`. Renders a `<button>`; the parent `Dropdown` injects the
/// `role="menuitem"`, roving `tabindex`, and stable id. Runs `action` and closes the menu on
/// select. `disabled: true` renders the button `inert` — removed from focus, pointer events, and
/// the accessibility tree, and skipped by keyboard roving. Use inside a `Dropdown { … }` builder.
```

- [ ] **Step 3: Confirm it still builds**

Run: `swift build`
Expected: builds clean (doc-only change).

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowUI/Dropdown.swift
git commit -m "docs(dropdown): describe the roving role=menu behavior

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Demo showcase + embed-templates regen

**Files:**
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift` (the `Dropdown("Actions")` block ~line 212)
- Regenerate: `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Add a disabled item to the demo dropdown**

In `examples/SwiflowUIDemo/Sources/App/App.swift`, update the dropdown so it includes a disabled item (showcasing `inert` + roving-skip):

```swift
                Dropdown("Actions") {
                    DropdownItem("Edit") { self.toasts.append(ToastItem("Edit selected")) }
                    DropdownItem("Duplicate") { self.toasts.append(ToastItem("Duplicated", variant: .success)) }
                    DropdownItem("Archive", disabled: true) {}
                    DropdownDivider()
                    DropdownItem("Delete", variant: .danger) { self.toasts.append(ToastItem("Deleted", variant: .danger)) }
                }
```

- [ ] **Step 2: Regenerate the embedded templates**

Run: `swift scripts/embed-templates.swift`
Expected: `Sources/SwiflowCLI/EmbeddedTemplates.swift` is rewritten with the updated SwiflowUIDemo source. (Required — the `embed-freshness`/`TemplateEmbedder` CI gate fails on stale bytes.)

- [ ] **Step 3: Confirm host build is green**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add examples/SwiflowUIDemo/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "docs(demo): show a disabled (inert) item in the SwiflowUIDemo dropdown

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Playwright e2e for roving focus (browser-only behavior)

> Controller runs this **inline** (never in a subagent — memory `no-subagent-playwright`), after building the release CLI (memory `run-e2e-locally-before-push`). The in-place SwiflowUIDemo build avoids the `.e2e-cache/sw` SourceKit-LSP race (memory `playwright-counter-config-lsp-race`) because it uses the example's own persistent `.build`, not the scaffold cache.

**Files:**
- Create: `Tests/playwright/playwright.swiflowui.config.ts`
- Create: `Tests/playwright/dropdown.spec.ts`

- [ ] **Step 1: Build the release CLI (the e2e harness reuses it)**

Run: `swift build -c release --product swiflow`
Expected: builds clean.

- [ ] **Step 2: Create the in-place SwiflowUIDemo config**

Create `Tests/playwright/playwright.swiflowui.config.ts` (mirrors `playwright.edgecases.config.ts`, on :3004):

```typescript
// Tests/playwright/playwright.swiflowui.config.ts
//
// Builds examples/SwiflowUIDemo IN-PLACE (swiflow dev --path …) on :3004 — no
// `swiflow init` scaffold, so the e2e tests the real demo source directly and
// never touches the .e2e-cache/sw scaffold cache (the SourceKit-LSP race).
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "SwiflowUIDemo");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["dropdown.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3004", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3004`,
      url: "http://127.0.0.1:3004",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
```

- [ ] **Step 3: Create the roving spec**

Create `Tests/playwright/dropdown.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";

// The SwiflowUIDemo dropdown: trigger "Actions"; items Edit, Duplicate,
// Archive (disabled/inert), Delete. Enabled roving order: Edit, Duplicate, Delete.
test.describe("Dropdown roving menu", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Actions" }).click();
    await expect(page.getByRole("menu")).toBeVisible();
  });

  test("focus lands on the first item on open", async ({ page }) => {
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
  });

  test("ArrowDown moves to next and wraps; ArrowUp wraps back", async ({ page }) => {
    await page.keyboard.press("ArrowDown");
    await expect(page.getByRole("menuitem", { name: "Duplicate" })).toBeFocused();
    await page.keyboard.press("ArrowDown"); // skips the disabled "Archive"
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
    await page.keyboard.press("ArrowDown"); // wraps to first
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
    await page.keyboard.press("ArrowUp");   // wraps to last
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
  });

  test("Home/End jump to the first/last enabled item", async ({ page }) => {
    await page.keyboard.press("End");
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
    await page.keyboard.press("Home");
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
  });

  test("the disabled item is inert (not a tabbable menuitem)", async ({ page }) => {
    const archive = page.locator('[inert]', { hasText: "Archive" });
    await expect(archive).toHaveCount(1);
  });

  test("Escape closes and returns focus to the trigger", async ({ page }) => {
    await page.keyboard.press("Escape");
    await expect(page.getByRole("menu")).toBeHidden();
    await expect(page.getByRole("button", { name: "Actions" })).toBeFocused();
  });

  test("Enter activates an item and closes the menu", async ({ page }) => {
    await page.keyboard.press("Enter"); // activates focused "Edit"
    await expect(page.getByRole("menu")).toBeHidden();
  });
});
```

- [ ] **Step 4: Run the spec inline**

Run: `cd Tests/playwright && npx playwright test --config=playwright.swiflowui.config.ts`
Expected: all tests pass. (First run cold-builds the demo wasm; up to ~3 min.)

If a focus assertion is flaky on open, add a short `await page.waitForTimeout(50)` after the trigger click before the first focus check — the popover focusing steps run async after `showPopover`.

- [ ] **Step 5: Commit**

```bash
git add Tests/playwright/playwright.swiflowui.config.ts Tests/playwright/dropdown.spec.ts
git commit -m "test(e2e): roving focus for the Dropdown menu (SwiflowUIDemo, in-place)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (controller, after all tasks)

- [ ] `swift build` — clean.
- [ ] `swift test --filter DropdownTests` — green.
- [ ] `swift build -c release --product swiflow` — clean (release CLI for e2e/demo).
- [ ] `swiflow build --path examples/SwiflowUIDemo` — demo compiles (memory `ci-skips-example-builds`: CI does not build examples).
- [ ] `npx playwright test --config=playwright.swiflowui.config.ts` (from `Tests/playwright`) — green.
- [ ] Dispatch the final code reviewer over the whole branch diff.
- [ ] Use superpowers:finishing-a-development-branch → open PR from `feat/swiflowui-menu-roving` (branched from origin/main) → **hold merge** until the user says "merge it — CI is green", then `gh pr merge <n> --admin --rebase`.

---

## Self-Review

- **Spec coverage:** `role=menu`/`menuitem` (T2), roving tabindex + ↑/↓ wrap + Home/End (T2/T5), native `autofocus` focus-on-open (T2/T5), Tab-closes / native Enter-Space-Escape (T2 `rove` + T5), `aria-haspopup="menu"` (T2), disabled⇒`inert` + excluded from roving (T1/T2/T5), `Autocomplete` untouched (no edits to that file), no core change (no `Sources/Swiflow/**` edits), doc rewrite (T3), demo + embed regen (T4). All covered.
- **Placeholder scan:** none — every code/test/CSS/TS block is complete.
- **Type/name consistency:** `isDropdownMenuItem` / `isEnabledDropdownItem` / `rovingMenuItems` / `rove(_:current:order:menuID:)` used identically across body wiring, helpers, and tests. `inert` checked as `== ""` (presence-only) consistently. Item id format `\(menuID)-item-\(n)` consistent between impl and unit tests.
