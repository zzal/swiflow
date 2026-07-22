// Sources/SwiflowUI/Theme.swift
import Swiflow

/// Namespace for SwiflowUI's module-level theme surface.
public enum SwiflowUI {
    /// The base sheet's absolute-oklch token values, authored with SwiflowUI's own typed
    /// `Color` — dogfooding the OKLCH definition API on our own hardest internal case, and a
    /// single Swift source of truth for the palette. ONLY absolute-oklch arms live here: the
    /// hex `@property` floors, the `light-dark()` wrappers, the `oklch(from …)` derivations,
    /// and `contrast-color()` stay raw in `baseStyleSheet` (`Color` models absolute oklch only).
    /// `.css` reproduces the exact strings the sheet shipped, so the emitted CSS is byte-identical
    /// — the palette-pin test in `ThemeTests` is the guard.
    private enum Palette {
        // Accent & status (light arm, dark arm) — chroma pushed toward the P3 gamut edge.
        static let accentLight  = Color.oklch(l: 0.6212, c: 0.2051, h: 254.13)
        static let accentDark   = Color.oklch(l: 0.7218, c: 0.1539, h: 249.3)
        static let dangerLight  = Color.oklch(l: 0.5795, c: 0.234,  h: 26)
        static let dangerDark   = Color.oklch(l: 0.7402, c: 0.1748, h: 22.79)
        static let successLight = Color.oklch(l: 0.6136, c: 0.1956, h: 153.85)
        static let successDark  = Color.oklch(l: 0.7958, c: 0.1889, h: 154.81)
        static let warningLight = Color.oklch(l: 0.5558, c: 0.1631, h: 49.72)
        static let warningDark  = Color.oklch(l: 0.8395, c: 0.19,   h: 83.48)
        // Neutral ramp (light arm, dark arm) — a faint cool cast keeps grays from reading flat.
        static let bgLight        = Color.oklch(l: 0.9759, c: 0.0029, h: 264.54)
        static let bgDark         = Color.oklch(l: 0.1591, c: 0,      h: 0)
        static let surfaceLight   = Color.oklch(l: 1,      c: 0,      h: 0)
        static let surfaceDark    = Color.oklch(l: 0.2178, c: 0,      h: 0)
        static let surface2Light  = Color.oklch(l: 0.967,  c: 0.0029, h: 264.54)
        static let surface2Dark   = Color.oklch(l: 0.2603, c: 0,      h: 0)
        static let textLight      = Color.oklch(l: 0.1776, c: 0,      h: 0)
        static let textDark       = Color.oklch(l: 0.9702, c: 0,      h: 0)
        static let textMutedLight = Color.oklch(l: 0.4909, c: 0.0177, h: 260.71)
        static let textMutedDark  = Color.oklch(l: 0.7137, c: 0.0192, h: 261.32)
        static let borderLight    = Color.oklch(l: 0.9276, c: 0.0058, h: 264.53)
        static let borderDark     = Color.oklch(l: 0.3211, c: 0,      h: 0)
        // Tooltip bubble — same in both schemes (inverted-bubble idiom).
        static let tooltipBg      = Color.oklch(l: 0.3729, c: 0.0306, h: 259.73)
        static let tooltipText    = Color.oklch(l: 1,      c: 0,      h: 0)
    }

    /// The design-token contract: the full `--sw-*` vocabulary at `:root`, plus
    /// the media-feature override layers that re-point those tokens.
    ///
    /// The load-bearing rule of SwiflowUI theming: **components only ever read
    /// `--sw-*` tokens — they never branch on user/device preferences.** All
    /// responsiveness lives here, expressed once as `@media` blocks that
    /// re-point tokens, so every component adapts for free:
    ///
    /// - `prefers-color-scheme` — handled inline by `light-dark()` in every
    ///   color token (`color-scheme: light dark` on `:root` enables it, and is
    ///   also what makes native form controls render in the dark variant).
    /// - `prefers-contrast: more` — stronger text/border colors, heavier border
    ///   and focus ring.
    /// - `prefers-reduced-motion: reduce` — `--sw-duration` collapses to `0s`
    ///   and `--sw-anim-play` pauses, so transitions and animations stop.
    /// - `prefers-reduced-transparency: reduce` — overlay scrim solidifies,
    ///   `--sw-backdrop` drops to `none`.
    /// - `color-gamut: p3` — NO explicit layer: accent/status tokens are authored as
    ///   absolute `oklch()`, which the browser renders in the display's own gamut (wider
    ///   on P3, gamut-mapped to sRGB elsewhere), so no `@media`/`@supports` block is needed.
    ///
    /// Motion is two orthogonal tokens, never a `transition` shorthand: a
    /// shorthand would default `transition-property: all` and animate every
    /// property. Components name their own: `transition: color var(--sw-duration)
    /// var(--sw-ease)`; animations gate on `animation-play-state: var(--sw-anim-play)`.
    ///
    /// Authored as one raw `:root` sheet because `:root`/`@media` must stay
    /// unscoped and raw CSS is the clearest representation of an unscoped token
    /// contract. RAW IS FOR UNSCOPED CSS ONLY — `:root` here, and the global
    /// `.sw-*` utility-class sheets that stateless skinned controls inject (e.g.
    /// `buttonStyleSheet`). Per-instance *scoped* component styles must use the
    /// `rule(_:)`/`media(_:)` builders so their rules get the scope class.
    public static let baseStyleSheet: CSSSheet = css {
        raw("""
        /* Register the scalar tokens so they are TYPE-VALIDATED and ANIMATABLE.
           @property is layer-agnostic and sits outside the cascade layer below.
           initial-value is the bottom-of-cascade fallback only — :root below always
           sets each token, and unlayered app overrides still win. */
        @property --sw-space-xs { syntax: "<length>"; inherits: true; initial-value: 0.25rem; }
        @property --sw-space-sm { syntax: "<length>"; inherits: true; initial-value: 0.5rem; }
        @property --sw-space-md { syntax: "<length>"; inherits: true; initial-value: 0.75rem; }
        @property --sw-space-lg { syntax: "<length>"; inherits: true; initial-value: 1.25rem; }
        @property --sw-space-xl { syntax: "<length>"; inherits: true; initial-value: 2rem; }
        @property --sw-radius-sm { syntax: "<length>"; inherits: true; initial-value: 4px; }
        @property --sw-radius { syntax: "<length>"; inherits: true; initial-value: 6px; }
        @property --sw-border-width { syntax: "<length>"; inherits: true; initial-value: 1px; }
        @property --sw-focus-ring-width { syntax: "<length>"; inherits: true; initial-value: 3px; }
        @property --sw-duration { syntax: "<time>"; inherits: true; initial-value: 150ms; }
        @property --sw-disabled-opacity { syntax: "<number>"; inherits: true; initial-value: 0.5; }
        /* Color tokens registered as <color>. initial-value must be computation-independent
           (no light-dark()/var()/relative color) — the light-arm hex is the fallback floor.
           The literal→oklch(from) double-declarations in :root are unaffected: an unsupported
           oklch(from …) is rejected at PARSE time (before registered-syntax validation), so the
           literal still wins on pre-Baseline engines exactly as before registration. */
        @property --sw-bg { syntax: "<color>"; inherits: true; initial-value: #f6f7f9; }
        @property --sw-surface { syntax: "<color>"; inherits: true; initial-value: #ffffff; }
        @property --sw-surface-2 { syntax: "<color>"; inherits: true; initial-value: #f3f4f6; }
        @property --sw-text { syntax: "<color>"; inherits: true; initial-value: #111111; }
        @property --sw-text-muted { syntax: "<color>"; inherits: true; initial-value: #5b616b; }
        @property --sw-tooltip-bg { syntax: "<color>"; inherits: true; initial-value: #374151; }
        @property --sw-tooltip-text { syntax: "<color>"; inherits: true; initial-value: #ffffff; }
        @property --sw-field-label-width { syntax: "<length>"; inherits: true; initial-value: 10rem; }
        @property --sw-accent { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
        @property --sw-accent-hover { syntax: "<color>"; inherits: true; initial-value: #2563eb; }
        @property --sw-accent-active { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-accent-text { syntax: "<color>"; inherits: true; initial-value: #0b1220; }
        @property --sw-danger { syntax: "<color>"; inherits: true; initial-value: #dc2626; }
        @property --sw-danger-hover { syntax: "<color>"; inherits: true; initial-value: #b91c1c; }
        @property --sw-danger-active { syntax: "<color>"; inherits: true; initial-value: #991b1b; }
        @property --sw-danger-text { syntax: "<color>"; inherits: true; initial-value: #ffffff; }
        @property --sw-success { syntax: "<color>"; inherits: true; initial-value: #16a34a; }
        @property --sw-warning { syntax: "<color>"; inherits: true; initial-value: #b45309; }
        @property --sw-info { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
        @property --sw-accent-strong { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-danger-strong { syntax: "<color>"; inherits: true; initial-value: #b91c1c; }
        @property --sw-success-strong { syntax: "<color>"; inherits: true; initial-value: #15803d; }
        @property --sw-warning-strong { syntax: "<color>"; inherits: true; initial-value: #92400e; }
        @property --sw-info-strong { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-border { syntax: "<color>"; inherits: true; initial-value: #e5e7eb; }
        @property --sw-focus-ring { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
        @property --sw-font-size-xs { syntax: "<length>"; inherits: true; initial-value: 0.75rem; }
        @property --sw-font-size-sm { syntax: "<length>"; inherits: true; initial-value: 0.875rem; }
        @property --sw-font-size-md { syntax: "<length>"; inherits: true; initial-value: 1rem; }
        @property --sw-font-size-lg { syntax: "<length>"; inherits: true; initial-value: 1.125rem; }
        @property --sw-font-size-xl { syntax: "<length>"; inherits: true; initial-value: 1.5rem; }
        @property --sw-font-size-2xl { syntax: "<length>"; inherits: true; initial-value: 2rem; }
        @property --sw-font-weight-regular { syntax: "<number>"; inherits: true; initial-value: 400; }
        @property --sw-font-weight-medium { syntax: "<number>"; inherits: true; initial-value: 500; }
        @property --sw-font-weight-semibold { syntax: "<number>"; inherits: true; initial-value: 600; }
        @property --sw-line-height { syntax: "<number>"; inherits: true; initial-value: 1.5; }
        @property --sw-line-height-tight { syntax: "<number>"; inherits: true; initial-value: 1.25; }
        @property --sw-container-sm { syntax: "<length>"; inherits: true; initial-value: 30ch; }
        @property --sw-container-md { syntax: "<length>"; inherits: true; initial-value: 60ch; }
        @property --sw-container-lg { syntax: "<length>"; inherits: true; initial-value: 90ch; }
        @property --sw-container-xl { syntax: "<length>"; inherits: true; initial-value: 120ch; }

        @layer swiflow.base {
        :root {
          color-scheme: light dark;

          /* spacing scale */
          --sw-space-xs: 0.25rem;
          --sw-space-sm: 0.5rem;
          --sw-space-md: 0.75rem;
          --sw-space-lg: 1.25rem;
          --sw-space-xl: 2rem;

          /* type scale (M14) */
          --sw-font-size-xs: 0.75rem;
          --sw-font-size-sm: 0.875rem;
          --sw-font-size-md: 1rem;
          --sw-font-size-lg: 1.125rem;
          --sw-font-size-xl: 1.5rem;
          --sw-font-size-2xl: 2rem;
          --sw-font-weight-regular: 400;
          --sw-font-weight-medium: 500;
          --sw-font-weight-semibold: 600;
          --sw-line-height: 1.5;
          --sw-line-height-tight: 1.25;

          /* container widths (M14) */
          --sw-container-sm: 30ch;
          --sw-container-md: 60ch;
          --sw-container-lg: 90ch;
          --sw-container-xl: 120ch;

          /* radii */
          --sw-radius-sm: 4px;
          --sw-radius: 6px;

          /* surfaces & text — authored in oklch (perceptual; the @property hex floor
             above is the pre-oklch fallback). Neutrals carry a faint cool cast (tiny C). */
          --sw-bg: light-dark(\(Palette.bgLight.css), \(Palette.bgDark.css));        /* page/canvas — surfaces lift off this */
          --sw-surface: light-dark(\(Palette.surfaceLight.css), \(Palette.surfaceDark.css));
          --sw-surface-2: light-dark(\(Palette.surface2Light.css), \(Palette.surface2Dark.css));
          --sw-text: light-dark(\(Palette.textLight.css), \(Palette.textDark.css));
          --sw-text-muted: light-dark(\(Palette.textMutedLight.css), \(Palette.textMutedDark.css));
          /* Tooltip bubble: white-on-dark-gray in BOTH schemes (deliberately NOT
             light-dark — an inverted bubble is the tooltip idiom and stays readable
             over any backdrop; 8.4:1 on the gray). Tokens so themes can re-skin it. */
          --sw-tooltip-bg: \(Palette.tooltipBg.css);
          --sw-tooltip-text: \(Palette.tooltipText.css);

          /* Horizontal-field label column (LabeledField layout: .horizontal). */
          --sw-field-label-width: 10rem;

          /* accent & semantic colors — accent/status authored as absolute oklch(): the
             browser renders each in the display's own gamut (wider on P3, gamut-mapped to
             sRGB elsewhere), so no color-gamut media block is needed. The chroma is pushed
             toward the P3 edge; the derived family below reads this via oklch(from …). */
          --sw-accent: light-dark(\(Palette.accentLight.css), \(Palette.accentDark.css));
          /* hover/active derive from --sw-accent (darken in light, lighten in dark) so
             re-pointing --sw-accent cascades the whole accent family. Literal fallback
             first for pre-oklch(from) browsers. */
          --sw-accent-hover: light-dark(#2563eb, #7cb0fb);
          --sw-accent-hover: light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h), oklch(from var(--sw-accent) calc(l + 0.08) c h));
          --sw-accent-active: light-dark(#1d4ed8, #93c1fc);
          --sw-accent-active: light-dark(oklch(from var(--sw-accent) calc(l - 0.16) c h), oklch(from var(--sw-accent) calc(l + 0.16) c h));
          /* Solid-fill text: contrast-color() picks black on the accent (both modes — the
             accent is medium/light blue), fixing today's sub-AA white (3.68:1 on #3b82f6).
             Fallback is dark in BOTH arms so pre-Baseline browsers also pass. See Button. */
          --sw-accent-text: light-dark(#0b1220, #0b1220);
          --sw-accent-text: contrast-color(var(--sw-accent));
          --sw-danger: light-dark(\(Palette.dangerLight.css), \(Palette.dangerDark.css));
          /* danger hover/active/text mirror the accent family exactly, so
             re-pointing --sw-danger cascades the whole destructive palette
             (Button .danger). Literal fallbacks first, same convention. */
          --sw-danger-hover: light-dark(#b91c1c, #ef4444);
          --sw-danger-hover: light-dark(oklch(from var(--sw-danger) calc(l - 0.08) c h), oklch(from var(--sw-danger) calc(l + 0.08) c h));
          --sw-danger-active: light-dark(#991b1b, #dc2626);
          --sw-danger-active: light-dark(oklch(from var(--sw-danger) calc(l - 0.16) c h), oklch(from var(--sw-danger) calc(l + 0.16) c h));
          --sw-danger-text: light-dark(#ffffff, #450a0a);
          --sw-danger-text: contrast-color(var(--sw-danger));
          --sw-success: light-dark(\(Palette.successLight.css), \(Palette.successDark.css));
          --sw-warning: light-dark(\(Palette.warningLight.css), \(Palette.warningDark.css));
          --sw-info: var(--sw-accent);
          /* "strong" = semantic-hue text readable on a 15% tint of that hue.
             Static fallback first (hand-tuned, kept for pre-Baseline browsers); the
             dynamic oklch(from …) derivation below re-pins lightness to clear WCAG 4.5
             on the tint and recomputes when an app overrides the base hue.
             Lightnesses proven by ThemeContrastTests. */
          --sw-accent-strong: light-dark(#1d4ed8, #60a5fa);
          --sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.40 c h), oklch(from var(--sw-accent) 0.80 c h));
          --sw-danger-strong: light-dark(#b91c1c, #f87171);
          --sw-danger-strong: light-dark(oklch(from var(--sw-danger) 0.40 c h), oklch(from var(--sw-danger) 0.80 c h));
          --sw-success-strong: light-dark(#15803d, #4ade80);
          --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.40 c h), oklch(from var(--sw-success) 0.80 c h));
          --sw-warning-strong: light-dark(#92400e, #fbbf24);
          --sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.40 c h), oklch(from var(--sw-warning) 0.80 c h));
          --sw-info-strong: var(--sw-accent-strong);
          --sw-info-strong: light-dark(oklch(from var(--sw-info) 0.40 c h), oklch(from var(--sw-info) 0.80 c h));

          /* borders, focus ring & elevation */
          --sw-border: light-dark(\(Palette.borderLight.css), \(Palette.borderDark.css));
          --sw-border-width: 1px;
          --sw-focus-ring: var(--sw-accent);
          --sw-focus-ring-width: 3px;
          /* macOS-style focus ring: a half-opaque halo hugging the control's border,
             following its border-radius. Controls transition box-shadow to this on
             focus and back on blur (both read --sw-duration → reduced-motion collapses
             it). Overridden to opaque under prefers-contrast: more, below. */
          --sw-focus-shadow: 0 0 0 var(--sw-focus-ring-width) color-mix(in oklab, var(--sw-focus-ring) 50%, transparent);
          /* light-dark() is COLOR-only, so it wraps just the shadow color (not the whole
             value — lengths can't ride light-dark()). Keeping it in color position lets the
             shadow flip with `color-scheme` like every other token; the dark arm leans on a
             higher alpha to stay visible on dark surfaces. */
          --sw-shadow: 0 24px 48px -32px light-dark(rgb(0 0 0 / 0.25), rgb(0 0 0 / 0.45));

          /* motion — components name their own properties:
             transition: <prop> var(--sw-duration) var(--sw-ease)
             animation:  <name> 1s linear infinite;
             animation-play-state: var(--sw-anim-play); */
          --sw-duration: 150ms;
          --sw-ease: ease;
          --sw-anim-play: running;

          /* interactive affordances */
          --sw-disabled-opacity: 0.5;

          /* overlay surface (consumed by the M6 overlays) */
          --sw-overlay-bg: rgb(0 0 0 / 0.5);
          --sw-backdrop: blur(8px);
        }

        /* Higher contrast: pure text, solid heavier borders + focus ring. */
        @media (prefers-contrast: more) {
          :root {
            --sw-text: light-dark(#000000, #ffffff);
            --sw-text-muted: light-dark(#1f2937, #e5e7eb);
            --sw-border: light-dark(#000000, #ffffff);
            --sw-border-width: 2px;
            --sw-focus-ring-width: 4px;
            --sw-focus-shadow: 0 0 0 var(--sw-focus-ring-width) var(--sw-focus-ring);  /* opaque + thicker for contrast */
            --sw-shadow: 0 0 0 var(--sw-border-width) var(--sw-border);  /* solid ring, not a soft shadow */
            /* -strong pushed to WCAG 7 on the tint (proven by ThemeContrastTests). */
            --sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.30 c h), oklch(from var(--sw-accent) 0.88 c h));
            --sw-danger-strong: light-dark(oklch(from var(--sw-danger) 0.30 c h), oklch(from var(--sw-danger) 0.88 c h));
            --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.30 c h), oklch(from var(--sw-success) 0.88 c h));
            --sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.30 c h), oklch(from var(--sw-warning) 0.88 c h));
            --sw-info-strong: light-dark(oklch(from var(--sw-info) 0.30 c h), oklch(from var(--sw-info) 0.88 c h));
          }
        }

        /* Reduced motion: transitions collapse and animations pause. */
        @media (prefers-reduced-motion: reduce) {
          :root {
            --sw-duration: 0s;
            --sw-anim-play: paused;
          }
        }

        /* Reduced transparency: solidify the overlay scrim, drop the backdrop filter. */
        @media (prefers-reduced-transparency: reduce) {
          :root {
            --sw-overlay-bg: rgb(0 0 0 / 0.92);
            --sw-backdrop: none;
          }
        }

        /* No color-gamut media block: the accent/status tokens above are absolute oklch(),
           which the browser already renders in the display's own gamut (wider on P3,
           gamut-mapped to sRGB elsewhere). One declaration, gamut-adaptive by construction. */
        }
        """)
    }

    /// Injects `baseStyleSheet` into `<head>` exactly once. Called automatically
    /// the first time any SwiflowUI primitive renders; also public so apps/tests
    /// can install deterministically up front (safe even before `Swiflow.render`
    /// — the registry buffers until the DOM sink is installed).
    @MainActor
    public static func installBaseStyles() {
        StyleInjectionRegistry.injectOnce(id: "swiflow-ui-base") {
            baseStyleSheet.cssString(scopeClass: "")
        }
    }
}

/// Internal trigger called by every primitive constructor. Idempotent.
@MainActor
func ensureBaseStyles() {
    SwiflowUI.installBaseStyles()
    #if DEBUG
    installStyleTokenValidator()   // arms the --sw- typo warn (see Token.swift)
    #endif
}
