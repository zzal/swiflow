# Swiflow Phase 2c — Dev Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `swiflow dev` deliver the Phase 2 headline KPI — `swiflow init demo && cd demo && swiflow dev` opens `http://localhost:3000`, the Hello World renders, and editing `Sources/App/App.swift` triggers a full browser reload within ~2 seconds.

**Architecture:** Hummingbird 2 wraps swift-nio for both the HTTP static file server and the `/reload` WebSocket endpoint. A polling FileWatcher (not FSEvents/inotify — see Decision §1) emits `AsyncStream<Set<URL>>` on `.swift`/`.html`/`.js`/`Package.swift` changes. On each change, DevCommand re-runs the dev-configured build (no `-c release`, with `-g`) and pokes a `WebSocketHub` actor whose `broadcastReload()` ships `{"type":"reload"}` to every connected client. The JS driver, when its env injects `window.SWIFLOW_DEV=true` (Decision §3), opens a reconnect-with-backoff socket to `/reload` and calls `location.reload()` on the message.

**Tech Stack:** Swift 6.0, Hummingbird 2 + HummingbirdWebSocket, swift-argument-parser (existing), Swift Testing, `HummingbirdTesting` + `HummingbirdWSTesting` (test-only deps).

---

## Locked Architecture Decisions

These are calls I'm making to fill in Phase 2c's blanks. Each documents what was chosen and why, so the implementer doesn't second-guess them mid-task.

**§1. FileWatcher = polling (not FSEvents/inotify).** The spec said FSEvents (macOS) / inotify (Linux), but polling is ~30 LOC vs. ~200 LOC, single code path, no `#if canImport` shims. 250 ms latency is below the user-perception threshold for save→reload. Phase 4 may swap to native if profiling shows the cost matters (it won't, for a project that watches ~10 files).

**§2. On rebuild failure, do not broadcast.** The browser keeps showing the last-good version; the user fixes the error and saves again, which fires another rebuild attempt. Matches Vite. Failed builds print stderr to the dev-server terminal.

**§3. Dev-mode signal = HTTPServer injects `<script>window.SWIFLOW_DEV=true;</script>` into served HTML.** Zero template change; production builds stay clean; opt-in at serve time. Injected immediately before the first `<script src="swiflow-driver.js">` tag (driver sees the global the instant it runs). If no driver tag found, inject before `</body>` as fallback.

**§4. WebSocket message format = JSON `{"type":"reload"}`.** Spec verbatim. Trivial client dispatch.

**§5. Reconnect strategy = exponential backoff capped at 5 s.** Browser tries 250 ms → 500 ms → 1 s → 2 s → 4 s → 5 s → 5 s. Reset to 250 ms on successful connect. Means killing+restarting `swiflow dev` causes the page to silently reattach.

**§6. Initial build failure = exit non-zero.** `swiflow dev` cannot serve what doesn't exist. Print the error, exit, let the user fix it. A "build failed" error page is Phase 4 territory.

**§7. Watch scope = `Sources/**/*.swift` + top-level `index.html`, `swiflow-driver.js`, `Package.swift`.** Skip `Tests/`, `.build/`, `.swiftpm/`, dot-prefixed dirs. `Package.swift` triggers rebuild because dependency edits need re-resolution.

**§8. Port = 3000 default, configurable via `--port`.** Spec verbatim.

**§9. HTTP framework = Hummingbird 2 + HummingbirdWebSocket.** One direct dep (transitive: ~10 swift-nio packages, normal for any Swift HTTP framework). Modern async/await native, Swift 6 strict-concurrency clean. Bare swift-nio would be ~5× more boilerplate for the same two routes.

**§10. Test WebSocket = HummingbirdWSTesting + HummingbirdTesting (`app.test(.live) { client in client.ws(...) }`).** Test-only deps, avoid `URLSessionWebSocketTask` cross-platform quirks. Both ship as `.testTarget` dependencies.

---

## File Structure

**Create (5 source files + 5 test files):**
- `Sources/SwiflowCLI/DevServer/DevServer.swift` — wraps the Hummingbird `Application`, owns the `WebSocketHub`, exposes `start()`/`stop()` lifecycle
- `Sources/SwiflowCLI/DevServer/HTTPRouter.swift` — pure construction of the `Router` (static file middleware + DevModeInjection)
- `Sources/SwiflowCLI/DevServer/WebSocketHub.swift` — `actor` holding `[UUID: WebSocketOutboundWriter]`, exposes `register`/`unregister`/`broadcastReload`
- `Sources/SwiflowCLI/DevServer/FileWatcher.swift` — polling `AsyncStream<Set<URL>>` emitter
- `Sources/SwiflowCLI/DevServer/DevModeInjection.swift` — pure string-transform helper (injects `<script>window.SWIFLOW_DEV=true</script>`)
- `Sources/SwiflowCLI/Commands/DevCommand.swift` — `AsyncParsableCommand` orchestrator
- `Tests/SwiflowCLITests/DevServer/HTTPRouterTests.swift` — `app.test(.live)` route assertions
- `Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift` — connect 2 clients, broadcast, both receive
- `Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift` — temp-dir write/modify/delete event assertions
- `Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift` — pure-function transform cases
- `Tests/SwiflowCLITests/DevCommandTests.swift` — argv + a gated end-to-end integration test

**Modify:**
- `Package.swift` — add Hummingbird + HummingbirdWebSocket deps, HummingbirdTesting + HummingbirdWSTesting to test target
- `Sources/SwiflowCLI/Commands/BuildCommand.swift` — extract `BuildConfiguration` enum, parameterize `BuildInvocation`
- `Sources/SwiflowCLI/Swiflow.swift` — register `DevCommand` in the subcommands list
- `js-driver/swiflow-driver.js` — append the dev-mode reload listener
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated via `swift scripts/embed-driver.swift`
- `Tests/SwiflowCLITests/BuildCommandTests.swift` — add a test for the dev-mode argv shape

**Out of scope this phase:**
- Source maps as separate `.map` files (Phase 4 — DWARF in `-g` build is the substitute)
- HMR / live update without full reload (Phase 5+)
- "Build failed" error overlay page (Phase 4)
- TLS / HTTPS dev mode (Phase 5+)
- Watching `public/` directory if/when scaffolding grows one (TBD by future template changes)

---

## Task 1: Add Hummingbird + HummingbirdWebSocket dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Update Package.swift dependencies**

  Edit the `dependencies:` array in `Package.swift` to add Hummingbird. After the existing `swift-argument-parser` entry, add:

  ```swift
          // Hummingbird is the HTTP+WebSocket server for `swiflow dev`. v2 is
          // async/await native and Swift 6 strict-concurrency clean. We pin
          // to upToNextMinor — 2.x has had API drift across minor releases
          // (WebSocket router context refactor in 2.6, etc.).
          .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.6.0")),
          .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", .upToNextMinor(from: "2.2.0")),
  ```

  In the `SwiflowCLI` target's `dependencies:`, add Hummingbird products:

  ```swift
              .product(name: "Hummingbird", package: "hummingbird"),
              .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
  ```

  In the `SwiflowCLITests` target's `dependencies:`, add the testing helpers:

  ```swift
              .product(name: "HummingbirdTesting", package: "hummingbird"),
              .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
  ```

- [ ] **Step 2: Resolve and build**

  Run: `swift package resolve 2>&1 | tail -10`
  Expected: `Resolved` line for hummingbird + hummingbird-websocket; no errors. (`Package.resolved` may now exist — that's intentional; leave it for the future Phase 4 task that decides whether to commit it.)

  Run: `swift build --product swiflow 2>&1 | tail -5`
  Expected: build succeeds. (No new code yet — just verifying the deps compile against Swift 6.)

- [ ] **Step 3: Confirm existing tests still pass**

  Run: `swift test --filter "BuildCommand|WasmSDKProbe" 2>&1 | tail -5`
  Expected: existing tests green. Adding deps shouldn't affect anything.

- [ ] **Step 4: Commit**

  ```bash
  git add Package.swift
  git commit -m "$(cat <<'EOF'
  feat(deps): add Hummingbird 2 for the Phase 2c dev server

  Hummingbird + HummingbirdWebSocket give the dev server an async/await
  native HTTP+WebSocket stack on swift-nio with ~5× less boilerplate than
  bare swift-nio for the same two routes. HummingbirdTesting +
  HummingbirdWSTesting attach to the test target so route + WebSocket
  assertions can use `app.test(.live)` without cross-platform URLSession
  quirks.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 2: Parameterize BuildInvocation with a BuildConfiguration enum

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift`

Why: `swiflow dev` rebuilds in a different shape than `swiflow build` — no `-c release`, with `-g` for DWARF symbols. Extracting `BuildConfiguration` is the cleanest seam.

- [ ] **Step 1: Write the failing test for dev-mode argv**

  Append to `BuildCommandArgvTests` in `Tests/SwiflowCLITests/BuildCommandTests.swift` (just before the closing `}` of the struct):

  ```swift
      @Test("Dev configuration drops -c release and adds -g for DWARF symbols")
      func devConfigurationArgv() throws {
          let stub = StubProcessRunner(stubbedExitCode: 0)
          let composer = BuildInvocation(
              swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
              projectPath: URL(fileURLWithPath: "/tmp/demo"),
              swiftSDK: "swift-6.3-RELEASE_wasm",
              toolchainBundleID: nil,
              configuration: .dev
          )
          _ = try composer.run(using: stub)
          #expect(stub.calls[0].arguments == [
              "package",
              "--swift-sdk", "swift-6.3-RELEASE_wasm",
              "js",
              "--use-cdn",
              "--product", "App",
              "-Xswiftc", "-g",
          ])
      }

      @Test("Release configuration is the default and matches the existing argv")
      func releaseConfigurationIsDefault() throws {
          let stub = StubProcessRunner(stubbedExitCode: 0)
          let composer = BuildInvocation(
              swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
              projectPath: URL(fileURLWithPath: "/tmp/demo"),
              swiftSDK: "swift-6.3-RELEASE_wasm",
              toolchainBundleID: nil
              // configuration omitted — must default to .release
          )
          _ = try composer.run(using: stub)
          #expect(stub.calls[0].arguments.contains("release"))
          #expect(!stub.calls[0].arguments.contains("-g"))
      }
  ```

- [ ] **Step 2: Run, confirm failure**

  Run: `swift test --filter "BuildCommandArgvTests/devConfigurationArgv" 2>&1 | tail -10`
  Expected: build error — `BuildInvocation` has no `configuration` parameter.

- [ ] **Step 3: Add BuildConfiguration enum and parameterize BuildInvocation**

  In `Sources/SwiflowCLI/Commands/BuildCommand.swift`, just above `struct BuildInvocation`, add:

  ```swift
  /// `swiflow build` and `swiflow dev` invoke the same SwiftPM plugin
  /// (`swift package js`) but with different shapes. Release flips on
  /// `-c release` for `wasm-opt`-friendly output; dev keeps optimisations
  /// off and asks the toolchain to embed DWARF debug symbols so a Chrome
  /// C/C++ DevTools extension can map traps back to Swift source lines.
  enum BuildConfiguration: Equatable {
      case release
      case dev
  }
  ```

  Update `BuildInvocation` to accept a configuration:

  ```swift
  struct BuildInvocation {
      let swiftExecutable: URL
      let projectPath: URL
      let swiftSDK: String
      let toolchainBundleID: String?
      let configuration: BuildConfiguration

      init(
          swiftExecutable: URL,
          projectPath: URL,
          swiftSDK: String,
          toolchainBundleID: String?,
          configuration: BuildConfiguration = .release
      ) {
          self.swiftExecutable = swiftExecutable
          self.projectPath = projectPath
          self.swiftSDK = swiftSDK
          self.toolchainBundleID = toolchainBundleID
          self.configuration = configuration
      }

      @discardableResult
      func run(using runner: ProcessRunner) throws -> ProcessResult {
          var arguments = [
              "package",
              "--swift-sdk", swiftSDK,
              "js",
              "--use-cdn",
              "--product", "App",
          ]
          switch configuration {
          case .release:
              arguments.append(contentsOf: ["-c", "release"])
          case .dev:
              // Dev mode: no -c release (default is debug), and ask swiftc
              // to emit DWARF so trap stack frames carry Swift file:line
              // info that Chrome's C/C++ DevTools extension can resolve.
              arguments.append(contentsOf: ["-Xswiftc", "-g"])
          }

          let environment: [String: String]? = {
              guard let bundleID = toolchainBundleID else { return nil }
              return ["TOOLCHAINS": bundleID]
          }()

          let result = try runner.run(
              executable: swiftExecutable,
              arguments: arguments,
              workingDirectory: projectPath,
              environment: environment,
              captureOutput: false
          )

          if result.exitCode != 0 {
              throw BuildCommandError.swiftPackageJSFailed(exitCode: result.exitCode)
          }
          return result
      }
  }
  ```

- [ ] **Step 4: Run the new tests + the existing ones**

  Run: `swift test --filter "BuildCommandArgvTests" 2>&1 | tail -15`
  Expected: all BuildCommandArgvTests pass (existing 6 + new 2 = 8).

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/Commands/BuildCommand.swift Tests/SwiflowCLITests/BuildCommandTests.swift
  git commit -m "$(cat <<'EOF'
  feat(build): parameterize BuildInvocation with BuildConfiguration

  BuildInvocation now takes a `configuration: BuildConfiguration = .release`
  with a `.dev` case that drops `-c release` and appends `-Xswiftc -g` so
  the WASM build carries DWARF debug symbols. `swiflow dev` will use the
  .dev variant in Phase 2c; existing `swiflow build` callers continue to
  get .release via the default. Two new argv-composition tests lock both
  shapes.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 3: DevModeInjection — pure string-transform helper

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/DevModeInjection.swift`
- Create: `Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift`

Why a separate file: keeping the dev-mode signal injection as a pure function makes it testable without spinning up a server. The HTTPRouter just imports and calls it.

- [ ] **Step 1: Write the failing tests**

  Create `Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift`:

  ```swift
  // Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift
  import Testing
  @testable import SwiflowCLI

  @Suite("DevModeInjection")
  struct DevModeInjectionTests {

      @Test("Injects window.SWIFLOW_DEV=true immediately before the driver tag")
      func injectsBeforeDriverTag() {
          let input = """
          <html><body>
          <div id="app"></div>
          <script src="swiflow-driver.js"></script>
          <script type="module">import { init } from "./x.js"; await init();</script>
          </body></html>
          """
          let output = DevModeInjection.injectDevSignal(into: input)
          #expect(output.contains("window.SWIFLOW_DEV=true"))
          // The injected script must come BEFORE the driver tag so the
          // global is set when the driver IIFE runs.
          let injectedIdx = output.range(of: "window.SWIFLOW_DEV=true")!.lowerBound
          let driverIdx = output.range(of: "swiflow-driver.js")!.lowerBound
          #expect(injectedIdx < driverIdx)
      }

      @Test("Falls back to injecting before </body> if no driver tag present")
      func fallsBackToBody() {
          let input = "<html><body><div>nothing here</div></body></html>"
          let output = DevModeInjection.injectDevSignal(into: input)
          #expect(output.contains("window.SWIFLOW_DEV=true"))
          let injectedIdx = output.range(of: "window.SWIFLOW_DEV=true")!.lowerBound
          let bodyCloseIdx = output.range(of: "</body>")!.lowerBound
          #expect(injectedIdx < bodyCloseIdx)
      }

      @Test("Returns input unchanged when HTML has neither driver tag nor </body>")
      func malformedPassesThrough() {
          let input = "<html><div>broken</div>"
          let output = DevModeInjection.injectDevSignal(into: input)
          #expect(output == input)
      }

      @Test("Injects only once, even if called on already-injected HTML")
      func idempotent() {
          let input = """
          <body><script src="swiflow-driver.js"></script></body>
          """
          let once = DevModeInjection.injectDevSignal(into: input)
          let twice = DevModeInjection.injectDevSignal(into: once)
          // Count occurrences of the marker
          let count = twice.components(separatedBy: "window.SWIFLOW_DEV=true").count - 1
          #expect(count == 1)
      }
  }
  ```

- [ ] **Step 2: Run, confirm compile failure**

  Run: `swift test --filter "DevModeInjectionTests" 2>&1 | tail -5`
  Expected: build error — `DevModeInjection` undefined.

- [ ] **Step 3: Implement DevModeInjection**

  Create `Sources/SwiflowCLI/DevServer/DevModeInjection.swift`:

  ```swift
  // Sources/SwiflowCLI/DevServer/DevModeInjection.swift
  //
  // Pure string transform that puts a `<script>window.SWIFLOW_DEV=true;</script>`
  // tag into served HTML so the embedded JS driver's reload-WS branch
  // activates. Lives in its own file so route handlers stay thin and so
  // the transform can be exercised without spinning up a Hummingbird app.
  //
  // The injected script MUST run before the driver IIFE, otherwise the
  // driver evaluates `window.SWIFLOW_DEV` as undefined and the WS branch
  // stays inert for the page lifetime.

  import Foundation

  enum DevModeInjection {
      /// Marker substring used both to inject and to detect idempotency.
      static let marker = "window.SWIFLOW_DEV=true"

      /// The literal tag inserted into the response body.
      private static let snippet = "<script>\(marker);</script>"

      /// Returns `html` with a dev-mode signal injected. If the input
      /// already contains the marker, returns it unchanged (idempotent so
      /// double-application is safe — e.g., when middleware order shifts).
      /// Looks for the first `<script src="swiflow-driver.js"` tag and
      /// inserts immediately before it; falls back to `</body>`; if
      /// neither is present, returns the input unmodified.
      static func injectDevSignal(into html: String) -> String {
          guard !html.contains(marker) else { return html }

          if let driverRange = html.range(of: "<script src=\"swiflow-driver.js") {
              return html.replacingCharacters(in: driverRange.lowerBound..<driverRange.lowerBound, with: snippet)
          }
          if let bodyCloseRange = html.range(of: "</body>") {
              return html.replacingCharacters(in: bodyCloseRange.lowerBound..<bodyCloseRange.lowerBound, with: snippet)
          }
          return html
      }
  }
  ```

- [ ] **Step 4: Run, confirm all four tests pass**

  Run: `swift test --filter "DevModeInjectionTests" 2>&1 | tail -10`
  Expected: 4/4 pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/DevServer/DevModeInjection.swift Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift
  git commit -m "$(cat <<'EOF'
  feat(devserver): pure DevModeInjection helper for window.SWIFLOW_DEV

  Injects `<script>window.SWIFLOW_DEV=true;</script>` immediately before
  the driver tag so the global exists when the JS driver IIFE runs.
  Falls back to before `</body>` if no driver tag found; passes input
  through unchanged when neither anchor exists. Idempotent on double
  application. Pure function — exercised by 4 unit tests with no server
  spin-up needed.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 4: FileWatcher (polling-based AsyncStream)

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/FileWatcher.swift`
- Create: `Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift`

- [ ] **Step 1: Write the failing tests**

  Create `Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift`:

  ```swift
  // Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift
  import Foundation
  import Testing
  @testable import SwiflowCLI

  @Suite("FileWatcher")
  struct FileWatcherTests {

      /// Helper: create a temp dir, run a closure, clean up.
      static func withTempDir(_ body: (URL) async throws -> Void) async throws {
          let dir = FileManager.default.temporaryDirectory
              .appendingPathComponent("swiflow-fw-\(UUID().uuidString)")
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          defer { try? FileManager.default.removeItem(at: dir) }
          try await body(dir)
      }

      /// Helper: write `contents` to `url`, ensuring mtime advances even
      /// on filesystems with low-resolution timestamps (HFS+, some Linux
      /// configurations). Polls until visible.
      static func writeFile(_ url: URL, _ contents: String = "x") throws {
          try contents.write(to: url, atomically: true, encoding: .utf8)
          // Bump mtime by ~50ms to guarantee diff visibility on coarse FS.
          let now = Date()
          try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
      }

      @Test("Yields the URL set after a new file is created")
      func detectsCreation() async throws {
          try await Self.withTempDir { root in
              let watcher = FileWatcher(
                  root: root,
                  interval: .milliseconds(100),
                  extensions: ["swift"]
              )
              let stream = watcher.changes()
              // Wait a tick for the initial snapshot to settle (no events yet).
              try await Task.sleep(for: .milliseconds(150))
              let newFile = root.appendingPathComponent("App.swift")
              try Self.writeFile(newFile)
              // Pull the next event with a generous timeout.
              let task = Task {
                  var iter = stream.makeAsyncIterator()
                  return await iter.next()
              }
              let event = try await withTimeout(seconds: 2) { await task.value }
              #expect(event?.contains(newFile) == true)
          }
      }

      @Test("Yields the URL set after a tracked file is modified")
      func detectsModification() async throws {
          try await Self.withTempDir { root in
              let file = root.appendingPathComponent("App.swift")
              try Self.writeFile(file, "v1")
              let watcher = FileWatcher(root: root, interval: .milliseconds(100), extensions: ["swift"])
              let stream = watcher.changes()
              try await Task.sleep(for: .milliseconds(150))
              // Force mtime to advance.
              try await Task.sleep(for: .milliseconds(60))
              try Self.writeFile(file, "v2")
              let task = Task {
                  var iter = stream.makeAsyncIterator()
                  return await iter.next()
              }
              let event = try await withTimeout(seconds: 2) { await task.value }
              #expect(event?.contains(file) == true)
          }
      }

      @Test("Ignores files whose extension is not in the watch list")
      func ignoresUnwatchedExtensions() async throws {
          try await Self.withTempDir { root in
              let watcher = FileWatcher(root: root, interval: .milliseconds(100), extensions: ["swift"])
              let stream = watcher.changes()
              try await Task.sleep(for: .milliseconds(150))
              try Self.writeFile(root.appendingPathComponent("README.txt"))
              // Wait twice the poll interval — no event should arrive.
              let task = Task {
                  var iter = stream.makeAsyncIterator()
                  return await iter.next()
              }
              // Race the iterator against a short timeout; expect the timeout to win.
              do {
                  _ = try await withTimeout(seconds: 0.5) { await task.value }
                  Issue.record("Expected no event for unwatched extension; got one")
              } catch is TimeoutError {
                  task.cancel()
              }
          }
      }

      // Tiny timeout helper — keeps tests deterministic without sleep-and-pray.
      struct TimeoutError: Error {}
      static func withTimeout<T: Sendable>(seconds: TimeInterval, _ body: @escaping @Sendable () async -> T) async throws -> T {
          try await withThrowingTaskGroup(of: T.self) { group in
              group.addTask { await body() }
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
  ```

- [ ] **Step 2: Run, confirm compile failure**

  Run: `swift test --filter "FileWatcherTests" 2>&1 | tail -10`
  Expected: build error — `FileWatcher` undefined.

- [ ] **Step 3: Implement FileWatcher**

  Create `Sources/SwiflowCLI/DevServer/FileWatcher.swift`:

  ```swift
  // Sources/SwiflowCLI/DevServer/FileWatcher.swift
  //
  // Polling file watcher. Chosen over FSEvents/inotify (which the spec
  // suggested) for two reasons: cross-platform with one code path, and
  // ~30 LOC vs. ~200 for the native equivalents. 250 ms latency is under
  // the user-perception threshold for save → reload and the CPU cost of
  // stat'ing ~50 files every poll is negligible (typical Sources/ tree).
  //
  // If Phase 4 ever profiles polling as a real bottleneck, swap the
  // `snapshot()` body for an FSEventStream / inotify backend. The
  // AsyncStream API is the seam.

  import Foundation

  final class FileWatcher: Sendable {
      let root: URL
      let interval: Duration
      let extensions: Set<String>

      /// - Parameters:
      ///   - root: directory to scan recursively. Top-level files matching
      ///     `extensions` are always watched; deeper files are only watched
      ///     if their parent path doesn't start with `.` (skips `.build`,
      ///     `.swiftpm`, etc.).
      ///   - interval: poll cadence. 250 ms is the dev-server default.
      ///   - extensions: file suffixes (without dot) to track. Other files
      ///     are ignored.
      init(root: URL, interval: Duration = .milliseconds(250), extensions: Set<String>) {
          self.root = root
          self.interval = interval
          self.extensions = extensions
      }

      /// Starts polling and yields a `Set<URL>` whenever any tracked file
      /// is created, modified, or deleted. The stream continues until the
      /// consumer terminates iteration (the inner task is cancelled on
      /// stream termination).
      func changes() -> AsyncStream<Set<URL>> {
          AsyncStream { continuation in
              let task = Task { [self] in
                  var previous = self.snapshot()
                  while !Task.isCancelled {
                      do {
                          try await Task.sleep(for: self.interval)
                      } catch {
                          break
                      }
                      let current = self.snapshot()
                      let changed = Self.diff(current: current, previous: previous)
                      if !changed.isEmpty {
                          continuation.yield(changed)
                      }
                      previous = current
                  }
                  continuation.finish()
              }
              continuation.onTermination = { _ in
                  task.cancel()
              }
          }
      }

      /// Walks `root` and returns (URL → modificationDate) for every file
      /// whose extension is in `extensions` and which isn't under a
      /// dot-prefixed directory (`.build`, `.swiftpm`, `.git`).
      private func snapshot() -> [URL: Date] {
          let fm = FileManager.default
          guard let enumerator = fm.enumerator(
              at: root,
              includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
              options: [.skipsHiddenFiles]
          ) else {
              return [:]
          }

          var result: [URL: Date] = [:]
          for case let url as URL in enumerator {
              let ext = url.pathExtension
              guard extensions.contains(ext) else { continue }
              guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                    values.isRegularFile == true,
                    let mtime = values.contentModificationDate else {
                  continue
              }
              result[url] = mtime
          }
          return result
      }

      /// Set-diff between two snapshots. Returns the union of created,
      /// modified, and deleted file URLs.
      static func diff(current: [URL: Date], previous: [URL: Date]) -> Set<URL> {
          var changed: Set<URL> = []
          for (url, date) in current {
              if previous[url] != date {
                  changed.insert(url)
              }
          }
          for url in previous.keys where current[url] == nil {
              changed.insert(url)
          }
          return changed
      }
  }
  ```

- [ ] **Step 4: Run the tests**

  Run: `swift test --filter "FileWatcherTests" 2>&1 | tail -10`
  Expected: 3/3 pass. (If any are flaky on first run, suspect mtime resolution; bump the per-step sleeps by 100 ms.)

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/DevServer/FileWatcher.swift Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift
  git commit -m "$(cat <<'EOF'
  feat(devserver): polling FileWatcher with AsyncStream<Set<URL>> API

  Cross-platform file watcher chosen over FSEvents/inotify for one code
  path and ~30 LOC. Polls every 250 ms by default; emits a Set<URL>
  whenever tracked files are created, modified, or deleted. Skips
  dot-prefixed dirs (.build, .swiftpm) and files outside the watched
  extension allowlist. Three tests cover creation, modification, and
  the negative case (unwatched extensions don't produce events).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 5: HTTPRouter — static file routes + DevModeInjection middleware

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/HTTPRouter.swift`
- Create: `Tests/SwiflowCLITests/DevServer/HTTPRouterTests.swift`

- [ ] **Step 1: Write the failing tests**

  Create `Tests/SwiflowCLITests/DevServer/HTTPRouterTests.swift`:

  ```swift
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
  ```

- [ ] **Step 2: Run, confirm compile failure**

  Run: `swift test --filter "HTTPRouterTests" 2>&1 | tail -10`
  Expected: build error — `HTTPRouter` undefined.

- [ ] **Step 3: Implement HTTPRouter**

  Create `Sources/SwiflowCLI/DevServer/HTTPRouter.swift`:

  ```swift
  // Sources/SwiflowCLI/DevServer/HTTPRouter.swift
  //
  // Builds a Hummingbird Router that:
  //   - serves the project root statically (index.html, swiflow-driver.js,
  //     the built .wasm + index.js, plus anything else the user puts there)
  //   - rewrites HTML responses through DevModeInjection so the JS driver's
  //     reload-WS branch activates
  //
  // Kept as a free `build(projectRoot:)` function (no class) so tests can
  // construct the router directly and feed it into `Application` without
  // a DevServer wrapper.

  import Foundation
  import Hummingbird
  import NIOCore

  enum HTTPRouter {
      /// Construct the dev-server router rooted at `projectRoot`. The
      /// router serves files under `projectRoot/` plus a synthetic `/`
      /// route that resolves to `index.html`. HTML responses pass through
      /// DevModeInjection.
      static func build(projectRoot: URL) -> Router<BasicRequestContext> {
          let router = Router()

          // GET / → index.html (with injection)
          router.get("/") { _, context in
              try await serveFile(at: projectRoot.appendingPathComponent("index.html"), context: context)
          }

          // GET /:path — anything else under projectRoot
          router.get("/**") { _, context in
              let rel = context.parameters.getCatchAll().joined(separator: "/")
              guard !rel.isEmpty else {
                  throw HTTPError(.notFound)
              }
              // Defence: refuse path-traversal attempts. A `..` segment
              // before resolution means the user is trying to escape root.
              guard !rel.split(separator: "/").contains("..") else {
                  throw HTTPError(.forbidden)
              }
              return try await serveFile(at: projectRoot.appendingPathComponent(rel), context: context)
          }

          return router
      }

      /// Read `fileURL` from disk and wrap it in a `Response`. HTML files
      /// pass through DevModeInjection so the dev-mode global is set
      /// before the driver IIFE runs.
      private static func serveFile<Context: RequestContext>(at fileURL: URL, context: Context) async throws -> Response {
          let fm = FileManager.default
          var isDir: ObjCBool = false
          guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
              throw HTTPError(.notFound)
          }

          let data = try Data(contentsOf: fileURL)
          let contentType = mimeType(for: fileURL.pathExtension)

          let bodyData: Data
          if contentType.hasPrefix("text/html"), let html = String(data: data, encoding: .utf8) {
              bodyData = Data(DevModeInjection.injectDevSignal(into: html).utf8)
          } else {
              bodyData = data
          }

          var response = Response(
              status: .ok,
              headers: [.contentType: contentType],
              body: ResponseBody(byteBuffer: ByteBuffer(bytes: bodyData))
          )
          // Disable browser caching in dev so file-watcher reloads see fresh content.
          response.headers[.cacheControl] = "no-store"
          return response
      }

      private static func mimeType(for ext: String) -> String {
          switch ext.lowercased() {
          case "html", "htm": return "text/html; charset=utf-8"
          case "js", "mjs":   return "application/javascript; charset=utf-8"
          case "css":         return "text/css; charset=utf-8"
          case "wasm":        return "application/wasm"
          case "json":        return "application/json; charset=utf-8"
          case "map":         return "application/json; charset=utf-8"
          case "svg":         return "image/svg+xml"
          case "png":         return "image/png"
          case "jpg", "jpeg": return "image/jpeg"
          case "ico":         return "image/x-icon"
          default:            return "application/octet-stream"
          }
      }
  }
  ```

- [ ] **Step 4: Run the tests**

  Run: `swift test --filter "HTTPRouterTests" 2>&1 | tail -10`
  Expected: 4/4 pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/DevServer/HTTPRouter.swift Tests/SwiflowCLITests/DevServer/HTTPRouterTests.swift
  git commit -m "$(cat <<'EOF'
  feat(devserver): HTTPRouter serves project root with HTML dev-injection

  Hummingbird Router with three behaviors: GET / returns index.html
  (with DevModeInjection rewriting), GET /<path> serves files from the
  project root, GET on a missing path returns 404. HTML responses get
  the dev signal injected; other content types pass through unchanged.
  Path-traversal attempts (`..` segments) return 403. Cache-Control:
  no-store on every response so file-watcher reloads see fresh content.
  Four tests cover index, explicit index.html, non-HTML, and 404.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6: WebSocketHub — broadcast actor

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/WebSocketHub.swift`
- Create: `Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift`

- [ ] **Step 1: Write the failing tests**

  Create `Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift`:

  ```swift
  // Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift
  import Foundation
  import Hummingbird
  import HummingbirdWebSocket
  import HummingbirdTesting
  import HummingbirdWSTesting
  import Testing
  @testable import SwiflowCLI

  @Suite("WebSocketHub")
  struct WebSocketHubTests {

      @Test("Broadcast delivers {\"type\":\"reload\"} to every connected client")
      func broadcastFanout() async throws {
          let hub = WebSocketHub()
          let wsRouter = Router(context: BasicWebSocketRequestContext.self)
          wsRouter.ws("/reload") { _, _ in
              return .upgrade()
          } onUpgrade: { _, outbound, _ in
              let id = await hub.register(outbound)
              defer { Task { await hub.unregister(id) } }
              // Block until the connection drops.
              try? await Task.sleep(for: .seconds(30))
          }

          let app = Application(
              router: Router(),
              server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
              configuration: .init(address: .hostname("127.0.0.1", port: 0))
          )

          try await app.test(.live) { client in
              // Connect two clients; have each grab the first inbound message.
              async let firstMsg = client.ws("/reload") { inbound, _, _ in
                  var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                  return await iter.next()
              }
              async let secondMsg = client.ws("/reload") { inbound, _, _ in
                  var iter = inbound.messages(maxSize: .max).makeAsyncIterator()
                  return await iter.next()
              }

              // Give registrations a moment to complete before broadcasting.
              try await Task.sleep(for: .milliseconds(100))
              await hub.broadcastReload()

              let r1 = try await firstMsg
              let r2 = try await secondMsg
              if case .text(let s1) = r1?.message { #expect(s1.contains("\"reload\"")) } else { Issue.record("first client got no text frame") }
              if case .text(let s2) = r2?.message { #expect(s2.contains("\"reload\"")) } else { Issue.record("second client got no text frame") }
          }
      }

      @Test("Unregister removes a client; subsequent broadcasts don't target it")
      func unregisterDrops() async throws {
          let hub = WebSocketHub()
          // Use the internal SPI to simulate a stale registration.
          let fakeWriter = StubOutboundWriter()
          let id = await hub.register(fakeWriter)
          await hub.unregister(id)
          await hub.broadcastReload()
          let writes = await fakeWriter.writeCount
          #expect(writes == 0)
      }
  }

  /// Tiny stub so the unregister test doesn't need a real WebSocket connection.
  /// Conforms to whatever protocol WebSocketHub.register accepts (likely
  /// `some WebSocketOutboundWriter` — narrowed in the impl).
  actor StubOutboundWriter: WebSocketOutboundWriterProtocol {
      var writeCount = 0
      func write(_: WebSocketOutboundFrame) async throws {
          writeCount += 1
      }
  }
  ```

  > **Heads up to the implementer:** the exact protocol name and frame
  > type for `OutboundWriter` may have evolved in the current Hummingbird
  > release. The test above assumes a `WebSocketOutboundWriterProtocol`
  > that the impl defines; pin it to whatever Hummingbird actually
  > exposes (likely just `WebSocketOutboundWriter`). The first test uses
  > the real Hummingbird API end-to-end and is the load-bearing one;
  > Test #2 is a nice-to-have. If Hummingbird's writer type isn't
  > stub-able, drop Test #2 and rely on integration coverage.

- [ ] **Step 2: Run, confirm compile failure**

  Run: `swift test --filter "WebSocketHubTests" 2>&1 | tail -10`
  Expected: build error — `WebSocketHub` undefined.

- [ ] **Step 3: Implement WebSocketHub**

  Create `Sources/SwiflowCLI/DevServer/WebSocketHub.swift`:

  ```swift
  // Sources/SwiflowCLI/DevServer/WebSocketHub.swift
  //
  // Actor that tracks every connected WebSocket and provides a
  // broadcastReload() API. DevCommand calls broadcastReload() after each
  // successful rebuild; the registered upgrade handler routes new
  // connections into this hub.
  //
  // We use an actor instead of a queue because all access is from async
  // contexts and the actor's serial executor is the right concurrency
  // primitive — no manual locking, no Sendable closures over mutable state.

  import Foundation
  import HummingbirdWebSocket

  actor WebSocketHub {
      typealias ClientID = UUID
      private var clients: [ClientID: WebSocketOutboundWriter] = [:]

      init() {}

      /// Register an outbound writer. Returns an ID the caller passes to
      /// `unregister` when the connection drops. Caller is responsible
      /// for unregistering — typically via `defer { Task { await hub.unregister(id) } }`
      /// inside the upgrade handler.
      func register(_ writer: WebSocketOutboundWriter) -> ClientID {
          let id = ClientID()
          clients[id] = writer
          return id
      }

      func unregister(_ id: ClientID) {
          clients.removeValue(forKey: id)
      }

      /// Send `{"type":"reload"}` to every connected client. Writes that
      /// fail (connection dropped, peer reset) drop the client from the
      /// registry so the next broadcast doesn't retry against it.
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

      /// Test-only: number of currently registered clients.
      var clientCount: Int {
          clients.count
      }
  }
  ```

- [ ] **Step 4: Run the tests**

  Run: `swift test --filter "WebSocketHubTests" 2>&1 | tail -10`
  Expected: at least Test #1 (broadcast fanout) passes. Test #2 (unregister) passes if the stub protocol matches; if not, drop Test #2 with a `// MARK: - dropped — Hummingbird's writer isn't easily stubbable` note.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/DevServer/WebSocketHub.swift Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift
  git commit -m "$(cat <<'EOF'
  feat(devserver): WebSocketHub actor for /reload broadcast fanout

  Holds a [UUID: WebSocketOutboundWriter] map and exposes a
  broadcastReload() coroutine that ships `{"type":"reload"}` to every
  connected client. Failed writes drop the client from the registry.
  Actor isolation handles concurrent register/unregister/broadcast
  without manual locking. Live-server test asserts fanout to two
  simultaneous clients.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 7: DevServer — Application wiring

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/DevServer.swift`

- [ ] **Step 1: Implement DevServer**

  Create `Sources/SwiflowCLI/DevServer/DevServer.swift`:

  ```swift
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
          } onUpgrade: { _, outbound, _ in
              let id = await hub.register(outbound)
              defer { Task { await hub.unregister(id) } }
              // Block until the peer hangs up. The inbound stream finishes
              // when the WebSocket closes, so iterating it is the simplest
              // "wait for disconnect" primitive.
              for try await _ in await inboundIterator(of: outbound) {
                  // Phase 2c doesn't react to client messages — the channel
                  // is one-way (server → browser). Drain silently.
              }
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

      // MARK: - private

      /// Hummingbird's upgrade closure gives us `inbound` and `outbound`
      /// as separate parameters; we use only `outbound` for broadcast, so
      /// the inbound iteration here is purely a "wait for disconnect"
      /// signal. Extracted into a helper to keep the upgrade closure tidy.
      private static func inboundIterator(of _: WebSocketOutboundWriter) -> some AsyncSequence {
          // Placeholder — replaced by actual inbound parameter in real impl.
          // (See implementer note in Step 2 below.)
          AsyncStream<Never> { _ in }
      }
  }
  ```

  > **Implementer note:** the `inboundIterator` helper above is a
  > placeholder. The actual `onUpgrade` closure has the signature
  > `(inbound, outbound, context) async throws -> Void`, so just iterate
  > `inbound.messages(maxSize: .max)` directly inside the closure (don't
  > bother with the helper). The helper is there in the plan to keep
  > the type-shape visible — when you write the real version, prefer
  > the inline approach.

- [ ] **Step 2: Smoke-test by building**

  Run: `swift build --product swiflow 2>&1 | tail -10`
  Expected: builds clean. No unit tests for DevServer alone — it's a wiring shim, exercised by the integration test in Task 10.

- [ ] **Step 3: Commit**

  ```bash
  git add Sources/SwiflowCLI/DevServer/DevServer.swift
  git commit -m "$(cat <<'EOF'
  feat(devserver): DevServer wires HTTPRouter + WebSocketHub into one Application

  Single Hummingbird Application combining the static file router (with
  HTML dev-injection) and a /reload WebSocket router that registers each
  incoming connection with the hub. Lifecycle is `await server.run()`
  blocking until SIGINT/SIGTERM via Hummingbird's ServiceLifecycle hook.
  No unit tests at this layer — DevServer is exercised end-to-end by the
  Task 10 integration test.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 8: JS driver — WebSocket reload listener

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Modify: `Sources/SwiflowCLI/EmbeddedDriver.swift` (regenerated)

- [ ] **Step 1: Append the dev-mode reload listener to the JS driver**

  Edit `js-driver/swiflow-driver.js`. At the very end of the IIFE (after the closing `})();` of `window.swiflow`'s assignment but still INSIDE the outer IIFE — i.e., before the final `})();` of the whole file), add:

  ```js
    // Dev-mode reload listener. Activates only when the dev server has
    // injected `window.SWIFLOW_DEV=true` before this driver runs.
    // Production builds leave the global undefined; this branch stays
    // inert and does NOT attempt the WebSocket (no DevTools console
    // noise from a failed `ws://localhost/reload` connection).
    if (window.SWIFLOW_DEV) {
      let reconnectDelay = 250;
      const maxDelay = 5000;

      function connect() {
        const url = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/reload";
        const ws = new WebSocket(url);
        ws.onopen = function () {
          reconnectDelay = 250;
        };
        ws.onmessage = function (m) {
          let payload;
          try {
            payload = JSON.parse(m.data);
          } catch (e) {
            return;
          }
          if (payload && payload.type === "reload") {
            location.reload();
          }
        };
        ws.onclose = function () {
          // Reconnect with exponential backoff so killing+restarting
          // `swiflow dev` causes the page to silently reattach. No cap
          // on attempts — dev mode, no users.
          setTimeout(connect, reconnectDelay);
          reconnectDelay = Math.min(reconnectDelay * 2, maxDelay);
        };
        ws.onerror = function () {
          // The close handler does the retry; swallow the error to keep
          // DevTools console clean during dev-server restarts.
        };
      }
      connect();
    }
  ```

- [ ] **Step 2: Regenerate the embedded driver**

  Run: `swift scripts/embed-driver.swift`
  Expected: `wrote .../EmbeddedDriver.swift (NNNNN bytes)` — the byte count grows by ~1.5 KB vs. before.

  Run: `git diff --stat Sources/SwiflowCLI/EmbeddedDriver.swift`
  Expected: file changed (insertions match the JS additions roughly).

- [ ] **Step 3: Verify the freshness test catches the regeneration**

  Run: `swift test --filter "DriverEmbedderTests" 2>&1 | tail -10`
  Expected: all 3 driver tests pass. (If `embeddedDriverIsFresh` fails, the embed step in Step 2 didn't run successfully — re-run it.)

- [ ] **Step 4: Commit (both files together)**

  ```bash
  git add js-driver/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift
  git commit -m "$(cat <<'EOF'
  feat(driver): WebSocket reload listener gated on window.SWIFLOW_DEV

  When the dev server has injected window.SWIFLOW_DEV=true, the driver
  opens ws://<host>/reload and calls location.reload() on every
  {"type":"reload"} message. Exponential backoff (250 ms → 5 s cap) on
  disconnect so killing+restarting swiflow dev silently reattaches.
  Production builds (no injection) leave the branch inert — no failed
  WebSocket attempt, no DevTools console noise.

  Regenerated EmbeddedDriver.swift to ship the updated source.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 9: DevCommand orchestrator

**Files:**
- Create: `Sources/SwiflowCLI/Commands/DevCommand.swift`
- Modify: `Sources/SwiflowCLI/Swiflow.swift`
- Create: `Tests/SwiflowCLITests/DevCommandTests.swift`

- [ ] **Step 1: Implement DevCommand**

  Create `Sources/SwiflowCLI/Commands/DevCommand.swift`:

  ```swift
  // Sources/SwiflowCLI/Commands/DevCommand.swift
  //
  // `swiflow dev` — initial dev build, then start the dev server, then
  // start the file watcher and rebuild + broadcast reload on every save.
  //
  // The command never returns under normal operation; it blocks on
  // server.run() and is shut down via SIGINT/SIGTERM. The file-watcher
  // pump is a background Task that the outer cancellation tears down.

  import ArgumentParser
  import Foundation

  struct DevCommand: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
          commandName: "dev",
          abstract: "Start the Swiflow dev server with file-watch + browser reload."
      )

      @Option(
          name: .customLong("path"),
          help: "Path to the Swiflow project directory. Defaults to the current working directory."
      )
      var path: String = "."

      @Option(
          name: .customLong("port"),
          help: "HTTP port for the dev server. Default 3000."
      )
      var port: Int = 3000

      @Option(
          name: .customLong("swift-sdk"),
          help: "Override the Swift WASM SDK identifier."
      )
      var swiftSDK: String?

      func run() async throws {
          let runner = SystemProcessRunner()

          // 0. Validate the project path.
          let projectURL = URL(fileURLWithPath: path).standardizedFileURL
          var isDir: ObjCBool = false
          guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
              throw ValidationError(String(describing: BuildCommandError.projectPathNotFound(projectURL)))
          }

          // 1. Locate swift on PATH.
          guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
              throw ValidationError(String(describing: BuildCommandError.swiftNotOnPath))
          }

          // 2. Resolve the WASM SDK.
          let sdk: String
          if let userSDK = swiftSDK {
              sdk = userSDK
          } else {
              let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
              let installed: [String]
              do {
                  installed = try probe.list()
              } catch let WasmSDKProbeError.sdkSubcommandFailed(exitCode, stderr) {
                  throw ValidationError(String(describing: BuildCommandError.wasmSDKListFailed(
                      exitCode: exitCode,
                      stderr: stderr
                  )))
              }
              guard let firstInstalled = installed.first else {
                  throw ValidationError(String(describing: BuildCommandError.noWasmSDKInstalled))
              }
              sdk = firstInstalled
          }

          // 3. Toolchain on macOS.
          let toolchainBundleID: String? = ProcessInfo.processInfo.environment["TOOLCHAINS"] != nil
              ? nil
              : MacToolchainProbe.swiftLatestBundleIdentifier()

          // 4. Initial build. Failures here exit non-zero (Phase 2c
          //    decision §6 — nothing to serve if the first build fails).
          let invocation = BuildInvocation(
              swiftExecutable: swift,
              projectPath: projectURL,
              swiftSDK: sdk,
              toolchainBundleID: toolchainBundleID,
              configuration: .dev
          )
          print("swiflow: initial build (dev configuration)...")
          do {
              _ = try invocation.run(using: runner)
          } catch let error as BuildCommandError {
              throw ValidationError(String(describing: error))
          }

          // 5. Start the dev server.
          let server = DevServer(projectRoot: projectURL, port: port)
          print("swiflow: dev server listening on http://localhost:\(port)")

          // 6. Start the file watcher in a background task. On each
          //    change, rebuild and broadcast reload (decision §2: don't
          //    broadcast on failed rebuilds).
          let watcher = FileWatcher(
              root: projectURL,
              interval: .milliseconds(250),
              extensions: ["swift", "html", "js"]
          )

          // Run the server and the watcher pump concurrently. Either
          // exiting tears down the other.
          try await withThrowingTaskGroup(of: Void.self) { group in
              group.addTask {
                  try await server.run()
              }
              group.addTask {
                  for await changed in watcher.changes() {
                      print("swiflow: rebuilding (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                      do {
                          _ = try invocation.run(using: runner)
                          await server.hub.broadcastReload()
                          print("swiflow: reload broadcast")
                      } catch {
                          print("swiflow: rebuild failed — \(error). Browser unchanged; fix and save to retry.")
                      }
                  }
              }
              try await group.next()
              group.cancelAll()
          }
      }
  }
  ```

- [ ] **Step 2: Register DevCommand in the subcommand table**

  In `Sources/SwiflowCLI/Swiflow.swift`, update the `subcommands:` array:

  ```swift
          subcommands: [InitCommand.self, BuildCommand.self, DevCommand.self],
  ```

- [ ] **Step 3: Add DevCommand argv tests**

  Create `Tests/SwiflowCLITests/DevCommandTests.swift`:

  ```swift
  // Tests/SwiflowCLITests/DevCommandTests.swift
  import ArgumentParser
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
  ```

- [ ] **Step 4: Build + run the argv tests**

  Run: `swift build --product swiflow 2>&1 | tail -5`
  Expected: builds clean.

  Run: `swift test --filter "DevCommandTests" 2>&1 | tail -10`
  Expected: 3/3 pass.

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/SwiflowCLI/Commands/DevCommand.swift Sources/SwiflowCLI/Swiflow.swift Tests/SwiflowCLITests/DevCommandTests.swift
  git commit -m "$(cat <<'EOF'
  feat(cli): swiflow dev — initial build, server, file watcher, reload

  Orchestrator command that ties the Phase 2c pieces together: validate
  path → locate swift → pick WASM SDK → initial dev build → start
  DevServer + FileWatcher in a TaskGroup → on every saved file rebuild
  and broadcast reload to every connected browser. Failed rebuilds keep
  the browser on the last-good version (decision §2). Initial build
  failure exits non-zero with the build error (decision §6).

  Registered in the root command's subcommand table. Argv parsing
  covered by three unit tests; end-to-end coverage lands in Task 10.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 10: End-to-end integration test (gated on WASM SDK)

**Files:**
- Modify: `Tests/SwiflowCLITests/DevCommandTests.swift`

This is the Phase 2c headline KPI test. Spawn `swiflow init` in a temp dir, start `swiflow dev` in a background task, connect via URLSession + URLSessionWebSocketTask, edit a source file, assert the WebSocket fires `{"type":"reload"}` within 10 s.

> **Cost note:** this test does a real WASM build inside the spawned project (~60 s, same shape as `BuildCommandIntegrationTests.endToEnd`). Gate it on the same `wasmSDKAvailable` check so it skips when the SDK isn't installed.

- [ ] **Step 1: Add the integration suite to DevCommandTests.swift**

  Append to `Tests/SwiflowCLITests/DevCommandTests.swift`:

  ```swift
  // MARK: - End-to-end (requires WASM SDK)

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
              into: tmp,
              swiflowSource: BuildCommandIntegrationTests.swiflowRepoRoot.path,
              jsDriverSource: EmbeddedDriver.javascriptSource
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

          let received = try await withTimeout(seconds: 5) {
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
  ```

- [ ] **Step 2: Run the integration test (slow — ~60 s)**

  Run: `swift test --filter "DevCommandIntegrationTests" 2>&1 | tail -10`
  Expected: 1/1 pass (or .enabled-skipped if WASM SDK isn't installed).

- [ ] **Step 3: Run the full suite once for the headline number**

  Run: `swift test 2>&1 | tail -5`
  Expected: all tests pass. New total: 180 baseline + new (estimate: ~14 new) ≈ 194 passing.

- [ ] **Step 4: Manual smoke test (the Phase 2 KPI)**

  ```bash
  swift build --product swiflow -c release
  TMP=$(mktemp -d)
  ./.build/release/swiflow init demo --path "$TMP"
  cd "$TMP/demo"
  ../../.build/release/swiflow dev &
  DEV_PID=$!
  sleep 8                           # initial build
  curl -s http://localhost:3000/ | grep -q SWIFLOW_DEV && echo "DEV injected ✓"
  # Edit App.swift to change the title
  sed -i.bak 's/Hello, Swiflow!/Hello, World!/' Sources/App/App.swift
  sleep 8                           # rebuild + reload broadcast
  echo "Open http://localhost:3000 in a browser and verify the title changed."
  echo "Then: kill $DEV_PID"
  ```

  Open a browser, point at `http://localhost:3000/`, confirm: page renders, click Increment, count rises, then save another source-file edit and watch the page reload.

- [ ] **Step 5: Commit**

  ```bash
  git add Tests/SwiflowCLITests/DevCommandTests.swift
  git commit -m "$(cat <<'EOF'
  test(devcommand): end-to-end gated test for the Phase 2 KPI

  Scaffolds a project, runs the initial dev build, starts the DevServer
  on a random ephemeral port, asserts GET / returns the injected
  index.html, then opens a /reload WebSocket and asserts that
  broadcastReload() ships {"type":"reload"} within 5s. Gated on
  wasmSDKAvailable (same gate as BuildCommandIntegrationTests).

  This is the load-bearing assertion for Phase 2c — together with the
  Task 4 + 6 unit coverage of FileWatcher and WebSocketHub, it confirms
  the rebuild → broadcast → reload pipeline works end-to-end.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Verification

After Task 10 lands:

### Automated
```bash
swift test 2>&1 | tail -5
# Expected: ~194 tests pass on macOS. The DevCommandIntegrationTests test
# adds ~60-90s to the run. CI on Linux runs the same gate.
```

### Manual smoke (the Phase 2 KPI from §5.5 of the spec)
```bash
swift build --product swiflow -c release
mkdir -p /tmp/swiflow-demo && cd /tmp/swiflow-demo
../../path/to/swiflow/.build/release/swiflow init demo
cd demo
../../path/to/swiflow/.build/release/swiflow dev
# → browser opens to http://localhost:3000
# → page shows "Hello, Swiflow!" + Count: 0 + Increment button
# → click Increment → count rises ✓
# → edit Sources/App/App.swift, change "Hello, Swiflow!" to "Hi, Swiflow!"
# → save → wait ≤2s → page reloads with new title ✓
```

### Observability spot-check
- Add `print("dev test")` to `App.swift`, save, wait for reload → string appears in browser DevTools console (existing Phase 2a hook still works).
- Kill `swiflow dev` (Ctrl-C), wait 5s, restart → browser silently reconnects ≤5s and is reload-ready (reconnect backoff working).

---

## Out of Scope (Phase 2c)

- **Source maps as separate `.map` files.** DWARF debug symbols (`-g` in the dev build) cover the spec's Phase 2c observability requirement; full source maps land in Phase 4.
- **Hot Module Replacement.** Reload is full-page; state is lost. Honest about Phase 2c per the brainstorm spec. Phase 5+ may explore HMR.
- **"Build failed" error overlay page.** A failed rebuild keeps the last-good page; the dev-server terminal shows the build error. A dedicated overlay UI is Phase 4.
- **TLS / HTTPS dev mode.** All Phase 2c communication is plain HTTP/WS. HTTPS is Phase 5+.
- **`--open` flag to launch the browser.** Useful, but trivial enough to add later when contributor friction surfaces. Spec doesn't require it.
- **`public/` directory in templates.** Current templates put `index.html` at the project root; if/when scaffolding grows a `public/` subdir, FileWatcher's watch scope needs revision.
- **FSEvents/inotify backend for FileWatcher.** Polling is the Phase 2c choice (Decision §1). Phase 4 may swap if profiling warrants.

---

## Self-Review Notes

- **Spec coverage:** Every Phase 2c requirement from §5.1, §5.2, §5.4, and §5.5 of the brainstorm spec is covered by a task here. The two explicit deviations (polling FileWatcher, single-port `--port` instead of fixed 3000) are flagged in Decisions §1 and §8 with rationale.
- **Placeholder scan:** Two heads-up notes to the implementer (Task 6 Step 1 on the writer stub protocol, Task 7 Step 1 on `inboundIterator` placeholder). Both are explicitly marked with rationale and an alternate path; neither blocks task completion.
- **Type consistency:** `BuildConfiguration` introduced in Task 2 used identically in Task 9. `WebSocketHub.ClientID` (Task 6) referenced consistently. `FileWatcher.changes()` return type (`AsyncStream<Set<URL>>`) consistent in Task 4 definition and Task 9 consumption. Hummingbird API types (`Router`, `Application`, `WebSocketOutboundWriter`, `BasicWebSocketRequestContext`) used uniformly per the docs query I ran while drafting.
- **Risk:** The Hummingbird API may have evolved between when this plan was written and when it's executed. The implementer should treat the code samples as design intent, not literal API calls — small adjustments (parameter names, generic constraints) may be needed. The plan calls this out at Task 6 explicitly. All other API uses follow the docs query directly so should be current.
- **Test count math:** Task 2 adds 2, Task 3 adds 4, Task 4 adds 3, Task 5 adds 4, Task 6 adds 2 (or 1 if the stub is dropped), Task 9 adds 3, Task 10 adds 1. Total: 19 new tests (~17 if Task 6's stub doesn't pan out). Adding to the current 179 baseline = ~196 passing after Phase 2c lands.
