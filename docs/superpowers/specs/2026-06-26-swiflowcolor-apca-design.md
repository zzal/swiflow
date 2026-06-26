# APCA advisory in SwiflowColor — Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** M8 follow-up — the **"APCA as an opt-in algorithm"** item deferred since the
> palette generator shipped.
> **Builds on:** the WCAG 2.x contrast pipeline + `validateAccentFamily` / `validateStatusFamily`
> in `Sources/SwiflowColor/ContrastColor.swift`.

## Problem

`swiflow theme` validates every generated color against **WCAG 2.x** contrast ratios — a good
legal-standard gate, but WCAG 2.x is known to mis-rate some color pairs perceptually (notably
mid-tone and dark-mode combinations). **APCA** (Accessible Perceptual Contrast Algorithm, the
WCAG 3 draft method) is a perceptual model that often disagrees with WCAG 2.x and is increasingly
used by designers. We want APCA available as a **second opinion** without disturbing the existing,
trusted WCAG gate.

## Goal

When a generated seed **fails** the WCAG gate, show its **APCA Lc** (and the usage-recommended Lc)
alongside the WCAG ratio in the same diagnostic — a perceptual cross-check exactly when something
is already wrong. WCAG 2.x remains the **sole gate**; APCA never blocks, and a fully passing
palette produces byte-identical output to today.

## Decisions (from brainstorming)

1. **Advisory, not a gate.** WCAG 2.x stays the only build gate; APCA is informational. (A
   selectable `--contrast apca` gate was considered and **declined**.)
2. **Surfaced on WCAG failures only.** No new CLI flag, no report flag, no output on a passing
   palette. (An opt-in `--contrast-report` table was considered and **declined** as extra surface.)
3. **`SwiflowColor` stays test/CLI-internal.** This does not undertake the separate
   "promote `SwiflowColor` to a public generator" deferral.

## APCA function — `Color.apcaContrast(textHex:bgHex:) -> Double`

A new `public static` function in `SwiflowColor` (public for test reach, exactly like
`wcagContrast`). Returns a **signed APCA Lc** (range ≈ −108…106); callers use the magnitude.

- **Algorithm version:** APCA-W3 **0.1.9** constants, pinned and documented inline with the version
  string. Constants: `mainTRC = 2.4`; coefficients `R 0.2126 / G 0.7152 / B 0.0722`; soft-clamp
  `blkThrs = 0.022`, `blkClmp = 1.414`; polarity exponents `normBG 0.56 / normTXT 0.57` (dark text
  on light) and `revTXT 0.62 / revBG 0.65` (light text on dark); `scale = 1.14`; low-contrast
  offsets `0.027`; `deltaYmin = 0.0005`; `loClip = 0.1`.
- **Color model:** APCA uses its **own sRGB-encoded `^2.4` luminance model** (`Ys`), distinct from
  the WCAG *linear-light* pipeline elsewhere in this file. The function therefore works from the
  sRGB 0…1 channels of each hex (parsed directly — not via the linear `hex()` path), computes `Ys`
  for text and background, applies the black soft-clamp, then the **polarity-specific** estimate.
  Polarity is decided by which input is text vs background — never ambiguous here, because the
  validators always know that pairing.
- **Output:** the standard APCA `Lc = Sapc × 100` with the low-contrast offset/clip applied;
  near-zero contrasts return `0`. Sign encodes polarity (negative = light-on-dark); callers compare
  `abs(lc)` against a target.

## Usage → recommended-Lc mapping (guidance only)

A small internal table maps each validated usage to an APCA target, shown as advice — **never
enforced**:

| Usage (as the validator already classifies it) | Recommended Lc |
|---|---|
| **Text:** error text (`--danger`), every `-strong` text-on-tint, accent-as-text/link, solid-fill `-text` | **75** (APCA "fluent text") |
| **Non-text:** `--success` / `--warning` / `--info` used as a border/tint UI color | **45** (APCA spot/UI-element minimum) |

These targets are advisory guidance, not thresholds; they are easy to retune without affecting any
gate.

## `PaletteFailure` augmentation

`PaletteFailure` (the existing per-token WCAG-shortfall struct) gains two fields:

```swift
public let apcaLc: Double      // signed APCA Lc for this token's text/surface pairing
public let apcaTarget: Double  // the recommended Lc for this usage (75 text / 45 non-text)
```

Its `description` appends an APCA clause to the current WCAG message, e.g.:

```
--sw-danger (light): WCAG 3.90:1 < 4.5 — APCA Lc 68 (suggests ≥ 75 for text)
```

(`abs(apcaLc)` is printed; the magnitude is what designers compare.) The leading WCAG portion is
unchanged, so any test asserting the existing substring still passes.

## Where it plugs in

Both `validateAccentFamily` and `validateStatusFamily` already compute, for each check, the **text
color and the surface it sits on** to run `wcagContrast`. At the point each one constructs a
`PaletteFailure`, it additionally calls `apcaContrast(textHex:bgHex:)` with that same pair and looks
up the usage's recommended Lc, populating the two new fields. No new validation pass, no change to
which colors are checked or to the WCAG targets. `accentThemeCSS` and the CLI are untouched (they
already surface `PaletteFailure.description` on build failure).

## Components & boundaries

| Unit | Change | New? |
|------|--------|------|
| `Color.apcaContrast(textHex:bgHex:)` | APCA-W3 Lc from sRGB, polarity-aware | new |
| `Color.recommendedLc(forText:)` (or inline map) | usage → advisory Lc target | new |
| `PaletteFailure` | `+ apcaLc`, `+ apcaTarget`; `description` shows APCA clause | extended |
| `validateAccentFamily` / `validateStatusFamily` | populate the two fields on each failure | extended |

`SwiflowColor` remains native-only (no wasm dependency added); no CSS, token, or threshold change.

## Testing

- **APCA correctness (`SwiflowColorTests`):** pin published APCA-W3 reference pairs within a small
  tolerance — e.g. `#000` text on `#fff` ≈ Lc 106.04, `#fff` on `#000` ≈ −107.88 (magnitude
  107.88), and one mid-gray pair — and assert the **sign flips** with polarity (text/bg swapped).
- **Mapping:** `recommendedLc` returns 75 for a text usage and 45 for a non-text usage.
- **Diagnostic integration:** a deliberately-failing seed yields a `PaletteFailure` whose
  `description` contains **both** the existing WCAG substring (`WCAG …:1 <`) and the new
  `APCA Lc … suggests ≥ … ` clause; the `apcaLc`/`apcaTarget` fields hold the expected values.
- **No-regression:** a known-good palette produces **zero** `PaletteFailure`s (so no output change),
  and existing `AccentThemeTests` / `StatusSeedTests` / `ThemeCommandTests` stay green.

## Verification

`swift test` green; build the host CLI and run `swiflow theme` with a deliberately-bad seed to eye
the augmented diagnostic; a good seed shows no change ([[ci-skips-example-builds]] doesn't apply —
this is pure `SwiflowColor` + CLI, both compiled by host CI). Update no guide content beyond a brief
note that failed-seed diagnostics now include an APCA reading.

## Non-goals

- **No gate, no CLI flag.** APCA never blocks a build; `--contrast apca` / `--contrast-report` are
  out of scope (both declined in brainstorming).
- **No public `SwiflowColor` promotion** — that is a separate M8 deferral.
- **No change** to the shipped CSS, tokens, WCAG thresholds, or `accentThemeCSS` output.
- **No vendored APCA code** — the formula is reimplemented clean-room from the published APCA-W3
  constants.

## Open flag for spec review

**APCA licensing/version.** The implementation is a clean-room reimplementation of the *published*
APCA-W3 0.1.9 formula and constants (no copied source), used only for an internal, advisory,
non-gating readout. APCA-W3 is being standardized under W3C terms; a from-scratch reimplementation
for this scope is low-risk. Flagged here so it can be vetoed before implementation if preferred.

## Decisions resolved during brainstorming

1. **Role** → advisory alongside WCAG (selectable-gate and gate+advisory rejected).
2. **Surface** → on WCAG failures only (opt-in report flag rejected).
3. **Scope** → `SwiflowColor`-internal advisory; no public promotion, no CSS/threshold change.
4. **Targets** → Lc 75 for text usages, Lc 45 for non-text/border usages (advisory, retunable).
5. **Provenance** → clean-room APCA-W3 0.1.9; flagged for licensing veto at spec review.
