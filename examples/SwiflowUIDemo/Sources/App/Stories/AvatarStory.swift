import Swiflow
import SwiflowUI

@Component
final class AvatarStory {
    // A tiny inline SVG data URI so the "with src" variant renders without a
    // network fetch — the same percent-encoded-data-URI technique Icon uses.
    private let placeholderSrc =
        "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='64' height='64'%3E" +
        "%3Crect width='64' height='64' fill='%236366f1'/%3E%3C/svg%3E"

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
            Avatar("Ada Lovelace", src: imageURL)   // renders <img>; falls back to "AL" if src is nil
            """) {
                Avatar("Ada Lovelace", src: placeholderSrc)
            }
        }
    }
}
