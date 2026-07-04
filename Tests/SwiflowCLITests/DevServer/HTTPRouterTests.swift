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

    @Test("A symlink under projectRoot pointing outside it is refused")
    func symlinkEscapeRefused() async throws {
        try await Self.withFixture { root in
            // Plant a secret file OUTSIDE root, then a symlink INSIDE root
            // pointing at it. The `..`-segment check in build(projectRoot:)
            // only catches traversal spelled out in the URL — a symlink hop
            // needs the canonicalized-prefix check in serveFile.
            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiflow-htr-outside-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outside) }
            let secret = outside.appendingPathComponent("secret.txt")
            try "top secret".write(to: secret, atomically: true, encoding: .utf8)

            let link = root.appendingPathComponent("escape.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/escape.txt", method: .get)
                #expect(response.status != .ok)
                let body = String(buffer: response.body)
                #expect(!body.contains("top secret"))
            }
        }
    }

    @Test("A project root that is itself a symlink still serves files")
    func symlinkedProjectRootStillServes() async throws {
        // macOS: FileManager.default.temporaryDirectory is under /var, which
        // is itself a symlink to /private/var — this already exercises the
        // "root is a symlink" case on macOS, but be explicit with our own
        // extra symlink layer so the test isn't relying on that incidentally.
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-htr-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        try "<!doctype html><html><body>hi</body></html>".write(
            to: real.appendingPathComponent("index.html"), atomically: true, encoding: .utf8
        )

        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-htr-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }

        let router = HTTPRouter.build(projectRoot: link)
        let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        try await app.test(.live) { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .ok)
            #expect(String(buffer: response.body).contains("hi"))
        }
    }

    @Test("A leftover build manifest is 404'd even when present on disk")
    func buildManifestNeverServed() async throws {
        try await Self.withFixture { root in
            // What `swiflow build` leaves behind. If dev ever serves it, the
            // service worker precaches the build outputs and shadows every
            // dev rebuild — the 404 is what flips the SW into no-manifest mode.
            try #"{"version":"1","wasm":{"url":"x","sha256":"y"},"runtime":[]}"#.write(
                to: root.appendingPathComponent("swiflow-manifest.json"),
                atomically: true, encoding: .utf8
            )
            let router = HTTPRouter.build(projectRoot: root)
            let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
            try await app.test(.live) { client in
                let response = try await client.execute(uri: "/swiflow-manifest.json", method: .get)
                #expect(response.status == .notFound)
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
