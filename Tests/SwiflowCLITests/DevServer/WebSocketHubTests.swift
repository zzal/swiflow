// Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift
import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import HummingbirdWSTesting
import Testing
@testable import SwiflowCLI

@Suite("WebSocketHub")
struct WebSocketHubTests {

    // MARK: - Test #1 (load-bearing): fanout through real Hummingbird stack
    //
    // Spins up an actual HTTP+WS server, opens two client connections, waits
    // until both have registered with the hub, then calls broadcastReload().
    // Each client's handler asserts it received the {"type":"reload"} text
    // frame inline (the test-client handler returns Void, so we can't return
    // the message out — assertions go inside the handler, matching the
    // Hummingbird WebSocketTests.testServerToClientMessage pattern).
    //
    // Concurrent client connect via withThrowingTaskGroup keeps the structured-
    // concurrency invariant the plan calls out: app.test(.live) waits for the
    // closure to fully return before tearing down the server, so we don't
    // orphan any Task that holds a stream iterator.

    @Test("Broadcast delivers {\"type\":\"reload\"} to every connected client")
    func broadcastFanout() async throws {
        let hub = WebSocketHub()
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/reload") { _, _ in
            return .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let id = await hub.register(outbound)
            // Iterate inbound to keep the upgrade handler alive until the
            // peer closes the connection — at that point the loop falls
            // through and we unregister.
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
                // Client 1 — asserts inline that it receives a "reload" text frame.
                group.addTask {
                    try await client.ws("/reload") { inbound, _, _ in
                        var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                        let msg = try await iter.next()
                        if case .text(let s) = msg {
                            #expect(s.contains("\"reload\""))
                        } else {
                            Issue.record("first client got no text frame (got: \(String(describing: msg)))")
                        }
                    }
                }
                // Client 2 — same assertion.
                group.addTask {
                    try await client.ws("/reload") { inbound, _, _ in
                        var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                        let msg = try await iter.next()
                        if case .text(let s) = msg {
                            #expect(s.contains("\"reload\""))
                        } else {
                            Issue.record("second client got no text frame (got: \(String(describing: msg)))")
                        }
                    }
                }
                // Orchestrator — wait until both clients have registered, then
                // fan out the reload. Polling with a short deadline so a
                // regression that breaks register() shows up as a fast test
                // failure rather than a 30-second timeout.
                group.addTask {
                    for _ in 0 ..< 50 {
                        if await hub.clientCount == 2 { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    #expect(await hub.clientCount == 2)
                    await hub.broadcastReload()
                }
                try await group.waitForAll()
            }
        }
    }

    // MARK: - Test #2 (state-introspection fallback)
    //
    // The plan suggested a StubOutboundWriter to verify unregister behavior
    // without a live server. That isn't viable: Hummingbird's
    // WebSocketOutboundWriter is a Sendable struct holding a real
    // WebSocketHandler — there's no protocol to conform a stub to. Instead,
    // verify the same property end-to-end through the hub's own state: after
    // a client connects and disconnects, clientCount returns to zero, so the
    // next broadcast genuinely has nothing to target.
    //
    // This is also cheaper than Test #1 (single client, no broadcast race),
    // which makes it useful coverage for the register/unregister bookkeeping
    // independent of the broadcast plumbing.

    @Test("Unregister removes the client; clientCount returns to zero")
    func unregisterDropsClient() async throws {
        let hub = WebSocketHub()
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/reload") { _, _ in
            return .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let id = await hub.register(outbound)
            // Iterate inbound until the peer closes — same idiom as Test #1.
            for try await _ in inbound {}
            await hub.unregister(id)
        }

        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )

        try await app.test(.live) { client in
            // Connect, then immediately return from the handler — that closes
            // the WS and drives the server-side inbound loop to EOF, which
            // calls unregister.
            try await client.ws("/reload") { _, _, _ in }

            // Give the upgrade handler a beat to observe the close and run
            // the unregister call (no public synchronization signal between
            // the client-side close and the server-side cleanup).
            for _ in 0 ..< 50 {
                if await hub.clientCount == 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(await hub.clientCount == 0)
            // A broadcast against an empty hub completes without crashing
            // or attempting any writes — this is the property the original
            // plan wanted to verify with a stub writer.
            await hub.broadcastReload()
        }
    }
}
