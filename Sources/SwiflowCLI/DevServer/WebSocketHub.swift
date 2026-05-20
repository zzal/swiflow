// Sources/SwiflowCLI/DevServer/WebSocketHub.swift
//
// Actor that tracks every connected /reload WebSocket and exposes a
// broadcastReload() coroutine. DevCommand calls broadcastReload() after each
// successful rebuild; the upgrade handler routes new connections into this
// hub via register() / unregister().
//
// Actor isolation is the right primitive here: all access is from async
// contexts, the per-client write is independent (no shared mutable buffer),
// and the actor's serial executor serializes the [ClientID: writer] map
// without manual locking.

import Foundation
import HummingbirdWebSocket

actor WebSocketHub {
    typealias ClientID = UUID

    private var clients: [ClientID: WebSocketOutboundWriter] = [:]

    init() {}

    /// Register an outbound writer. Returns an ID the caller passes to
    /// `unregister` when the connection drops. Caller is responsible for
    /// invoking `unregister` — typically once the upgrade handler's inbound
    /// loop exits (peer closed, IO error, etc.).
    func register(_ writer: WebSocketOutboundWriter) -> ClientID {
        let id = ClientID()
        clients[id] = writer
        return id
    }

    func unregister(_ id: ClientID) {
        clients.removeValue(forKey: id)
    }

    /// Send `{"type":"reload"}` to every connected client. Writes that fail
    /// (peer reset, connection torn down between the broadcast trigger and
    /// the write) drop the client from the registry so the next broadcast
    /// doesn't retry against it. We don't propagate the error — a single
    /// stale client must not prevent reload signals reaching the rest.
    func broadcastReload() async {
        let payload = #"{"type":"reload"}"#
        for (id, writer) in clients {
            do {
                try await writer.write(.text(payload))
            } catch {
                clients.removeValue(forKey: id)
            }
        }
    }

    /// Send `{"type":"hmr-swap","wasmURL":..,"jsURL":..}` to every
    /// connected client. Used by `DevCommand`'s rebuild loop in place
    /// of `broadcastReload()`. Same drop-on-write-failure semantics:
    /// a single stale client must not block the broadcast from
    /// reaching the rest.
    ///
    /// `wasmURL` is informational for v1 — the new entry point
    /// (`index.js`) loads the WASM itself. We still ship it so the
    /// driver can log "fetching <wasmURL>" and so a future
    /// preflight-fetch optimization has it available.
    func broadcastHMRSwap(wasmURL: String, jsURL: String) async {
        struct HMRSwapPayload: Encodable {
            let type = "hmr-swap"
            let wasmURL: String
            let jsURL: String
        }
        // JSONEncoder escapes "/" as "\/" (valid but unnecessary here).
        // Strip those escapes so the output matches what the driver expects.
        let encoded = (try? JSONEncoder().encode(HMRSwapPayload(wasmURL: wasmURL, jsURL: jsURL)))
            .flatMap { String(bytes: $0, encoding: .utf8) }
            .map { $0.replacingOccurrences(of: "\\/", with: "/") }
            ?? #"{"type":"hmr-swap","wasmURL":"","jsURL":""}"#
        for (id, writer) in clients {
            do {
                try await writer.write(.text(encoded))
            } catch {
                clients.removeValue(forKey: id)
            }
        }
    }

    /// Test-only: number of currently registered clients. Useful as a
    /// barrier in tests that need to wait until N concurrent connections
    /// have completed their register() call before broadcasting.
    var clientCount: Int {
        clients.count
    }
}
