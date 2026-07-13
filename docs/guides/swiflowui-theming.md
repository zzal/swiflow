# SwiflowUI theming

SwiflowUI's one load-bearing rule:

> **Components only ever read `--sw-*` tokens — they never branch on user or device
> preferences.** All responsiveness lives in one place, as `@media` blocks that
> re-point tokens. Every component adapts for free.

So you re-skin the whole library by overriding tokens, and the library adapts to dark
mode / contrast / reduced motion / reduced transparency / wide gamut without any
per-component code. The token contract lives in
`Sources/SwiflowUI/Theme.swift` (`SwiflowUI.baseStyleSheet`), injected once at
`:root`.

## The token contract

| Group | Tokens |
|------|--------|
| **Spacing** | `--sw-space-xs` `--sw-space-sm` `--sw-space-md` `--sw-space-lg` `--sw-space-xl` |
| **Radius** | `--sw-radius-sm` `--sw-radius` |
| **Surfaces & text** | `--sw-bg` (page) `--sw-surface` `--sw-surface-2` `--sw-text` `--sw-text-muted` |
| **Accent & semantic** | `--sw-accent` `--sw-accent-hover` `--sw-accent-active` `--sw-accent-text` `--sw-danger` `--sw-success` `--sw-warning` `--sw-info` (aliases `--sw-accent`) |
| **"Strong" text variants** | `--sw-accent-strong` `--sw-danger-strong` `--sw-success-strong` `--sw-warning-strong` `--sw-info-strong` |
| **Border, focus, elevation** | `--sw-border` `--sw-border-width` `--sw-focus-ring` `--sw-focus-ring-width` `--sw-focus-shadow` (the composed macOS-style ring: a half-opaque `box-shadow` halo controls animate to on focus) `--sw-shadow` |
| **Motion** | `--sw-duration` `--sw-ease` `--sw-anim-play` |
| **Affordances** | `--sw-disabled-opacity` |
| **Overlay** | `--sw-overlay-bg` `--sw-backdrop` |

Two conventions worth knowing:

- **`light-dark()` everywhere.** Color tokens are `light-dark(<light>, <dark>)`, and
  `:root` sets `color-scheme: light dark`. That single mechanism gives you dark mode
  (see below) *and* makes native form controls render their dark variant.
- **"Strong" variants exist for tinted text.** A soft tint of `--sw-accent` (e.g. a
  Badge background) is too pale to carry the mid-tone `--sw-accent` as *text* in light
  mode (fails WCAG). Components that put a semantic color on a tint of itself use the
  `-strong` token for the text. Reach for `-strong` if you do the same.
- **Motion is two tokens, never a shorthand.** Components name the property they
  animate (`transition: color var(--sw-duration) var(--sw-ease)`) and gate keyframe
  animations on `animation-play-state: var(--sw-anim-play)`. A `transition: all`
  shorthand would animate everything — don't.

## The media-feature layers

`baseStyleSheet` re-points tokens under each media feature. You get all of this for
free by reading tokens:

| Feature | What changes |
|---------|--------------|
| `prefers-color-scheme` | handled inline by `light-dark()` (no `@media` needed) |
| `prefers-contrast: more` | pure text, heavier `--sw-border-width` / `--sw-focus-ring-width`, and `--sw-shadow` becomes a solid ring |
| `prefers-reduced-motion: reduce` | `--sw-duration: 0s` and `--sw-anim-play: paused` — transitions/animations stop |
| `prefers-reduced-transparency: reduce` | `--sw-overlay-bg` solidifies, `--sw-backdrop: none` |
| `color-gamut: p3` | saturated colors upgrade to `display-p3` (gated on `@supports color()`; sRGB is the fallback) |

## Re-skinning via tokens

Override any token in your own `:root` (or a scoped block) — every component follows,
no component code touched. This is the primary customization path:

```html
<style>
  :root {
    --sw-accent: rebeccapurple;
    --sw-accent-hover: color-mix(in oklab, rebeccapurple 85%, black);
    --sw-radius: 12px;
    --sw-space-md: 1rem;
  }
</style>
```

> Your `:root` overrides win because SwiflowUI's base tokens ship in `@layer swiflow.base`
> — any unlayered rule (your `index.html`, a `swiflow theme` `theme.css`, the `Theme`
> component) beats a layer regardless of source order, so the override applies even though
> the base sheet is injected at runtime.

### Generating a theme from brand colors

`swiflow theme --primary "#7c3aed"` derives a contrast-validated `--sw-accent` family and prints
a `:root` override (use `--out theme.css` to write a file, then link it after SwiflowUI's styles).
Add optional seeds:

- `--neutrals` — also derive the accent-tinted neutral ramp (surfaces/text/border).
- `--danger "#e11d48"` — set the brand danger/error color (validated as error text, ≥ 4.5:1).
- `--success "#059669"` — set the brand success color (validated as a UI/border color, ≥ 3:1).
- `--warning "#d97706"` — set the brand warning color (amber; validated as a UI/border color, ≥ 3:1).
- `--info "#0284c7"` — set the brand info color (defaults to the accent if unset; validated ≥ 3:1).

```text
swiflow theme --primary "#7c3aed" --danger "#e11d48" --success "#059669" --warning "#d97706" --info "#0284c7" --neutrals --out theme.css
```

Each seed is WCAG-validated for the way that token is actually rendered; a color that can't meet
its bar fails the build with a per-token diagnostic rather than shipping an unreadable theme.

When a seed fails, its diagnostic also includes an **APCA** (perceptual) reading — e.g.
`APCA Lc 68 (suggests ≥ 75 for text)` — as a second opinion alongside the WCAG ratio. APCA is
advisory only: WCAG 2.x remains the gate, and a passing palette prints nothing extra.

The generator is also a public Swift library — see [SwiflowColor](swiflowcolor.md) to call
`ThemeGenerator.generate` from your own host tooling instead of the CLI.

Generated accent/status colors ship a progressive `oklch()` line after their hex fallback, so they
render at the **display-P3 gamut edge** on capable screens (richer color; identical sRGB hex
fallback elsewhere). Lightness and hue are preserved, so contrast is unchanged. Neutrals stay
hex-only (grays gain nothing from a wider gamut).

Scope an override to a subtree by setting tokens on a container:

```swift
section(.style("--sw-accent", "var(--brand-teal)")) {
    Button("Branded") { … }   // teal here only
}
```

## Dark mode

Because every color is `light-dark()`, dark mode is driven by `color-scheme`:

- **Follow the OS:** nothing to do — `prefers-color-scheme` resolves `light-dark()`.
- **Force a scheme:** set `color-scheme` on a root element. A theme toggle is just
  `@State`:

```swift
.style("color-scheme", isDark ? "dark" : "light")
```

Forcing `color-scheme` re-resolves every descendant's `light-dark()` tokens live —
this is how the SwiflowUIDemo dark-mode switch works (it does *not* use a
`prefers-color-scheme` media query).

## Going deeper with `#css`

Tokens cover re-skinning. For structural tweaks, use the `#css` macro on your own
components (see the [styling guide](styling.md)) — it composes with the tokens:

```swift
static var scopedStyles: CSSSheet? = #css("""
    .stat-card {
      background: var(--sw-surface);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      padding: var(--sw-space-lg);
    }
    """)
```

> The `sw-` class prefix is reserved for SwiflowUI. Override **token values** and
> author CSS on **your own** classes; don't write rules against `.sw-*` internals
> (they're not a stable API). A scoped `button { }` / `input { }` rule will also win
> over the `.sw-*` styling by specificity — name your own classes instead.

## How components get their styles (the two seams)

You rarely need this, but for context:

- **Stateless controls** (Button, the fields, feedback) inject a single global
  `.sw-*` utility sheet once via `installControlSheet` — unscoped, token-only raw CSS.
- **Overlays** share a global `.sw-dialog` chrome sheet (Alert/Prompt) or their own
  `.sw-toast*` sheet; they're `@Component`s for behavior, but their *styling* is the
  same global-sheet approach.

Both read only tokens, so the media layers above apply uniformly.

## Verifying

- Unit-test the emitted CSS: assert each `@media` token layer is present in
  `SwiflowUI.baseStyleSheet.cssString(scopeClass: "")`.
- In Playwright, `page.emulateMedia({ colorScheme, reducedMotion, contrast })` and
  assert components actually respond (palette flips, transitions disabled, heavier
  borders). `prefers-reduced-transparency` and `color-gamut` aren't emulable today —
  cover them with the emitted-CSS test plus a manual check.
