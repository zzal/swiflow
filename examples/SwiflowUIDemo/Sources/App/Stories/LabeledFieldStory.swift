import Swiflow
import SwiflowUI

@Component
final class LabeledFieldStory {
    @State var host: String = ""
    @State var port: String = ""
    @State var token: String = ""

    private static let infoIcon =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' " +
        "stroke='currentColor' stroke-width='1.5'><circle cx='8' cy='8' r='6.5'/>" +
        "<path d='M8 7.5v3.5'/><circle cx='8' cy='5' r='0.5' fill='currentColor'/></svg>"

    var body: VNode {
        storyPage("LabeledField",
                  blurb: "The shared field chrome, public: label line (with optional subtle "
                       + "prefix/suffix adornments), your control, and the standard error — plus "
                       + "a horizontal layout with a fixed label column (--sw-field-label-width) "
                       + "so stacked fields align. The built-in controls render this internally; "
                       + "use it directly for custom controls.") {
            variantSection("Horizontal settings form", snippet: """
            TextField("Host", text: $host, layout: .horizontal)
            TextField("Port", text: $port, layout: .horizontal)
            TextField("API token", text: $token, layout: .horizontal, labelSuffix: text("optional"))
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Host", text: $host, placeholder: "example.com", layout: .horizontal)
                        TextField("Port", text: $port, placeholder: "443", layout: .horizontal)
                        TextField("API token", text: $token, layout: .horizontal,
                                  labelSuffix: text("optional"))
                    }
                }
            }
            variantSection("Label adornments", snippet: """
            TextField("Endpoint", text: $host, labelPrefix: Icon(infoIcon), labelSuffix: text("optional"))
            """) {
                Card(variant: .plain) {
                    TextField("Endpoint", text: $host,
                              labelPrefix: Icon(LabeledFieldStory.infoIcon),
                              labelSuffix: text("optional"))
                }
            }
            variantSection("Custom control", snippet: """
            LabeledField("Favorite hue", layout: .horizontal) {
                element("input", attributes: [.attr("type", "color")])
            }
            """) {
                Card(variant: .plain) {
                    LabeledField("Favorite hue", layout: .horizontal) {
                        element("input", attributes: [.attr("type", "color")])
                    }
                }
            }
        }
    }
}
