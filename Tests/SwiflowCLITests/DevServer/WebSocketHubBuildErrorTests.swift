// Tests/SwiflowCLITests/DevServer/WebSocketHubBuildErrorTests.swift
//
// Audit III Wave-2 #7 — compile errors must reach the browser. Mirrors
// WebSocketHubHMRTests' live-stack shape for the new broadcastBuildError
// path. The payload carries arbitrary compiler output, so unlike the
// hmr-swap payload it MUST be real JSON encoding end-to-end (newlines,
// quotes) and must NOT apply hmr-swap's cosmetic "\/" → "/" strip — that
// strip corrupts a literal backslash-before-slash in the content.
import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import HummingbirdWSTesting
import Testing
@testable import SwiflowCLI

@Suite("WebSocketHub build-error broadcast")
struct WebSocketHubBuildErrorTests {

    @Test("broadcastBuildError delivers {\"type\":\"build-error\", message} with compiler output intact")
    func buildErrorBroadcastFanout() async throws {
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

        // Newline, quotes, and a literal backslash-followed-by-slash — the
        // exact shape hmr-swap's "\/" strip would corrupt.
        let diagnostics = "App.swift:7:9: error: cannot find 'oops' in scope\n    let x = \"oops\\/\""

        try await app.test(.live) { client in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await client.ws("/reload") { inbound, _, _ in
                        var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                        let msg = try await iter.next()
                        if case .text(let s) = msg {
                            #expect(s.contains("\"type\":\"build-error\""))
                            // Round-trip through a real JSON decode — the
                            // driver JSON.parses, so THIS is the contract.
                            struct Frame: Decodable { let type: String; let message: String }
                            let frame = try JSONDecoder().decode(Frame.self, from: Data(s.utf8))
                            #expect(frame.type == "build-error")
                            #expect(frame.message == diagnostics,
                                    "compiler output must survive the wire byte-for-byte")
                        } else {
                            Issue.record("client got no text frame (got: \(String(describing: msg)))")
                        }
                    }
                }
                group.addTask {
                    for _ in 0 ..< 50 {
                        if await hub.clientCount == 1 { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    #expect(await hub.clientCount == 1)
                    await hub.broadcastBuildError(message: diagnostics)
                }
                try await group.waitForAll()
            }
        }
    }
}
