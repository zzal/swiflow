// Tests/SwiflowUITests/OverlayLivenessTests.swift
//
// Audit V Wave-2 #6: Alert/Prompt display props thread LIVE. The embed at a
// stable (type, nil-key) position REUSES the dialog instance — before this,
// title/message froze at first mount and only a key: remount updated them.
// The facades now push the props in refresh:, so an interpolated title just
// works. (Pre-fix, these tests fail with the FIRST title still rendered.)
import Testing
import Swiflow
@testable import SwiflowUI
@testable import SwiflowTesting

@Component
private final class AlertHost {
    @State var n: Int = 1
    var body: VNode {
        div {
            Alert("Delete \(n) items?", isPresented: Binding(get: { true }, set: { _ in }),
                  message: "Count: \(n)") {
                Button("Cancel", variant: .secondary) {}
            }
            button(.on(.click) { self.n += 1 }) { VNode.text("bump") }
        }
    }
}

@Component
private final class PromptHost {
    @State var n: Int = 1
    var body: VNode {
        div {
            Prompt("Rename file \(n)", isPresented: Binding(get: { true }, set: { _ in }),
                   text: Binding(get: { "x" }, set: { _ in }),
                   confirmTitle: "Rename \(n)") { _ in }
            button(.on(.click) { self.n += 1 }) { VNode.text("bump") }
        }
    }
}

@Suite("Overlay display props are live")
@MainActor
struct OverlayLivenessTests {

    @Test("Alert title/message update on parent re-render — no key:, no remount")
    func alertLive() {
        let h = render(AlertHost())
        #expect(h.allText.contains("Delete 1 items?"))
        h.click("button", text: "bump")
        #expect(h.allText.contains("Delete 2 items?"), "title pushed live into the reused dialog")
        #expect(h.allText.contains("Count: 2"), "message too")
        #expect(!h.allText.contains("Delete 1 items?"), "the stale first-mount title is gone")
    }

    @Test("Prompt title/confirmTitle update on parent re-render")
    func promptLive() {
        let h = render(PromptHost())
        #expect(h.allText.contains("Rename file 1"))
        h.click("button", text: "bump")
        #expect(h.allText.contains("Rename file 2"))
        #expect(h.allText.contains("Rename 2"), "the confirm button title threads too")
    }
}
