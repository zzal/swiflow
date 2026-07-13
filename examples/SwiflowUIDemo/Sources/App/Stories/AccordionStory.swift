import Swiflow
import SwiflowUI

@Component
final class AccordionStory {
    var body: VNode {
        storyPage("Accordion",
                  blurb: "Native <details>/<summary> disclosure — no JS. AccordionItem is a stateless "
                       + "free function; Accordion is a thin @Component facade that exists purely to keep "
                       + "a stable group name across re-renders. exclusive: true groups every item under "
                       + "the same native <details name> value, so the browser enforces one-open-at-a-time "
                       + "(Baseline 2024) with no wiring on your end.") {
            variantSection("Independent (default)", snippet: """
            Accordion {
                AccordionItem("Shipping", open: true) {
                    p("Ships within two business days.")
                }
                AccordionItem("Returns") {
                    p("Returns are accepted within 30 days of delivery.")
                }
                AccordionItem("Warranty") {
                    p("Covers manufacturing defects for one year.")
                }
            }
            """) {
                Accordion {
                    AccordionItem("Shipping", open: true) {
                        p("Ships within two business days.")
                    }
                    AccordionItem("Returns") {
                        p("Returns are accepted within 30 days of delivery.")
                    }
                    AccordionItem("Warranty") {
                        p("Covers manufacturing defects for one year.")
                    }
                }
            }
            variantSection("Exclusive — one open at a time", snippet: """
            Accordion(exclusive: true) {
                AccordionItem("What is Swiflow?", open: true) {
                    p("A Swift-native framework for building web UIs that compile to WebAssembly.")
                }
                AccordionItem("Does it need JavaScript?") {
                    p("Not for this — <details name> grouping is a native platform feature.")
                }
                AccordionItem("Is it accessible?") {
                    p("Yes — <details>/<summary> carry disclosure semantics to assistive tech for free.")
                }
            }
            """) {
                Accordion(exclusive: true) {
                    AccordionItem("What is Swiflow?", open: true) {
                        p("A Swift-native framework for building web UIs that compile to WebAssembly.")
                    }
                    AccordionItem("Does it need JavaScript?") {
                        p("Not for this — <details name> grouping is a native platform feature.")
                    }
                    AccordionItem("Is it accessible?") {
                        p("Yes — <details>/<summary> carry disclosure semantics to assistive tech for free.")
                    }
                }
            }
        }
    }
}
