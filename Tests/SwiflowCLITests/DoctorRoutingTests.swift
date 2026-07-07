// Tests/SwiflowCLITests/DoctorRoutingTests.swift
//
// Audit III Wave-1 #1: doctor is a capable toolchain audit, but it was a dead
// end nobody was sent to — a missing/mismatched SDK surfaced during build/dev
// as "exit code N. See output above." with no pointer, and init's next steps
// jumped straight to `swiflow dev`, so a first-timer without the SDK met a
// cryptic failure before learning doctor exists. These pin the routing.
import Testing
@testable import SwiflowCLI

@Suite("Failures route to swiflow doctor")
struct DoctorRoutingTests {
    // Toolchain-plausible failures must point at doctor.

    @Test("a swift-package-js failure suggests doctor (conditionally — compile errors dominate)")
    func packageJSFailurePointsAtDoctor() {
        let msg = String(describing: BuildCommandError.swiftPackageJSFailed(exitCode: 1))
        #expect(msg.contains("swiflow doctor"))
    }

    @Test("a swift-build failure suggests doctor")
    func swiftBuildFailurePointsAtDoctor() {
        let msg = String(describing: BuildCommandError.swiftBuildFailed(exitCode: 1))
        #expect(msg.contains("swiflow doctor"))
    }

    @Test("a missing WASM SDK points at doctor")
    func noWasmSDKPointsAtDoctor() {
        let msg = String(describing: BuildCommandError.noWasmSDKInstalled)
        #expect(msg.contains("swiflow doctor"))
    }

    @Test("a failed `swift sdk list` points at doctor")
    func sdkListFailurePointsAtDoctor() {
        let msg = String(describing: BuildCommandError.wasmSDKListFailed(exitCode: 2, stderr: "boom"))
        #expect(msg.contains("swiflow doctor"))
        #expect(msg.contains("boom"), "the stderr detail must survive the added pointer")
    }

    @Test("swift-not-on-PATH points at doctor")
    func swiftNotOnPathPointsAtDoctor() {
        let msg = String(describing: BuildCommandError.swiftNotOnPath)
        #expect(msg.contains("swiflow doctor"))
    }

    // Failures that are NOT toolchain problems must stay quiet about doctor —
    // a bad --path or a packaging bug isn't something doctor can diagnose,
    // and pointing at it there would erode the pointer's signal.

    @Test("non-toolchain failures do not mention doctor")
    func nonToolchainFailuresStayQuiet() {
        let url = URL(fileURLWithPath: "/tmp/nope")
        #expect(!String(describing: BuildCommandError.projectPathNotFound(url)).contains("doctor"))
        #expect(!String(describing: BuildCommandError.manifestArtifactMissing(url)).contains("doctor"))
    }

    // Init's next steps: doctor is step 0, before dev — a first-timer without
    // the SDK should learn about doctor BEFORE the first cryptic failure.

    @Test("init's next steps lead with doctor, before swiflow dev")
    func initNextStepsLeadWithDoctor() throws {
        let steps = InitCommand.nextSteps(projectPath: "/tmp/my-app")
        let doctor = try #require(steps.range(of: "swiflow doctor"))
        let dev = try #require(steps.range(of: "swiflow dev"))
        #expect(doctor.lowerBound < dev.lowerBound, "doctor must be step 0, ahead of dev")
        #expect(steps.contains("cd /tmp/my-app"))
    }

    // Audit III Wave-1 #2: the serve suggestion used to chain
    // `http.server 3000 && open http://localhost:3000` — the server blocks in
    // the foreground, so `open` never ran until Ctrl-C and the promised tab
    // never opened, at the exact moment first-run trust is being earned.

    @Test("init's serve suggestion never chains a command AFTER the blocking server")
    func serveSuggestionDoesNotChainPastTheBlockingServer() throws {
        let steps = InitCommand.nextSteps(projectPath: "/tmp/my-app")
        let server = try #require(steps.range(of: "http.server 3000"))
        // Nothing may be `&&`-chained after the foreground server…
        let afterServer = steps[server.upperBound...]
        let serverLine = afterServer.prefix(while: { $0 != "\n" })
        #expect(!serverLine.contains("&&"),
                "the server blocks; anything chained after it never runs")
        // …but the URL must still be told to the user (as a comment).
        #expect(steps.contains("http://localhost:3000"))
    }
}

import Foundation
