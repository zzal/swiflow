// Sources/App/Shell+Styles.swift
import Swiflow

extension GridShell {
    @MainActor static var scopedStyles: CSSSheet? = base + map

    static let base = #css("""
        :root {
          --gb-bg: light-dark(oklch(.98 .005 250), oklch(.16 .01 250));
          --gb-panel: light-dark(oklch(.995 0 0), oklch(.21 .012 250));
          --gb-text: CanvasText;
          --gb-dim: color-mix(in oklab, CanvasText 60%, Canvas);
          --gb-border: color-mix(in oklab, CanvasText 14%, transparent);
          --gb-accent: oklch(.62 .17 255);
        }
        :host { display: block; min-height: 100dvh; background: var(--gb-bg); }
        .gb-shell {
          display: grid;
          grid-template-rows: auto 1fr auto;
          gap: 12px;
          max-width: 1400px;
          margin: 0 auto;
          padding: 16px 20px 20px;
          min-height: 100dvh;
          box-sizing: border-box;
        }
        .gb-header h1 { margin: 0; font-size: 22px; letter-spacing: -0.02em; }
        .gb-tagline { margin: 2px 0 0; color: var(--gb-dim); font-size: 13px; }
        .gb-main {
          display: grid;
          grid-template-columns: 1fr 340px;
          gap: 14px;
          min-height: 0;
        }
        .gb-panel {
          background: var(--gb-panel);
          border: 1px solid var(--gb-border);
          border-radius: 12px;
          padding: 14px;
          overflow-y: auto;
        }
        .gb-controls { display: grid; grid-template-columns: 1fr auto; gap: 14px; align-items: end; }
        """)

    static let map = #css("""
        .gb-map-wrap { position: relative; }
        .gb-map { width: 100%; height: auto; display: block; }
        .gb-zone {
          stroke: light-dark(oklch(.98 0 0 / .85), oklch(.14 .01 250 / .9));
          stroke-width: 1.5;
          cursor: pointer;
          transition: fill 220ms ease;
        }
        .gb-zone:hover { filter: brightness(1.12); }
        .gb-zone--focus { stroke: var(--gb-accent); stroke-width: 3; }
        .gb-zone-label {
          font: 600 12px system-ui, sans-serif;
          fill: light-dark(oklch(.99 0 0 / .92), oklch(.95 0 0 / .92));
          text-anchor: middle;
          pointer-events: none;
          paint-order: stroke;
          stroke: rgb(0 0 0 / .25);
          stroke-width: 2;
        }
        """)
}
