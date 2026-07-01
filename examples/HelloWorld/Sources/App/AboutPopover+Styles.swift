// Sources/App/AboutPopover+Styles.swift
import Swiflow

extension AboutPopover {
    // The component root carries .info-card itself, so the rule compounds
    // with the scope class via `&.info-card`.
    @MainActor static var scopedStyles: CSSSheet? = #css("""
        &.info-card {
          position-anchor: --info-anchor;
          position-area: bottom span-right;
          /* Popover top-layer reset. */
          margin: 0.5rem 0 0 0;
          padding: 0.75rem 1rem;
          background: color-mix(in oklab, Canvas 92%, CanvasText);
          color: CanvasText;
          border: 1px solid color-mix(in oklab, CanvasText 12%, transparent);
          border-radius: 12px;
          box-shadow: 0 12px 32px -12px rgb(0 0 0 / .35);
          max-width: 280px;
          font-size: 0.9375rem;
        }
        h3 {
          margin: 0 0 0.25rem 0;
          font-size: 0.95rem;
          font-weight: 600;
        }
        .body {
          margin: 0 0 0.5rem 0;
          color: color-mix(in oklab, CanvasText 80%, Canvas);
        }
        a {
          color: color-mix(in oklab, CanvasText 70%, blue);
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
        """)
}
