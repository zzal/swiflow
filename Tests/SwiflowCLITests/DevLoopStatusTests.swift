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

    @Test("a failed rebuild names the reason and how to recover")
    func rebuildFailureVoice() {
        let msg = DevCommand.rebuildFailed(reason: "boom")
        #expect(msg == "swiflow: rebuild failed — boom. Browser unchanged; fix and save to retry.")
    }
}
