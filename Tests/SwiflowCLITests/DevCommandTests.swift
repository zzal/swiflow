// Tests/SwiflowCLITests/DevCommandTests.swift
import ArgumentParser
import Foundation
// Linux splits URLSession out of Foundation into swift-corelibs-foundation's
// FoundationNetworking. Without this import, `URLSession.shared` resolves
// to `AnyObject.shared` (i.e. nothing) and the test target fails to compile.
// Darwin's Foundation already bundles URLSession so the import doesn't exist
// there — hence the canImport guard.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwiflowCLI

@Suite("DevCommand")
struct DevCommandTests {

    @Test("Defaults: --path is ., --port is 3000")
    func defaults() throws {
        let parsed = try DevCommand.parse([])
        #expect(parsed.path == ".")
        #expect(parsed.port == 3000)
        #expect(parsed.swiftSDK == nil)
    }

    @Test("Flags parse: --path, --port, --swift-sdk")
    func flags() throws {
        let parsed = try DevCommand.parse([
            "--path", "/tmp/demo",
            "--port", "4000",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
        ])
        #expect(parsed.path == "/tmp/demo")
        #expect(parsed.port == 4000)
        #expect(parsed.swiftSDK == "swift-6.3-RELEASE_wasm")
    }

    @Test("Appears in the root command's subcommand list")
    func registeredInRoot() {
        let names = Swiflow.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("dev"))
    }
}

// MARK: - End-to-end (requires WASM SDK)

// The e2e test is Apple-only because URLSession.webSocketTask(with:) on
// swift-corelibs-foundation (Linux) is either unimplemented or stubs out
// — runtime hangs and "unimplemented" exceptions, depending on Swift
// version. Rather than pull in AsyncHTTPClient + a WS client just for
// this one test, scope the suite to Darwin. Linux CI still gets:
//   - all unit tests in this file (argv parsing)
//   - BuildCommandIntegrationTests (the init+build e2e, no WS needed)
//   - all DevServer component tests (FileWatcher, HTTPRouter, hub, etc.)
// If a Linux user breaks the dev server, BuildCommandIntegrationTests
// + the component tests still catch the structural regressions.
@Suite struct DevChangeDispatchTests {

    private func urls(_ paths: [String]) -> Set<URL> {
        Set(paths.map { URL(fileURLWithPath: $0) })
    }

    @Test("Swift-only changes trigger a rebuild and an HMR swap broadcast") func swiftOnlyChangesRebuildAndHMRSwap() {
        let d = DevCommand.changeDispatch(for: urls(["/p/Sources/App/Main.swift"]))
        #expect(d == .init(rebuild: true, broadcast: .hmrSwap))
    }

    @Test("HTML/JS-only changes broadcast a reload without rebuilding") func webOnlyChangesReloadWithoutRebuild() {
        let d = DevCommand.changeDispatch(for: urls(["/p/index.html"]))
        #expect(d == .init(rebuild: false, broadcast: .reload))
        let js = DevCommand.changeDispatch(for: urls(["/p/styles.js"]))
        #expect(js == .init(rebuild: false, broadcast: .reload))
    }

    @Test("Mixed Swift+web changes rebuild and broadcast a full reload") func mixedChangesRebuildAndReload() {
        let d = DevCommand.changeDispatch(
            for: urls(["/p/Sources/App/Main.swift", "/p/index.html"]))
        #expect(d == .init(rebuild: true, broadcast: .reload))
    }
}

#if canImport(Darwin)

@Suite("DevCommand end-to-end (requires WASM SDK)")
struct DevCommandIntegrationTests {

    static var wasmSDKAvailable: Bool {
        BuildCommandIntegrationTests.wasmSDKAvailable
    }

    @Test(
        "swiflow init + swiflow dev serves the page and reloads on file change",
        .enabled(if: wasmSDKAvailable)
    )
    func endToEnd() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-dev-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Scaffold a project pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(BuildCommandIntegrationTests.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
        )
        let projectRoot = tmp.appendingPathComponent("Demo")

        // 2. Resolve SDK + toolchain like BuildCommand does.
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH"); return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty even though .enabled gated true"); return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Initial dev build (same as DevCommand.run step 4).
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectRoot,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            configuration: .dev
        )
        _ = try invocation.run(using: runner)

        // 4. Pick an ephemeral port by binding briefly to 0 then closing
        //    (Hummingbird doesn't currently expose the bound port when
        //    you ask for 0, so we pre-select one and pray it stays free).
        let port = Int.random(in: 49152...65535)

        // 5. Start the dev server in a background task.
        let server = DevServer(projectRoot: projectRoot, port: port)
        let serverTask = Task {
            try await server.run()
        }
        defer { serverTask.cancel() }

        // 6. Wait until the server accepts connections (poll with timeout).
        let serverURL = URL(string: "http://127.0.0.1:\(port)/")!
        var attempts = 0
        while attempts < 50 {
            if let (_, response) = try? await URLSession.shared.data(from: serverURL),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        #expect(attempts < 50, "server did not become ready within 5s")

        // 7. Fetch index.html; verify SWIFLOW_DEV is injected.
        let (data, _) = try await URLSession.shared.data(from: serverURL)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("window.SWIFLOW_DEV=true"))
        #expect(body.contains("<div id=\"app\""))

        // 8. Connect a WebSocket client to /reload, then trigger a
        //    file change, then assert the reload message arrives.
        let wsURL = URL(string: "ws://127.0.0.1:\(port)/reload")!
        let ws = URLSession.shared.webSocketTask(with: wsURL)
        ws.resume()
        defer { ws.cancel() }

        // Give the connection time to register with the hub.
        try await Task.sleep(for: .milliseconds(250))

        // Trigger a "reload" by directly broadcasting (cheaper than
        // re-running the build — the FileWatcher → rebuild → broadcast
        // path is covered by unit tests; this assertion confirms the
        // wire format end-to-end).
        await server.hub.broadcastReload()

        let received = try await Self.withTimeout(seconds: 5) {
            try await ws.receive()
        }
        switch received {
        case .string(let s): #expect(s.contains("\"reload\""))
        case .data(let d):   #expect(String(data: d, encoding: .utf8)?.contains("\"reload\"") == true)
        @unknown default:    Issue.record("unexpected WebSocket frame kind")
        }
    }

    struct TimeoutError: Error {}
    static func withTimeout<T: Sendable>(seconds: TimeInterval, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                throw TimeoutError()
            }
            guard let first = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return first
        }
    }
}

#endif // canImport(Darwin)
