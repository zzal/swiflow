// Sources/App/Counter+Styles.swift
import Swiflow

extension Counter {
    static var scopedStyles: CSSSheet? = tokens + layout + theme + animations + responsive

    // ---- tokens ----
    // @property and :root escape scoping automatically (hoisted/unscoped).
    static let tokens = #css("""
        @property --accent {
          syntax: "<color>";
          inherits: true;
          initial-value: oklch(.65 .14 250);
        }
        :root {
          --accent: light-dark(oklch(.55 .18 250), oklch(.75 .14 250));
          --surface: light-dark(oklch(.99 0 0), oklch(.18 .005 250));
          --surface-elev: light-dark(oklch(.97 0 0), oklch(.22 .005 250));
          --text: CanvasText;
          --text-dim: color-mix(in oklab, CanvasText 65%, Canvas);
          --border: color-mix(in oklab, CanvasText 12%, transparent);
        }
        """)

    // ---- layout ----
    // The component root carries .card itself, so that rule compounds with
    // the scope class via `&.card`; :host styles the same element at the
    // lower specificity the DSL's host {} block had.
    static let layout = #css("""
        :host {
          display: block;
          max-width: 520px;
          margin: 2.5rem auto;
          padding: 2rem;
          container-type: inline-size;
        }
        &.card {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          padding: 1.75rem;
          border-radius: 16px;
          background: var(--surface);
          border: 1px solid var(--border);
          box-shadow: 0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25);
        }
        .header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          margin: 0;
          padding: 0;
          border: 0;
        }
        .greeting-heading {
          margin: 0;
          font-size: 1.4rem;
          font-weight: 600;
        }
        .info-trigger {
          anchor-name: --info-anchor;
          display: grid;
          place-items: center;
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 50%;
          border: 1px solid var(--border);
          background: transparent;
          color: var(--text-dim);
          cursor: pointer;
          font-size: 0.9rem;
        }
        .actions {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }
        .greeting-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
        }
        .greeting-row input {
          flex: 1;
          padding: 0.4rem 0.6rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: Canvas;
          color: CanvasText;
        }
        .checkbox-row {
          display: flex;
          gap: 0.5rem;
          align-items: center;
          cursor: pointer;
        }
        .inspector {
          border: 1px solid var(--border);
          border-radius: 10px;
          padding: 0.5rem 0.75rem;
          interpolate-size: allow-keywords;
        }
        .inspector summary {
          cursor: pointer;
          list-style: none;
          font-size: 0.95rem;
          color: var(--text-dim);
        }
        .inspector summary::-webkit-details-marker {
          display: none;
        }
        .inspector summary::before {
          content: "▸ ";
          display: inline-block;
          transition: transform .15s ease;
        }
        .inspector[open] summary::before {
          transform: rotate(90deg);
        }
        .inspector-list {
          margin: 0.5rem 0 0 0;
          padding: 0 0 0 1.25rem;
          color: var(--text-dim);
          font-size: 0.9rem;
        }
        """)

    // ---- theme ----
    static let theme = #css("""
        .count {
          margin: 0;
          font-size: 1.6rem;
          font-weight: 600;
          color: var(--accent);
          transition: --accent .25s ease;
        }
        button {
          padding: 0.4rem 0.9rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--accent);
          color: Canvas;
          cursor: pointer;
          font-size: 0.95rem;
        }
        .secondary {
          background: transparent;
          color: var(--text);
        }
        button:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }
        input:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }
        .checkbox-row:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }

        /* <dialog> + ::backdrop styling, animated entirely in CSS — no JS, no
           View Transition. A modal <dialog> moves through the top layer, so we
           transition `overlay` and `display` with `allow-discrete` to keep the
           element painted through its exit animation; `@starting-style` (below)
           supplies the values it animates *from* on open. */
        .signin-dialog {
          border: 0;
          border-radius: 16px;
          padding: 0;
          background: var(--surface-elev);
          color: var(--text);
          box-shadow: 0 24px 48px -16px rgb(0 0 0 / .45);
          max-width: min(90vw, 420px);
          opacity: 0;
          transform: translateY(8px) scale(.98);
          transition: opacity .2s ease, transform .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete;
        }
        .signin-dialog[open] {
          opacity: 1;
          transform: translateY(0) scale(1);
        }
        .signin-dialog .signin {
          padding: 1.5rem;
        }
        .signin-dialog::backdrop {
          background: color-mix(in oklab, Canvas 30%, transparent);
          backdrop-filter: blur(6px);
          opacity: 0;
          transition: opacity .2s ease, overlay .2s ease allow-discrete, display .2s ease allow-discrete;
        }
        .signin-dialog[open]::backdrop {
          opacity: 1;
        }
        /* Entry animation origin: without these, the dialog would pop in at full
           opacity instead of fading/sliding from the closed state. */
        @starting-style {
          .signin-dialog[open] {
            opacity: 0;
            transform: translateY(8px) scale(.98);
          }
          .signin-dialog[open]::backdrop {
            opacity: 0;
          }
        }
        """)

    // ---- animations ----
    static let animations = #css("""
        @keyframes counter-in {
          from { opacity: 0; transform: translateY(-6px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        :host {
          animation: counter-in 0.3s ease forwards;
        }
        """)

    // ---- responsive ----
    // @container nests inside the scope wrapper, so its rules stay scoped
    // through the normal pipeline — no hand-pasted `.swiflow-Counter` prefix
    // and no coupling to the scope-class naming scheme.
    static let responsive = #css("""
        @container (max-width: 380px) {
          .actions {
            flex-direction: column;
            align-items: stretch;
          }
          &.card {
            padding: 1.25rem;
            gap: 0.75rem;
          }
        }
        """)
}
