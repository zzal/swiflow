# GridBoard

A serverless, Electricity-Maps-style dashboard of the Canadian grid —
and a showcase of what WASM compute makes possible in the browser.

Every interaction is a full-dataset query: a year of 5-minute-resolution
data for 13 provinces and territories (~12M data points) lives in WASM
linear memory, and dragging the scrubber, painting the season×hour
wheel, or hovering a province re-scans it between two frames. No server,
no API, no precomputed tiles. The perf HUD shows the receipts.

## Run it

    swiflow dev

## The tour

- **Time scrubber** — the year's demand curve IS the track. Drag the
  playhead, press play, or switch to Brush and drag a range.
- **Season×hour wheel** — outer ring months, inner ring hours. Paint
  "January evenings" and the whole map re-aggregates for that slice.
- **Provinces** — click to focus the right-hand panel; hover for a live
  lens (trailing-24h sparkline computed per pointer-move).
- **Donut** — click a source to recolor the map by that source's share.
- **Flow arcs** — click an interconnect for its flow-duration curve.

## Point it at your data

`Sources/GridCore` is the seam. It is pure Swift — no Foundation, no
browser imports — and the app only ever calls `GridEngine.query(_:)`
plus two helpers. Replace `GridDataset.generate(seed:)` with a loader
for your own columnar data and everything downstream follows. The
GridCore test suite (`swift test`) runs on the host.

## Architecture notes

- `GridCore` — columnar struct-of-arrays store, deterministic synthetic
  generator, brute-force masked-scan aggregation engine.
- `App` — one Swiflow component (`GridShell`) owning all state; SVG map
  and controls are plain VNodes; the flow particles are the one canvas
  layer, painted through the `.ref` escape hatch; native pointer
  listeners supply the coordinates Swiflow events don't carry.
