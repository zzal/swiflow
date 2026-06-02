# QueryDemo

A Swiflow example demonstrating `SwiflowQuery` — cached, deduplicated,
stale-while-revalidate data fetching with a `.task`-free `query()` call.

A `Query` is a value that knows how to fetch itself (`fetch()`) and where it
lives in the cache (`queryKey`). The component just *consumes* it:

```swift
let u = query(UserByID(id: userID))
```

No `.task`, no `@State` for the loading flag — `query()` returns a
`QueryState` (`data` / `error` / `isLoading` / `isFetching`) backed by the
per-root `QueryClient` cache.

## Build

```bash
swiflow dev
```

This compiles the example to WASM and serves it. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`. Then open the printed URL.

## What you should see

- A heading: **Query demo**
- For ~400 ms, **Loading…** while `UserByID(id: 1)` fetches; then
  **Loaded: User #1**.
- A button: **Next user** — each click bumps `userID`, which changes the
  query key (`["users", .int(id)]`). The new key triggers a fetch for that
  user. Keys you have visited before are cached, so revisiting shows the
  cached value instantly while a background revalidation runs.
- A small **⟳** spinner appears whenever a fetch is in flight in the
  background (`isFetching`) — including the stale-while-revalidate refetch
  over already-cached data.

## How it works

- **Key-driven fetching.** A fetch happens on mount, on key change, or on
  `invalidate` — *not* on every re-render. The `userID` lives in the key, so
  bumping it is what drives the next fetch.
- **Dedup.** Two components asking for the same key at the same time share one
  in-flight fetch.
- **Stale-while-revalidate.** With the default `staleTime` of `.zero`, every
  trigger revalidates: cached data renders immediately, and a background
  refetch updates it when it lands.
- **Invalidation.** A `QueryClient` (installed automatically per render root)
  can refetch by key prefix (`invalidate(["users"])`), exact key
  (`invalidate(["users", 1], exact: true)`), or tag (`invalidate(tag:
  "users")`).

See [`docs/guides/query.md`](../../docs/guides/query.md) for the full guide.
