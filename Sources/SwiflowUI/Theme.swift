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
    ///   color token (`color-scheme: light dark` on `:root` enables it).
    /// - `prefers-contrast: more` — stronger text/border colors, heavier border.
    /// - `prefers-reduced-motion: reduce` — motion tokens collapse to `none`/`0s`.
    /// - `prefers-reduced-transparency: reduce` — overlay scrim solidifies, blur off.
    /// - `color-gamut: p3` — saturated colors upgrade to `display-p3` (sRGB above
    ///   is the fallback).
    ///
    /// Authored as one raw `:root` sheet: `:root`/`@media` must stay unscoped,
    /// and raw CSS is the clearest representation of an unscoped token contract.
    /// (Scoped component sheets in later milestones use the `media(_:)` builder
    /// so their rules participate in scoping.)
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
          --sw-surface: light-dark(#ffffff, #1a1a1a);
          --sw-surface-2: light-dark(#f3f4f6, #242424);
          --sw-text: light-dark(#111111, #f5f5f5);
          --sw-text-muted: light-dark(#6b7280, #9ca3af);

          /* borders */
          --sw-border: light-dark(#e5e7eb, #333333);
          --sw-border-width: 1px;

          /* accent & semantic colors */
          --sw-accent: light-dark(#3b82f6, #60a5fa);
          --sw-accent-text: light-dark(#ffffff, #0b1220);
          --sw-danger: light-dark(#dc2626, #f87171);
          --sw-success: light-dark(#16a34a, #4ade80);

          /* motion */
          --sw-transition: 150ms ease;
          --sw-anim-duration: 150ms;

          /* overlay surface (consumed by the M6 overlays) */
          --sw-overlay-bg: rgb(0 0 0 / 0.5);
          --sw-backdrop-blur: 8px;
        }

        /* Higher contrast: pure text, solid heavier borders. */
        @media (prefers-contrast: more) {
          :root {
            --sw-text: light-dark(#000000, #ffffff);
            --sw-text-muted: light-dark(#1f2937, #e5e7eb);
            --sw-border: light-dark(#000000, #ffffff);
            --sw-border-width: 2px;
          }
        }

        /* Reduced motion: any component reading these tokens stops animating. */
        @media (prefers-reduced-motion: reduce) {
          :root {
            --sw-transition: none;
            --sw-anim-duration: 0s;
          }
        }

        /* Reduced transparency: solidify the overlay scrim, drop the blur. */
        @media (prefers-reduced-transparency: reduce) {
          :root {
            --sw-overlay-bg: rgb(0 0 0 / 0.92);
            --sw-backdrop-blur: 0px;
          }
        }

        /* Wide gamut: richer saturated colors; the sRGB values above are the fallback. */
        @media (color-gamut: p3) {
          :root {
            --sw-accent: light-dark(color(display-p3 0.21 0.51 0.96), color(display-p3 0.4 0.66 0.98));
            --sw-danger: light-dark(color(display-p3 0.82 0.18 0.18), color(display-p3 0.96 0.5 0.48));
            --sw-success: light-dark(color(display-p3 0.15 0.63 0.32), color(display-p3 0.42 0.86 0.55));
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
