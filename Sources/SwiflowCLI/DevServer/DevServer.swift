// Sources/SwiflowCLI/DevServer/DevServer.swift
//
// Stitches HTTPRouter + WebSocketHub into a single Hummingbird
// Application. DevCommand owns one DevServer instance plus one
// FileWatcher; on each watcher event it rebuilds and then calls
// `server.hub.broadcastReload()`.
//
// Lifecycle: callers `await server.run()` which blocks until the
// caller's outer Task is cancelled — that's the signal swiflow uses
// to shut down on SIGINT (Hummingbird wires SIGINT/SIGTERM via the
// ServiceLifecycle integration).

import Foundation
import Hummingbird
import HummingbirdWebSocket

final class DevServer: Sendable {
    let hub: WebSocketHub
    private let app: any ApplicationProtocol

    init(projectRoot: URL, port: Int) {
        let hub = WebSocketHub()
        self.hub = hub

        let httpRouter = HTTPRouter.build(projectRoot: projectRoot)

        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/reload") { _, _ in
            return .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let id = await hub.register(outbound)
            // Drain inbound until the peer closes. The for-await exits when
            // inbound finishes (peer hangup), then unregister runs
            // synchronously in the structured upgrade-handler scope.
            // Phase 2c doesn't react to client messages — the channel is
            // one-way (server → browser).
            for try await _ in inbound {}
            await hub.unregister(id)
        }

        self.app = Application(
            router: httpRouter,
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
    }

    func run() async throws {
        try await app.runService()
    }
}
