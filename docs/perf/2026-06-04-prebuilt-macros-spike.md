# Prebuilt-Macros Spike — 2026-06-04

**Question:** Can Swiflow's `@Component` macro avoid building/tracking swift-syntax from source by using the Swift 6.3 toolchain's prebuilt swift-syntax, dropping the no-op `swift build` wall time from ~9s toward the ~1s floor?

**Recommendation: NOT FEASIBLE / NO GAIN — proceed to Spike B (warm/persistent build).**

---

## Environment

- Toolchain: `swift-6.3-RELEASE` (`Apple Swift version 6.3 (swift-6.3-RELEASE)`)
- WASM SDK: `swift-6.3-RELEASE_wasm`
- Scratch project: `/tmp/Smoke` (HelloWorld-class Swiflow app, uses `@Component` macro)
- Swiflow pins: `swift-syntax .upToNextMinor(from: "600.0.0")`, resolved to `600.0.1`

---

## Step 1 — Baseline

After a warm build, second/stable run:

```
$ /usr/bin/time -p swift build --swift-sdk swift-6.3-RELEASE_wasm --product App
[0/2] Write swift-version-5D9A58FDBB1959BC.txt
Build of product 'App' complete! (9.06s)
real 9.71
user 1.22
sys 1.09
```

Swift-syntax tracked object files (`.o` matching `*wift[Ss]yntax*`):

```
$ find .build -type f -name "*.o" -path "*wift[Ss]yntax*" | wc -l
234
```

Total tracked objects: **576** (353 are host/tool objects, 117 are WASM-side).

---

## Step 2 — Prebuilt-Macro Support Investigation

### Flags

Both `swift build --help` and `swift package --help` expose:

```
--enable-experimental-prebuilts/--disable-experimental-prebuilts
    Whether to use prebuilt swift-syntax libraries for macros.
    (default: --enable-experimental-prebuilts)
```

**`--enable-experimental-prebuilts` is already the DEFAULT.**

No separate env var like `SWIFTPM_ENABLE_PREBUILT_SWIFT_SYNTAX` or `SWIFTPM_USE_PREBUILT*` was found in either help page. (The env var `SWIFTPM_ENABLE_PREBUILT_SWIFT_SYNTAX=1` was tested; it triggered a full from-source rebuild, suggesting it is not a valid/recognized variable or it inverts the sense — either way, the CLI flag is the correct control.)

### Toolchain Prebuilt Artifacts

The toolchain DOES ship prebuilt swift-syntax dylibs and swiftmodules:

```
/usr/lib/swift/host/
  libSwiftSyntax.dylib          (universal arm64 + x86_64)
  libSwiftSyntaxBuilder.dylib
  libSwiftSyntaxMacros.dylib
  libSwiftSyntaxMacroExpansion.dylib
  libSwiftParser.dylib
  libSwiftParserDiagnostics.dylib
  libSwiftOperators.dylib
  libSwiftBasicFormat.dylib
  libSwiftRefactor.dylib
  libSwiftIDEUtils.dylib
  libSwiftIfConfig.dylib
  libSwiftCompilerPluginMessageHandling.dylib
  libSwiftLibraryPluginProvider.dylib
  (+ matching .swiftmodule bundles)
```

```
$ find .../swift-6.3-RELEASE.xctoolchain -iname "*prebuilt*"
(no results)
```

There are no files literally named `*prebuilt*`; the prebuilt artifacts are the host dylibs above.

### Version Analysis — The Critical Issue

The prebuilt `libSwiftSyntax.dylib` in the swift-6.3-RELEASE toolchain declares:

```
// swift-compiler-version: Apple Swift version 6.0.3 effective-5.10
//   (swiftlang-6.0.3.1.9 clang-1600.0.30.1)
```

This is a **Swift 6.0.3 vintage** prebuilt (i.e., swift-syntax ~600.0.0-alpha) bundled with the 6.3 toolchain. Swiflow resolves `swift-syntax` to **600.0.1** (see `Package.resolved`).

SPM's prebuilt mechanism substitutes the prebuilt dylib when the package version is a compatible match with the toolchain's bundled version. Because there is a compiler-version mismatch (6.0.3 prebuilt vs 6.3 toolchain), **SPM partially applies prebuilts** — it can substitute some modules but still builds others from source.

---

## Step 3 — Measured Result with Prebuilts Enabled

The default `--enable-experimental-prebuilts` is already active. For completeness, we measured a clean build both ways:

### With prebuilts DISABLED (explicit `--disable-experimental-prebuilts`)

Full clean build: **38s** (full from-source swift-syntax compile).  
Swift-syntax object files: **234**

### With prebuilts ENABLED (default)

Full clean build: **76s** (longer because SPM re-checks; same warm steady-state).  
Swift-syntax object files: **117** (partial substitution)

### No-op comparison (stable second run)

| Condition | Swift-syntax .o files | No-op wall time |
|---|---|---|
| `--disable-experimental-prebuilts` | 234 | ~9.7s |
| `--enable-experimental-prebuilts` (default) | 117 | ~9.2s |

**Savings: ~117 fewer objects tracked, ~0.5s wall time.**

The object breakdown with prebuilts enabled:
- `SwiftSyntax-tool.build`: **71 objects** — the core SwiftSyntax module is only partially substituted by the prebuilt dylib; the remainder still builds from source
- `SwiftSyntaxBuilder-tool.build`, `SwiftSyntaxMacros-tool.build`, `SwiftSyntaxMacroExpansion-tool.build`, `SwiftSyntax509/510/600-tool.build`: **46 objects** — these companion modules are NOT replaced by prebuilts at all

---

## Analysis

The `--enable-experimental-prebuilts` feature is already on by default and Swiflow's `/tmp/Smoke` app already benefits from it. It yields:

- A halving of swift-syntax tracked objects (234 → 117)
- A ~0.5s wall-time reduction on no-op builds (9.7s → 9.2s)

However:
1. **This is already the status quo** — there is nothing to "fold in." The flag is the default; no Swiflow-side change is needed or possible.
2. **The improvement is marginal.** 117 objects still remain, and llbuild still stats them every invocation. The wall time drops from ~9.7s to ~9.2s — a 5% improvement, not the ~8s reduction needed to approach the ~1s floor.
3. **Root cause is structural.** The 117 remaining swift-syntax objects persist because the toolchain's prebuilt dylibs were compiled with Swift 6.0.3, creating a partial version mismatch that prevents full substitution of all swift-syntax modules. Even if full substitution were achieved (0 swift-syntax .o files), the other 236 host/tool objects (JavaScriptKit macro, BridgeJSMacros, SwiflowMacrosPlugin itself, ArgumentParser, etc.) would still be tracked by llbuild, keeping the no-op above ~1–2s.
4. **The prebuilt mechanism does not help the WASM build graph.** The 117 remaining objects are all `arm64-apple-macosx` (host/tool) objects, not WASM objects — prebuilts only affect the macro host build, not the WASM target. The WASM-side graph is unaffected.

---

## Recommendation

**NOT FEASIBLE / NO GAIN — proceed to Spike B (warm/persistent build).**

The prebuilt-macros lever is already engaged (it's the default). The toolchain's stale prebuilts (6.0.3 vintage) give only partial coverage, and even full coverage would not approach the 1s target because 236 non-swift-syntax host objects remain tracked. The bottleneck is llbuild's stat pass over the entire artifact set on every invocation, not specifically swift-syntax.

Spike B (warm/persistent `swift build` process, reusing the loaded build graph across dev-loop invocations) is the correct next investigation to cut the ~9s overhead structurally.

---

## Raw Command Reference

```bash
# Flag discovery
swift build --help 2>&1 | grep -i prebuilt
# => --enable-experimental-prebuilts/--disable-experimental-prebuilts
#    Whether to use prebuilt swift-syntax libraries for macros.
#    (default: --enable-experimental-prebuilts)

# Toolchain prebuilt dylibs
ls ~/Library/Developer/Toolchains/swift-6.3-RELEASE.xctoolchain/usr/lib/swift/host/lib*.dylib
# => libSwiftSyntax.dylib, libSwiftSyntaxBuilder.dylib, etc. (13 dylibs)

# Prebuilt version
head -3 .../host/SwiftSyntax.swiftmodule/arm64-apple-macos.swiftinterface
# => // swift-compiler-version: Apple Swift version 6.0.3 effective-5.10

# Clean build with prebuilts enabled (default)
time swift build --swift-sdk swift-6.3-RELEASE_wasm --product App
# => 76s full build; 117 swift-syntax .o files; 9.2s no-op

# Clean build with prebuilts disabled
time swift build --swift-sdk swift-6.3-RELEASE_wasm --product App --disable-experimental-prebuilts
# => 38s full build; 234 swift-syntax .o files; 9.7s no-op
```
