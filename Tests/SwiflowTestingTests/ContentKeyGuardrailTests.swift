// Tests/SwiflowTests/DiffTests/ContentKeyGuardrailTests.swift
//
// Audit V Wave-2 #6: the key:-freeze guardrail. An embedded component is
// reused at a (type, key) position — its factory ran at FIRST MOUNT only,
// so init props freeze. `contentKey` is an optional cheap digest of that
// frozen content: when the same position arrives with a DIFFERENT digest
// and no `refresh:` closure, DEBUG builds warn instead of silently showing
// stale data. A key CHANGE is a remount (different identity) and never
// reaches the check; `refresh:` present means the caller already threads
// data live.
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class FrozenChild {
    var body: VNode { p("child") }
}

@Component
private final class EmbeddingParent {
    // Plain vars — the test mutates them and re-renders via the harness.
    var digest: String? = "v1"
    var key: String = "slot"
    var useRefresh: Bool = false
    @State var tick: Int = 0

    var body: VNode {
        div {
            p("tick \(tick)")
            if useRefresh {
                embed(key, contentKey: digest, { FrozenChild() }, refresh: { _ in })
            } else {
                embed(key, contentKey: digest) { FrozenChild() }
            }
            button(.on(.click) { self.tick += 1 }) { VNode.text("bump") }
        }
    }
}

@Suite("contentKey guardrail", .serialized)
struct ContentKeyGuardrailTests {

    @MainActor
    private func captureWarnings(_ body: () -> Void) -> [String] {
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    @Test("digest change under an unchanged key warns ONCE, naming the component")
    @MainActor
    func digestChangeWarnsOnce() {
        let parent = EmbeddingParent()
        let warnings = captureWarnings {
            let h = render(parent)
            parent.digest = "v2"
            h.click("button")             // re-render: same key, new digest
            h.click("button")             // digest now stored → no re-warn
        }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("FrozenChild"), "names the stale component")
        #expect((warnings.first ?? "").contains("key:") && (warnings.first ?? "").contains("refresh:"),
                "offers both fixes")
    }

    @Test("refresh: present means data is threaded — silent")
    @MainActor
    func refreshSilences() {
        let parent = EmbeddingParent()
        parent.useRefresh = true
        let warnings = captureWarnings {
            let h = render(parent)
            parent.digest = "v2"
            h.click("button")
        }
        #expect(warnings.isEmpty)
    }

    @Test("nil digests are silent — the guardrail is opt-in")
    @MainActor
    func nilDigestSilent() {
        let parent = EmbeddingParent()
        parent.digest = nil
        let warnings = captureWarnings {
            let h = render(parent)
            h.click("button")
        }
        #expect(warnings.isEmpty)
    }

    @Test("an unchanged digest is silent")
    @MainActor
    func unchangedDigestSilent() {
        let parent = EmbeddingParent()
        let warnings = captureWarnings {
            let h = render(parent)
            h.click("button")
            h.click("button")
        }
        #expect(warnings.isEmpty)
    }

    @Test("a key change is a remount — different identity, never warns")
    @MainActor
    func keyChangeRemountsSilently() {
        let parent = EmbeddingParent()
        let warnings = captureWarnings {
            let h = render(parent)
            parent.digest = "v2"
            parent.key = "slot-2"        // identity changes WITH the content — the documented fix
            h.click("button")
        }
        #expect(warnings.isEmpty)
    }
}
