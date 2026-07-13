import Swiflow
import SwiflowUI

@Component
final class CalloutStory {
    var body: VNode {
        storyPage("Callout",
                  blurb: "A stateless semantic status banner — a bordered, soft-tinted div with an "
                       + "optional title, a message, and an optional actions slot. role/aria-live map "
                       + "like Toast: .danger is assertive (role=alert), the other three are polite "
                       + "(role=status). No icon — that's M14.") {
            variantSection("Variants", snippet: """
            Callout("This is an informational note.")
            Callout("Changes saved.", variant: .success)
            Callout("Your session will expire soon.", variant: .warning)
            Callout("Couldn't reach the server.", variant: .danger)
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Callout("This is an informational note.")
                    Callout("Changes saved.", variant: .success)
                    Callout("Your session will expire soon.", variant: .warning)
                    Callout("Couldn't reach the server.", variant: .danger)
                }
            }
            variantSection("Title + actions", snippet: """
            Callout("We couldn't process your last payment.", variant: .danger, title: "Payment failed") {
                Button("Retry") {}
                TextLink("Contact support", href: "https://example.com/support")
            }
            """) {
                Callout("We couldn't process your last payment.", variant: .danger, title: "Payment failed") {
                    Button("Retry") {}
                    TextLink("Contact support", href: "https://example.com/support")
                }
            }
        }
    }
}
