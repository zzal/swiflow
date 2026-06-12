// Sources/App/SignIn+Styles.swift
import Swiflow

extension SignIn {
    // The component root carries .signin itself, so the rule compounds with
    // the scope class via `&.signin` (what the DSL's dual emission matched).
    static var scopedStyles: CSSSheet? = #css("""
        &.signin {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          max-width: 320px;
          font-family: system-ui, sans-serif;
        }
        .title {
          margin: 0;
          font-size: 1.25rem;
        }
        .field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        input {
          padding: 0.4rem 0.6rem;
          border: 1px solid color-mix(in oklab, CanvasText 18%, transparent);
          border-radius: 6px;
          background: Canvas;
          color: CanvasText;
          font-size: 0.9375rem;
          accent-color: CanvasText;
        }
        input:focus-visible {
          outline: 2px solid color-mix(in oklab, CanvasText 50%, blue);
          outline-offset: 2px;
        }
        .error {
          margin: 0.125rem 0 0 0;
          color: oklch(.55 .2 25);
          font-size: 0.85rem;
        }
        .welcome {
          margin: 0;
          font-size: 1rem;
        }
        .actions {
          display: flex;
          gap: 0.5rem;
        }
        button {
          padding: 0.4rem 0.9rem;
          border: 1px solid color-mix(in oklab, CanvasText 18%, transparent);
          border-radius: 6px;
          background: color-mix(in oklab, Canvas 90%, CanvasText);
          color: CanvasText;
          cursor: pointer;
          font-size: 0.9375rem;
        }
        button:focus-visible {
          outline: 2px solid color-mix(in oklab, CanvasText 50%, blue);
          outline-offset: 2px;
        }
        .secondary {
          background: transparent;
        }
        button[disabled] {
          opacity: 0.5;
          cursor: not-allowed;
        }
        """)
}
