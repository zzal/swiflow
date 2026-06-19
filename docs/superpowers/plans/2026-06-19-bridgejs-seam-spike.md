# BridgeJS Seam Toolchain Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine, with browser-verified evidence, whether JavaScriptKit's BridgeJS build-tool plugin produces a working Swift↔JS seam through Swiflow's real build pipeline (`swiflow build` and `swiflow dev`/`CompilerBypass`) under strict-concurrency v6.

**Architecture:** A standalone throwaway Swiflow app at `spike/bridgejs-probe/` (path-deps the local Swiflow clone). Its `App` target opts into the BridgeJS plugin + experimental `Extern`, exposes one exported function shaped like the real event-dispatch seam (`@JS func spikeDispatch` taking a `@JS struct EventInfo`) and imports one JS function (`spikeLog`) via a `bridge-js.d.ts`. A vanilla button in `index.html` calls the export; Swift calls the import back. We build it both ways, verify in a browser, and record findings.

**Tech Stack:** Swift 6 / SwiftWasm, JavaScriptKit + BridgeJS plugin, the Swiflow CLI (`swiflow init/build/dev`), `wasm32-unknown-wasi` reactor modules, chrome-devtools MCP for browser verification.

---

## How to use this plan (READ FIRST — this is a SPIKE, not TDD)

This plan **investigates an unknown toolchain**, so it does not follow the write-failing-test → implement → pass loop. Instead:

- Most steps are **run-a-command → observe → record** experiments. The "Expected" line states what we *hope* to see; the real job is to **record what actually happens** in the findings doc (Task 7).
- A **clean failure is a successful spike.** If something is blocked, capture the exact error and move on — do not try to "make the migration work." We are answering questions, not shipping.
- Each task ends with a commit (checkpoint). The branch `spike/bridgejs-seam` is **throwaway**; commits are for reproducibility, not merge.
- **All commit messages end with the trailer** `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted from the snippets below for brevity).

The five questions this spike must answer (from the spec) — keep them in view; every observation maps to one:
1. Does JSKit **0.53.0** expose the `BridgeJS` plugin, or must we bump / track `main`?
2. Does the plugin run under `swift package js` **and** under `CompilerBypass`?
3. Do `Extern` + `@JS` compile under strict concurrency v6, alongside the `@Component` macro plugin?
4. How is the generated `bridge-js.js` loaded/bound relative to PackageToJS `index.js` / the driver's `init()`?
5. Any collision with the `-mexec-model=reactor … --export-if-defined` linker flags?

---

## File structure

| Path | Responsibility |
|---|---|
| `spike/bridgejs-probe/Package.swift` | Probe manifest: path-dep on local Swiflow, JavaScriptKit dep, `App` target with BridgeJS plugin + `Extern` + v6 |
| `spike/bridgejs-probe/Sources/App/App.swift` | Minimal Swiflow app + the `@JS` export (`spikeDispatch`) + `@JS struct EventInfo` + `@main` |
| `spike/bridgejs-probe/Sources/App/bridge-js.d.ts` | Declares the imported JS function `spikeLog` for BridgeJS to bind |
| `spike/bridgejs-probe/index.html` | Vanilla button that calls the export + `spikeLog` impl + glue wiring (shape discovered in Task 3) |
| `spike/bridgejs-probe/swiflow-driver.js`, `swiflow-sw.js`, `swiflow-manifest.json` | Scaffolded by `swiflow init`; left as-is |
| `docs/superpowers/specs/2026-06-19-bridgejs-seam-spike-findings.md` | The real deliverable — answers Q1–Q5 with evidence |

---

## Task 0: Preconditions & scaffold a working baseline

Establishes a **control**: a vanilla scaffolded app that builds, so any later failure is attributable to BridgeJS, not the pipeline.

**Files:**
- Create: `spike/bridgejs-probe/` (via `swiflow init`)

- [ ] **Step 1: Build the release CLI (avoid the stale-binary trap)**

The harness can reuse a stale `swiflow` binary. Always drive this spike through the freshly built release CLI.

Run:
```bash
swift build -c release --product swiflow
```
Expected: builds clean; `.build/release/swiflow` exists.

- [ ] **Step 2: Confirm a wasm SDK is installed**

Run:
```bash
swift sdk list && .build/release/swiflow doctor
```
Expected: at least one Swift wasm SDK is listed. If none, install the swift.org wasm SDK matching the toolchain (swiftly 6.3.2 pair) before continuing — the spike cannot build wasm without it.

- [ ] **Step 3: Scaffold the throwaway probe**

Run:
```bash
mkdir -p spike
.build/release/swiflow init bridgejs-probe --path spike --swiflow-source /Users/alainduchesneau/Projects/swiflow
```
Expected: prints `Created …/spike/bridgejs-probe`. The dir contains `Package.swift`, `Sources/App/`, `index.html`, `swiflow-driver.js`, `swiflow-sw.js`, `swiflow-manifest.json`.

- [ ] **Step 4: Build the unmodified scaffold (the control)**

Run:
```bash
.build/release/swiflow build --path spike/bridgejs-probe
```
Expected: build succeeds; `spike/bridgejs-probe/.build/plugins/PackageToJS/outputs/Package/App.wasm` is produced. **Record:** baseline pipeline works (yes/no). If this fails, stop — the environment, not BridgeJS, is the problem; capture the error.

- [ ] **Step 5: Commit the baseline**

```bash
git add spike/bridgejs-probe
git commit -m "spike: scaffold throwaway bridgejs-probe baseline (control)"
```

---

## Task 1: Strip the probe to a minimal app

Reduce variables: drop SwiflowUI and the HelloWorld kitchen sink so the only moving parts are Swiflow core + (soon) BridgeJS.

**Files:**
- Modify: `spike/bridgejs-probe/Sources/App/App.swift` (replace whole file)
- Modify: `spike/bridgejs-probe/Package.swift` (drop the `SwiflowUI` dependency if present)
- Delete: any other `spike/bridgejs-probe/Sources/App/*.swift` the template added

- [ ] **Step 1: Replace `App.swift` with a minimal app**

Overwrite `spike/bridgejs-probe/Sources/App/App.swift`:
```swift
import Swiflow
import SwiflowDOM

@MainActor @Component
final class Probe {
    var body: VNode {
        div {
            h1("BridgeJS probe")
            p("The button + log live in index.html, outside #app.")
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Probe() }
    }
}
```

- [ ] **Step 2: Remove extra template sources and the SwiflowUI dep**

Run:
```bash
ls spike/bridgejs-probe/Sources/App
# Delete every .swift file EXCEPT App.swift, e.g.:
# rm spike/bridgejs-probe/Sources/App/SignIn.swift spike/bridgejs-probe/Sources/App/AboutPopover*.swift spike/bridgejs-probe/Sources/App/Counter+Styles.swift
```
Then, in `spike/bridgejs-probe/Package.swift`, remove the `.product(name: "SwiflowUI", package: "Swiflow")` line from the `App` target's `dependencies` if the template added it. Leave `SwiflowDOM`.

- [ ] **Step 3: Rebuild to confirm the minimal app is still green**

Run:
```bash
.build/release/swiflow build --path spike/bridgejs-probe
```
Expected: build succeeds. **Record:** minimal app builds (yes/no).

- [ ] **Step 4: Commit**

```bash
git add -A spike/bridgejs-probe
git commit -m "spike: strip probe to a minimal Swiflow app"
```

---

## Task 2: Opt into BridgeJS — export + struct + import (the core experiment)

This is the make-or-break task. It answers Q1 (plugin on 0.53), Q2-release (plugin under `swift package js`), and Q3 (Extern + @JS + v6 + @Component coexist).

**Files:**
- Modify: `spike/bridgejs-probe/Package.swift` (add plugin, `Extern`, v6)
- Modify: `spike/bridgejs-probe/Sources/App/App.swift` (add `@JS` export + struct)
- Create: `spike/bridgejs-probe/Sources/App/bridge-js.d.ts`

- [ ] **Step 1: Add the BridgeJS plugin, Extern, and v6 to the `App` target**

In `spike/bridgejs-probe/Package.swift`, change the `App` target so it reads:
```swift
.executableTarget(
    name: "App",
    dependencies: [
        .product(name: "SwiflowDOM", package: "Swiflow"),
        .product(name: "JavaScriptKit", package: "JavaScriptKit"),
    ],
    path: "Sources/App",
    swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("Extern"),   // BridgeJS generated glue uses @_extern(wasm)
    ],
    plugins: [
        .plugin(name: "BridgeJS", package: "JavaScriptKit"),
    ]
),
```
(The `JavaScriptKit` package dependency is already declared at package level by the scaffold; the snippet just adds the product to the target and the plugin.)

- [ ] **Step 2: Add the `@JS` export + struct to `App.swift`**

Insert at the top of `spike/bridgejs-probe/Sources/App/App.swift`, after the imports (add `import JavaScriptKit`):
```swift
import JavaScriptKit

/// Shaped like the real Seam A payload (Sources/SwiflowDOM/DispatcherBridge.swift).
@JS struct EventInfo {
    var type: String
    var targetValue: String?
    var targetChecked: Bool?
    var isSelfTarget: Bool
    var key: String?
    var shiftKey: Bool
    var ctrlKey: Bool
    var altKey: Bool
    var metaKey: Bool
    var detail: String?
}

/// Exported to JS. Calls the imported `spikeLog` back — proves both directions.
@JS public func spikeDispatch(handlerId: Int, event: EventInfo) {
    spikeLog("swift got handlerId=\(handlerId) type=\(event.type) self=\(event.isSelfTarget)")
}
```

- [ ] **Step 3: Declare the imported JS function**

Create `spike/bridgejs-probe/Sources/App/bridge-js.d.ts`:
```ts
// JS the probe imports into Swift; BridgeJS generates the Swift binding `spikeLog`.
export function spikeLog(message: string): void;
```

- [ ] **Step 4: Build and OBSERVE (the central experiment)**

Run:
```bash
.build/release/swiflow build --path spike/bridgejs-probe 2>&1 | tee /tmp/bridgejs-build.log
```
Expected (hoped): build succeeds; BridgeJS codegen runs. **Record all of:**
- **Q1:** Did SwiftPM resolve a `BridgeJS` plugin from JavaScriptKit 0.53.0? (Look for the plugin running, or an error like "no such plugin 'BridgeJS'".)
- **Q2-release:** Did codegen run under `swift package js`? (Search the log for `bridge-js`, `BridgeJS`, generated-file mentions.)
- **Q3:** Did `Extern` + `@JS` + `@Component` compile under v6? (Any concurrency or `@_extern` errors?)
- Locate generated artifacts: `find spike/bridgejs-probe/.build -iname 'bridge-js*' -o -iname 'BridgeJS*'`

- [ ] **Step 5: If Q1 fails (no plugin on 0.53), retry on `main`**

Only if Step 4 reported the plugin is absent. In `spike/bridgejs-probe/Package.swift`, change the JavaScriptKit dependency line to:
```swift
.package(url: "https://github.com/swiftwasm/JavaScriptKit.git", branch: "main"),
```
Then re-run the Step 4 build command. **Record:** does `main` expose the plugin, and does it still build under our wasm SDK + v6? (If `main` also fails, that is a *red* spike result — capture the exact error and skip to Task 7.)

- [ ] **Step 6: Commit the experiment state**

```bash
git add -A spike/bridgejs-probe
git commit -m "spike: opt probe into BridgeJS (export spikeDispatch + EventInfo + spikeLog import)"
```

---

## Task 3: Discover the glue wiring and wire the page (Q4)

Only proceed if Task 2 produced a green build. This answers Q4 by reading what the plugin actually emitted.

**Files:**
- Read (generated): `spike/bridgejs-probe/.build/**/bridge-js.js`, `bridge-js.d.ts`, `BridgeJS.swift`
- Modify: `spike/bridgejs-probe/index.html`

- [ ] **Step 1: Read the generated glue to learn the contract**

Run:
```bash
find spike/bridgejs-probe/.build -iname 'bridge-js.js' -o -iname 'bridge-js.d.ts' -o -iname 'BridgeJS.swift'
```
Then read each hit. **Determine and record:**
- How the **export** `spikeDispatch` is surfaced to JS (a property on the instance's exports? a wrapper module?).
- How the **import** `spikeLog` must be supplied (passed into an imports object at instantiation? a global the glue looks up?).
- Confirm the generated Swift import binding is callable as `spikeLog(_:)` (matches the call in Task 2 Step 2); if codegen named it differently, note the real name.

- [ ] **Step 2: Confirm how the driver instantiates**

Read `spike/bridgejs-probe/swiflow-driver.js` around the boot/`init` call (the scaffolded driver mirrors `js-driver/swiflow-driver.js:700-723`). **Record:** does it call PackageToJS `init({ module })`, and is there a seam to pass a BridgeJS imports object or read its exports?

- [ ] **Step 3: Wire the page**

Edit `spike/bridgejs-probe/index.html`. Inside `<body>`, after the `<div id="app"></div>`, add the button + log + the `spikeLog` implementation. Use the contract discovered in Steps 1–2. The likely shape (adjust to what the glue actually exposes):
```html
<button id="probe-btn" type="button">Call spikeDispatch</button>
<pre id="probe-log" style="font:14px ui-monospace,monospace"></pre>
<script>
  // The import the Swift side calls back into.
  window.spikeLog = function (message) {
    document.getElementById("probe-log").textContent += message + "\n";
  };
  // Call the export when the button is clicked. `swiflowProbeExports` is whatever
  // handle the generated glue / driver exposes the BridgeJS exports under — set in
  // Step 1/2's discovery; wire it here.
  document.getElementById("probe-btn").addEventListener("click", function () {
    const ev = {
      type: "click", targetValue: null, targetChecked: null, isSelfTarget: true,
      key: null, shiftKey: false, ctrlKey: false, altKey: false, metaKey: false, detail: null,
    };
    window.swiflowProbeExports.spikeDispatch(1, ev);
  });
</script>
```
If the driver does not already expose the exports, add the minimal wiring the discovery indicated (e.g. assign `window.swiflowProbeExports = exports` at the driver's `init` return) — keep it to the throwaway probe only.

- [ ] **Step 4: Rebuild**

Run:
```bash
.build/release/swiflow build --path spike/bridgejs-probe
```
Expected: build succeeds with the page wired. **Record:** Q4 answer (auto-wired vs the manual seam you added).

- [ ] **Step 5: Commit**

```bash
git add -A spike/bridgejs-probe
git commit -m "spike: wire index.html button to the BridgeJS export/import"
```

---

## Task 4: Browser-verify the round-trip (release path)

The proof: a real click crossing JS → wasm → JS.

- [ ] **Step 1: Serve the built probe**

Run (background):
```bash
cd spike/bridgejs-probe && python3 -m http.server 3000
```
Expected: server on `http://localhost:3000`.

- [ ] **Step 2: Load and screenshot via chrome-devtools MCP**

Use the chrome-devtools MCP: `new_page` → navigate to `http://localhost:3000` → `take_snapshot` + `take_screenshot`.
Expected: the page loads, `#app` shows "BridgeJS probe", the button + empty `#probe-log` are visible. **Record:** screenshot, and any console errors (`list_console_messages`).

- [ ] **Step 3: Click the button and observe the round-trip**

Use chrome-devtools MCP `click` on `#probe-btn`, then `take_snapshot` of `#probe-log`.
Expected (green): `#probe-log` shows `swift got handlerId=1 type=click self=true` — proving the export fired Swift, `EventInfo` fields arrived intact, and the imported `spikeLog` reached JS. **Record:** the log text + a screenshot. If nothing appears, capture console errors — that is a meaningful (possibly red) finding about Q4 wiring.

- [ ] **Step 4: Stop the server**

Stop the background `http.server`.

---

## Task 5: Dev / CompilerBypass path (Q2-dev — the highest-value question)

Tests whether the fast dev rebuild path runs the build-tool plugin, or skips it the way it once skipped reactor conversion.

- [ ] **Step 1: Start the dev server**

Run (background):
```bash
.build/release/swiflow dev --path spike/bridgejs-probe 2>&1 | tee /tmp/bridgejs-dev.log
```
Expected: dev server starts and serves the probe. Load `http://localhost:<dev-port>` via chrome-devtools MCP and click the button as in Task 4. **Record:** does the round-trip work under `swiflow dev` on first load?

- [ ] **Step 2: Trigger an HMR rebuild and re-test**

Edit `spike/bridgejs-probe/Sources/App/App.swift` — change the `spikeLog` message string (e.g. add `" v2"`). Save. Wait for the dev server to rebuild (watch `/tmp/bridgejs-dev.log`).
Then click the button again in the browser.
Expected (green): the log now shows the ` v2` text — codegen re-ran under the bypass. **Record Q2-dev:** one of (a) works after HMR (bypass runs codegen), (b) stale/old glue (bypass *skips* codegen — note this, it mirrors the reactor-flag gap at `CompilerBypass.swift:258`), or (c) hard error. If (b), inspect `Sources/SwiflowCLI/DevServer/CompilerBypass.swift` and note what step would need to invoke `bridge-js generate`/`link`.

- [ ] **Step 3: Stop the dev server and commit any notes**

Stop the background dev server. (No source change to keep unless you want the ` v2` edit; revert it.)
```bash
git checkout -- spike/bridgejs-probe/Sources/App/App.swift
```

---

## Task 6: Reactor-flag collision check (Q5)

- [ ] **Step 1: Inspect the produced wasm's exports**

Run:
```bash
find spike/bridgejs-probe/.build -name 'App.wasm' -path '*PackageToJS*'
# Then dump exports (use whichever is installed):
wasm-tools print <App.wasm path> 2>/dev/null | grep -i 'export' | head -40 \
  || wasm-objdump -x <App.wasm path> | grep -iA2 'Export' | head -40
```
Expected: the module is a reactor (exports `_initialize`) **and** carries the BridgeJS export(s) for `spikeDispatch` without the link having failed. **Record Q5:** any sign of conflict between BridgeJS `@_extern`/exports and the `-mexec-model=reactor … --export-if-defined` flags (check `/tmp/bridgejs-build.log` for linker warnings/errors too).

---

## Task 7: Write the findings doc (the deliverable) + teardown note

- [ ] **Step 1: Write the findings**

Create `docs/superpowers/specs/2026-06-19-bridgejs-seam-spike-findings.md` with one section per question (Q1–Q5), each stating **the answer + the evidence** (quoted log lines, the screenshot path, the generated-file paths). End with a **go/no-go recommendation** for the real A+B+C migration and any newly-discovered risks (e.g. "CompilerBypass needs a codegen step", "must track JSKit `main`").

- [ ] **Step 2: Commit the findings**

```bash
git add docs/superpowers/specs/2026-06-19-bridgejs-seam-spike-findings.md
git commit -m "spike: BridgeJS seam findings (Q1-Q5 + go/no-go)"
```

- [ ] **Step 3: Teardown note**

The branch `spike/bridgejs-seam` and `spike/bridgejs-probe/` are **discarded** — do not merge the probe. To preserve the knowledge, cherry-pick **only** the two docs (`…-spike-design.md`, `…-spike-findings.md`) onto a short-lived `docs/bridgejs-spike` branch and open a docs-only PR (merged with `--admin --rebase` per repo convention). Then the spike branch can be deleted:
```bash
# after docs are salvaged:
git switch main && git branch -D spike/bridgejs-seam
```

---

## Self-review (done while writing)

- **Spec coverage:** Q1→Task 2 S4/S5; Q2-release→Task 2 S4; Q2-dev→Task 5; Q3→Task 2 S4; Q4→Task 3 + Task 4; Q5→Task 6. Probe shape (export+struct+import, isolated, outside `examples/`, v6)→Tasks 0–2. Both build paths→Tasks 4 (build) & 5 (dev). Findings output + teardown→Task 7. All spec sections mapped.
- **Placeholder scan:** the one intentionally-discovered value is the page-glue handle (`swiflowProbeExports`) in Task 3 — its exact shape is *determined by reading generated code in Task 3 Steps 1–2*, which is the legitimate purpose of a spike, not a hidden TODO.
- **Type consistency:** `spikeDispatch(handlerId:event:)`, `EventInfo` fields, and `spikeLog(_:)` are used identically in App.swift (Task 2) and index.html (Task 3); `EventInfo` fields match `DispatcherBridge.swift`.
- **Correction vs spec:** spec said target `BridgeJSProbe`/`Sources/BridgeJSProbe/`; corrected to product/target **`App`** at `Sources/App/` because `swiflow build` invokes `--product App`. `bridge-js.d.ts` therefore lives at `Sources/App/`.
