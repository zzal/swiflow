# Mission Control — live-API flagship sampler

**Date:** 2026-06-11
**Status:** Approved

## Problem

Every networked example fakes its API: `examples/AsyncFetch` and
`examples/QueryDemo` simulate latency with `Task.sleep`; `examples/HelloWorld`
does no networking at all. Nothing demonstrates `SwiflowFetcher.HTTPClient`
against a real server, `SwiflowQuery`'s polling/staleness machinery on live
data, or `SwiflowUI` stacks in a real layout.

## Concept

**Mission Control** — watching the planet live from Swift in the browser.
Two tabs via `SwiflowRouter`:

- **Weather** (`/`) — pinned city cards (seeded: Montréal, Tokyo, Lisbon) on
  Open-Meteo's forecast API; debounced city search on Open-Meteo's geocoding
  API; °C/°F toggle.
- **Quakes** (`/quakes`) — USGS earthquake feed with magnitude + time-window
  filters, polling every 30 s, relative "n min ago" timestamps.

Both APIs are free, keyless, CORS-open (`Access-Control-Allow-Origin: *`),
and infrastructure-grade (verified 2026-06-11).

## Why these pieces

| Feature | Demonstrated by |
|---|---|
| `.task(rerunOn:)` | 300 ms search debounce keyed on raw input text |
| bare `.task { }` | relative-time ticker (`while !Task.isCancelled`) |
| `VStack`/`HStack` + tokens | all layout; card grid; `--sw-*` vars in scoped styles |
| `HTTPClient` | two real clients; `Decodable` models via `JSValueDecoder` |
| query cache | per-city / per-filter keys; tab switches + re-pins are instant |
| `refetchInterval` | quake feed polls 30 s; weather refreshes 5 min |
| `staleTime` / `refetchOnFocus` | weather 60 s freshness; focus revalidation |
| `isFetching` vs `isLoading` | "⟳ live" pulse without clearing rendered data |
| `SwiflowRouter` | `RouterRoot`, two `Route`s, `Link` nav |
| two-way bindings | `.value($searchText)`, `.selection(...)` selects |
| `scopedStyles` | card/feed styling on theme tokens |

## Out of scope

- `Mutation`/optimistic edits — neither API accepts writes;
  `examples/QueryDemo` remains the Mutation demo (README says so).
- Persisting pinned cities — session-only `@State`.
- Playwright e2e — network-dependent tests are flaky; verification is the
  manual checklist in the implementation plan.

## Structure

```
examples/MissionControl/
  Package.swift  index.html  README.md
  Sources/App/
    App.swift  NavBar.swift  API.swift
    Weather/  WeatherQueries.swift  WeatherPage.swift  CityCard.swift
    Quakes/   QuakeQueries.swift    QuakesPage.swift   QuakeRow.swift
```

Endpoints, decoding caveats (snake_case CodingKeys, epoch-ms times,
`JSDate.now()` instead of Foundation `Date`), and the verification checklist
live in the approved implementation plan of the same date.
