# Mission Control

Watching the planet live from Swift in the browser — the flagship *networked*
sampler. Two routed tabs over free, keyless, CORS-open APIs:

- **Weather** (`/`) — pinned city cards on [Open-Meteo](https://open-meteo.com)
  (forecast + geocoding), with debounced search-to-pin and a °C/°F toggle.
- **Quakes** (`/quakes`) — the live
  [USGS earthquake feed](https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php),
  filtered by magnitude and time window, polling every 30 s.

Unlike `AsyncFetch` and `QueryDemo` (which simulate latency with `Task.sleep`),
everything here hits real servers.

## Run it

```sh
cd examples/MissionControl
swiflow dev        # builds WASM, serves, hot-reloads on save
```

## What's demonstrated where

| Feature | Where |
|---|---|
| `.task(rerunOn:)` | `WeatherPage` — 300 ms search debounce keyed on the input text; superseded keystrokes cancel the sleep and the runtime drops their writes |
| bare `.task { }` | `QuakesPage` — mount-scoped ticker keeping "n min ago" honest |
| `VStack`/`HStack` + tokens | all layout; spacing/alignment from the `--sw-*` scale |
| `HTTPClient` (SwiflowFetcher) | `API.swift` — three real clients; `Decodable` models with explicit snake_case `CodingKeys` (`JSValueDecoder` has no key strategy) |
| Keyed queries + cache | per-(city, unit) and per-(magnitude, window) keys — flip a filter back, or unpin → re-pin, and it paints instantly from cache |
| `refetchInterval` | quake feed polls every 30 s; weather refreshes every 5 min |
| `staleTime` / `refetchOnFocus` | weather is fresh for 60 s; both feeds revalidate on window focus |
| `isFetching` vs `isLoading` | the "⟳" pulses during background polls while rendered data stays put (stale-while-revalidate) |
| `SwiflowRouter` | `RouterRoot` + two `Route`s + `Link` tabs |
| Two-way bindings | `.value($searchText)`, `.selection(...)` on every select |
| `scopedStyles` | every component; theme on SwiflowUI's `--sw-*` token contract |

**Not here:** `Mutation` / optimistic edits — neither API accepts writes.
`examples/QueryDemo` remains the mutation demo.

## Things to try

1. Type "par" in the search box, slowly, then quickly — watch the network
   panel: one geocoding request per *settled* prefix, never per keystroke.
2. Pin Paris, unpin it, re-pin it within a minute — no request the second time.
3. Toggle °C → °F (refetch) → °C (instant, cached).
4. Switch tabs back and forth — instant both ways; no spinners after first load.
5. Leave the Quakes tab open — rows appear/reorder as the planet rumbles,
   the "⟳" spinning on each 30 s poll.
6. DevTools → Network → Offline: cards and feed show error states; restore
   and refocus the window to watch `refetchOnFocus` recover everything.
