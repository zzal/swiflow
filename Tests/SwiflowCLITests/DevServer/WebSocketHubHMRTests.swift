// Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift
//
// Phase 8 — companion to WebSocketHubTests, exercising the new
// `broadcastHMRSwap(wasmURL:jsURL:)` path through the live Hummingbird
// stack. We deliberately mirror the orchestrator shape from
// WebSocketHubTests.broadcastFanout (poll-clientCount-then-broadcast,
// 50 × 50ms ceiling) so a regression that breaks register() shows up
// as a fast test failure rather than a 30-second timeout.
import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import HummingbirdWSTesting
import Testing
@testable import SwiflowCLI

@Suite("WebSocketHub HMR broadcast")
struct WebSocketHubHMRTests {

    @Test("broadcastHMRSwap delivers {\"type\":\"hmr-swap\", wasmURL, jsURL} to every connected client")
    func hmrBroadcastFanout() async throws {
        let hub = WebSocketHub()
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/reload") { _, _ in
            return .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let id = await hub.register(outbound)
            for try await _ in inbound {}
            await hub.unregister(id)
        }

        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )

        try await app.test(.live) { client in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await client.ws("/reload") { inbound, _, _ in
                        var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                        let msg = try await iter.next()
                        if case .text(let s) = msg {
                            #expect(s.contains("\"type\":\"hmr-swap\""))
                            #expect(s.contains("\"wasmURL\":\"/Bundle.wasm?h=123\""))
                            #expect(s.contains("\"jsURL\":\"/index.js?h=123\""))
                        } else {
                            Issue.record("client got no text frame (got: \(String(describing: msg)))")
                        }
                    }
                }
                group.addTask {
                    // Wait until the client has registered, then broadcast.
                    // Match the WebSocketHubTests.broadcastFanout polling
                    // shape: 50 iterations of 50ms (2.5s ceiling) is fast
                    // enough to fail loudly under regression.
                    for _ in 0 ..< 50 {
                        if await hub.clientCount == 1 { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    #expect(await hub.clientCount == 1)
                    await hub.broadcastHMRSwap(
                        wasmURL: "/Bundle.wasm?h=123",
                        jsURL: "/index.js?h=123"
                    )
                }
                try await group.waitForAll()
            }
        }
    }
}
