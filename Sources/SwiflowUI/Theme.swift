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
        :root {
          color-scheme: light dark;

          /* spacing scale */
          --sw-space-xs: 0.25rem;
          --sw-space-sm: 0.5rem;
          --sw-space-md: 0.75rem;
          --sw-space-lg: 1.25rem;
          --sw-space-xl: 2rem;

          /* radii */
          --sw-radius-sm: 4px;
          --sw-radius: 8px;

          /* surfaces & text */
          --sw-bg: light-dark(#f6f7f9, #0d0d0d);        /* page/canvas — surfaces lift off this */
          --sw-surface: light-dark(#ffffff, #1a1a1a);
          --sw-surface-2: light-dark(#f3f4f6, #242424);
          --sw-text: light-dark(#111111, #f5f5f5);
          --sw-text-muted: light-dark(#5b616b, #9ca3af);

          /* accent & semantic colors */
          --sw-accent: light-dark(#3b82f6, #60a5fa);
          --sw-accent-hover: light-dark(#2563eb, #7cb0fb);
          --sw-accent-active: light-dark(#1d4ed8, #93c1fc);
          --sw-accent-text: light-dark(#ffffff, #0b1220);
          --sw-danger: light-dark(#dc2626, #f87171);
          --sw-success: light-dark(#16a34a, #4ade80);
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

          /* borders, focus ring & elevation */
          --sw-border: light-dark(#e5e7eb, #333333);
          --sw-border-width: 1px;
          --sw-focus-ring: var(--sw-accent);
          --sw-focus-ring-width: 2px;
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
            --sw-focus-ring-width: 3px;
            --sw-shadow: 0 0 0 var(--sw-border-width) var(--sw-border);  /* solid ring, not a soft shadow */
            /* -strong pushed to WCAG 7 on the tint (proven by ThemeContrastTests). */
            --sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.30 c h), oklch(from var(--sw-accent) 0.88 c h));
            --sw-danger-strong: light-dark(oklch(from var(--sw-danger) 0.30 c h), oklch(from var(--sw-danger) 0.88 c h));
            --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.30 c h), oklch(from var(--sw-success) 0.88 c h));
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
func ensureBaseStyles() { SwiflowUI.installBaseStyles() }
