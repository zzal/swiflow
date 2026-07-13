// Sources/SwiflowUI/Theme.swift
import Swiflow

/// Namespace for SwiflowUI's module-level theme surface.
public enum SwiflowUI {
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
    /// - `color-gamut: p3` — saturated colors upgrade to `display-p3` (gated on
    ///   `@supports color()`; the sRGB values above are the fallback).
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

          /* surfaces & text */
          --sw-bg: light-dark(#f6f7f9, #0d0d0d);        /* page/canvas — surfaces lift off this */
          --sw-surface: light-dark(#ffffff, #1a1a1a);
          --sw-surface-2: light-dark(#f3f4f6, #242424);
          --sw-text: light-dark(#111111, #f5f5f5);
          --sw-text-muted: light-dark(#5b616b, #9ca3af);

          /* accent & semantic colors */
          --sw-accent: light-dark(#3b82f6, #60a5fa);
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
          --sw-danger: light-dark(#dc2626, #f87171);
          /* danger hover/active/text mirror the accent family exactly, so
             re-pointing --sw-danger cascades the whole destructive palette
             (Button .danger). Literal fallbacks first, same convention. */
          --sw-danger-hover: light-dark(#b91c1c, #ef4444);
          --sw-danger-hover: light-dark(oklch(from var(--sw-danger) calc(l - 0.08) c h), oklch(from var(--sw-danger) calc(l + 0.08) c h));
          --sw-danger-active: light-dark(#991b1b, #dc2626);
          --sw-danger-active: light-dark(oklch(from var(--sw-danger) calc(l - 0.16) c h), oklch(from var(--sw-danger) calc(l + 0.16) c h));
          --sw-danger-text: light-dark(#ffffff, #450a0a);
          --sw-danger-text: contrast-color(var(--sw-danger));
          --sw-success: light-dark(#16a34a, #4ade80);
          --sw-warning: light-dark(#b45309, #fbbf24);
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
          --sw-border: light-dark(#e5e7eb, #333333);
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

        /* Wide gamut: richer saturated colors; the sRGB values above are the fallback.
           Gated on @supports so a p3 display lacking color() keeps the sRGB values. */
        @media (color-gamut: p3) {
          @supports (color: color(display-p3 0 0 0)) {
            :root {
              --sw-accent: light-dark(color(display-p3 0.21 0.51 0.96), color(display-p3 0.4 0.66 0.98));
              --sw-danger: light-dark(color(display-p3 0.82 0.18 0.18), color(display-p3 0.96 0.5 0.48));
              --sw-success: light-dark(color(display-p3 0.15 0.63 0.32), color(display-p3 0.42 0.86 0.55));
              --sw-warning: light-dark(color(display-p3 0.68 0.33 0.04), color(display-p3 0.98 0.75 0.14));
            }
          }
        }
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
