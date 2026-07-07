// Tests/SwiflowCLITests/DevLoopStatusTests.swift
//
// Audit III Wave-1 #3 + #6: the dev loop's status lines.
//
// #3 — the cold first build printed one line then went silent through a
// possibly-minutes-long dependency-resolve + WASM compile, looking hung.
// An expectation-setting line (cold builds only) plus an elapsed-time
// stamp on completion converts "is it broken?" into "it's working".
//
// #6 — within one loop the voice was mixed: "rebuilding (1 file
// changed)..." (present progressive) → "HMR broadcast" / "reload
// broadcast" (noun phrases, internal jargon). One action-first voice:
// rebuilding… / hot-swapped / reloaded / rebuild failed — <reason>.
import Testing
@testable import SwiflowCLI

@Suite("Dev-loop status voice")
struct DevLoopStatusTests {

    // MARK: #3 — cold first build sets expectations, completion stamps elapsed

    @Test("a cold initial build warns that resolve + compile can take minutes")
    func coldBuildSetsExpectations() {
        let status = DevCommand.initialBuildStatus(cold: true)
        #expect(status.contains("resolves dependencies"))
        #expect(status.contains("can take a few minutes"))
    }

    @Test("a warm initial build stays quiet about first-build duration")
    func warmBuildStaysQuiet() {
        let status = DevCommand.initialBuildStatus(cold: false)
        #expect(!status.contains("can take a few minutes"))
        #expect(status.contains("building"), "the build announcement itself must remain")
    }

    @Test("initial build completion stamps the elapsed time")
    func completionStampsElapsed() {
        let msg = DevCommand.initialBuildCompleted(elapsed: .seconds(222))
        #expect(msg == "swiflow: built in 3m 42s")
    }

    @Test("elapsed formatting: sub-minute gets one decimal, minutes get m/s")
    func elapsedFormatting() {
        #expect(DevCommand.formatElapsed(.milliseconds(800)) == "0.8s")
        #expect(DevCommand.formatElapsed(.milliseconds(12_340)) == "12.3s")
        #expect(DevCommand.formatElapsed(.seconds(60)) == "1m 0s")
        #expect(DevCommand.formatElapsed(.seconds(222)) == "3m 42s")
    }

    // MARK: #6 — one action-first voice across the loop

    @Test("the loop announces work in the progressive voice with the change count")
    func loopStatusVoice() {
        let rebuild = DevCommand.loopStatus(
            dispatch: .init(rebuild: true, broadcast: .hmrSwap), changedCount: 1)
        #expect(rebuild == "swiflow: rebuilding (1 file changed)...")
        let reload = DevCommand.loopStatus(
            dispatch: .init(rebuild: false, broadcast: .reload), changedCount: 2)
        #expect(reload == "swiflow: reloading (2 files changed)...")
    }

    @Test("a completed hot swap says hot-swapped with the rebuild latency")
    func hmrCompletionVoice() {
        let msg = DevCommand.loopCompletion(
            broadcast: .hmrSwap, rebuildElapsed: .milliseconds(1_400))
        #expect(msg == "swiflow: hot-swapped in 1.4s")
    }

    @Test("a rebuild+reload says reloaded with the rebuild latency")
    func rebuildReloadCompletionVoice() {
        let msg = DevCommand.loopCompletion(
            broadcast: .reload, rebuildElapsed: .milliseconds(5_200))
        #expect(msg == "swiflow: reloaded in 5.2s")
    }

    @Test("a static-asset reload (no rebuild) says reloaded, with no phantom latency")
    func staticReloadCompletionVoice() {
        let msg = DevCommand.loopCompletion(broadcast: .reload, rebuildElapsed: nil)
        #expect(msg == "swiflow: reloaded")
    }

    @Test("completions never leak internal jargon (broadcast/HMR)")
    func noJargon() {
        for broadcast in [DevCommand.ChangeDispatch.Broadcast.hmrSwap, .reload] {
            for elapsed in [Duration.milliseconds(1_400), nil] {
                let msg = DevCommand.loopCompletion(broadcast: broadcast, rebuildElapsed: elapsed)
                #expect(!msg.contains("broadcast"))
                #expect(!msg.contains("HMR"))
            }
        }
    }

    // "Browser unchanged" retired with the build-error overlay (audit III
    // Wave-2 #7) — the browser now shows the failure.
    @Test("a failed rebuild names the reason and how to recover")
    func rebuildFailureVoice() {
        let msg = DevCommand.rebuildFailed(reason: "boom")
        #expect(msg == "swiflow: rebuild failed — boom. Error shown in the browser overlay; fix and save to retry.")
    }

    // MARK: #7 (Wave 2) — the compiler-output tail forwarded to the overlay

    @Test("no captured diagnostics falls back to the error description")
    func tailFallsBackToErrorDescription() {
        #expect(DevCommand.buildErrorTail(diagnostics: nil, fallback: "swift build failed with exit code 1")
                == "swift build failed with exit code 1")
        #expect(DevCommand.buildErrorTail(diagnostics: "  \n ", fallback: "fb") == "fb",
                "whitespace-only capture is as good as none")
    }

    @Test("short diagnostics pass through whole")
    func tailPassesShortOutputThrough() {
        let d = "App.swift:7:9: error: cannot find 'oops' in scope\n    let x = oops\n"
        #expect(DevCommand.buildErrorTail(diagnostics: d, fallback: "fb") == d)
    }

    // Live-smoke finding: `swift build` puts compiler diagnostics on STDOUT
    // while stderr ends with kilobytes of manifest/dependency chatter — a
    // last-N-lines tail of the combined output forwarded pure noise and
    // buried the actual error. The excerpt must anchor at the first
    // `error:` line instead.
    @Test("the excerpt starts at the first error line, however much noise follows")
    func excerptAnchorsAtFirstErrorLine() {
        let d = (1...50).map { "build progress \($0)" }.joined(separator: "\n")
            + "\nApp.swift:7:9: error: cannot find 'oops' in scope"
            + "\n    let x = oops"
            + "\n" + (1...300).map { "warning: 'dep\($0)': manifest chatter" }.joined(separator: "\n")
        let tail = DevCommand.buildErrorTail(diagnostics: d, fallback: "fb", maxLines: 100)
        #expect(tail.hasPrefix("App.swift:7:9: error: cannot find 'oops' in scope"),
                "the root-cause error must be the FIRST thing the overlay shows")
        #expect(!tail.contains("build progress"))
    }

    @Test("with an error anchor, the byte cap keeps the head (where the error is)")
    func errorAnchoredByteCapKeepsHead() {
        let longNote = "note: " + String(repeating: "x", count: 200) + "\n"
        let d = "error: the bit that matters\n" + String(repeating: longNote, count: 100)
        let tail = DevCommand.buildErrorTail(diagnostics: d, fallback: "fb", maxBytes: 4_096)
        #expect(tail.utf8.count <= 4_096)
        #expect(tail.hasPrefix("error: the bit that matters"))
    }

    @Test("without a recognizable error line, the last maxLines lines are kept")
    func fallbackTailKeepsLastLines() {
        let noise = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let tail = DevCommand.buildErrorTail(diagnostics: noise, fallback: "fb", maxLines: 100)
        #expect(!tail.contains("line 400\n"))
        #expect(tail.hasPrefix("line 401\n"))
        #expect(tail.hasSuffix("line 500"))
    }

    // Second live-smoke finding: swiftc emits ANSI color escapes even into a
    // pipe here, which (a) render as garbage in the overlay and (b) sit
    // between ": " and "error:", hiding the line from the anchor.
    @Test("ANSI color escapes are stripped before anchoring and display")
    func stripsANSIColorEscapes() {
        let d = "building...\nApp.swift:7:9: \u{1B}[1;31merror: \u{1B}[1;39mcannot find 'oops'\u{1B}[0m"
        let tail = DevCommand.buildErrorTail(diagnostics: d, fallback: "fb")
        #expect(tail == "App.swift:7:9: error: cannot find 'oops'",
                "colored error lines must still anchor, and the escapes must not reach the overlay")
    }

    @Test("argv dumps mentioning error flags do not fool the anchor")
    func anchorRequiresRealErrorLine() {
        // Manifest-compile argv lines are one giant token soup — they must
        // not match, or the excerpt anchors on noise ABOVE the real error.
        let d = "warning: 'dep': /usr/bin/swift-frontend -frontend -serialize-diagnostics-path /tmp/errors.dia\n"
            + "App.swift:1:1: error: real one"
        let tail = DevCommand.buildErrorTail(diagnostics: d, fallback: "fb")
        #expect(tail.hasPrefix("App.swift:1:1: error: real one"))
    }
}
