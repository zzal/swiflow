// Tests/SwiflowTestingTests/DebugDumpTests.swift
//
// Audit VI Wave-2 #5: tree-dumping failure messages. `#expect(h.find(...) !=
// nil)` failures said "expected non-nil" and nothing else; `h.expect(...)`
// matchers record an Issue that INCLUDES the rendered tree, and `h.debug()`
// prints/returns the same dump for ad-hoc inspection.
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class DumpFixture {
    @State var count: Int = 0
    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 }, .attr("id", "inc"))
        }
    }
}

@Suite("debug dump + expect matchers")
@MainActor
struct DebugDumpTests {

    @Test("debug() renders tags, attributes, handlers, text, and component names")
    func debugDumpShape() {
        let h = render(DumpFixture())
        let dump = h.debug()
        #expect(dump.contains("DumpFixture"), "component anchors named")
        #expect(dump.contains("<div"))
        #expect(dump.contains("<p"))
        #expect(dump.contains("\"Count: 0\""), "text nodes quoted")
        #expect(dump.contains("id=\"inc\""), "attributes shown")
        #expect(dump.contains("on:[click]"), "handler events shown")
    }

    @Test("expect(text:) is silent when the text is present")
    func expectTextPasses() {
        let h = render(DumpFixture())
        h.expect(text: "Count: 0")
    }

    @Test("expect(text:) failure carries the rendered tree")
    func expectTextFailureDumps() {
        let h = render(DumpFixture())
        withKnownIssue {
            h.expect(text: "Count: 99")
        } matching: { issue in
            let msg = String(describing: issue.comments.first ?? "")
            return msg.contains("Count: 99") && msg.contains("<button")
        }
    }

    @Test("expect(tag:text:) is silent on a match, dumps the tree on a miss")
    func expectTagMatcher() {
        let h = render(DumpFixture())
        h.expect("button", text: "Increment")
        withKnownIssue {
            h.expect("select")
        } matching: { issue in
            String(describing: issue.comments.first ?? "").contains("<div")
        }
    }
}
