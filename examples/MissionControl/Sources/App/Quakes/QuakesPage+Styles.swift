// Sources/App/Quakes/QuakesPage+Styles.swift
//
// Written with #css — real CSS, structurally validated at compile time,
// scoped to the component via native CSS nesting. The other example pages
// use the css { rule(...) } builder DSL; both are first-class.
import Swiflow

extension QuakesPage {
    static var scopedStyles: CSSSheet? = #css("""
        :host {
          display: block;
          max-width: 860px;
          margin: 0 auto;
          padding: 0 var(--sw-space-lg) var(--sw-space-xl);
        }

        h1 {
          font-size: 1.4rem;
          margin: 0;
        }

        .filters select {
          padding: var(--sw-space-xs) var(--sw-space-sm);
          border-radius: var(--sw-radius);
          font: inherit;
        }

        .feed-meta {
          margin: 0;
          color: color-mix(in srgb, var(--sw-text) 60%, transparent);
          font-size: 0.85rem;
        }

        .quake-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
        }

        .quake-row {
          display: grid;
          grid-template-columns: 5.5rem 1fr max-content;
          align-items: center;
          gap: var(--sw-space-md);
          padding: var(--sw-space-sm) var(--sw-space-xs);
          border-bottom: 1px solid color-mix(in srgb, var(--sw-text) 10%, transparent);
        }

        .when {
          color: color-mix(in srgb, var(--sw-text) 60%, transparent);
          font-size: 0.85rem;
          font-variant-numeric: tabular-nums;
        }

        .error {
          color: light-dark(#b91c1c, #fca5a5);
        }

        .mag {
          justify-self: start;
          padding: 2px var(--sw-space-sm);
          border-radius: 999px;
          font-size: 0.8rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .mag-low {
          background: color-mix(in srgb, light-dark(#16a34a, #4ade80) 18%, transparent);
          color: light-dark(#166534, #4ade80);
        }
        .mag-mid {
          background: color-mix(in srgb, light-dark(#d97706, #fbbf24) 18%, transparent);
          color: light-dark(#92400e, #fbbf24);
        }
        .mag-high {
          background: color-mix(in srgb, light-dark(#dc2626, #f87171) 22%, transparent);
          color: light-dark(#991b1b, #f87171);
        }

        @keyframes mc-spin {
          to { transform: rotate(360deg); }
        }
        .live-dot {
          display: inline-block;
          color: var(--sw-accent);
          animation: mc-spin 1s linear infinite;
        }
        """)
}
