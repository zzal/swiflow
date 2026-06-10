# TodoCRUD

SwiflowQuery against a **real** local CRUD API — Bun + SQLite, Dockerized.

Unlike `QueryDemo`/`AsyncFetch` (which simulate the network with `Task.sleep` and
hardcoded data), this example performs actual HTTP `fetch` calls from the WASM app to a
running backend. The SwiflowQuery machinery — cache, stale-while-revalidate, dedup,
optimistic updates, invalidation — is identical to the simulated examples; only the
`Query.fetch()` / `Mutation.perform()` bodies change to call a real server.

## What it shows

- **Read** the list with `query(TodoList())` → a `QueryState<[Todo]>`.
- **Write** with `@MutationState` mutations — `AddTodo` / `ToggleTodo` / `DeleteTodo` —
  each with an **optimistic** cache edit (append / field-flip / remove) and an
  **`.exact(["todos"])` invalidation** that refetches the canonical list to reconcile.
- The **⟳ spinner** (`isFetching`) during the post-mutation revalidation.
- **Refetch-on-focus**: the list refreshes automatically when you return to the tab,
  so edits made in another tab or by another user appear as soon as you switch back.
- **5-second polling**: `refetchInterval: .seconds(5)` keeps the list live — out-of-band
  edits (made directly against the API or by another browser) appear within ~5 s.
- The real `fetch` + JSON-decode idiom for WASM via the **`SwiflowFetcher`** module
  — `HTTPClient(baseURL:)` over the browser `fetch` + `JSValueDecoder`; no
  `Foundation`/`URLSession`.

## Architecture

```
Browser  ──┐
  WASM app (swiflow dev, :3002)
           │  CORS fetch (GET/POST/PUT/DELETE /todos)
           ▼
  Bun API (:8080)  ──►  bun:sqlite (in-memory)
```

## Run the backend

```bash
cd backend
docker compose up --build      # serves http://localhost:8080
```

## Run the frontend

```bash
# from this directory (examples/TodoCRUD)
swiflow dev --port 3002        # compiles to WASM, serves on http://localhost:3002
```

Open the printed URL.

## What you should see

- The three seeded todos render (the first is checked) after a brief **Loading…**.
- Type a title + **Add** → the row appears **instantly** (optimistic), the **⟳** spinner
  shows during revalidation, then the row reconciles to the server-assigned id.
- Toggling a checkbox flips **done** instantly; the `PUT` runs in the background; the
  list reconciles.
- **✕** removes the row instantly; the `DELETE` runs; the list reconciles.
- In the browser Network tab, each mutation is immediately followed by a `GET /todos`
  (the `.exact(["todos"])` invalidation refetch).

## Notes

- **Persistence:** the backend uses an in-memory SQLite DB, re-seeded each container
  start — writes persist for the session. To persist across restarts, change
  `new Database(":memory:")` to `new Database("/data/todos.db")` in `backend/server.ts`
  and uncomment the `volumes:` lines in `backend/docker-compose.yml`.
- **CORS:** the Swiflow dev server is static-only (no proxy), so the backend sends
  permissive CORS headers and answers the `OPTIONS` preflight that POST/PUT/DELETE with
  a JSON body trigger.
- **Config:** change the `HTTPClient(baseURL:)` in `Sources/App/App.swift` to target a different host/port.

See the SwiflowQuery design in `docs/superpowers/specs/` and the lifecycle diagram in
`docs/diagrams/swiflow-update-lifecycle.html`.
