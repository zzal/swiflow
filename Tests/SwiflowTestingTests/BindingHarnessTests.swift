// Tests/SwiflowTestingTests/BindingHarnessTests.swift
import Testing
import Swiflow
import SwiflowTesting

@MainActor @Component
private final class EchoInput {
    @State var text: String = ""
    var body: VNode {
        div {
            input(.value($text))
            p { VNode.text("echo: \(text)") }
        }
    }
}

@Suite
@MainActor
struct BindingHarnessTests {

    @Test("harness.input(value:) round-trips through a .value binding into the rendered output") func valueBindingRoundTripsThroughHarness() {
        let harness = render(EchoInput())
        #expect(harness.allText.contains("echo: "))

        harness.input(value: "hello")

        #expect(harness.allText.contains("echo: hello"))
    }
}
