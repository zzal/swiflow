# WASM Bundle Audit — 2026-05-26

Pre-trim measurements taken on the HelloWorld example built with the
current `swiflow build` (Swift 6.3, WASM SDK 6.3, `-O` release).

> **Note on example name:** The plan references "Counter" throughout, but the
> actual example used for all perf tracking is `examples/HelloWorld` (the
> only complete example in the repo at time of writing). All measurements
> here are for HelloWorld. Future tasks should continue using HelloWorld
> unless a Counter example is added.

## Toolchain at measurement time

| Tool | Version | Source |
|---|---|---|
| Swift | 6.3 (swiftlang-6.3.0) | `swift --version` |
| WASM SDK | swift-6.3-RELEASE_wasm | `swift sdk list` |
| wasm-objdump | 1.0.41 | `brew install wabt` |
| wasm-opt | 129 | `brew install binaryen` |
| wasm-strip | 1.0.41 | `brew install wabt` |
| wasm-tools | not installed | cargo not present on this machine |

`wasm-tools` was unavailable (no cargo). The audit uses `wasm-objdump -h` for
section sizes and `wasm-opt --func-metrics` (on the pre-PackageToJS linker
output) for function-level attribution. All essential data was captured.

## Headline numbers

| Build | Raw bytes | Gzipped bytes | Notes |
|---|---|---|---|
| Current release (`-O`) | 46,128,206 | 18,203,153 | Baseline before Track 2. PackageToJS default: DWARF stripped, wasm-opt `-O`. |
| With `-Osize` + `-gnone` | 46,059,478 | 18,165,326 | Task 3. `-Xswiftc -Osize -Xswiftc -gnone` passed before the `js` plugin subcommand. Delta: −68,728 raw (−0.15%), −37,827 gzipped (−0.21%). Small reduction because WASM SDK stdlib/Foundation is pre-compiled at Apple's settings; only app and Swiflow layers benefit. |
| With `-Osize` + `wasm-opt -Oz` | TBD (Task 4) | TBD (Task 4) | Measured at Task 4 |
| With above + `wasm-strip` (name) | TBD (Task 5) | TBD (Task 5) | Measured at Task 5 |
| With `-Osize -disable-reflection-metadata` | ~46,041,608 (est.) | ~18,158,362 (est.) | **Measurement only — binary crashes at runtime.** Processed via `wasm-opt --strip-debug -O` to match PackageToJS treatment. Delta: −44,791 gzipped bytes (−0.25%). Records the theoretical floor available if `@State` is redesigned (post-1.0). |

> **Baseline vs. plan:** The plan's stated baseline of 20.6 MB gzipped / 61.9 MB
> raw refers to a pre-Phase-14a (pre-Track-1) measurement. The current
> on-disk baseline is 18.2 MB gzipped / 46.1 MB raw, reflecting refinements
> already applied. The ≤16.5 MB target remains. `docs/perf/bundle-baseline.json`
> records `total_gzip_bytes: 20,601,631` (JS + WASM combined). WASM alone is
> 18,203,153 gzipped.

## Section breakdown

```
App.wasm:	file format wasm 0x1

Sections:

     Type start=0x0000000b end=0x00000bc5 (size=0x00000bba) count: 312
   Import start=0x00000bc8 end=0x0000170a (size=0x00000b42) count: 80
 Function start=0x0000170e end=0x0000a23f (size=0x00008b31) count: 35342
    Table start=0x0000a241 end=0x0000a24a (size=0x00000009) count: 1
   Memory start=0x0000a24c end=0x0000a250 (size=0x00000004) count: 1
   Global start=0x0000a252 end=0x0000a260 (size=0x0000000e) count: 2
   Export start=0x0000a263 end=0x0000a36e (size=0x0000010b) count: 11
     Elem start=0x0000a372 end=0x00023124 (size=0x00018db2) count: 1
DataCount start=0x00023126 end=0x00023129 (size=0x00000003) count: 75225
     Code start=0x0002312e end=0x009e548a (size=0x009c235c) count: 35342
     Data start=0x009e548f end=0x02be7285 (size=0x02201df6) count: 75225
   Custom start=0x02be7289 end=0x02bfdaae (size=0x00016825) ".swift1_autolink_entries"
   Custom start=0x02bfdab1 end=0x02bfdbb7 (size=0x00000106) "producers"
   Custom start=0x02bfdbba end=0x02bfdc4e (size=0x00000094) "target_features"
```

In decimal and as a share of the total:

| Section | Bytes | % of file |
|---|---:|---:|
| Type | 3,002 | 0.0% |
| Import | 2,882 | 0.0% |
| Function | 35,633 | 0.1% |
| Table | 9 | 0.0% |
| Memory | 4 | 0.0% |
| Global | 14 | 0.0% |
| Export | 267 | 0.0% |
| Elem | 101,810 | 0.2% |
| DataCount | 3 | 0.0% |
| **Code** | **10,232,668** | **22.2%** |
| **Data** | **35,659,254** | **77.3%** |
| Custom: .swift1_autolink_entries | 92,197 | 0.2% |
| Custom: producers | 262 | 0.0% |
| Custom: target_features | 148 | 0.0% |
| **Total** | **46,128,153** | 100% |

> **Note:** The section-body sum (46,128,153 bytes) is 53 bytes less than the raw file size (46,128,206 bytes). The delta is the WASM module preamble (8-byte magic + version) and the per-section header bytes that `wasm-objdump -h` reports as section body size but does not include in the body totals — this is expected and not a measurement error.

The **Data section dominates at 77.3%** (35.7 MB). It holds Swift's static
string table, Unicode data tables (ICU), reflection metadata (type names,
field offsets), and constant data embedded by the stdlib and Foundation.
The **Code section is 22.2%** (10.2 MB) — executable WASM bytecode for
35,342 functions. There are no `name` or `dwarf` custom sections in the
PackageToJS output because they are stripped as part of the build pipeline.

The key leverage points for Track 2 are in the Code section (function
inlining + size-tuned codegen via `-Osize`) and the Custom sections (none
actionable for Track 2; the autolink section goes away in a link-time
optimization pass, post-1.0).

## Top functions

Source: `wasm-opt --func-metrics` on the pre-PackageToJS linker output
(`.build/wasm32-unknown-wasip1/release/App.wasm`) which retains the `name`
section. The final shipped WASM has names stripped. Function names are
demangled with `swift demangle`.

| # | Bytes | Module | Demangled name |
|---|---:|---|---|
| 1 | 61,700 | Swift stdlib | closure #1 (String) → Unicode.Block? in `_RegexParser`.classifyBlockProperty |
| 2 | 42,420 | Swift stdlib | closure #1 (String) → Unicode.Script? in `_RegexParser`.classifyScriptProperty |
| 3 | 41,142 | Swift stdlib | `swift::Demangle::NodePrinter::print` (C++ runtime demangler) |
| 4 | 33,528 | Swift stdlib | `SIMD32.debugDescription` getter |
| 5 | 32,492 | Swift stdlib | `SIMD64.debugDescription` getter |
| 6 | 30,771 | Swift stdlib | `SIMD16.debugDescription` getter |
| 7 | 27,689 | Foundation | specialization of `URLResourceValuesStorage.read(_:for:)` |
| 8 | 27,433 | Swift stdlib | `swift::Demangle::TypeDecoder::decodeMangledType` (C++ runtime) |
| 9 | 26,487 | Foundation (ICU) | `icu_76::DateFormatSymbols::initializeData` |
| 10 | 24,062 | Swift stdlib | specialization of `_DebuggerSupport.printForDebuggerImpl(…)` |
| 11 | 22,796 | Swift stdlib | `SIMD8.debugDescription` getter |
| 12 | 20,049 | Foundation (ICU) | `icu_76::RegexMatcher::MatchAt` |
| 13 | 19,480 | Foundation (CF) | `__CFStringAppendFormatCore` |
| 14 | 16,446 | Swift stdlib | closure in `_RegexParser`.classifyBoolProperty |
| 15 | 15,958 | Foundation (CF) | `CFStringFindWithOptionsAndLocale` |
| 16 | 15,878 | Foundation (ICU) | `icu_76::DateFormatSymbols::copyData` |
| 17 | 14,808 | Swift stdlib | closure in `_RegexParser`.canLexDotNetCharClassSubtraction |
| 18 | 14,699 | Swift stdlib | `DecodingError.debugDescription` getter |
| 19 | 14,656 | Foundation | specialization of `FoundationEssentials.readBytesFromFile(path:…)` |
| 20 | 14,173 | Swift stdlib | `SIMD4.debugDescription` getter |
| 21 | 13,883 | Foundation | `_CalendarGregorian._ordinality(of:in:for:)` |
| 22 | 12,398 | Foundation (ICU) | `icu_76::RegexMatcher::MatchChunkAt` |
| 23 | 12,304 | Foundation | `DateComponents.ISO8601FormatStyle.components(from:…)` |
| 24 | 12,187 | Swift stdlib | `SIMD3.debugDescription` getter |
| 25 | 12,109 | Swift stdlib | `swift_umutablecptrie_buildImmutable` (Unicode trie builder) |
| 26 | 11,989 | Swift stdlib | `BinaryFloatingPoint._convert(from:value:exact:)` specialization |
| 27 | 11,832 | Foundation | `_FileOperations._copyRegularFile` specialization (copy delegate) |
| 28 | 11,832 | Foundation | `_FileOperations._copyRegularFile` specialization (link delegate) |
| 29 | 11,523 | Swift stdlib | `EncodingError.debugDescription` getter |
| 30 | 11,170 | Swift stdlib | `BinaryFloatingPoint._convert` partial specialization |

**Attribution bucket summary:**

| Bucket | Functions in top 30 | Total bytes |
|---|---:|---:|
| Swift stdlib | 18 | ~435,448 |
| Foundation (FoundationEssentials) | 6 | ~92,196 |
| Foundation (ICU — icu_76) | 4 | ~74,812 |
| Foundation (CoreFoundation) | 2 | ~35,438 |
| JavaScriptKit | 0 | — |
| Swiflow | 0 | — |
| App (HelloWorld) | 0 | — |

**What dominates and why:** The top 30 functions are entirely Swift
stdlib and Foundation — zero JavaScriptKit, zero Swiflow, zero app code.
The stdlib dominates with Unicode/Regex classification tables (functions
#1, #2, #14, #17) and SIMD `debugDescription` getters (#4, #5, #6, #11,
#20, #24). The SIMD getters are pulled in transitively through `Mirror`
(used by `@State`'s property enumeration) and by `CustomStringConvertible`
conformances in the reflection path. Foundation contributes ICU
internationalization machinery (`DateFormatSymbols`, `RegexMatcher`) and
CoreFoundation string-formatting routines — code that HelloWorld never
calls directly but that gets linked in because Swift's static-linked WASM
SDK does not dead-strip unused library code at the same granularity as a
native dylib. The two C++ runtime demangler functions (#3, #8) are required
for `Mirror` type-name lookup at runtime. The effective floor for function-
level savings via `-Osize` is constrained by the stdlib/Foundation
baseline: they are already compiled with Apple's settings and we cannot
recompile the SDK. `-Osize` will save code in the app and Swiflow layers,
which are small; the bulk of the Code section comes from the SDK and
stdlib.

## The reflection wall

`@State` uses `Mirror` to enumerate properties on a `Component` at mount.
That ties us to Swift's reflection metadata; the compiler flag
`-disable-reflection-metadata` strips it but breaks `@State`.

The measurement above records what we'd save if `@State` were redesigned
to emit explicit accessors via a macro instead of relying on `Mirror`.
The measured saving is only ~44,791 gzipped bytes (~0.25%) — meaning
reflection metadata itself is small, but the functions it pulls in at
runtime (the demangler, `_DebuggerSupport.printForDebuggerImpl`, SIMD
`debugDescription` getters) represent a much larger transitive cost that
would require redesigning the entire `@State` + `Mirror` path to recoup.
That redesign is on the post-1.0 punch list.

## What this audit does *not* measure

- Cost of individual transitive Foundation usage (we don't have
  per-import tooling for Swift-WASM yet; `wasm-tools` requires cargo,
  which was not available on this machine)
- Cost of JavaScriptKit's `JSObject` machinery vs. an ahead-of-time JS
  bridge (different architectural choice; documented as a multi-quarter
  post-1.0 project in `docs/superpowers/specs/2026-05-26-phase14b-wasm-perf-design.md`)
- Savings from `wasm-strip` targeting the `name` section (Task 5): the
  `name` custom section is already absent from the PackageToJS-emitted
  artifact — confirmed by `wasm-objdump -h` showing no `name` section.
  Task 5's `wasm-strip` invocation has no effect on the shipped WASM and
  can be dropped from the plan or redirected to another target.
