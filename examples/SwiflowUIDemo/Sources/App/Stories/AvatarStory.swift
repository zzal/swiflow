import Swiflow
import SwiflowUI

@Component
final class AvatarStory {
    // A real relative URL, served from the example root. NOT a data: URI — the
    // previous data:-based placeholder rendered a broken image: URLSanitizer
    // strips data: srcs by default (allowDataURLs is an opt-in startup knob).
    private let placeholderSrc = "avatar.svg"

    var body: VNode {
        storyPage("Avatar",
                  blurb: "A user/entity picture — Badge's shape, sized via ControlSize — that falls back "
                       + "to initials when there's no image. With src, an <img> (the URL is sanitized via "
                       + ".src, exactly like TextLink's href). Without one, a role=img span filled with "
                       + "the name's initials.") {
            variantSection("Sizes", snippet: """
            HStack(spacing: .md, align: .center) {
                Avatar("Ada Lovelace", size: .sm)
                Avatar("Ada Lovelace", size: .md)
                Avatar("Ada Lovelace", size: .lg)
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Avatar("Ada Lovelace", size: .sm)
                    Avatar("Ada Lovelace", size: .md)
                    Avatar("Ada Lovelace", size: .lg)
                }
            }
            variantSection("Shapes", snippet: """
            HStack(spacing: .md, align: .center) {
                Avatar("Grace Hopper", shape: .circle)
                Avatar("Grace Hopper", shape: .rounded)
                Avatar("Grace Hopper", shape: .square)
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Avatar("Grace Hopper", shape: .circle)
                    Avatar("Grace Hopper", shape: .rounded)
                    Avatar("Grace Hopper", shape: .square)
                }
            }
            variantSection("With an image", snippet: """
            Avatar("Ada Lovelace", src: "avatar.svg")   // renders <img>; initials when src is nil
            // NB: data: srcs are stripped by URLSanitizer unless you opt in at startup
            // (URLSanitizer.allowDataURLs = true) — use real URLs for avatar images.
            """) {
                Avatar("Ada Lovelace", src: placeholderSrc)
            }
        }
    }
}
