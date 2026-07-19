// Sources/App/Shell+Styles.swift
import Swiflow

extension GridShell {
    @MainActor static var scopedStyles: CSSSheet? = base + map + scrubber + wheel + panel + lens + arcs + canvas + hud + boot

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
        /* Surface chrome comes from the SwiflowUI Card; the panel only
           pins scroll behavior. */
        .gb-panel { overflow-y: auto; }
        .gb-controls { display: grid; grid-template-columns: 1fr auto; gap: 14px; align-items: end; }
        """)

    static let map = #css("""
        .gb-map-wrap {
          position: relative;
          width: 100%;
          /* Fit the whole dashboard in the viewport: cap the map's WIDTH
             so its aspect-locked height leaves room for the header and
             the scrubber/wheel row. Width stays the scale driver — the
             lens hit-test and the canvas overlay both assume it. */
          max-width: calc((100dvh - 310px) * (1000 / 620));
          margin-inline: auto;
        }
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

    static let scrubber = #css("""
        .gb-scrubber { display: grid; gap: 6px; }
        .gb-scrubber-bar { display: flex; gap: 8px; align-items: center; }
        .gb-readout { color: var(--gb-dim); font: 500 13px ui-monospace, monospace; }
        .gb-track {
          width: 100%;
          height: 64px;
          display: block;
          background: color-mix(in oklab, var(--gb-panel) 70%, var(--gb-bg));
          border: 1px solid var(--gb-border);
          border-radius: 10px;
          cursor: ew-resize;
          touch-action: none;
        }
        .gb-spark { fill: color-mix(in oklab, var(--gb-accent) 25%, transparent); stroke: var(--gb-accent); stroke-width: 1; vector-effect: non-scaling-stroke; }
        .gb-tick { stroke: var(--gb-border); }
        .gb-playhead { stroke: var(--gb-text); stroke-width: 2; vector-effect: non-scaling-stroke; }
        .gb-playhead-knob { fill: var(--gb-accent); stroke: white; stroke-width: 2; vector-effect: non-scaling-stroke; }
        .gb-brush-range { fill: color-mix(in oklab, var(--gb-accent) 18%, transparent); }
        .gb-thumb { stroke: var(--gb-accent); stroke-width: 4; vector-effect: non-scaling-stroke; cursor: ew-resize; }
        """)

    static let wheel = #css("""
        .gb-wheel-svg { width: 148px; height: 148px; display: block; user-select: none; }
        .gb-seg {
          fill: color-mix(in oklab, var(--gb-text) 8%, var(--gb-panel));
          stroke: var(--gb-bg);
          stroke-width: 1;
          cursor: pointer;
          transition: fill 120ms ease;
        }
        .gb-seg:hover { fill: color-mix(in oklab, var(--gb-accent) 30%, var(--gb-panel)); }
        .gb-seg--on { fill: var(--gb-accent); }
        .gb-seg-label { font: 600 8px system-ui; fill: var(--gb-dim); text-anchor: middle; pointer-events: none; }
        .gb-wheel-clear { fill: var(--gb-panel); stroke: var(--gb-border); cursor: pointer; }
        .gb-wheel-clear--idle { opacity: 0.6; }
        .gb-wheel-clear-label { font: 600 9px system-ui; fill: var(--gb-dim); text-anchor: middle; pointer-events: none; }
        """)

    static let panel = #css("""
        .gb-panel-title { margin: 0 0 8px; font-size: 17px; }
        .gb-empty { font-style: italic; }
        .gb-stat-row { display: flex; gap: 18px; margin-bottom: 8px; }
        .gb-stat { display: grid; }
        .gb-stat strong { font-size: 17px; }
        .gb-stat small { color: var(--gb-dim); }
        .gb-donut { width: 160px; margin: 0 auto; display: block; }
        .gb-donut-seg { cursor: pointer; transition: opacity 120ms ease; stroke: var(--gb-panel); stroke-width: 1; }
        .gb-donut-seg:hover { opacity: 0.85; }
        .gb-donut-hole { fill: var(--gb-panel); cursor: pointer; }
        .gb-donut-label { text-anchor: middle; font: 600 12px system-ui; fill: var(--gb-dim); pointer-events: none; }
        .gb-legend { list-style: none; margin: 8px 0; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 4px 10px; font-size: 12px; }
        .gb-legend-item { display: flex; align-items: center; gap: 6px; }
        .gb-legend-swatch { width: 10px; height: 10px; border-radius: 3px; display: inline-block; }
        .gb-chart-card h3 { margin: 10px 0 4px; font-size: 12px; color: var(--gb-dim); text-transform: uppercase; letter-spacing: 0.04em; }
        .gb-chart { width: 100%; display: block; background: color-mix(in oklab, var(--gb-text) 4%, var(--gb-panel)); border-radius: 8px; }
        .gb-area { opacity: 0.9; }
        .gb-price-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        """)

    static let lens = #css("""
        .gb-lens {
          position: absolute;
          z-index: 5;
          pointer-events: none;
          padding: 8px 10px;
          width: 160px;
          font-size: 12px;
          gap: 5px;
        }
        .gb-lens--hidden { display: none; }
        .gb-lens-stats { color: var(--gb-dim); }
        .gb-lens-mix { width: 100%; border-radius: 3px; }
        .gb-lens-spark { width: 100%; }
        .gb-lens-spark-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        """)

    static let arcs = #css("""
        .gb-arc {
          fill: none;
          stroke: color-mix(in oklab, var(--gb-accent) 70%, white);
          stroke-linecap: round;
          opacity: 0.65;
          pointer-events: none;
          transition: stroke-width 220ms ease;
        }
        .gb-arc--reverse { stroke: color-mix(in oklab, oklch(.7 .15 60) 80%, white); }
        .gb-arc--focus { opacity: 1; stroke: var(--gb-accent); }
        .gb-arc-hit { fill: none; stroke: transparent; stroke-width: 14; cursor: pointer; }
        .gb-inspector-head { display: flex; justify-content: space-between; align-items: start; }
        .gb-duration-line { fill: none; stroke: var(--gb-accent); stroke-width: 1.5; vector-effect: non-scaling-stroke; }
        .gb-cap-line { stroke: var(--gb-dim); stroke-dasharray: 4 4; vector-effect: non-scaling-stroke; }
        .gb-inspector-note { color: var(--gb-dim); font-size: 12px; }
        """)

    static let canvas = #css("""
        .gb-flow-canvas {
          position: absolute;
          inset: 0;
          width: 100%;
          height: auto;
          aspect-ratio: 1000 / 620;
          pointer-events: none;
        }
        """)

    static let hud = #css("""
        .gb-header { display: flex; justify-content: space-between; align-items: start; gap: 16px; }
        .gb-hud {
          flex-direction: row;
          gap: 8px;
          align-items: start;
          padding: 8px 10px;
        }
        .gb-hud-grid { display: flex; gap: 14px; margin: 0; }
        .gb-hud-cell dt { font: 500 10px system-ui; color: var(--gb-dim); text-transform: uppercase; letter-spacing: 0.05em; }
        .gb-hud-cell dd { margin: 0; font: 600 14px ui-monospace, monospace; }
        @media (max-width: 900px) {
          .gb-main { grid-template-columns: 1fr; }
          .gb-header { flex-direction: column; }
        }
        """)

    static let boot = #css("""
        .gb-boot {
          min-height: 100dvh;
          display: grid;
          place-items: center;
          background: var(--gb-bg);
        }
        /* Chrome comes from SwiflowUI (Card/Text/ProgressView tokens);
           only the app-specific width cap and the monospace percent
           readout live here. */
        .gb-boot-card { width: min(440px, 86vw); }
        .gb-boot-pct { font-family: ui-monospace, monospace; }
        """)
}
