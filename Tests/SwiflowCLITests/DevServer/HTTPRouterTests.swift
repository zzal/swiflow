// Tests/SwiflowCLITests/DevServer/HTTPRouterTests.swift
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import SwiflowCLI

@Suite("HTTPRouter")
struct HTTPRouterTests {

    static func withFixture(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-htr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Plant minimal fixture files
        try """
        <!doctype html><html><body><div id="app"></div>
        <script src="swiflow-driver.js"></script>
        </body></html>
        """.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "// driver".write(to: root.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
        try await body(root)
    }

    @Test("GET / serves index.html with SWIFLOW_DEV injected")
    func getIndexInjectsDevSignal() async throws {
        try await Self.withFixture { root in
            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/", method: .get)
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("window.SWIFLOW_DEV=true"))
                #expect(body.contains("<div id=\"app\""))
            }
        }
    }

    @Test("GET /index.html returns the same content as GET /")
    func getIndexExplicitPath() async throws {
        try await Self.withFixture { root in
            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/index.html", method: .get)
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("window.SWIFLOW_DEV=true"))
            }
        }
    }

    @Test("Non-HTML static files are served unchanged (no injection)")
    func nonHTMLServedRaw() async throws {
        try await Self.withFixture { root in
            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/swiflow-driver.js", method: .get)
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body == "// driver")
                #expect(!body.contains("SWIFLOW_DEV"))
            }
        }
    }

    @Test("GET on a missing path returns 404")
    func missingPath404() async throws {
        try await Self.withFixture { root in
            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/does-not-exist", method: .get)
                #expect(response.status == .notFound)
            }
        }
    }
}
